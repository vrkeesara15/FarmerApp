import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../db/app_database.dart';
import '../duty/duty_models.dart';
import '../geo/geo.dart';
import '../sync/local_entities.dart';
import '../sync/sync_models.dart';
import '../sync/sync_store.dart';
import 'visit_models.dart';
import 'visit_proof.dart';

/// The server's rejection of a queued check-in (`outside_geofence`, ...).
@immutable
class VisitFailure {
  /// Creates the failure.
  const VisitFailure({
    required this.code,
    required this.detail,
    this.distanceM,
    this.target,
    this.radiusM,
  });

  /// Parses the `failure_detail` JSON of a visit row.
  factory VisitFailure.fromRow(Visit row) {
    final raw = row.failureDetail == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(row.failureDetail!) as Map);
    return VisitFailure(
      code: row.failureCode ?? (raw['code'] as String?) ?? 'rejected',
      detail: (raw['detail'] as String?) ?? '',
      distanceM: (raw['distance_m'] as num?)?.toDouble(),
      target: raw['target'] as String?,
      radiusM: (raw['radius_m'] as num?)?.toDouble(),
    );
  }

  /// Problem code.
  final String code;

  /// Server detail text.
  final String detail;

  /// Distance to the nearest target (m), when the server sent it.
  final double? distanceM;

  /// `farm` | `meeting_point`.
  final String? target;

  /// Radius applied.
  final double? radiusM;

  /// The check-in was refused for being outside the geofence.
  bool get outsideGeofence => code == 'outside_geofence';

  @override
  bool operator ==(Object other) =>
      other is VisitFailure &&
      other.code == code &&
      other.detail == detail &&
      other.distanceM == distanceM;

  @override
  int get hashCode => Object.hash(code, detail, distanceM);
}

/// One A34 / A22 row.
@immutable
class VisitSummary {
  /// Creates the summary.
  const VisitSummary({
    required this.visit,
    required this.farmerName,
    required this.pendingSync,
    this.failure,
  });

  /// The row.
  final Visit visit;

  /// Farmer visited.
  final String farmerName;

  /// A queued op still references the visit (or its photos).
  final bool pendingSync;

  /// Rejected by the server.
  final VisitFailure? failure;

  /// Not checked out yet.
  bool get open => visit.checkoutAt == null;

  /// Check-in point.
  GeoPoint get checkinPoint => GeoPoint(visit.checkinLat, visit.checkinLon);

  @override
  bool operator ==(Object other) =>
      other is VisitSummary &&
      other.visit == visit &&
      other.farmerName == farmerName &&
      other.pendingSync == pendingSync &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(visit, farmerName, pendingSync, failure);
}

/// Everything A31 / A32 / A33 show for one visit.
@immutable
class VisitDetail {
  /// Creates the detail.
  const VisitDetail({
    required this.visit,
    required this.photos,
    required this.confirmations,
    required this.farmer,
    required this.farm,
    required this.village,
    required this.pendingSync,
    required this.settings,
    this.failure,
  });

  /// The row.
  final Visit visit;

  /// Photos taken during the visit, oldest first.
  final List<VisitPhoto> photos;

  /// Confirmation requests, oldest first.
  final List<VisitConfirmation> confirmations;

  /// Farmer visited.
  final Farmer? farmer;

  /// Farm (geofence target).
  final Farm? farm;

  /// Village (meeting point).
  final Village? village;

  /// A queued op still references the visit or one of its photos.
  final bool pendingSync;

  /// Tenant settings the proof uses.
  final VisitSettings settings;

  /// Rejected by the server.
  final VisitFailure? failure;

  /// Not checked out yet.
  bool get open => visit.checkoutAt == null;

  /// Confirmed through one channel (server-owned `confirmed_at`, or the
  /// confirmation row the OTP path wrote).
  bool get confirmed =>
      visit.confirmedAt != null ||
      confirmations.any((c) => c.status == ConfirmationStatuses.confirmed);

  /// The latest confirmation request, if any.
  VisitConfirmation? get latestConfirmation =>
      confirmations.isEmpty ? null : confirmations.last;

  /// The server has scored the visit (VV-004 stored).
  bool get serverScored => visit.score != null;

  /// Geofence result the checklist uses: the server's once known, else the
  /// client pre-check (`override` when checked in with a note).
  String get geofenceResult {
    final server = visit.geofenceResult;
    if (server != null) return server;
    if (visit.overrideNote != null && visit.precheckResult != 'inside') {
      return GeofenceResults.override;
    }
    return visit.precheckResult ?? GeofenceResults.outside;
  }

  /// Client pre-check as recorded at check-in.
  GeofenceCheck? get precheck => visit.precheckResult == null
      ? null
      : GeofenceCheck.fromJson(<String, Object?>{
          'result': visit.precheckResult,
          'distance_m': visit.precheckDistanceM,
          'target': visit.precheckTarget,
          'radius_m': visit.precheckRadiusM,
        });

  /// Check-in point.
  GeoPoint get checkinPoint => GeoPoint(visit.checkinLat, visit.checkinLon);

  /// FA-028 snapshot recorded at check-in.
  IntegritySnapshot get integrity => IntegritySnapshot.fromJson(
    Map<String, Object?>.from(jsonDecode(visit.deviceIntegrity) as Map),
  );

  /// Server score components, when stored.
  Map<String, int>? get serverComponents => visit.scoreComponents == null
      ? null
      : <String, int>{
          for (final e in (jsonDecode(visit.scoreComponents!) as Map).entries)
            e.key as String: (e.value as num?)?.toInt() ?? 0,
        };

  /// Server flags (`under_minimum`).
  List<String> get flags =>
      (jsonDecode(visit.flags) as List<Object?>).cast<String>();

  /// Local expected proof at [now] (the server's twin, VV-004).
  VisitProof proofAt(DateTime now) => evaluateVisitProof(
    geofenceResult: geofenceResult,
    overrideApproved: visit.overrideApprovedBy != null,
    confirmed: confirmed,
    photos: <PhotoEvidence>[
      for (final p in photos)
        PhotoEvidence(
          takenInApp: p.takenInApp,
          exifTime: p.exifTime?.toUtc(),
          exifLat: p.exifLat,
          exifLon: p.exifLon,
        ),
    ],
    checkinAt: visit.checkinAt.toUtc(),
    checkoutAt: visit.checkoutAt?.toUtc(),
    now: now,
    checkinPoint: checkinPoint,
    minDurationS: settings.minVisitDurationS,
    integrity: integrity,
  );

  @override
  bool operator ==(Object other) =>
      other is VisitDetail &&
      other.visit == visit &&
      listEquals(other.photos, photos) &&
      listEquals(other.confirmations, confirmations) &&
      other.farmer == farmer &&
      other.farm == farm &&
      other.village == village &&
      other.pendingSync == pendingSync &&
      other.settings == settings &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(
    visit,
    Object.hashAll(photos),
    Object.hashAll(confirmations),
    pendingSync,
    failure,
  );
}

/// Visits, photos and confirmations from the local Drift tables
/// (FA-014 .. FA-017, works offline).
class VisitRepository {
  /// Creates the repository over [db].
  VisitRepository(this.db);

  /// The database.
  final AppDatabase db;

  /// [load] now and after every write to [tables] (see
  /// `DutyRepository._poll` for why a controller and not `async*`).
  Stream<T> _poll<T>(
    Future<T> Function() load,
    Iterable<TableInfo<Table, Object?>> tables,
  ) {
    late final StreamController<T> controller;
    StreamSubscription<void>? updates;
    Future<void> emit() async {
      try {
        final value = await load();
        if (!controller.isClosed) controller.add(value);
      } on Object catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        unawaited(emit());
        updates = db
            .tableUpdates(TableUpdateQuery.onAllTables(tables))
            .listen((_) => unawaited(emit()));
      },
      onCancel: () async {
        await updates?.cancel();
        updates = null;
      },
    );
    return controller.stream;
  }

  List<TableInfo<Table, Object?>> get _detailTables =>
      <TableInfo<Table, Object?>>[
        db.visits,
        db.visitPhotos,
        db.visitConfirmations,
        db.outboxTable,
        db.farmers,
        db.farms,
        db.villages,
        db.kv,
      ];

  // --- settings -----------------------------------------------------------

  /// Tenant settings cached in `kv` (defaults until a pull stores them).
  Future<VisitSettings> settings() async {
    final raw = await db.getValue(VisitSettings.kvKey);
    if (raw == null) return const VisitSettings();
    try {
      return VisitSettings.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } on FormatException {
      return const VisitSettings();
    }
  }

  /// Caches [settings].
  Future<void> saveSettings(VisitSettings settings) =>
      db.setValue(VisitSettings.kvKey, jsonEncode(settings.toJson()));

  // --- reads --------------------------------------------------------------

  /// One visit row.
  Future<Visit?> visit(String id) =>
      (db.select(db.visits)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Photos of [visitId], oldest first (not tombstoned).
  Future<List<VisitPhoto>> photos(String visitId) =>
      (db.select(db.visitPhotos)
            ..where((t) => t.visitId.equals(visitId) & t.deleted.equals(false))
            ..orderBy(<OrderingTerm Function($VisitPhotosTable)>[
              (t) => OrderingTerm.asc(t.updatedAt),
            ]))
          .get();

  /// Confirmations of [visitId], oldest first.
  Future<List<VisitConfirmation>> confirmations(String visitId) =>
      (db.select(db.visitConfirmations)
            ..where((t) => t.visitId.equals(visitId))
            ..orderBy(<OrderingTerm Function($VisitConfirmationsTable)>[
              (t) => OrderingTerm.asc(t.updatedAt),
            ]))
          .get();

  Future<bool> _pending(String visitId, List<VisitPhoto> photos) async {
    final ids = <String>[visitId, for (final p in photos) p.id];
    final rows =
        await (db.select(db.outboxTable)..where(
              (t) =>
                  t.entityId.isIn(ids) &
                  t.state.isIn(<String>['queued', 'sending']),
            ))
            .get();
    return rows.isNotEmpty;
  }

  /// A31 / A33 detail, or `null` when unknown.
  Future<VisitDetail?> detail(String id) async {
    final row = await visit(id);
    if (row == null) return null;
    final farmer = await (db.select(
      db.farmers,
    )..where((t) => t.id.equals(row.farmerId))).getSingleOrNull();
    final farm = row.farmId == null
        ? null
        : await (db.select(
            db.farms,
          )..where((t) => t.id.equals(row.farmId!))).getSingleOrNull();
    final villageId = row.villageId ?? farmer?.villageId;
    final village = villageId == null
        ? null
        : await (db.select(
            db.villages,
          )..where((t) => t.id.equals(villageId))).getSingleOrNull();
    final photoRows = await photos(id);
    return VisitDetail(
      visit: row,
      photos: photoRows,
      confirmations: await confirmations(id),
      farmer: farmer,
      farm: farm,
      village: village,
      pendingSync: await _pending(id, photoRows),
      settings: await settings(),
      failure: row.failureCode == null ? null : VisitFailure.fromRow(row),
    );
  }

  /// [detail], live.
  Stream<VisitDetail?> watchDetail(String id) =>
      _poll(() => detail(id), _detailTables);

  /// The visit still open on this device (latest check-in), if any.
  Future<Visit?> openVisit() =>
      (db.select(db.visits)
            ..where(
              (t) =>
                  t.checkoutAt.isNull() &
                  t.deleted.equals(false) &
                  t.failureCode.isNull(),
            )
            ..orderBy(<OrderingTerm Function($VisitsTable)>[
              (t) => OrderingTerm.desc(t.checkinAt),
            ])
            ..limit(1))
          .getSingleOrNull();

  Future<List<VisitSummary>> _summaries(List<Visit> rows) async {
    if (rows.isEmpty) return const <VisitSummary>[];
    final farmerIds = rows.map((v) => v.farmerId).toSet();
    final farmers = <String, Farmer>{
      for (final f in await (db.select(
        db.farmers,
      )..where((t) => t.id.isIn(farmerIds))).get())
        f.id: f,
    };
    final ids = rows.map((v) => v.id).toSet();
    final photoRows = await (db.select(
      db.visitPhotos,
    )..where((t) => t.visitId.isIn(ids))).get();
    final entityIds = <String>{...ids, for (final p in photoRows) p.id};
    final pendingOps =
        await (db.select(db.outboxTable)..where(
              (t) =>
                  t.entityId.isIn(entityIds) &
                  t.state.isIn(<String>['queued', 'sending']),
            ))
            .get();
    final pendingIds = <String>{
      for (final op in pendingOps)
        op.entity == SyncEntities.visitPhoto
            ? photoRows.firstWhere((p) => p.id == op.entityId).visitId
            : op.entityId,
    };
    return <VisitSummary>[
      for (final v in rows)
        VisitSummary(
          visit: v,
          farmerName: farmers[v.farmerId]?.name ?? '',
          pendingSync: pendingIds.contains(v.id),
          failure: v.failureCode == null ? null : VisitFailure.fromRow(v),
        ),
    ];
  }

  /// Visits checked in within `[from, to)`, newest first; [status] filters
  /// on the server status (`open` matches visits not checked out yet).
  Future<List<VisitSummary>> visitsBetween(
    DateTime from,
    DateTime to, {
    String? status,
  }) async {
    final rows =
        await (db.select(db.visits)
              ..where(
                (t) =>
                    t.checkinAt.isBiggerOrEqualValue(from) &
                    t.checkinAt.isSmallerThanValue(to) &
                    t.deleted.equals(false),
              )
              ..orderBy(<OrderingTerm Function($VisitsTable)>[
                (t) => OrderingTerm.desc(t.checkinAt),
              ]))
            .get();
    final filtered = status == null
        ? rows
        : rows.where((v) {
            if (status == VisitStatuses.open) return v.checkoutAt == null;
            return v.status == status;
          }).toList();
    return _summaries(filtered);
  }

  /// [visitsBetween], live.
  Stream<List<VisitSummary>> watchVisitsBetween(
    DateTime from,
    DateTime to, {
    String? status,
  }) => _poll(
    () => visitsBetween(from, to, status: status),
    <TableInfo<Table, Object?>>[
      db.visits,
      db.visitPhotos,
      db.outboxTable,
      db.farmers,
    ],
  );

  /// Visits of [farmerId], newest first (A22 Visits tab).
  Future<List<VisitSummary>> visitsOfFarmer(String farmerId) async {
    final rows =
        await (db.select(db.visits)
              ..where(
                (t) => t.farmerId.equals(farmerId) & t.deleted.equals(false),
              )
              ..orderBy(<OrderingTerm Function($VisitsTable)>[
                (t) => OrderingTerm.desc(t.checkinAt),
              ]))
            .get();
    return _summaries(rows);
  }

  /// [visitsOfFarmer], live.
  Stream<List<VisitSummary>> watchVisitsOfFarmer(String farmerId) =>
      _poll(() => visitsOfFarmer(farmerId), <TableInfo<Table, Object?>>[
        db.visits,
        db.visitPhotos,
        db.outboxTable,
        db.farmers,
      ]);

  /// Verified visits checked in within `[from, to)` (A10 tile).
  Future<int> verifiedCount(DateTime from, DateTime to) async {
    final rows =
        await (db.select(db.visits)..where(
              (t) =>
                  t.checkinAt.isBiggerOrEqualValue(from) &
                  t.checkinAt.isSmallerThanValue(to) &
                  t.status.equals(VisitStatuses.verified) &
                  t.deleted.equals(false),
            ))
            .get();
    return rows.length;
  }

  /// [verifiedCount], live.
  Stream<int> watchVerifiedCount(DateTime from, DateTime to) => _poll(
    () => verifiedCount(from, to),
    <TableInfo<Table, Object?>>[db.visits],
  );

  // --- local writes (no op) -----------------------------------------------

  /// Records the client-side VV-003 decision on the row.
  Future<void> setPrecheck(String id, GeofenceCheck check) =>
      (db.update(db.visits)..where((t) => t.id.equals(id))).write(
        VisitsCompanion(
          precheckResult: Value<String?>(check.wire),
          precheckDistanceM: Value<double?>(check.distanceM),
          precheckTarget: Value<String?>(check.target),
          precheckRadiusM: Value<double?>(check.radiusM),
        ),
      );

  /// Clears a server rejection after the officer retried from the farm.
  Future<void> clearFailure(String id) =>
      (db.update(db.visits)..where((t) => t.id.equals(id))).write(
        const VisitsCompanion(
          failureCode: Value<String?>(null),
          failureDetail: Value<String?>(null),
        ),
      );

  /// Records the local file of a photo row (thumbnail).
  Future<void> setPhotoPath(String photoId, String path) =>
      (db.update(db.visitPhotos)..where((t) => t.id.equals(photoId))).write(
        VisitPhotosCompanion(localPath: Value<String?>(path)),
      );

  /// Upserts a confirmation row from the server's `VisitConfirmationOut`
  /// (or a local placeholder) keeping the QR [token] on the device.
  Future<void> upsertConfirmation(
    Map<String, Object?> data, {
    required DateTime now,
    String? token,
    String? status,
    int? version,
  }) async {
    final id = data['id']! as String;
    final entities = LocalEntities(db);
    final existing = await entities.read(SyncEntities.visitConfirmation, id);
    final merged = <String, Object?>{
      ...?existing?.data,
      ...data,
      'status': ?status,
      LocalEntities.localKey: <String, Object?>{
        'token':
            token ??
            ((existing?.data[LocalEntities.localKey] as Map?)?['token']
                as String?),
      },
    };
    await entities.write(
      SyncEntities.visitConfirmation,
      id,
      merged,
      version: version ?? (data['version'] as num?)?.toInt() ?? 0,
      dirty: false,
      now: now,
    );
  }

  /// Applies a `VisitDetailOut` the officer-side OTP confirmation returned:
  /// server fields on the visit row (version included, so the next update
  /// op is based on it) and the confirmation rows.
  Future<void> applyServerVisit(
    Map<String, Object?> detail, {
    required DateTime now,
  }) async {
    final id = detail['id'] as String?;
    if (id == null) return;
    final entities = LocalEntities(db);
    final existing = await entities.read(SyncEntities.visit, id);
    final patch = <String, Object?>{
      for (final e in detail.entries)
        if (e.key != 'photos' && e.key != 'confirmations') e.key: e.value,
    };
    await entities.merge(
      SyncEntities.visit,
      id,
      patch,
      now: now,
      version: (detail['version'] as num?)?.toInt() ?? existing?.version,
    );
    final confirmations = detail['confirmations'];
    if (confirmations is List) {
      for (final c in confirmations) {
        if (c is Map) {
          await upsertConfirmation(Map<String, Object?>.from(c), now: now);
        }
      }
    }
  }

  /// Confirmation rows requested while offline (`queued`), oldest first.
  Future<List<VisitConfirmation>> queuedConfirmations() =>
      (db.select(db.visitConfirmations)
            ..where((t) => t.status.equals(ConfirmationStatuses.queued))
            ..orderBy(<OrderingTerm Function($VisitConfirmationsTable)>[
              (t) => OrderingTerm.asc(t.updatedAt),
            ]))
          .get();

  /// The rejected outbox op of [visitId], if any.
  Future<OutboxRow?> rejectedOp(String visitId) =>
      (db.select(db.outboxTable)
            ..where(
              (t) =>
                  t.entityId.equals(visitId) &
                  t.state.equals(OutboxState.rejected.name),
            )
            ..orderBy(<OrderingTerm Function($OutboxTableTable)>[
              (t) => OrderingTerm.asc(t.seq),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// Decoded error of [row].
  static SyncError? errorOf(OutboxRow row) => SyncStore.errorOf(row);
}
