import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

import '../db/app_database.dart';
import '../farmers/photo_store.dart';
import '../kisan/kisan_cache.dart' show watchTables;
import '../photo/photo_processor.dart';
import '../photo/photo_quality.dart';
import '../sync/outbox.dart';
import '../sync/sync_models.dart';
import '../sync/sync_store.dart';
import 'diagnosis_api.dart';
import 'diagnosis_models.dart';
import 'on_device_block.dart';

/// Most photos per diagnosis (FM-004, `MAX_PHOTOS` on the server).
const int maxDiagnosisPhotos = 3;

/// Upload purpose of crop-doctor photos.
const String diagnosisUploadPurpose = 'diagnosis';

/// A photo that went through [PhotoProcessor] and the on-device gate.
@immutable
class CapturedPhoto {
  /// Creates the photo.
  const CapturedPhoto({required this.processed, required this.quality});

  /// NF-004 processed JPEG.
  final ProcessedPhoto processed;

  /// DX-001 gate result.
  final PhotoQualityResult quality;

  /// Passed the gate.
  bool get accepted => quality.isAcceptable;
}

/// What the user asked for (F20–F23 / A40–A41).
@immutable
class DiagnosisRequest {
  /// Creates the request.
  const DiagnosisRequest({
    required this.photos,
    this.farmerId,
    this.cropPlotId,
    this.cropId,
    this.cropCode,
    this.cropStage,
    this.cropGuess,
    this.onDeviceModel,
    this.askExpert = false,
    this.subject = 'farmer',
  });

  /// Accepted photos (1–3).
  final List<CapturedPhoto> photos;

  /// Required for a field officer (scouting); a farmer asks for themself.
  final String? farmerId;

  /// Crop plot to attach the result to (FA-019).
  final String? cropPlotId;

  /// Server crop id; null (or a `pilot:` placeholder) sends [cropCode], else
  /// `unknown`.
  final String? cropId;

  /// Crop code (`paddy`): shown before the answer and sent as `crop_code`
  /// when there is no server id (the server resolves it per tenant).
  final String? cropCode;

  /// Crop stage of the plot.
  final String? cropStage;

  /// On-device crop guess `(code, confidence)`, sent only while the
  /// `on_device_crop_guess` flag is on.
  final (String, double)? cropGuess;

  /// `ondevice-v1.0` or `heuristic-laplacian-v1` (DX-005), sent as the
  /// legacy `on_device_model` next to the `on_device` block (built from
  /// [photos]) for servers that predate the block.
  final String? onDeviceModel;

  /// FM-006: send to the agronomist as well.
  final bool askExpert;

  /// `farmer` or `officer`.
  final String subject;
}

/// What "Ask an expert" did (FM-006).
enum AskExpertOutcome {
  /// The case is already in the agronomist's queue (provisional, out of
  /// scope or asked before): nothing new is sent.
  alreadyWithExpert,

  /// The answered case was put in the agronomist queue (same photos).
  sent,

  /// Not queued yet: the flag was added to the queued request.
  addedToQueued,

  /// The server could not be reached (offline); nothing changed, try again.
  failed,
}

/// Crop-doctor cases (FM-004 .. FM-006, FA-019): photos saved on the phone,
/// resumable uploads and one `diagnosis` create op in the outbox (so it
/// works offline), the answer stored in `sync_docs` from the applied echo,
/// the poll and the change feed (NF-002: results stay readable offline).
class DiagnosisRepository {
  /// Creates the repository.
  DiagnosisRepository({
    required this.db,
    required this.outbox,
    required this.photos,
    required this.api,
    required DateTime Function() clock,
    required String Function() ids,
  }) : _now = clock,
       _newId = ids;

  /// Database.
  final AppDatabase db;

  /// Outbox.
  final Outbox outbox;

  /// Where photos are kept until uploaded.
  final PhotoStore photos;

  /// `GET /v1/diagnoses/{id}`.
  final DiagnosisApi api;

  final DateTime Function() _now;
  final String Function() _newId;

  SyncStore get _store => outbox.store;

  /// Queues photos + the create op; returns the diagnosis id.
  Future<String> submit(DiagnosisRequest request) async {
    final photos = request.photos.where((p) => p.accepted).toList();
    if (photos.isEmpty || photos.length > maxDiagnosisPhotos) {
      throw ArgumentError.value(
        request.photos.length,
        'photos',
        'need 1 to $maxDiagnosisPhotos accepted photos',
      );
    }
    final id = _newId();
    final now = _now();
    final paths = <String>[];
    final images = <Map<String, Object?>>[];
    for (final (i, p) in photos.indexed) {
      final bytes = Uint8List.fromList(p.processed.bytes);
      final path = await this.photos.save(
        'diagnosis_${id}_${i + 1}.jpg',
        bytes,
      );
      final uploadId = await outbox.enqueueUpload(
        filePath: path,
        bytes: bytes,
        purpose: diagnosisUploadPurpose,
      );
      paths.add(path);
      images.add(<String, Object?>{
        'blob_uri': Outbox.uploadRef(uploadId),
        'sha256': p.processed.sha256,
        'quality': p.quality.toDiagnosisQuality(),
      });
    }
    final cropId = request.cropId;
    final guess = request.cropGuess;
    await outbox.enqueueCreate(
      SyncEntities.diagnosis,
      id,
      <String, Object?>{
        'farmer_id': ?request.farmerId,
        'crop_plot_id': ?request.cropPlotId,
        if (cropId != null && _isServerId(cropId))
          'crop_id': cropId
        else if (request.cropCode case final code?)
          'crop_code': code
        else
          'crop_id': 'unknown',
        'images': images,
        if (guess != null)
          'crop_guess': <String, Object?>{
            'code': guess.$1,
            'confidence': guess.$2,
          },
        'on_device_model': ?request.onDeviceModel,
        'on_device': ?OnDeviceBlock.fromResults(photos.map((p) => p.quality)),
        'crop_stage': ?request.cropStage,
        'captured_at': now.toIso8601String(),
        'ask_expert': request.askExpert,
      },
      local: <String, Object?>{
        'photos': paths,
        'crop_code': ?request.cropCode,
        'subject': request.subject,
        if (request.askExpert) 'ask_expert': true,
      },
    );
    return id;
  }

  static bool _isServerId(String id) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  ).hasMatch(id);

  Future<Diagnosis?> _load(String id) async {
    final row =
        await (db.select(db.syncDocs)..where(
              (t) =>
                  t.entity.equals(SyncEntities.diagnosis) & t.docId.equals(id),
            ))
            .getSingleOrNull();
    if (row == null || row.deleted) return null;
    return Diagnosis.fromData(
      id,
      Map<String, Object?>.from(jsonDecode(row.data) as Map),
      dirty: row.dirty,
    );
  }

  /// One diagnosis.
  Future<Diagnosis?> get(String id) => _load(id);

  /// One diagnosis, live.
  Stream<Diagnosis?> watch(String id) => watchTables(
    db,
    <TableInfo<Table, Object?>>[db.syncDocs],
    () => _load(id),
  );

  Future<List<Diagnosis>> _all({
    String? farmerId,
    String? cropPlotId,
    String? subject,
  }) async {
    final rows =
        await (db.select(db.syncDocs)
              ..where((t) => t.entity.equals(SyncEntities.diagnosis))
              ..orderBy(<OrderClauseGenerator<$SyncDocsTable>>[
                (t) => OrderingTerm.desc(t.updatedAt),
              ]))
            .get();
    return <Diagnosis>[
        for (final r in rows)
          if (!r.deleted)
            Diagnosis.fromData(
              r.docId,
              Map<String, Object?>.from(jsonDecode(r.data) as Map),
              dirty: r.dirty,
            ),
      ].where((d) {
        if (farmerId != null && d.farmerId != farmerId) return false;
        if (cropPlotId != null && d.cropPlotId != cropPlotId) return false;
        if (subject != null && d.subject != subject) return false;
        return true;
      }).toList()
      ..sort((a, b) {
        final at = a.capturedAt ?? a.updatedAt ?? DateTime(2000);
        final bt = b.capturedAt ?? b.updatedAt ?? DateTime(2000);
        return bt.compareTo(at);
      });
  }

  /// Every diagnosis (optionally of one farmer / plot / subject), newest
  /// first, live.
  Stream<List<Diagnosis>> watchAll({
    String? farmerId,
    String? cropPlotId,
    String? subject,
  }) => watchTables(db, <TableInfo<Table, Object?>>[
    db.syncDocs,
  ], () => _all(farmerId: farmerId, cropPlotId: cropPlotId, subject: subject));

  /// `GET /v1/diagnoses/{id}` into the store; null when offline or not
  /// there yet. A row with a queued op is left alone (the push settles it).
  Future<Diagnosis?> refresh(String id) async {
    final local = await _store.entities.read(SyncEntities.diagnosis, id);
    if (local != null && local.dirty) return _load(id);
    final r = await api.get(id);
    if (!r.ok) return null;
    await _store.entities.write(
      SyncEntities.diagnosis,
      id,
      r.body,
      version: (r.body['version'] as num?)?.toInt() ?? local?.version ?? 0,
      dirty: false,
      now: _now(),
    );
    return _load(id);
  }

  /// Clears the F27 "updated" banner.
  Future<void> markSeen(String id) async {
    final row = await _store.entities.read(SyncEntities.diagnosis, id);
    if (row == null) return;
    final local = Map<String, Object?>.from(
      (row.data[Diagnosis.localKey] as Map?) ?? const <String, Object?>{},
    );
    if (local['update_unseen'] != true) return;
    local.remove('update_unseen');
    await _store.entities.write(
      SyncEntities.diagnosis,
      id,
      <String, Object?>{...row.data, Diagnosis.localKey: local},
      version: row.version,
      dirty: row.dirty,
      now: _now(),
    );
  }

  /// FM-006 "Ask an expert".
  Future<(AskExpertOutcome, String)> askExpert(String id) async {
    final d = await _load(id);
    if (d == null) throw StateError('diagnosis $id not found');
    if (d.askExpert ||
        d.provisional ||
        d.isOutOfScope ||
        d.status == DiagnosisStatus.provisional) {
      return (AskExpertOutcome.alreadyWithExpert, id);
    }
    final open = await _store.firstOpenOp(id);
    if (open != null) {
      final payload = <String, Object?>{
        ...SyncStore.payloadOf(open),
        'ask_expert': true,
      };
      await _store.setPayload(
        open.opId,
        payload,
        dependsOnUploadId: open.dependsOnUploadId,
      );
      final row = await _store.entities.read(SyncEntities.diagnosis, id);
      if (row != null) {
        await _store.entities.write(
          SyncEntities.diagnosis,
          id,
          <String, Object?>{
            ...row.data,
            'ask_expert': true,
            Diagnosis.localKey: <String, Object?>{
              ...?(row.data[Diagnosis.localKey] as Map?)
                  ?.cast<String, Object?>(),
              'ask_expert': true,
            },
          },
          version: row.version,
          dirty: row.dirty,
          now: _now(),
        );
      }
      return (AskExpertOutcome.addedToQueued, id);
    }
    // Answered already: the server moves this case into the agronomist queue
    // (`POST /v1/diagnoses/{id}/ask-expert`, same photos, no re-upload).
    final r = await api.askExpert(id);
    if (r.status == 409) return (AskExpertOutcome.alreadyWithExpert, id);
    if (!r.ok) return (AskExpertOutcome.failed, id);
    final row = await _store.entities.read(SyncEntities.diagnosis, id);
    await _store.entities.write(
      SyncEntities.diagnosis,
      id,
      <String, Object?>{
        ...r.body,
        Diagnosis.localKey: <String, Object?>{
          ...?(row?.data[Diagnosis.localKey] as Map?)?.cast<String, Object?>(),
          'ask_expert': true,
        },
      },
      version: (r.body['version'] as num?)?.toInt() ?? row?.version ?? 0,
      dirty: false,
      now: _now(),
    );
    return (AskExpertOutcome.sent, id);
  }
}

/// Polls `GET /v1/diagnoses/{id}` while the answer is pending (every 2 s,
/// backing off to 10 s; docs/prs/M6-diagnosis-api.md), until [stop] or an
/// answer. The sync feed delivers it too; polling only makes F24 faster.
class DiagnosisPoller {
  /// Creates the poller.
  DiagnosisPoller({
    required this.repository,
    required this.sleep,
    this.flush,
    this.maxAttempts = 60,
  });

  /// Where answers are stored.
  final DiagnosisRepository repository;

  /// Waits between polls (tests make it controllable).
  final Future<void> Function(Duration) sleep;

  /// Pushes queued work first (the create op and its uploads).
  final Future<void> Function()? flush;

  /// Give up after this many polls (the feed still delivers).
  final int maxAttempts;

  bool _stopped = false;

  /// Stops after the current wait.
  void stop() => _stopped = true;

  /// Delay before poll [attempt] (0-based): 2, 4, 6, 8, 10, 10, ... s.
  static Duration delayFor(int attempt) =>
      Duration(seconds: (2 * (attempt + 1)).clamp(2, 10));

  /// Runs until answered, stopped or out of attempts.
  Future<Diagnosis?> run(String id) async {
    Diagnosis? last;
    for (var attempt = 0; attempt < maxAttempts && !_stopped; attempt++) {
      if (flush != null) {
        try {
          await flush!();
        } on Object {
          // Offline: keep waiting.
        }
      }
      last = await repository.refresh(id) ?? await repository.get(id);
      if (last != null && !last.status.isWaiting) return last;
      if (_stopped) break;
      await sleep(delayFor(attempt));
    }
    return last;
  }
}
