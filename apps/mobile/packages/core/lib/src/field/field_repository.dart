import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../kisan/kisan_cache.dart' show watchTables;
import '../sync/local_entities.dart';
import '../sync/outbox.dart';
import '../utils/format.dart';
import 'field_api.dart';
import 'field_models.dart';

/// `kv` key prefix of the M7 officer screen caches (A12, A60, A61, A62).
/// They are read-only server views, so they are cached as JSON blobs rather
/// than as sync entities.
const String fieldCachePrefix = 'field.';

/// Upload purpose of an A61 receipt photo (NF-004 pipeline).
const String receiptUploadPurpose = 'travel_receipt';

/// Upload purpose of an A36 stage photo.
const String demoPhotoUploadPurpose = 'demo_plot';

/// A cached server view plus when it was fetched ("as of ..." on screen).
class CachedView<T> {
  /// Creates the wrapper.
  const CachedView(this.value, {this.asOf, this.stale = false});

  /// The view; null when nothing has been fetched yet.
  final T? value;

  /// When the cache was written (UTC).
  final DateTime? asOf;

  /// The last refresh failed; [value] is the older copy.
  final bool stale;

  /// Nothing to show at all.
  bool get isEmpty => value == null;
}

/// Everything the M7 officer screens read and write: A11 beat plan, A12 day
/// timeline, A13 inbox, A35 meetings, A36 demo plots, A60 performance,
/// A61 travel allowance and A62 my flags.
///
/// Reads are cached (A12 / A60 / A61 / A62 in `kv`, the sync entities in
/// `sync_docs`) so every screen opens offline; writes go through the outbox
/// except the two the server must arbitrate live — the attendance OTP
/// (FA-016-style) and a flag explanation (VA-005).
class FieldRepository {
  /// Creates the repository.
  FieldRepository({
    required this.db,
    required this.api,
    required this.outbox,
    DateTime Function()? clock,
    String Function()? ids,
  }) : _now = clock ?? (() => DateTime.now().toUtc()),
       _newId = ids ?? (() => DateTime.now().microsecondsSinceEpoch.toString());

  /// Local database.
  final AppDatabase db;

  /// Server endpoints.
  final FieldApi api;

  /// Queue for offline writes.
  final Outbox outbox;

  final DateTime Function() _now;
  final String Function() _newId;

  LocalEntities get _entities => outbox.store.entities;

  // --- caches ---------------------------------------------------------------

  Future<void> _writeCache(String key, Map<String, Object?> json) =>
      db.setValue(
        '$fieldCachePrefix$key',
        jsonEncode(<String, Object?>{
          'as_of': _now().toIso8601String(),
          'value': json,
        }),
      );

  Future<(Map<String, Object?>, DateTime)?> _readCache(String key) async {
    final raw = await db.getValue('$fieldCachePrefix$key');
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final value = decoded['value'];
    if (value is! Map) return null;
    return (
      Map<String, Object?>.from(value),
      DateTime.parse('${decoded['as_of']}').toUtc(),
    );
  }

  Future<List<Map<String, Object?>>> _docs(String entity) async {
    final rows = await (db.select(
      db.syncDocs,
    )..where((t) => t.entity.equals(entity) & t.deleted.equals(false))).get();
    return <Map<String, Object?>>[
      for (final r in rows)
        Map<String, Object?>.from(jsonDecode(r.data) as Map),
    ];
  }

  Stream<T> _watch<T>(
    Future<T> Function() load,
    List<TableInfo<Table, Object?>> tables,
  ) => watchTables(db, tables, load);

  // --- FA-007 inbox (A13) ---------------------------------------------------

  /// The inbox as stored locally (the `notification` sync entity), newest
  /// first, with the unread count.
  Future<Inbox> inbox() async {
    final items = <InboxItem>[
      for (final d in await _docs(FieldEntities.notification))
        InboxItem.fromJson(d),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Inbox(items: items, unread: items.where((i) => i.unread).length);
  }

  /// [inbox] now and after every change.
  Stream<Inbox> watchInbox() =>
      _watch(inbox, <TableInfo<Table, Object?>>[db.syncDocs]);

  /// Unread count only (the bottom-nav badge).
  Stream<int> watchUnread() =>
      watchInbox().map((i) => i.unread).asBroadcastStream();

  /// Pulls `GET /v1/notifications` into the local rows. Silently keeps the
  /// cache when the device is offline.
  Future<bool> refreshInbox() async {
    try {
      final fresh = await api.notifications();
      final now = _now();
      for (final item in fresh.items) {
        final existing = await _entities.read(
          FieldEntities.notification,
          item.id,
        );
        // A queued "mark read" must not be undone by the pull.
        if (existing != null && existing.dirty) continue;
        await _entities.write(
          FieldEntities.notification,
          item.id,
          item.toJson(),
          version: 1,
          dirty: false,
          now: now,
        );
      }
      return true;
    } on FieldUnavailableException {
      return false;
    }
  }

  /// Marks one row read (offline-safe: the op syncs later).
  Future<void> markRead(String id) async {
    final row = await _entities.read(FieldEntities.notification, id);
    if (row == null || row.data['read_at'] != null) return;
    await outbox.enqueueUpdate(
      FieldEntities.notification,
      id,
      <String, Object?>{'read_at': _now().toIso8601String()},
    );
  }

  /// Marks every unread row read.
  Future<int> markAllRead() async {
    final current = await inbox();
    var marked = 0;
    for (final item in current.items) {
      if (!item.unread) continue;
      await markRead(item.id);
      marked += 1;
    }
    return marked;
  }

  // --- FA-018 beat plan (A11) ----------------------------------------------

  /// The plan for [date] (`YYYY-MM-DD`) as stored locally, or null.
  Future<BeatPlan?> beat(String date) async {
    for (final d in await _docs(FieldEntities.beatPlan)) {
      if (d['plan_date'] == date) return BeatPlan.fromJson(d);
    }
    return null;
  }

  /// [beat] now and after every change.
  Stream<BeatPlan?> watchBeat(String date) =>
      _watch(() => beat(date), <TableInfo<Table, Object?>>[db.syncDocs]);

  /// Pulls `GET /v1/me/beat?date=`; keeps a locally edited plan.
  Future<bool> refreshBeat(String date) async {
    try {
      final fresh = await api.beat(date);
      if (fresh == null) return true;
      final existing = await _entities.read(FieldEntities.beatPlan, fresh.id);
      if (existing != null && existing.dirty) return true;
      await _entities.write(
        FieldEntities.beatPlan,
        fresh.id,
        fresh.toJson(),
        version: fresh.version,
        dirty: false,
        now: _now(),
      );
      return true;
    } on FieldUnavailableException {
      return false;
    }
  }

  /// Stores a reordered / edited plan and queues the `{items}` update.
  ///
  /// The op is queued first: `enqueueUpdate` merges its payload into the
  /// local row, and that payload is the server's `BeatItemIn` shape (ids
  /// only). Writing the full plan afterwards puts the names and reasons
  /// back, so the screen keeps rendering while the op waits.
  Future<void> saveBeat(BeatPlan plan) async {
    await outbox.enqueueUpdate(
      FieldEntities.beatPlan,
      plan.id,
      plan.toUpdate(),
    );
    await _entities.write(
      FieldEntities.beatPlan,
      plan.id,
      plan.toJson(),
      version: plan.version,
      dirty: true,
      now: _now(),
    );
  }

  // --- VV-008 my day (A12) --------------------------------------------------

  /// The day `date` from the cache, with the reasons queued here applied.
  Future<CachedView<DayTimeline>> day(String date) async {
    final cached = await _readCache('day.$date');
    if (cached == null) return const CachedView<DayTimeline>(null);
    var timeline = DayTimeline.fromJson(cached.$1);
    for (final d in await _docs(FieldEntities.trackGap)) {
      final reason = GapReason.parse(d['reason'] as String?);
      if (reason == null) continue;
      final id = '${d['id']}';
      for (final gap in timeline.gaps) {
        if (gap.id == id) {
          timeline = timeline.withGap(
            gap.withReason(reason, d['note'] as String?),
          );
        }
      }
    }
    return CachedView<DayTimeline>(timeline, asOf: cached.$2);
  }

  /// [day] now and after every change.
  Stream<CachedView<DayTimeline>> watchDay(String date) =>
      _watch(() => day(date), <TableInfo<Table, Object?>>[db.kv, db.syncDocs]);

  /// Pulls `GET /v1/me/day?date=` into the cache.
  Future<bool> refreshDay(String date) async {
    try {
      final fresh = await api.day(date);
      await _writeCache('day.$date', fresh.toJson());
      return true;
    } on FieldUnavailableException {
      return false;
    }
  }

  /// Records why the track has a hole (VV-008). Works offline: the op is a
  /// `track_gap` create (or update, when a reason was already given).
  Future<void> setGapReason(
    String gapId,
    GapReason reason, {
    String? note,
  }) async {
    final payload = <String, Object?>{
      'reason': reason.wire,
      if (note != null && note.isNotEmpty) 'note': note,
    };
    final existing = await _entities.read(FieldEntities.trackGap, gapId);
    if (existing == null) {
      await outbox.enqueueCreate(FieldEntities.trackGap, gapId, payload);
    } else {
      await outbox.enqueueUpdate(FieldEntities.trackGap, gapId, payload);
    }
  }

  // --- FA-024 my performance (A60) -----------------------------------------

  /// The cached performance for `[from, to]`, with the local trend.
  Future<CachedView<Performance>> performance({
    required String from,
    required String to,
  }) async {
    final cached = await _readCache('performance.$from.$to');
    if (cached == null) return const CachedView<Performance>(null);
    final targets = cached.$1['targets'];
    final base = Performance.fromJson(cached.$1).with2(
      targets: targets is Map
          ? PerformanceTargets.fromJson(Map<String, Object?>.from(targets))
          : null,
      trend: await verifiedVisitTrend(),
    );
    return CachedView<Performance>(base, asOf: cached.$2);
  }

  /// [performance] now and after every change.
  Stream<CachedView<Performance>> watchPerformance({
    required String from,
    required String to,
  }) => _watch(
    () => performance(from: from, to: to),
    <TableInfo<Table, Object?>>[db.kv, db.visits],
  );

  /// Pulls `GET /v1/me/performance` (with the month's targets).
  Future<bool> refreshPerformance({
    required String from,
    required String to,
  }) async {
    try {
      final fresh = await api.performance(from: from, to: to);
      await _writeCache('performance.$from.$to', <String, Object?>{
        ...fresh.toJson(),
        'targets': fresh.targets?.toJson(),
      });
      return true;
    } on FieldUnavailableException {
      return false;
    }
  }

  /// Verified visits per IST day over the trailing [days] days, oldest
  /// first — the A60 sparkline. Read from the device's own synced `visits`
  /// rows, so it renders offline and needs no extra endpoint.
  Future<List<int>> verifiedVisitTrend({int days = 14}) async {
    final now = _now();
    final todayIst = now.add(istOffset);
    final start = DateTime.utc(
      todayIst.year,
      todayIst.month,
      todayIst.day,
    ).subtract(istOffset + Duration(days: days - 1));
    final rows =
        await (db.select(db.visits)..where(
              (t) =>
                  t.checkinAt.isBiggerOrEqualValue(start) &
                  t.deleted.equals(false),
            ))
            .get();
    final buckets = List<int>.filled(days, 0);
    for (final v in rows) {
      if (v.status != 'verified') continue;
      final index = v.checkinAt
          .add(istOffset)
          .difference(start.add(istOffset))
          .inDays;
      if (index >= 0 && index < days) buckets[index] += 1;
    }
    return buckets;
  }

  // --- FA-023 travel allowance (A61) ---------------------------------------

  /// The month's statement from the cache, with the claims queued here
  /// merged in front of the server's.
  Future<CachedView<TravelStatement>> travel(String month) async {
    final cached = await _readCache('travel.$month');
    final queued = <TravelClaim>[
      for (final d in await _docs(FieldEntities.travelClaim))
        if ('${d['claim_date']}'.startsWith(month) && d['status'] == null)
          TravelClaim.fromJson(d),
    ]..sort((a, b) => b.claimDate.compareTo(a.claimDate));
    if (cached == null) {
      return queued.isEmpty
          ? const CachedView<TravelStatement>(null)
          : CachedView<TravelStatement>(
              TravelStatement(month: month, claims: queued),
            );
    }
    final statement = TravelStatement.fromJson(month, cached.$1);
    final ids = <String>{for (final c in queued) c.id};
    return CachedView<TravelStatement>(
      statement.withClaims(<TravelClaim>[
        ...queued,
        for (final c in statement.claims)
          if (!ids.contains(c.id)) c,
      ]),
      asOf: cached.$2,
    );
  }

  /// [travel] now and after every change.
  Stream<CachedView<TravelStatement>> watchTravel(String month) => _watch(
    () => travel(month),
    <TableInfo<Table, Object?>>[db.kv, db.syncDocs],
  );

  /// Pulls `GET /v1/travel/statement?month=`.
  Future<bool> refreshTravel(String month) async {
    try {
      final fresh = await api.travelStatement(month);
      await _writeCache('travel.$month', fresh.toJson());
      return true;
    } on FieldUnavailableException {
      return false;
    }
  }

  /// Queues an expense claim with its receipt photo (NF-004: the bytes are
  /// already processed). The claim op waits for the upload to finish.
  Future<String> addClaim({
    required String claimDate,
    required ClaimType type,
    required int amountPaise,
    required String receiptPath,
    required Uint8List receiptBytes,
    String? note,
  }) async {
    final uploadId = await outbox.enqueueUpload(
      filePath: receiptPath,
      bytes: receiptBytes,
      purpose: receiptUploadPurpose,
    );
    final id = _newId();
    final claim = TravelClaim(
      id: id,
      claimDate: claimDate,
      type: type,
      amountPaise: amountPaise,
      receiptUri: Outbox.uploadRef(uploadId),
      note: note,
    );
    await outbox.enqueueCreate(FieldEntities.travelClaim, id, claim.toCreate());
    return id;
  }

  // --- VA-005 my flags (A62) ------------------------------------------------

  /// The officer's own flags from the cache.
  Future<CachedView<List<MyFlag>>> flags() async {
    final cached = await _readCache('flags');
    if (cached == null) return const CachedView<List<MyFlag>>(null);
    final rows = cached.$1['items'];
    return CachedView<List<MyFlag>>(<MyFlag>[
      if (rows is List)
        for (final r in rows)
          if (r is Map) MyFlag.fromJson(Map<String, Object?>.from(r)),
    ], asOf: cached.$2);
  }

  /// [flags] now and after every change.
  Stream<CachedView<List<MyFlag>>> watchFlags() =>
      _watch(flags, <TableInfo<Table, Object?>>[db.kv]);

  /// Pulls `GET /v1/flags/mine`.
  Future<bool> refreshFlags() async {
    try {
      final fresh = await api.myFlags();
      await _writeCache('flags', <String, Object?>{
        'items': <Object?>[for (final f in fresh) f.toJson()],
      });
      return true;
    } on FieldUnavailableException {
      return false;
    }
  }

  /// Adds an explanation to an open flag. Needs connectivity: the server
  /// refuses one on a resolved flag (409 `flag_resolved`), so it is never
  /// queued blind.
  Future<MyFlag> explainFlag(String flagId, String body) async {
    final updated = await api.explainFlag(flagId, body);
    final current = await flags();
    await _writeCache('flags', <String, Object?>{
      'items': <Object?>[
        for (final f in current.value ?? const <MyFlag>[])
          (f.id == flagId ? updated : f).toJson(),
      ],
    });
    return updated;
  }

  // --- FA-027 meetings (A35) ------------------------------------------------

  /// Meetings stored locally, newest first.
  Future<List<Meeting>> meetings() async {
    final rows = <Meeting>[
      for (final d in await _docs(FieldEntities.farmerMeeting))
        Meeting.fromJson(d),
    ]..sort((a, b) => b.heldAt.compareTo(a.heldAt));
    final queued = await _docs(FieldEntities.meetingAttendance);
    final out = <Meeting>[];
    for (final m in rows) {
      final seen = <String>{for (final a in m.attendance) a.farmerId};
      final merged = <MeetingAttendee>[...m.attendance];
      for (final a in queued) {
        if (a['meeting_id'] != m.id) continue;
        // A farmer attends once (the server returns the first row for a
        // repeat); a QR scan carries no farmer id until the op syncs.
        final farmerId = '${a['farmer_id'] ?? ''}';
        if (farmerId.isNotEmpty && !seen.add(farmerId)) continue;
        merged.add(
          MeetingAttendee.fromJson(<String, Object?>{...a, '_pending': true}),
        );
      }
      out.add(m.copyWith(attendance: merged));
    }
    return out;
  }

  /// [meetings] now and after every change.
  Stream<List<Meeting>> watchMeetings() =>
      _watch(meetings, <TableInfo<Table, Object?>>[db.syncDocs]);

  /// One meeting, live.
  Stream<Meeting?> watchMeeting(String id) =>
      watchMeetings().map((all) => all.where((m) => m.id == id).firstOrNull);

  /// Pulls `GET /v1/meetings` into the local rows.
  Future<bool> refreshMeetings() async {
    try {
      final now = _now();
      for (final m in await api.meetings()) {
        final existing = await _entities.read(
          FieldEntities.farmerMeeting,
          m.id,
        );
        if (existing != null && existing.dirty) continue;
        final detail = await api.meeting(m.id);
        await _entities.write(
          FieldEntities.farmerMeeting,
          m.id,
          detail.toJson(),
          version: 1,
          dirty: false,
          now: now,
        );
      }
      return true;
    } on FieldUnavailableException {
      return false;
    }
  }

  /// Creates a meeting at the village meeting point (offline-capable; the
  /// server re-evaluates the geofence when the op syncs).
  Future<Meeting> createMeeting({
    required String villageId,
    String? villageName,
    required String topic,
    required double lat,
    required double lon,
    double? accuracyM,
  }) async {
    final id = _newId();
    final heldAt = _now();
    final meeting = Meeting(
      id: id,
      villageId: villageId,
      villageName: villageName,
      topic: topic,
      heldAt: heldAt,
      pending: true,
    );
    await outbox.enqueueCreate(
      FieldEntities.farmerMeeting,
      id,
      <String, Object?>{
        'village_id': villageId,
        'topic': topic,
        'held_at': heldAt.toIso8601String(),
        'checkin_point': <String, Object?>{
          'lat': lat,
          'lon': lon,
          'accuracy_m': ?accuracyM,
        },
      },
      local: <String, Object?>{'village_name': villageName, '_pending': true},
    );
    await _entities.write(
      FieldEntities.farmerMeeting,
      id,
      meeting.toJson(),
      version: 0,
      dirty: true,
      now: heldAt,
    );
    return meeting;
  }

  /// Sends the farmer an attendance OTP (needs connectivity).
  Future<String> sendAttendanceOtp(String meetingId, String farmerId) =>
      api.sendAttendanceOtp(meetingId, farmerId);

  /// Records attendance. `method: otp` carries the code the farmer read
  /// out; `method: qr` carries the farmer app's signed token and works
  /// offline (the server validates it against the scan time).
  Future<MeetingAttendee> addAttendance({
    required String meetingId,
    required AttendanceMethod method,
    String? farmerId,
    String? farmerName,
    String? code,
    String? token,
  }) async {
    final id = _newId();
    final at = _now();
    await outbox.enqueueCreate(
      FieldEntities.meetingAttendance,
      id,
      <String, Object?>{
        'meeting_id': meetingId,
        'method': method.name,
        'farmer_id': ?farmerId,
        'code': ?code,
        'token': ?token,
        'recorded_at': at.toIso8601String(),
      },
      local: <String, Object?>{'farmer_name': farmerName},
    );
    await _entities.write(
      FieldEntities.meetingAttendance,
      id,
      <String, Object?>{
        'id': id,
        'meeting_id': meetingId,
        'farmer_id': farmerId ?? '',
        'farmer_name': farmerName,
        'method': method.name,
        'recorded_at': at.toIso8601String(),
      },
      version: 0,
      dirty: true,
      now: at,
    );
    return MeetingAttendee(
      id: id,
      farmerId: farmerId ?? '',
      farmerName: farmerName,
      method: method,
      recordedAt: at,
      pending: true,
    );
  }

  /// Closes the meeting (attendance stops).
  Future<void> closeMeeting(String id) async {
    final current = (await meetings()).where((m) => m.id == id).firstOrNull;
    if (current == null || !current.open) return;
    await _entities.write(
      FieldEntities.farmerMeeting,
      id,
      current.copyWith(status: 'closed').toJson(),
      version: 0,
      dirty: true,
      now: _now(),
    );
    await outbox.enqueueUpdate(
      FieldEntities.farmerMeeting,
      id,
      <String, Object?>{'status': 'closed'},
    );
  }

  // --- FA-026 demo plots (A36) ---------------------------------------------

  /// Demo plots stored locally, newest first.
  Future<List<DemoPlot>> demoPlots() async {
    final plots = <DemoPlot>[
      for (final d in await _docs(FieldEntities.demoPlot)) DemoPlot.fromJson(d),
    ];
    final queued = await _docs(FieldEntities.demoObservation);
    return <DemoPlot>[
      for (final p in plots)
        p.copyWith(
          observations: <DemoObservation>[
            ...p.observations,
            for (final o in queued)
              if (o['demo_plot_id'] == p.id &&
                  !p.observations.any((x) => x.id == o['id']))
                DemoObservation.fromJson(<String, Object?>{
                  ...o,
                  '_pending': true,
                }),
          ]..sort((a, b) => a.observedAt.compareTo(b.observedAt)),
        ),
    ];
  }

  /// [demoPlots] now and after every change.
  Stream<List<DemoPlot>> watchDemoPlots() =>
      _watch(demoPlots, <TableInfo<Table, Object?>>[db.syncDocs]);

  /// One demo plot, live.
  Stream<DemoPlot?> watchDemoPlot(String id) =>
      watchDemoPlots().map((all) => all.where((p) => p.id == id).firstOrNull);

  /// Pulls `GET /v1/demo-plots` into the local rows.
  Future<bool> refreshDemoPlots() async {
    try {
      final now = _now();
      for (final p in await api.demoPlots()) {
        final existing = await _entities.read(FieldEntities.demoPlot, p.id);
        if (existing != null && existing.dirty) continue;
        final detail = await api.demoPlot(p.id);
        await _entities.write(
          FieldEntities.demoPlot,
          p.id,
          detail.toJson(),
          version: 1,
          dirty: false,
          now: now,
        );
      }
      return true;
    } on FieldUnavailableException {
      return false;
    }
  }

  /// Registers a demo plot (offline-capable).
  Future<DemoPlot> createDemoPlot({
    required String farmerId,
    String? farmerName,
    required String cropPlotId,
    required String treatment,
    String baseline = 'farmer_practice',
    String? comparisonCropPlotId,
    String? productId,
  }) async {
    final id = _newId();
    final plot = DemoPlot(
      id: id,
      farmerId: farmerId,
      farmerName: farmerName,
      cropPlotId: cropPlotId,
      treatment: treatment,
      baseline: baseline,
      pending: true,
    );
    await outbox.enqueueCreate(
      FieldEntities.demoPlot,
      id,
      <String, Object?>{
        'farmer_id': farmerId,
        'crop_plot_id': cropPlotId,
        'baseline': baseline,
        'comparison_crop_plot_id': ?comparisonCropPlotId,
        'product_id': ?productId,
        'treatment': treatment,
      },
      local: <String, Object?>{'farmer_name': farmerName},
    );
    await _entities.write(
      FieldEntities.demoPlot,
      id,
      plot.toJson(),
      version: 0,
      dirty: true,
      now: _now(),
    );
    return plot;
  }

  /// Adds a stage observation with its photos (NF-004 bytes already
  /// processed; each photo becomes a resumable upload).
  Future<DemoObservation> addObservation({
    required String demoPlotId,
    required DemoStage stage,
    String side = 'demo',
    String? note,
    List<(String path, Uint8List bytes)> photos = const <(String, Uint8List)>[],
  }) async {
    final uris = <String>[];
    for (final (path, bytes) in photos) {
      uris.add(
        Outbox.uploadRef(
          await outbox.enqueueUpload(
            filePath: path,
            bytes: bytes,
            purpose: demoPhotoUploadPurpose,
          ),
        ),
      );
    }
    final id = _newId();
    final at = _now();
    await outbox.enqueueCreate(
      FieldEntities.demoObservation,
      id,
      <String, Object?>{
        'demo_plot_id': demoPlotId,
        'stage': stage.name,
        'side': side,
        'observed_at': at.toIso8601String(),
        if (note != null && note.isNotEmpty) 'note': note,
        'photo_uris': uris,
      },
    );
    await _entities.write(
      FieldEntities.demoObservation,
      id,
      <String, Object?>{
        'id': id,
        'demo_plot_id': demoPlotId,
        'stage': stage.name,
        'side': side,
        'observed_at': at.toIso8601String(),
        'note': note,
        'photo_uris': uris,
      },
      version: 0,
      dirty: true,
      now: at,
    );
    return DemoObservation(
      id: id,
      stage: stage,
      side: side,
      observedAt: at,
      note: note,
      photoUris: uris,
      pending: true,
    );
  }

  /// Moves the demo plot to [to] (`active` or `reported`).
  Future<void> transitionDemoPlot(String id, DemoStatus to) async {
    final plot = (await demoPlots()).where((p) => p.id == id).firstOrNull;
    if (plot == null || !plot.nextStates.contains(to)) return;
    await _entities.write(
      FieldEntities.demoPlot,
      id,
      plot.copyWith(status: to).toJson(),
      version: 0,
      dirty: true,
      now: _now(),
    );
    await outbox.enqueueUpdate(FieldEntities.demoPlot, id, <String, Object?>{
      'status': to.name,
    });
  }

  /// Enters the harvest yields; the demo plot becomes `harvested`.
  Future<void> enterYield(
    String id, {
    required double demoKgPerAcre,
    double? practiceKgPerAcre,
    String? note,
  }) async {
    final plot = (await demoPlots()).where((p) => p.id == id).firstOrNull;
    if (plot == null) return;
    await _entities.write(
      FieldEntities.demoPlot,
      id,
      plot
          .copyWith(
            status: DemoStatus.harvested,
            demoYieldKgPerAcre: demoKgPerAcre,
            practiceYieldKgPerAcre: practiceKgPerAcre,
          )
          .toJson(),
      version: 0,
      dirty: true,
      now: _now(),
    );
    await outbox.enqueueUpdate(FieldEntities.demoPlot, id, <String, Object?>{
      'demo_yield_kg_per_acre': demoKgPerAcre,
      'practice_yield_kg_per_acre': ?practiceKgPerAcre,
      if (note != null && note.isNotEmpty) 'yield_note': note,
      'status': DemoStatus.harvested.name,
    });
  }

  /// Drops every M7 officer cache (SEC-025 wipe, logout).
  Future<void> clearCaches() async {
    final rows = await (db.select(
      db.kv,
    )..where((t) => t.key.like('$fieldCachePrefix%'))).get();
    for (final row in rows) {
      await db.removeValue(row.key);
    }
  }
}
