import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../db/app_database.dart';
import '../geo/geo.dart';
import '../sync/sync_models.dart';
import 'duty_models.dart';

/// One session on A12.
@immutable
class DutySessionSummary {
  /// Creates the summary.
  const DutySessionSummary({
    required this.session,
    required this.pointsPending,
    required this.pointsAccepted,
    required this.pointsRejected,
    required this.distanceM,
  });

  /// The row.
  final DutySession session;

  /// Points still in the buffer.
  final int pointsPending;

  /// Points the server accepted (from `location_batch` results).
  final int pointsAccepted;

  /// Points the server rejected.
  final int pointsRejected;

  /// Client km estimate in metres (haversine over the day's points).
  final double distanceM;

  /// Still on duty.
  bool get active => session.endAt == null;

  @override
  bool operator ==(Object other) =>
      other is DutySessionSummary &&
      other.session == session &&
      other.pointsPending == pointsPending &&
      other.pointsAccepted == pointsAccepted &&
      other.pointsRejected == pointsRejected &&
      other.distanceM == distanceM;

  @override
  int get hashCode =>
      Object.hash(session, pointsPending, pointsAccepted, distanceM);
}

/// Everything A12 shows for one day.
@immutable
class MyDay {
  /// Creates the view.
  const MyDay({
    required this.sessions,
    required this.track,
    required this.distanceM,
    required this.pointsPending,
    required this.pointsAccepted,
  });

  /// Sessions started that day, earliest first.
  final List<DutySessionSummary> sessions;

  /// Points of the day in time order (for the map).
  final List<GeoPoint> track;

  /// Total client km estimate in metres.
  final double distanceM;

  /// Points waiting for upload.
  final int pointsPending;

  /// Points the server accepted.
  final int pointsAccepted;

  /// Nothing recorded yet.
  bool get isEmpty => sessions.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is MyDay &&
      listEquals(other.sessions, sessions) &&
      listEquals(other.track, track) &&
      other.distanceM == distanceM &&
      other.pointsPending == pointsPending &&
      other.pointsAccepted == pointsAccepted;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(sessions),
    track.length,
    distanceM,
    pointsPending,
    pointsAccepted,
  );
}

/// Duty sessions and the location buffer (FA-010, VV-001, A12).
class DutyRepository {
  /// Creates the repository over [db].
  DutyRepository(this.db);

  /// The database.
  final AppDatabase db;

  /// The session still open on this device, if any (latest start).
  Future<DutySession?> activeSession() =>
      (db.select(db.dutySessions)
            ..where((t) => t.endAt.isNull() & t.deleted.equals(false))
            ..orderBy(<OrderingTerm Function($DutySessionsTable)>[
              (t) => OrderingTerm.desc(t.startAt),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// One session.
  Future<DutySession?> session(String id) => (db.select(
    db.dutySessions,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// [load] now and after every write to [tables]. Built on a controller
  /// rather than `async*` so cancelling takes effect at once (an `async*`
  /// generator parked on `await for` only notices a cancel at its next
  /// yield, which would stall `DutyController` while ending a session), and
  /// without Drift's query-stream cache so widget tests end with no pending
  /// timers.
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

  /// The session row now and after every change.
  Stream<DutySession?> watchSession(String id) =>
      _poll(() => session(id), <TableInfo<Table, Object?>>[db.dutySessions]);

  /// Outbox rows of [entityId], live (the duty create op's rejection).
  Stream<List<OutboxRow>> watchOps(String entityId) => _poll(
    () => (db.select(
      db.outboxTable,
    )..where((t) => t.entityId.equals(entityId))).get(),
    <TableInfo<Table, Object?>>[db.outboxTable],
  );

  /// Sessions started in `[from, to)`, earliest first.
  Future<List<DutySession>> sessionsBetween(DateTime from, DateTime to) =>
      (db.select(db.dutySessions)
            ..where(
              (t) =>
                  t.startAt.isBiggerOrEqualValue(from) &
                  t.startAt.isSmallerThanValue(to) &
                  t.deleted.equals(false),
            )
            ..orderBy(<OrderingTerm Function($DutySessionsTable)>[
              (t) => OrderingTerm.asc(t.startAt),
            ]))
          .get();

  /// Marks a session ended locally without an op (rejected start).
  Future<void> markEnded(
    String id, {
    required DateTime endAt,
    required DutyEndReason reason,
  }) => (db.update(db.dutySessions)..where((t) => t.id.equals(id))).write(
    DutySessionsCompanion(
      endAt: Value<DateTime?>(endAt),
      endReason: Value<String?>(reason.wire),
      updatedAt: Value<DateTime>(endAt),
    ),
  );

  /// Adds [metres] to the session's client distance estimate.
  Future<void> addDistance(String id, double metres) async {
    final row = await session(id);
    if (row == null) return;
    await (db.update(db.dutySessions)..where((t) => t.id.equals(id))).write(
      DutySessionsCompanion(distanceM: Value<double>(row.distanceM + metres)),
    );
  }

  // --- buffer -------------------------------------------------------------

  /// Appends a point; only the controller calls this, only while on duty.
  Future<int> insertPoint({
    required String sessionId,
    required LocationFix fix,
    required IntegritySnapshot integrity,
    int? batteryPct,
  }) => db
      .into(db.locationBuffer)
      .insert(
        LocationBufferCompanion.insert(
          sessionId: sessionId,
          ts: fix.time.toUtc(),
          lat: fix.point.latitude,
          lon: fix.point.longitude,
          accuracyM: fix.accuracyM,
          speedMps: Value<double?>(fix.speedMps),
          bearing: Value<double?>(fix.bearing),
          batteryPct: Value<int?>(batteryPct),
          isMock: Value<bool>(integrity.isMock),
          isRooted: Value<bool>(integrity.isRooted),
          clockDriftS: Value<int?>(integrity.clockDriftS),
          provider: Value<String?>(fix.provider),
        ),
      );

  /// Points of [sessionId] not yet in a batch, oldest first, at most [limit].
  Future<List<LocationBufferRow>> pendingPoints(
    String sessionId, {
    int limit = maxPointsPerBatch,
  }) =>
      (db.select(db.locationBuffer)
            ..where((t) => t.sessionId.equals(sessionId) & t.batchId.isNull())
            ..orderBy(<OrderingTerm Function($LocationBufferTable)>[
              (t) => OrderingTerm.asc(t.ts),
              (t) => OrderingTerm.asc(t.id),
            ])
            ..limit(limit))
          .get();

  /// Number of points of [sessionId] not yet in a batch.
  Future<int> pendingCount(String sessionId) async {
    final count = db.locationBuffer.id.count();
    final row =
        await (db.selectOnly(db.locationBuffer)
              ..addColumns(<Expression<Object>>[count])
              ..where(
                db.locationBuffer.sessionId.equals(sessionId) &
                    db.locationBuffer.batchId.isNull(),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Last point of [sessionId] (for the cadence after a restart).
  Future<LocationBufferRow?> lastPoint(String sessionId) =>
      (db.select(db.locationBuffer)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy(<OrderingTerm Function($LocationBufferTable)>[
              (t) => OrderingTerm.desc(t.ts),
              (t) => OrderingTerm.desc(t.id),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// Stamps [ids] with the batch they went out in.
  Future<void> markBatched(List<int> ids, String batchId) =>
      (db.update(db.locationBuffer)..where((t) => t.id.isIn(ids))).write(
        LocationBufferCompanion(batchId: Value<String?>(batchId)),
      );

  /// All points of [sessionIds] in time order (A12 track, km).
  Future<List<LocationBufferRow>> pointsOf(Iterable<String> sessionIds) =>
      (db.select(db.locationBuffer)
            ..where((t) => t.sessionId.isIn(sessionIds))
            ..orderBy(<OrderingTerm Function($LocationBufferTable)>[
              (t) => OrderingTerm.asc(t.ts),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  /// Drops batched points older than [before] (the day's points stay for
  /// A12; un-batched points are never dropped).
  Future<int> purgeBatchedBefore(DateTime before) =>
      (db.delete(db.locationBuffer)..where(
            (t) => t.batchId.isNotNull() & t.ts.isSmallerThanValue(before),
          ))
          .go();

  /// Wire shape of a buffered point (VV-002 fields).
  static Map<String, Object?> pointJson(LocationBufferRow r) =>
      <String, Object?>{
        'ts': r.ts.toUtc().toIso8601String(),
        'lat': r.lat,
        'lon': r.lon,
        'accuracy_m': r.accuracyM,
        'speed_mps': r.speedMps,
        'bearing': r.bearing,
        'battery_pct': r.batteryPct,
        'is_mock': r.isMock,
        'is_rooted': r.isRooted,
        'clock_drift_s': r.clockDriftS,
        'provider': r.provider,
      };

  // --- batches ------------------------------------------------------------

  /// `location_batch` docs of [sessionId] (server counts once applied).
  Future<List<Map<String, Object?>>> batchesOf(String sessionId) async {
    final rows = await (db.select(
      db.syncDocs,
    )..where((t) => t.entity.equals(SyncEntities.locationBatch))).get();
    return <Map<String, Object?>>[
      for (final r in rows)
        if ((jsonDecode(r.data) as Map)['duty_session_id'] == sessionId)
          Map<String, Object?>.from(jsonDecode(r.data) as Map),
    ];
  }

  /// Drops applied batch docs older than [before].
  Future<int> purgeBatchDocsBefore(DateTime before) =>
      (db.delete(db.syncDocs)..where(
            (t) =>
                t.entity.equals(SyncEntities.locationBatch) &
                t.dirty.equals(false) &
                t.updatedAt.isSmallerThanValue(before),
          ))
          .go();

  // --- A10 ----------------------------------------------------------------

  /// Farmers captured in `[from, to)` (A10 "Farmers added" tile), live.
  Stream<int> watchFarmersAdded(DateTime from, DateTime to) => _poll(
    () async =>
        (await (db.select(db.farmers)..where(
                  (t) =>
                      t.updatedAt.isBiggerOrEqualValue(from) &
                      t.updatedAt.isSmallerThanValue(to) &
                      t.deleted.equals(false),
                ))
                .get())
            .length,
    <TableInfo<Table, Object?>>[db.farmers],
  );

  // --- A12 ----------------------------------------------------------------

  /// The day `[from, to)` as A12 shows it.
  Future<MyDay> day(DateTime from, DateTime to) async {
    final sessions = await sessionsBetween(from, to);
    final points = await pointsOf(sessions.map((s) => s.id));
    final summaries = <DutySessionSummary>[];
    var totalDistance = 0.0;
    var totalPending = 0;
    var totalAccepted = 0;
    for (final s in sessions) {
      final own = points.where((p) => p.sessionId == s.id).toList();
      var distance = 0.0;
      for (var i = 1; i < own.length; i++) {
        distance += distanceMetres(
          GeoPoint(own[i - 1].lat, own[i - 1].lon),
          GeoPoint(own[i].lat, own[i].lon),
        );
      }
      final pending = own.where((p) => p.batchId == null).length;
      var accepted = 0;
      var rejected = 0;
      for (final b in await batchesOf(s.id)) {
        accepted += (b['accepted'] as num?)?.toInt() ?? 0;
        final r = b['rejected'];
        rejected += r is List ? r.length : (r as num?)?.toInt() ?? 0;
      }
      summaries.add(
        DutySessionSummary(
          session: s,
          pointsPending: pending,
          pointsAccepted: accepted,
          pointsRejected: rejected,
          distanceM: distance,
        ),
      );
      totalDistance += distance;
      totalPending += pending;
      totalAccepted += accepted;
    }
    return MyDay(
      sessions: summaries,
      track: <GeoPoint>[for (final p in points) GeoPoint(p.lat, p.lon)],
      distanceM: totalDistance,
      pointsPending: totalPending,
      pointsAccepted: totalAccepted,
    );
  }

  /// [day] now and after every change.
  Stream<MyDay> watchDay(DateTime from, DateTime to) =>
      _poll(() => day(from, to), <TableInfo<Table, Object?>>[
        db.dutySessions,
        db.locationBuffer,
        db.syncDocs,
      ]);
}
