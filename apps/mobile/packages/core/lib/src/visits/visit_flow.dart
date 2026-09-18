import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../duty/duty_models.dart';
import '../duty/duty_providers.dart';
import '../farmers/farmers_providers.dart';
import '../geo/geo.dart';
import '../photo/photo_processor.dart';
import '../photo/photo_quality.dart';
import '../sync/outbox.dart';
import '../sync/sync_models.dart';
import '../sync/sync_providers.dart';
import '../sync/sync_store.dart';
import '../widgets/visit_card.dart' show VisitPurpose;
import 'visit_confirm_api.dart';
import 'visit_models.dart';
import 'visit_providers.dart';
import 'visit_repository.dart';

/// A30: the current fix and the client-side geofence decision.
@immutable
class VisitPrecheck {
  /// Creates the pre-check.
  const VisitPrecheck({
    required this.fix,
    required this.check,
    required this.settings,
    required this.farmBoundary,
    required this.meetingPoint,
  });

  /// The fix used; null when the device gave none.
  final LocationFix? fix;

  /// The decision; null without a fix.
  final GeofenceCheck? check;

  /// Tenant settings applied.
  final VisitSettings settings;

  /// Farm ring checked against (empty when the farm has no boundary).
  final List<GeoPoint> farmBoundary;

  /// Village meeting point checked against, if any.
  final GeoPoint? meetingPoint;

  /// Check-in allowed without an override note.
  bool get allowed => check?.allowed ?? false;
}

/// Why a check-in did not happen.
enum CheckInResult {
  /// The visit row and its create op exist; go to A31.
  started,

  /// Duty is off (FA-010: visits are on-duty work).
  offDuty,

  /// No GPS fix.
  noFix,

  /// Outside the geofence and no override note was given.
  needsOverride,
}

/// Outcome of [VisitFlow.checkIn].
@immutable
class CheckInOutcome {
  /// Creates the outcome.
  const CheckInOutcome(this.result, {this.visitId});

  /// What happened.
  final CheckInResult result;

  /// The new visit id on [CheckInResult.started].
  final String? visitId;
}

/// A processed photo waiting for the officer's Use / Retake (A31).
@immutable
class PendingVisitPhoto {
  /// Creates the pending photo.
  const PendingVisitPhoto({
    required this.processed,
    required this.quality,
    required this.location,
  });

  /// NF-004 output (EXIF time + GPS embedded).
  final ProcessedPhoto processed;

  /// Blur / darkness gate.
  final PhotoQualityResult quality;

  /// Fix at capture (null when the device gave none).
  final GeoPoint? location;
}

/// Outcome of [VisitFlow.retryFromFarm].
enum RetryResult {
  /// The check-in op was requeued with the new fix.
  retried,

  /// Still outside (see [RetryOutcome.check]); add a note or move.
  stillOutside,

  /// No GPS fix.
  noFix,

  /// Nothing to retry (no rejected op).
  nothingToRetry,
}

/// Outcome of [VisitFlow.retryFromFarm].
@immutable
class RetryOutcome {
  /// Creates the outcome.
  const RetryOutcome(this.result, {this.check});

  /// What happened.
  final RetryResult result;

  /// The new pre-check.
  final GeofenceCheck? check;
}

/// Outcome of [VisitFlow.requestConfirmation].
enum RequestResult {
  /// Requested; see [RequestOutcome].
  ok,

  /// Offline: the push request is queued locally and goes out when the
  /// network is back.
  queuedOffline,

  /// Offline: this channel needs the network right now.
  needsNetwork,

  /// The check-in has not reached the server yet (sync first).
  notSynced,

  /// Already confirmed.
  alreadyConfirmed,

  /// Locked / rate limited / channel unusable.
  refused,
}

/// Outcome of [VisitFlow.requestConfirmation].
@immutable
class RequestOutcome {
  /// Creates the outcome.
  const RequestOutcome(this.result, {this.api});

  /// What happened.
  final RequestResult result;

  /// The server's answer on [RequestResult.ok] / [RequestResult.refused].
  final ConfirmationRequestOutcome? api;
}

/// The FA-014 .. FA-017 write path: pre-check, check-in, photos, capture,
/// check-out, retry after a rejection and the FA-016 confirmation calls.
/// Every write is an outbox op (offline first); only the confirmation
/// request / OTP completion need the network.
class VisitFlow {
  /// Creates the flow over [ref].
  VisitFlow(this.ref);

  /// Provider access.
  final Ref ref;

  VisitRepository get _repo => ref.read(visitRepositoryProvider);
  Outbox get _outbox => ref.read(outboxProvider);
  DateTime get _now => ref.read(clockProvider)();
  String _newId() => ref.read(idGeneratorProvider)();

  /// On duty right now (the local session row is the source of truth so a
  /// restored session counts before the controller has run).
  Future<bool> onDuty() async =>
      await ref.read(dutyRepositoryProvider).activeSession() != null;

  /// One fix from the duty sampler (on-duty GPS; FA-010).
  Future<LocationFix?> currentFix() =>
      ref.read(locationSamplerProvider).current();

  /// A30: the current fix against [farm]'s polygon and [village]'s meeting
  /// point (falling back to the village centre).
  Future<VisitPrecheck> precheck({Farm? farm, Village? village}) async {
    final settings = await _repo.settings();
    final boundary = polygonFromGeoJson(farm?.boundary);
    final meeting = village == null
        ? null
        : village.meetingPointLat != null
        ? GeoPoint(village.meetingPointLat!, village.meetingPointLon!)
        : village.latitude != null
        ? GeoPoint(village.latitude!, village.longitude!)
        : null;
    final fix = await currentFix();
    return VisitPrecheck(
      fix: fix,
      check: fix == null
          ? null
          : evaluateGeofence(
              point: fix.point,
              farmBoundary: boundary,
              meetingPoint: meeting,
              radiusM: settings.geofenceRadiusM,
              meetingRadiusM: village?.meetingPointRadiusM,
            ),
      settings: settings,
      farmBoundary: boundary,
      meetingPoint: meeting,
    );
  }

  /// FA-014 check-in: `visit` create op with the fix, the FA-028 snapshot
  /// and the client id; the row is written optimistically with the
  /// pre-check. Outside the geofence the op carries [overrideNote] (the
  /// server decides); without a note nothing is queued.
  Future<CheckInOutcome> checkIn({
    required String farmerId,
    required VisitPurpose purpose,
    required VisitPrecheck precheck,
    String? farmId,
    String? villageId,
    String? overrideNote,
  }) async {
    if (!await onDuty()) return const CheckInOutcome(CheckInResult.offDuty);
    final fix = precheck.fix;
    final check = precheck.check;
    if (fix == null || check == null) {
      return const CheckInOutcome(CheckInResult.noFix);
    }
    final note = overrideNote?.trim();
    if (!check.allowed && (note == null || note.isEmpty)) {
      return const CheckInOutcome(CheckInResult.needsOverride);
    }
    final now = _now;
    final integrity = await ref
        .read(deviceIntegrityProvider)
        .snapshot(fixIsMock: fix.isMock, now: now);
    final id = _newId();
    await _outbox.enqueueCreate(SyncEntities.visit, id, <String, Object?>{
      'farmer_id': farmerId,
      'farm_id': farmId,
      'village_id': villageId,
      'purpose': purpose.name,
      'checkin_at': now.toIso8601String(),
      'checkin_point': fix.toPointJson(),
      'device_integrity': <String, Object?>{
        'is_mock': integrity.isMock,
        'is_rooted': integrity.isRooted,
        'clock_drift_s': integrity.clockDriftS ?? 0,
      },
      if (!check.allowed) 'override_note': note,
      'client_visit_id': id,
    });
    await _repo.setPrecheck(id, check);
    return CheckInOutcome(CheckInResult.started, visitId: id);
  }

  /// FA-015: opens the in-app camera (there is no gallery path: the
  /// [CameraSource] interface only has `capture`), runs the NF-004 pipeline
  /// with the current fix and the quality gate. `null` when cancelled.
  Future<PendingVisitPhoto?> capturePhoto() async {
    final bytes = await ref.read(cameraSourceProvider).capture();
    if (bytes == null) return null;
    final fix = await currentFix();
    final processed = await PhotoProcessor.process(
      bytes,
      captureTime: _now,
      location: fix == null
          ? null
          : PhotoLocation(
              latitude: fix.point.latitude,
              longitude: fix.point.longitude,
              accuracyMetres: fix.accuracyM,
            ),
    );
    final quality = await PhotoQualityCheck.evaluate(processed.bytes);
    return PendingVisitPhoto(
      processed: processed,
      quality: quality,
      location: fix?.point,
    );
  }

  /// FA-015: saves the accepted photo, queues its upload and the
  /// `visit_photo` create op (`taken_in_app: true`, EXIF time + GPS, device
  /// time); the op waits for the upload's `blob_uri`.
  Future<String> acceptPhoto(String visitId, PendingVisitPhoto pending) async {
    final n = (await _repo.photos(visitId)).length + 1;
    final bytes = Uint8List.fromList(pending.processed.bytes);
    final path = await ref
        .read(photoStoreProvider)
        .save('visit_${visitId}_$n.jpg', bytes);
    final uploadId = await _outbox.enqueueUpload(
      filePath: path,
      bytes: bytes,
      purpose: 'visit_photo',
    );
    final exif = pending.processed.exif;
    final photoId = _newId();
    await _outbox.enqueueCreate(
      SyncEntities.visitPhoto,
      photoId,
      <String, Object?>{
        'visit_id': visitId,
        'blob_uri': Outbox.uploadRef(uploadId),
        'sha256': pending.processed.sha256,
        'exif_time': exif.takenAt?.toIso8601String(),
        'exif_point': exif.latitude == null
            ? null
            : <String, Object?>{'lat': exif.latitude, 'lon': exif.longitude},
        'taken_in_app': true,
        'device_time': _now.toIso8601String(),
      },
    );
    await _repo.setPhotoPath(photoId, path);
    return photoId;
  }

  Future<Map<String, Object?>> _captureChanges(
    Visit row, {
    String? notes,
    String? cropStage,
  }) async {
    final patch = <String, Object?>{};
    if (notes != null && notes.trim() != (row.notes ?? '')) {
      patch['notes'] = notes.trim();
    }
    if (cropStage != null && cropStage != row.cropStage) {
      patch['crop_stage'] = cropStage;
    }
    return patch;
  }

  /// FA-015: queues a `visit` update with the changed notes / crop stage
  /// (nothing when unchanged).
  Future<bool> saveCapture(
    String visitId, {
    String? notes,
    String? cropStage,
  }) async {
    final row = await _repo.visit(visitId);
    if (row == null) return false;
    final patch = await _captureChanges(
      row,
      notes: notes,
      cropStage: cropStage,
    );
    if (patch.isEmpty) return false;
    await _outbox.enqueueUpdate(SyncEntities.visit, visitId, patch);
    return true;
  }

  /// FA-017 check-out: `visit` update op with `checkout_at` and the fix
  /// (plus unsaved notes / crop stage). The server computes the duration,
  /// the score and the status; the row shows the local expectation until
  /// the echo / pull replaces it.
  Future<bool> checkOut(
    String visitId, {
    String? notes,
    String? cropStage,
  }) async {
    final row = await _repo.visit(visitId);
    if (row == null || row.checkoutAt != null) return false;
    final fix = await currentFix();
    final now = _now;
    await _outbox.enqueueUpdate(SyncEntities.visit, visitId, <String, Object?>{
      ...await _captureChanges(row, notes: notes, cropStage: cropStage),
      'checkout_at': now.toIso8601String(),
      'checkout_point': fix == null
          ? null
          : <String, Object?>{
              'lat': fix.point.latitude,
              'lon': fix.point.longitude,
            },
    });
    return true;
  }

  /// "Retry from the farm" after an `outside_geofence` rejection: a new
  /// fix and pre-check; inside (or with [overrideNote]) the rejected create
  /// op is requeued with the new point and time.
  Future<RetryOutcome> retryFromFarm(
    String visitId, {
    String? overrideNote,
  }) async {
    final detail = await _repo.detail(visitId);
    final op = await _repo.rejectedOp(visitId);
    if (detail == null || op == null) {
      return const RetryOutcome(RetryResult.nothingToRetry);
    }
    final pre = await precheck(farm: detail.farm, village: detail.village);
    final fix = pre.fix;
    final check = pre.check;
    if (fix == null || check == null) {
      return const RetryOutcome(RetryResult.noFix);
    }
    final note = overrideNote?.trim();
    if (!check.allowed && (note == null || note.isEmpty)) {
      return RetryOutcome(RetryResult.stillOutside, check: check);
    }
    final now = _now;
    final store = _outbox.store;
    final payload = <String, Object?>{
      ...SyncStore.payloadOf(op),
      'checkin_at': now.toIso8601String(),
      'checkin_point': fix.toPointJson(),
    };
    if (check.allowed) {
      payload.remove('override_note');
    } else {
      payload['override_note'] = note;
    }
    await store.setPayload(
      op.opId,
      payload,
      dependsOnUploadId: op.dependsOnUploadId,
    );
    await store.requeue(op.opId);
    await store.entities.merge(
      SyncEntities.visit,
      visitId,
      <String, Object?>{
        'checkin_at': payload['checkin_at'],
        'checkin_point': payload['checkin_point'],
        'override_note': payload['override_note'],
      },
      now: now,
      dirty: true,
    );
    await _repo.setPrecheck(visitId, check);
    await _repo.clearFailure(visitId);
    return RetryOutcome(RetryResult.retried, check: check);
  }

  // --- FA-016 ---------------------------------------------------------------

  Future<bool> _online() => ref.read(connectivityMonitorProvider).isOnline();

  /// Asks the farmer to confirm through [channel]. SMS OTP and QR need the
  /// network now; a push request made offline is queued on the device and
  /// sent by [flushQueuedConfirmations] when the network is back.
  Future<RequestOutcome> requestConfirmation(
    String visitId,
    ConfirmationChannel channel,
  ) async {
    if (!await _online()) {
      if (channel == ConfirmationChannel.appPush) {
        await _repo.upsertConfirmation(
          <String, Object?>{
            'id': _newId(),
            'visit_id': visitId,
            'channel': channel.wire,
            'requested_at': _now.toIso8601String(),
          },
          now: _now,
          status: ConfirmationStatuses.queued,
        );
        return const RequestOutcome(RequestResult.queuedOffline);
      }
      return const RequestOutcome(RequestResult.needsNetwork);
    }
    return _request(visitId, channel);
  }

  Future<RequestOutcome> _request(
    String visitId,
    ConfirmationChannel channel,
  ) async {
    final api = ref.read(visitConfirmApiProvider);
    final outcome = await api.request(visitId, channel);
    switch (outcome.result) {
      case ConfirmationRequestResult.ok:
        final confirmation = outcome.confirmation;
        if (confirmation != null) {
          await _repo.upsertConfirmation(
            confirmation,
            now: _now,
            token: outcome.token,
          );
        }
        return RequestOutcome(RequestResult.ok, api: outcome);
      case ConfirmationRequestResult.network:
        return RequestOutcome(RequestResult.needsNetwork, api: outcome);
      case ConfirmationRequestResult.notFound:
        return RequestOutcome(RequestResult.notSynced, api: outcome);
      case ConfirmationRequestResult.alreadyConfirmed:
        return RequestOutcome(RequestResult.alreadyConfirmed, api: outcome);
      case ConfirmationRequestResult.locked:
      case ConfirmationRequestResult.rateLimited:
      case ConfirmationRequestResult.channelInvalid:
        return RequestOutcome(RequestResult.refused, api: outcome);
    }
  }

  /// Sends the push requests queued while offline (call on reconnect and
  /// when A32 opens online). Requests whose check-in has not synced yet
  /// stay queued.
  Future<int> flushQueuedConfirmations() async {
    if (!await _online()) return 0;
    var sent = 0;
    for (final row in await _repo.queuedConfirmations()) {
      final channel = ConfirmationChannel.parse(row.channel);
      if (channel == null) continue;
      final outcome = await _request(row.visitId, channel);
      if (outcome.result == RequestResult.ok ||
          outcome.result == RequestResult.alreadyConfirmed ||
          outcome.result == RequestResult.refused) {
        await (_repo.db.delete(
          _repo.db.visitConfirmations,
        )..where((t) => t.id.equals(row.id))).go();
        if (outcome.result == RequestResult.ok) sent += 1;
      }
    }
    return sent;
  }

  /// Officer-side SMS OTP completion (online): on success the returned
  /// visit (confirmed_at, channel, version, confirmation rows) is applied
  /// locally.
  Future<OtpConfirmOutcome> confirmOtp(String visitId, String code) async {
    if (!await _online()) {
      return const OtpConfirmOutcome(OtpConfirmResult.network);
    }
    final outcome = await ref
        .read(visitConfirmApiProvider)
        .confirm(visitId, code);
    if (outcome.result == OtpConfirmResult.ok && outcome.visit != null) {
      await _repo.applyServerVisit(outcome.visit!, now: _now);
    }
    return outcome;
  }
}
