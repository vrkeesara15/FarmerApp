import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../geo/geo.dart';

/// Wire names of the M7 field entities the officer app writes through
/// `/v1/sync` (docs/prs/M7-field-p1-api.md "Sync").
///
/// None of them has a typed Drift table: they live in `sync_docs` as JSON,
/// which is why adding them is additive for both apps.
abstract final class FieldEntities {
  /// FA-007 inbox row; the device only ever updates `{read_at}`.
  static const String notification = 'notification';

  /// VV-008 tracking gap; the device writes `{reason, note}` on the gap id
  /// that `/v1/me/day` handed out.
  static const String trackGap = 'track_gap';

  /// FA-018 beat plan; the device writes the whole ordered `{items}`.
  static const String beatPlan = 'beat_plan';

  /// FA-023 expense claim (create only; the receipt is uploaded first).
  static const String travelClaim = 'travel_claim';

  /// FA-026 demo plot.
  static const String demoPlot = 'demo_plot';

  /// FA-026 stage observation.
  static const String demoObservation = 'demo_observation';

  /// FA-027 village meeting.
  static const String farmerMeeting = 'farmer_meeting';

  /// FA-027 attendance row (OTP online, QR offline).
  static const String meetingAttendance = 'meeting_attendance';

  /// Every entity above, for the sync registry.
  static const Set<String> all = <String>{
    notification,
    trackGap,
    beatPlan,
    travelClaim,
    demoPlot,
    demoObservation,
    farmerMeeting,
    meetingAttendance,
  };

  /// Conflict rule per entity, mirroring the server table in
  /// docs/prs/M7-field-p1-api.md.
  static const Map<String, String> conflictRules = <String, String>{
    notification: 'last_writer_wins',
    trackGap: 'last_writer_wins',
    beatPlan: 'last_writer_wins',
    travelClaim: 'server_wins',
    demoPlot: 'last_writer_wins',
    demoObservation: 'server_wins',
    farmerMeeting: 'last_writer_wins',
    meetingAttendance: 'server_wins',
  };
}

DateTime? _time(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.parse(v).toUtc() : null;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

double? _num(Object? v) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

String _str(Object? v) => v is String ? v : '';

List<Map<String, Object?>> _rows(Object? v) => <Map<String, Object?>>[
  if (v is List)
    for (final e in v)
      if (e is Map) Map<String, Object?>.from(e),
];

// --- FA-007 notifications inbox (A13) --------------------------------------

/// One inbox row (`NotificationOut`). The server never sends text: the app
/// renders [titleKey] / [bodyKey] from its own ARB files.
@immutable
class InboxItem {
  /// Creates the row.
  const InboxItem({
    required this.id,
    required this.kind,
    required this.titleKey,
    required this.bodyKey,
    required this.route,
    required this.createdAt,
    this.readAt,
    this.data = const <String, Object?>{},
  });

  /// Parses the wire shape (also the `sync_docs` shape).
  factory InboxItem.fromJson(Map<String, Object?> json) => InboxItem(
    id: _str(json['id']),
    kind: _str(json['kind']),
    titleKey: _str(json['title_key']),
    bodyKey: _str(json['body_key']),
    route: _str(json['route']),
    createdAt: _time(json['created_at']) ?? DateTime.utc(1970),
    readAt: _time(json['read_at']),
    data: json['data'] is Map
        ? Map<String, Object?>.from(json['data']! as Map)
        : const <String, Object?>{},
  );

  /// Row id.
  final String id;

  /// Notification kind (`visit_confirm_request`, `beat_plan_ready`, ...).
  final String kind;

  /// i18n key of the title.
  final String titleKey;

  /// i18n key of the body.
  final String bodyKey;

  /// Deep link inside the app (`/visits/{id}/confirm`, `/inbox`, ...).
  final String route;

  /// When the server created the row.
  final DateTime createdAt;

  /// When the officer read it; null while unread.
  final DateTime? readAt;

  /// Ids the route needs.
  final Map<String, Object?> data;

  /// Still unread.
  bool get unread => readAt == null;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'title_key': titleKey,
    'body_key': bodyKey,
    'route': route,
    'created_at': createdAt.toIso8601String(),
    'read_at': readAt?.toIso8601String(),
    'data': data,
  };

  @override
  bool operator ==(Object other) =>
      other is InboxItem && other.id == id && other.readAt == readAt;

  @override
  int get hashCode => Object.hash(id, readAt);
}

/// The inbox as A13 shows it.
@immutable
class Inbox {
  /// Creates the view.
  const Inbox({this.items = const <InboxItem>[], this.unread = 0});

  /// Newest first.
  final List<InboxItem> items;

  /// Unread count (drives the bottom-nav badge).
  final int unread;

  /// Nothing to show.
  bool get isEmpty => items.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is Inbox &&
      other.unread == unread &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(unread, Object.hashAll(items));
}

// --- FA-018 beat plan (A11) -------------------------------------------------

/// Why the system put a farmer on today's beat.
enum BeatReasonCode {
  /// A follow-up visit is due.
  followUpDue,

  /// A pest alert is running in the district.
  pestAlert,

  /// Credit falls due within seven days.
  creditDue,

  /// A demo plot stage observation is due.
  demoPlotStage;

  /// Parses the wire value; unknown codes give null.
  static BeatReasonCode? parse(String value) => switch (value) {
    'follow_up_due' => followUpDue,
    'pest_alert' => pestAlert,
    'credit_due' => creditDue,
    'demo_plot_stage' => demoPlotStage,
    _ => null,
  };

  /// Wire value.
  String get wire => switch (this) {
    followUpDue => 'follow_up_due',
    pestAlert => 'pest_alert',
    creditDue => 'credit_due',
    demoPlotStage => 'demo_plot_stage',
  };
}

/// One item of the beat plan.
@immutable
class BeatItem {
  /// Creates the item.
  const BeatItem({
    required this.id,
    required this.kind,
    this.farmerId,
    this.farmerName,
    this.villageId,
    this.villageName,
    this.reasons = const <BeatReasonCode>[],
    this.priority = 0,
    this.source = 'system',
    this.note,
  });

  /// Parses the wire shape.
  factory BeatItem.fromJson(Map<String, Object?> json) => BeatItem(
    id: _str(json['id']),
    kind: _str(json['kind']).isEmpty ? 'farmer' : _str(json['kind']),
    farmerId: json['farmer_id'] as String?,
    farmerName: json['farmer_name'] as String?,
    villageId: json['village_id'] as String?,
    villageName: json['village_name'] as String?,
    reasons: <BeatReasonCode>[
      for (final r in _rows(json['reasons']))
        ?BeatReasonCode.parse(_str(r['code'])),
    ],
    priority: _int(json['priority']),
    source: _str(json['source']).isEmpty ? 'system' : _str(json['source']),
    note: json['note'] as String?,
  );

  /// Server item id (empty for an item the officer just added offline).
  final String id;

  /// `farmer` or `village`.
  final String kind;

  /// Farmer to visit (`kind == farmer`).
  final String? farmerId;

  /// Farmer name for display.
  final String? farmerName;

  /// Village (always set by the server).
  final String? villageId;

  /// Village name for display.
  final String? villageName;

  /// Why this item is on the plan.
  final List<BeatReasonCode> reasons;

  /// System priority (lower is more urgent).
  final int priority;

  /// `system` or `officer`.
  final String source;

  /// Officer's own note.
  final String? note;

  /// Label shown on the card.
  String get title => kind == 'village'
      ? (villageName ?? villageId ?? '')
      : (farmerName ?? farmerId ?? '');

  /// The shape `PUT /v1/me/beat` expects for this item.
  Map<String, Object?> toItemIn() => <String, Object?>{
    if (id.isNotEmpty) 'id': id,
    if (id.isEmpty) 'kind': kind,
    if (id.isEmpty && farmerId != null) 'farmer_id': farmerId,
    if (id.isEmpty && villageId != null) 'village_id': villageId,
    if (note != null) 'note': note,
  };

  /// Wire shape (also what the cache keeps).
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'farmer_id': farmerId,
    'farmer_name': farmerName,
    'village_id': villageId,
    'village_name': villageName,
    'reasons': <Object?>[
      for (final r in reasons) <String, Object?>{'code': r.wire},
    ],
    'priority': priority,
    'source': source,
    'note': note,
  };

  /// Copy with overrides.
  BeatItem copyWith({String? note}) => BeatItem(
    id: id,
    kind: kind,
    farmerId: farmerId,
    farmerName: farmerName,
    villageId: villageId,
    villageName: villageName,
    reasons: reasons,
    priority: priority,
    source: source,
    note: note ?? this.note,
  );

  @override
  bool operator ==(Object other) =>
      other is BeatItem &&
      other.id == id &&
      other.farmerId == farmerId &&
      other.villageId == villageId &&
      other.note == note;

  @override
  int get hashCode => Object.hash(id, farmerId, villageId, note);
}

/// Today's beat plan (`BeatPlanOut`).
@immutable
class BeatPlan {
  /// Creates the plan.
  const BeatPlan({
    required this.id,
    required this.planDate,
    this.status = 'generated',
    this.target = 0,
    this.items = const <BeatItem>[],
    this.version = 0,
  });

  /// Parses the wire shape.
  factory BeatPlan.fromJson(Map<String, Object?> json) => BeatPlan(
    id: _str(json['id']),
    planDate: _str(json['plan_date']),
    status: _str(json['status']).isEmpty ? 'generated' : _str(json['status']),
    target: _int(json['target']),
    items: <BeatItem>[
      for (final i in _rows(json['items'])) BeatItem.fromJson(i),
    ],
    version: _int(json['version']),
  );

  /// Plan id.
  final String id;

  /// `YYYY-MM-DD` in IST.
  final String planDate;

  /// `generated` or `edited`.
  final String status;

  /// The tenant's daily target.
  final int target;

  /// Items in visit order.
  final List<BeatItem> items;

  /// Server row version (optimistic concurrency on `PUT`).
  final int version;

  /// Nothing planned.
  bool get isEmpty => items.isEmpty;

  /// Copy with a new item order / set.
  BeatPlan withItems(List<BeatItem> next) => BeatPlan(
    id: id,
    planDate: planDate,
    status: 'edited',
    target: target,
    items: next,
    version: version,
  );

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'plan_date': planDate,
    'status': status,
    'target': target,
    'items': <Object?>[for (final i in items) i.toJson()],
    'version': version,
  };

  /// The `{items}` payload of `PUT /v1/me/beat` (and of the sync update).
  Map<String, Object?> toUpdate() => <String, Object?>{
    'items': <Object?>[for (final i in items) i.toItemIn()],
    'version': version,
  };

  @override
  bool operator ==(Object other) =>
      other is BeatPlan &&
      other.id == id &&
      other.status == status &&
      other.version == version &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(id, status, version, Object.hashAll(items));
}

// --- VV-008 my day (A12) ----------------------------------------------------

/// Why the track has a hole (VV-008).
enum GapReason {
  /// No network / no GPS.
  network,

  /// Lunch, prayer, rest.
  personalBreak,

  /// Vehicle trouble.
  vehicle,

  /// Anything else; the note carries it.
  other;

  /// Parses the wire value.
  static GapReason? parse(String? value) => switch (value) {
    'network' => network,
    'personal_break' => personalBreak,
    'vehicle' => vehicle,
    'other' => other,
    _ => null,
  };

  /// Wire value.
  String get wire => switch (this) {
    network => 'network',
    personalBreak => 'personal_break',
    vehicle => 'vehicle',
    other => 'other',
  };
}

/// A hole in the day's track.
@immutable
class DayGap {
  /// Creates the gap.
  const DayGap({
    required this.id,
    required this.start,
    required this.end,
    required this.durationS,
    this.dutySessionId = '',
    this.reason,
    this.note,
  });

  /// Parses `GapOut`.
  factory DayGap.fromJson(Map<String, Object?> json) => DayGap(
    id: _str(json['id']),
    start: _time(json['start']) ?? DateTime.utc(1970),
    end: _time(json['end']) ?? DateTime.utc(1970),
    durationS: _int(json['duration_s']),
    dutySessionId: _str(json['duty_session_id']),
    reason: GapReason.parse(json['reason'] as String?),
    note: json['note'] as String?,
  );

  /// Gap id (the sync entity id of a `track_gap` op).
  final String id;

  /// Start of the hole (UTC).
  final DateTime start;

  /// End of the hole (UTC).
  final DateTime end;

  /// How long it lasted.
  final int durationS;

  /// Session the gap belongs to.
  final String dutySessionId;

  /// Reason the officer gave, if any.
  final GapReason? reason;

  /// Free-text note next to the reason.
  final String? note;

  /// Still waiting for a reason.
  bool get needsReason => reason == null;

  /// Copy with a reason.
  DayGap withReason(GapReason reason, String? note) => DayGap(
    id: id,
    start: start,
    end: end,
    durationS: durationS,
    dutySessionId: dutySessionId,
    reason: reason,
    note: note,
  );

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'duration_s': durationS,
    'duty_session_id': dutySessionId,
    'reason': reason?.wire,
    'note': note,
  };

  @override
  bool operator ==(Object other) =>
      other is DayGap &&
      other.id == id &&
      other.reason == reason &&
      other.note == note;

  @override
  int get hashCode => Object.hash(id, reason, note);
}

/// A stop the track processing found (>= 5 min within 100 m).
@immutable
class DayStop {
  /// Creates the stop.
  const DayStop({
    required this.point,
    required this.start,
    required this.end,
    required this.durationS,
  });

  /// Parses `StopOut`.
  factory DayStop.fromJson(Map<String, Object?> json) => DayStop(
    point: GeoPoint(_num(json['lat']) ?? 0, _num(json['lon']) ?? 0),
    start: _time(json['start']) ?? DateTime.utc(1970),
    end: _time(json['end']) ?? DateTime.utc(1970),
    durationS: _int(json['duration_s']),
  );

  /// Where the officer stopped.
  final GeoPoint point;

  /// Start (UTC).
  final DateTime start;

  /// End (UTC).
  final DateTime end;

  /// Length in seconds.
  final int durationS;

  @override
  bool operator ==(Object other) =>
      other is DayStop && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// A visit pin on the day map.
@immutable
class DayVisit {
  /// Creates the pin.
  const DayVisit({
    required this.id,
    required this.point,
    required this.checkinAt,
    this.farmerName = '',
    this.status = 'open',
    this.score,
  });

  /// Parses `ReplayVisitOut`.
  factory DayVisit.fromJson(Map<String, Object?> json) => DayVisit(
    id: _str(json['id']),
    point: GeoPoint(_num(json['lat']) ?? 0, _num(json['lon']) ?? 0),
    checkinAt: _time(json['checkin_at']) ?? DateTime.utc(1970),
    farmerName: _str(json['farmer_name']),
    status: _str(json['status']),
    score: json['score'] is num ? (json['score']! as num).toInt() : null,
  );

  /// Visit id.
  final String id;

  /// Check-in position.
  final GeoPoint point;

  /// Check-in time (UTC).
  final DateTime checkinAt;

  /// Farmer visited.
  final String farmerName;

  /// VV-005 status.
  final String status;

  /// VV-004 score.
  final int? score;

  @override
  bool operator ==(Object other) => other is DayVisit && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// `GET /v1/me/day` — the officer's own copy of the console day replay.
@immutable
class DayTimeline {
  /// Creates the view.
  const DayTimeline({
    required this.date,
    this.km = 0,
    this.track = const <GeoPoint>[],
    this.stops = const <DayStop>[],
    this.gaps = const <DayGap>[],
    this.visits = const <DayVisit>[],
    this.travel,
    this.fromServer = false,
  });

  /// Parses `MeDayOut`.
  factory DayTimeline.fromJson(Map<String, Object?> json) {
    final track = <GeoPoint>[];
    final geo = json['track'];
    if (geo is Map && geo['coordinates'] is List) {
      for (final line in geo['coordinates']! as List) {
        if (line is! List) continue;
        for (final pair in line) {
          if (pair is List && pair.length >= 2) {
            track.add(GeoPoint(_num(pair[1]) ?? 0, _num(pair[0]) ?? 0));
          }
        }
      }
    }
    return DayTimeline(
      date: _str(json['date']),
      km: _num(json['km']) ?? 0,
      track: track,
      stops: <DayStop>[
        for (final s in _rows(json['stops'])) DayStop.fromJson(s),
      ],
      gaps: <DayGap>[for (final g in _rows(json['gaps'])) DayGap.fromJson(g)],
      visits: <DayVisit>[
        for (final v in _rows(json['visits'])) DayVisit.fromJson(v),
      ],
      travel: json['travel'] is Map
          ? TravelDay.fromJson(
              Map<String, Object?>.from(json['travel']! as Map),
            )
          : null,
      fromServer: true,
    );
  }

  /// `YYYY-MM-DD` in IST.
  final String date;

  /// Processed km (server); 0 until the track has been processed.
  final double km;

  /// The day's track.
  final List<GeoPoint> track;

  /// Stops.
  final List<DayStop> stops;

  /// Gaps, with their reasons.
  final List<DayGap> gaps;

  /// Visit pins.
  final List<DayVisit> visits;

  /// The day's travel allowance.
  final TravelDay? travel;

  /// True when this came from `/v1/me/day` rather than the local cache
  /// being empty (A12 shows the client km estimate until then).
  final bool fromServer;

  /// Gaps still without a reason.
  List<DayGap> get unexplainedGaps => <DayGap>[
    for (final g in gaps)
      if (g.needsReason) g,
  ];

  /// Replaces one gap (after a reason was queued).
  DayTimeline withGap(DayGap gap) => DayTimeline(
    date: date,
    km: km,
    track: track,
    stops: stops,
    gaps: <DayGap>[
      for (final g in gaps)
        if (g.id == gap.id) gap else g,
    ],
    visits: visits,
    travel: travel,
    fromServer: fromServer,
  );

  /// Wire shape (what the cache keeps).
  Map<String, Object?> toJson() => <String, Object?>{
    'date': date,
    'km': km,
    'track': <String, Object?>{
      'type': 'MultiLineString',
      'coordinates': <Object?>[
        <Object?>[
          for (final p in track) <Object?>[p.longitude, p.latitude],
        ],
      ],
    },
    'stops': <Object?>[
      for (final s in stops)
        <String, Object?>{
          'lat': s.point.latitude,
          'lon': s.point.longitude,
          'start': s.start.toIso8601String(),
          'end': s.end.toIso8601String(),
          'duration_s': s.durationS,
        },
    ],
    'gaps': <Object?>[for (final g in gaps) g.toJson()],
    'visits': <Object?>[
      for (final v in visits)
        <String, Object?>{
          'id': v.id,
          'lat': v.point.latitude,
          'lon': v.point.longitude,
          'checkin_at': v.checkinAt.toIso8601String(),
          'farmer_name': v.farmerName,
          'status': v.status,
          'score': v.score,
        },
    ],
    'travel': travel?.toJson(),
  };
}

// --- FA-024 my performance (A60) -------------------------------------------

/// `GET /v1/me/performance` plus the officer's own targets and the local
/// verified-visit trend.
@immutable
class Performance {
  /// Creates the view.
  const Performance({
    required this.from,
    required this.to,
    this.dutyDays = 0,
    this.visits = 0,
    this.verifiedVisits = 0,
    this.farmersAdded = 0,
    this.confirmationRate,
    this.salesNetPaise = 0,
    this.collectionsPaise = 0,
    this.kmPerDay,
    this.rank = 0,
    this.incentiveEarnedPaise,
    this.targets,
    this.trend = const <int>[],
  });

  /// Parses `PerformanceOut`.
  factory Performance.fromJson(Map<String, Object?> json) => Performance(
    from: _str(json['from']),
    to: _str(json['to']),
    dutyDays: _int(json['duty_days']),
    visits: _int(json['visits']),
    verifiedVisits: _int(json['verified_visits']),
    farmersAdded: _int(json['farmers_added']),
    confirmationRate: _num(json['confirmation_rate']),
    salesNetPaise: _int(json['sales_net_paise']),
    collectionsPaise: _int(json['collections_paise']),
    kmPerDay: _num(json['km_per_day']),
    rank: _int(json['rank']),
    incentiveEarnedPaise: json['incentive_earned_paise'] is num
        ? (json['incentive_earned_paise']! as num).toInt()
        : null,
  );

  /// Period start (`YYYY-MM-DD`).
  final String from;

  /// Period end.
  final String to;

  /// Days on duty.
  final int dutyDays;

  /// Visits made.
  final int visits;

  /// Visits that scored >= 70 (VV-005).
  final int verifiedVisits;

  /// Farmers registered.
  final int farmersAdded;

  /// Share of visits the farmer confirmed (0..1).
  final double? confirmationRate;

  /// Net sales in paise.
  final int salesNetPaise;

  /// Credit collected in paise.
  final int collectionsPaise;

  /// Km per duty day.
  final double? kmPerDay;

  /// Rank in the cluster.
  final int rank;

  /// WC-009 payout; null while the tenant has no active rules.
  final int? incentiveEarnedPaise;

  /// The month's targets, if the tenant set any.
  final PerformanceTargets? targets;

  /// Verified visits per day over the trailing fortnight (local `visits`).
  final List<int> trend;

  /// Copy with the targets and trend attached.
  Performance with2({PerformanceTargets? targets, List<int>? trend}) =>
      Performance(
        from: from,
        to: to,
        dutyDays: dutyDays,
        visits: visits,
        verifiedVisits: verifiedVisits,
        farmersAdded: farmersAdded,
        confirmationRate: confirmationRate,
        salesNetPaise: salesNetPaise,
        collectionsPaise: collectionsPaise,
        kmPerDay: kmPerDay,
        rank: rank,
        incentiveEarnedPaise: incentiveEarnedPaise,
        targets: targets ?? this.targets,
        trend: trend ?? this.trend,
      );

  /// Wire shape (cache).
  Map<String, Object?> toJson() => <String, Object?>{
    'from': from,
    'to': to,
    'duty_days': dutyDays,
    'visits': visits,
    'verified_visits': verifiedVisits,
    'farmers_added': farmersAdded,
    'confirmation_rate': confirmationRate,
    'sales_net_paise': salesNetPaise,
    'collections_paise': collectionsPaise,
    'km_per_day': kmPerDay,
    'rank': rank,
    'incentive_earned_paise': incentiveEarnedPaise,
  };
}

/// The officer's monthly targets (`GET /v1/targets`, WC-009).
@immutable
class PerformanceTargets {
  /// Creates the targets.
  const PerformanceTargets({
    this.visitsVerified,
    this.newFarmers,
    this.salesPaise,
    this.collectionsPaise,
  });

  /// Parses one `TargetOut`.
  factory PerformanceTargets.fromJson(Map<String, Object?> json) =>
      PerformanceTargets(
        visitsVerified: json['visits_verified'] is num
            ? (json['visits_verified']! as num).toInt()
            : null,
        newFarmers: json['new_farmers'] is num
            ? (json['new_farmers']! as num).toInt()
            : null,
        salesPaise: json['sales_paise'] is num
            ? (json['sales_paise']! as num).toInt()
            : null,
        collectionsPaise: json['collections_paise'] is num
            ? (json['collections_paise']! as num).toInt()
            : null,
      );

  /// Verified-visit target.
  final int? visitsVerified;

  /// New-farmer target.
  final int? newFarmers;

  /// Sales target in paise.
  final int? salesPaise;

  /// Collections target in paise.
  final int? collectionsPaise;

  /// Nothing set.
  bool get isEmpty =>
      visitsVerified == null &&
      newFarmers == null &&
      salesPaise == null &&
      collectionsPaise == null;

  /// Wire shape (cache).
  Map<String, Object?> toJson() => <String, Object?>{
    'visits_verified': visitsVerified,
    'new_farmers': newFarmers,
    'sales_paise': salesPaise,
    'collections_paise': collectionsPaise,
  };
}

// --- FA-023 travel allowance (A61) -----------------------------------------

/// One day of the travel statement.
@immutable
class TravelDay {
  /// Creates the day.
  const TravelDay({
    required this.date,
    this.km = 0,
    this.kmCapped = 0,
    this.capKm = 0,
    this.ratePerKmPaise = 0,
    this.taPaise = 0,
    this.sessions = 0,
    this.openSession = false,
  });

  /// Parses `TravelDayOut` (km fields arrive as decimal strings).
  factory TravelDay.fromJson(Map<String, Object?> json) => TravelDay(
    date: _str(json['date']),
    km: _num(json['km']) ?? 0,
    kmCapped: _num(json['km_capped']) ?? 0,
    capKm: _int(json['cap_km']),
    ratePerKmPaise: _int(json['rate_per_km_paise']),
    taPaise: _int(json['ta_paise']),
    sessions: _int(json['sessions']),
    openSession: json['open_session'] == true,
  );

  /// `YYYY-MM-DD`.
  final String date;

  /// Processed km.
  final double km;

  /// Km after the daily cap.
  final double kmCapped;

  /// The tenant's daily cap.
  final int capKm;

  /// Rate in paise per km.
  final int ratePerKmPaise;

  /// Allowance for the day.
  final int taPaise;

  /// Duty sessions that day.
  final int sessions;

  /// A session is still open (km not final).
  final bool openSession;

  /// The cap bit into the day's km.
  bool get capped => km > kmCapped;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'date': date,
    'km': km,
    'km_capped': kmCapped,
    'cap_km': capKm,
    'rate_per_km_paise': ratePerKmPaise,
    'ta_paise': taPaise,
    'sessions': sessions,
    'open_session': openSession,
  };

  @override
  bool operator ==(Object other) =>
      other is TravelDay && other.date == date && other.taPaise == taPaise;

  @override
  int get hashCode => Object.hash(date, taPaise);
}

/// What an expense claim can be for.
enum ClaimType {
  /// Fuel for the officer's own vehicle.
  fuel,

  /// Bus or shared transport fare.
  bus,

  /// Anything else; the note explains.
  other;

  /// Parses the wire value.
  static ClaimType parse(String? value) => switch (value) {
    'fuel' => fuel,
    'bus' => bus,
    _ => other,
  };
}

/// Where a claim stands.
enum ClaimStatus {
  /// Still on the device, not yet sent.
  queued,

  /// With the cluster head.
  submitted,

  /// Approved for payroll.
  approved,

  /// Rejected, with a note.
  rejected;

  /// Parses the wire value.
  static ClaimStatus parse(String? value) => switch (value) {
    'submitted' => submitted,
    'approved' => approved,
    'rejected' => rejected,
    _ => queued,
  };
}

/// An expense claim (`TravelClaimOut`).
@immutable
class TravelClaim {
  /// Creates the claim.
  const TravelClaim({
    required this.id,
    required this.claimDate,
    required this.type,
    required this.amountPaise,
    this.receiptUri = '',
    this.note,
    this.status = ClaimStatus.queued,
    this.decisionNote,
    this.kmComputed,
  });

  /// Parses the wire shape.
  factory TravelClaim.fromJson(Map<String, Object?> json) => TravelClaim(
    id: _str(json['id']),
    claimDate: _str(json['claim_date']),
    type: ClaimType.parse(json['type'] as String?),
    amountPaise: _int(json['amount_paise']),
    receiptUri: _str(json['receipt_uri']),
    note: json['note'] as String?,
    status: ClaimStatus.parse(json['status'] as String?),
    decisionNote: json['decision_note'] as String?,
    kmComputed: _num(json['km_computed']),
  );

  /// Claim id (client uuid).
  final String id;

  /// `YYYY-MM-DD` the expense was incurred.
  final String claimDate;

  /// Fuel, bus or other.
  final ClaimType type;

  /// Amount in paise.
  final int amountPaise;

  /// Receipt blob, or an `upload:<id>` placeholder while queued.
  final String receiptUri;

  /// Officer's note.
  final String? note;

  /// Where the claim stands.
  final ClaimStatus status;

  /// The cluster head's note on a decision.
  final String? decisionNote;

  /// Km the server computed for the claim date (VA-E07 compares them).
  final double? kmComputed;

  /// Still on the device.
  bool get pending => status == ClaimStatus.queued;

  /// Wire shape (`TravelClaimIn` plus the read-only fields).
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'claim_date': claimDate,
    'type': type.name,
    'amount_paise': amountPaise,
    'receipt_uri': receiptUri,
    'note': note,
    'status': status == ClaimStatus.queued ? null : status.name,
    'decision_note': decisionNote,
    'km_computed': kmComputed,
  };

  /// The create payload of `POST /v1/travel/claims`.
  Map<String, Object?> toCreate() => <String, Object?>{
    'claim_date': claimDate,
    'type': type.name,
    'amount_paise': amountPaise,
    'receipt_uri': receiptUri,
    if (note != null && note!.isNotEmpty) 'note': note,
  };

  @override
  bool operator ==(Object other) =>
      other is TravelClaim && other.id == id && other.status == status;

  @override
  int get hashCode => Object.hash(id, status);
}

/// `GET /v1/travel/statement` for one month, plus the claims queued here.
@immutable
class TravelStatement {
  /// Creates the statement.
  const TravelStatement({
    required this.month,
    this.days = const <TravelDay>[],
    this.claims = const <TravelClaim>[],
    this.kmTotal = 0,
    this.kmCappedTotal = 0,
    this.taTotalPaise = 0,
    this.claimsApprovedPaise = 0,
    this.claimsSubmittedPaise = 0,
    this.payablePaise = 0,
    this.ratePerKmPaise = 0,
  });

  /// Parses the wire shape.
  factory TravelStatement.fromJson(String month, Map<String, Object?> json) =>
      TravelStatement(
        month: _str(json['month']).isEmpty ? month : _str(json['month']),
        days: <TravelDay>[
          for (final d in _rows(json['days'])) TravelDay.fromJson(d),
        ],
        claims: <TravelClaim>[
          for (final c in _rows(json['claims'])) TravelClaim.fromJson(c),
        ],
        kmTotal: _num(json['km_total']) ?? 0,
        kmCappedTotal: _num(json['km_capped_total']) ?? 0,
        taTotalPaise: _int(json['ta_total_paise']),
        claimsApprovedPaise: _int(json['claims_approved_paise']),
        claimsSubmittedPaise: _int(json['claims_submitted_paise']),
        payablePaise: _int(json['payable_paise']),
        ratePerKmPaise: _int(json['rate_per_km_paise']),
      );

  /// `YYYY-MM`.
  final String month;

  /// Km by day, newest first as the screen shows it.
  final List<TravelDay> days;

  /// Claims of the month (queued ones first).
  final List<TravelClaim> claims;

  /// Raw km.
  final double kmTotal;

  /// Km after the daily cap.
  final double kmCappedTotal;

  /// Allowance from km.
  final int taTotalPaise;

  /// Approved claims.
  final int claimsApprovedPaise;

  /// Claims still with the cluster head.
  final int claimsSubmittedPaise;

  /// What payroll owes so far.
  final int payablePaise;

  /// Paise per km.
  final int ratePerKmPaise;

  /// Nothing recorded this month.
  bool get isEmpty => days.isEmpty && claims.isEmpty;

  /// Copy with [claims] merged in (queued claims from the outbox).
  TravelStatement withClaims(List<TravelClaim> next) => TravelStatement(
    month: month,
    days: days,
    claims: next,
    kmTotal: kmTotal,
    kmCappedTotal: kmCappedTotal,
    taTotalPaise: taTotalPaise,
    claimsApprovedPaise: claimsApprovedPaise,
    claimsSubmittedPaise: claimsSubmittedPaise,
    payablePaise: payablePaise,
    ratePerKmPaise: ratePerKmPaise,
  );

  /// Wire shape (cache).
  Map<String, Object?> toJson() => <String, Object?>{
    'month': month,
    'days': <Object?>[for (final d in days) d.toJson()],
    'claims': <Object?>[for (final c in claims) c.toJson()],
    'km_total': kmTotal,
    'km_capped_total': kmCappedTotal,
    'ta_total_paise': taTotalPaise,
    'claims_approved_paise': claimsApprovedPaise,
    'claims_submitted_paise': claimsSubmittedPaise,
    'payable_paise': payablePaise,
    'rate_per_km_paise': ratePerKmPaise,
  };
}

// --- VA-005 my flags (A62) --------------------------------------------------

/// A flag about the officer, as VA-005 lets them see it.
@immutable
class MyFlag {
  /// Creates the flag.
  const MyFlag({
    required this.id,
    required this.ruleId,
    required this.severity,
    required this.title,
    required this.state,
    required this.createdAt,
    this.ruleTitle,
    this.canExplain = false,
    this.outcome,
    this.explanations = const <FlagExplanation>[],
    this.metrics = const <String, Object?>{},
  });

  /// Parses `SubjectFlagOut` / `SubjectFlagDetailOut`.
  factory MyFlag.fromJson(Map<String, Object?> json) {
    final evidence = json['evidence'];
    return MyFlag(
      id: _str(json['id']),
      ruleId: _str(json['rule_id']),
      severity: _str(json['severity']),
      title: _str(json['title']),
      state: _str(json['state']).isEmpty ? 'open' : _str(json['state']),
      createdAt: _time(json['created_at']) ?? DateTime.utc(1970),
      ruleTitle: json['rule_title'] as String?,
      canExplain: json['can_explain'] == true,
      outcome: json['outcome'] is Map
          ? FlagOutcome.fromJson(
              Map<String, Object?>.from(json['outcome']! as Map),
            )
          : null,
      explanations: <FlagExplanation>[
        for (final e in _rows(json['explanations']))
          FlagExplanation.fromJson(e),
      ],
      metrics: evidence is Map && evidence['metrics'] is Map
          ? Map<String, Object?>.from(evidence['metrics']! as Map)
          : const <String, Object?>{},
    );
  }

  /// Flag id.
  final String id;

  /// Rule that raised it.
  final String ruleId;

  /// `low` | `medium` | `high`.
  final String severity;

  /// Short title from the rule.
  final String title;

  /// `open` | `in_review` | `resolved`.
  final String state;

  /// When it was raised.
  final DateTime createdAt;

  /// Rule title, when the rule has one.
  final String? ruleTitle;

  /// The officer may still add an explanation.
  final bool canExplain;

  /// Outcome — **only** present once [resolved] (VA-005).
  final FlagOutcome? outcome;

  /// The officer's own explanations.
  final List<FlagExplanation> explanations;

  /// Evidence metrics (numbers only; no other officer's records).
  final Map<String, Object?> metrics;

  /// Closed, with an outcome to show.
  bool get resolved => state == 'resolved';

  /// Wire shape (cache).
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'rule_id': ruleId,
    'rule_title': ruleTitle,
    'severity': severity,
    'title': title,
    'state': state,
    'created_at': createdAt.toIso8601String(),
    'can_explain': canExplain,
    'outcome': outcome?.toJson(),
    'explanations': <Object?>[for (final e in explanations) e.toJson()],
    'evidence': <String, Object?>{'metrics': metrics},
  };

  @override
  bool operator ==(Object other) =>
      other is MyFlag &&
      other.id == id &&
      other.state == state &&
      other.explanations.length == explanations.length;

  @override
  int get hashCode => Object.hash(id, state, explanations.length);
}

/// What the reviewer decided (VA-005: visible only once resolved).
@immutable
class FlagOutcome {
  /// Creates the outcome.
  const FlagOutcome({
    required this.status,
    required this.resolvedAt,
    this.label,
    this.note,
  });

  /// Parses `SubjectOutcome`.
  factory FlagOutcome.fromJson(Map<String, Object?> json) => FlagOutcome(
    status: _str(json['status']),
    resolvedAt: _time(json['resolved_at']) ?? DateTime.utc(1970),
    label: json['label'] as String?,
    note: json['note'] as String?,
  );

  /// `resolved_valid` | `resolved_invalid` | ...
  final String status;

  /// When it was resolved.
  final DateTime resolvedAt;

  /// Resolution label.
  final String? label;

  /// Reviewer's note to the officer.
  final String? note;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    'resolved_at': resolvedAt.toIso8601String(),
    'label': label,
    'note': note,
  };
}

/// One explanation the officer added (`FlagCommentOut`).
@immutable
class FlagExplanation {
  /// Creates the explanation.
  const FlagExplanation({
    required this.id,
    required this.body,
    required this.createdAt,
  });

  /// Parses the wire shape.
  factory FlagExplanation.fromJson(Map<String, Object?> json) =>
      FlagExplanation(
        id: _str(json['id']),
        body: _str(json['body']),
        createdAt: _time(json['created_at']) ?? DateTime.utc(1970),
      );

  /// Comment id.
  final String id;

  /// What the officer wrote.
  final String body;

  /// When.
  final DateTime createdAt;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'body': body,
    'created_at': createdAt.toIso8601String(),
    'is_subject_explanation': true,
  };
}

// --- FA-027 meetings (A35) --------------------------------------------------

/// How a farmer's attendance was recorded.
enum AttendanceMethod {
  /// OTP to the farmer's phone (needs connectivity).
  otp,

  /// Signed QR from the farmer app (works offline).
  qr;

  /// Parses the wire value.
  static AttendanceMethod parse(String? value) => value == 'qr' ? qr : otp;
}

/// One attendee.
@immutable
class MeetingAttendee {
  /// Creates the row.
  const MeetingAttendee({
    required this.id,
    required this.farmerId,
    required this.method,
    required this.recordedAt,
    this.farmerName,
    this.pending = false,
  });

  /// Parses `AttendanceOut`.
  factory MeetingAttendee.fromJson(Map<String, Object?> json) =>
      MeetingAttendee(
        id: _str(json['id']),
        farmerId: _str(json['farmer_id']),
        method: AttendanceMethod.parse(json['method'] as String?),
        recordedAt: _time(json['recorded_at']) ?? DateTime.utc(1970),
        farmerName: json['farmer_name'] as String?,
        pending: json['_pending'] == true,
      );

  /// Attendance id.
  final String id;

  /// Farmer who attended.
  final String farmerId;

  /// OTP or QR.
  final AttendanceMethod method;

  /// When they were marked present.
  final DateTime recordedAt;

  /// Farmer name for display.
  final String? farmerName;

  /// Queued on this device, not yet accepted by the server.
  final bool pending;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'farmer_id': farmerId,
    'method': method.name,
    'recorded_at': recordedAt.toIso8601String(),
    'farmer_name': farmerName,
    if (pending) '_pending': true,
  };

  @override
  bool operator ==(Object other) =>
      other is MeetingAttendee && other.id == id && other.pending == pending;

  @override
  int get hashCode => Object.hash(id, pending);
}

/// A village meeting (`MeetingOut` / `MeetingDetailOut`).
@immutable
class Meeting {
  /// Creates the meeting.
  const Meeting({
    required this.id,
    required this.villageId,
    required this.topic,
    required this.heldAt,
    this.villageName,
    this.status = 'open',
    this.geofenceResult = '',
    this.attendance = const <MeetingAttendee>[],
    this.pending = false,
  });

  /// Parses the wire shape.
  factory Meeting.fromJson(Map<String, Object?> json) => Meeting(
    id: _str(json['id']),
    villageId: _str(json['village_id']),
    topic: _str(json['topic']),
    heldAt: _time(json['held_at']) ?? DateTime.utc(1970),
    villageName: json['village_name'] as String?,
    status: _str(json['status']).isEmpty ? 'open' : _str(json['status']),
    geofenceResult: _str(json['geofence_result']),
    attendance: <MeetingAttendee>[
      for (final a in _rows(json['attendance'])) MeetingAttendee.fromJson(a),
    ],
    pending: json['_pending'] == true,
  );

  /// Meeting id (client uuid).
  final String id;

  /// Village it was held in.
  final String villageId;

  /// What it was about.
  final String topic;

  /// When it was held (UTC).
  final DateTime heldAt;

  /// Village name for display.
  final String? villageName;

  /// `open` | `closed`.
  final String status;

  /// `meeting_point` when the check-in was inside the village geofence.
  final String geofenceResult;

  /// Attendees.
  final List<MeetingAttendee> attendance;

  /// Created offline, not yet accepted.
  final bool pending;

  /// Attendance is still being taken.
  bool get open => status != 'closed';

  /// Copy with a new attendance list / status.
  Meeting copyWith({List<MeetingAttendee>? attendance, String? status}) =>
      Meeting(
        id: id,
        villageId: villageId,
        topic: topic,
        heldAt: heldAt,
        villageName: villageName,
        status: status ?? this.status,
        geofenceResult: geofenceResult,
        attendance: attendance ?? this.attendance,
        pending: pending,
      );

  /// Wire shape (cache).
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'village_id': villageId,
    'village_name': villageName,
    'topic': topic,
    'held_at': heldAt.toIso8601String(),
    'status': status,
    'geofence_result': geofenceResult,
    'attendance': <Object?>[for (final a in attendance) a.toJson()],
    if (pending) '_pending': true,
  };

  @override
  bool operator ==(Object other) =>
      other is Meeting &&
      other.id == id &&
      other.status == status &&
      listEquals(other.attendance, attendance);

  @override
  int get hashCode => Object.hash(id, status, Object.hashAll(attendance));
}

// --- FA-026 demo plots (A36) ------------------------------------------------

/// Crop stage an observation belongs to.
enum DemoStage {
  /// Sowing.
  sown,

  /// Vegetative growth.
  vegetative,

  /// Flowering.
  flowering,

  /// Fruiting / boll formation.
  fruiting,

  /// Maturity.
  maturity,

  /// Harvest.
  harvest;

  /// Parses the wire value.
  static DemoStage? parse(String? value) => value == null
      ? null
      : DemoStage.values.where((s) => s.name == value).firstOrNull;
}

/// Where the demo plot stands in its lifecycle.
enum DemoStatus {
  /// Registered, not started.
  created,

  /// Running.
  active,

  /// Yield entered.
  harvested,

  /// Reported to the farmer and the cluster.
  reported;

  /// Parses the wire value.
  static DemoStatus parse(String? value) =>
      DemoStatus.values.where((s) => s.name == value).firstOrNull ?? created;
}

/// One stage observation with photos.
@immutable
class DemoObservation {
  /// Creates the observation.
  const DemoObservation({
    required this.id,
    required this.stage,
    required this.side,
    required this.observedAt,
    this.note,
    this.photoUris = const <String>[],
    this.pending = false,
  });

  /// Parses `ObservationOut`.
  factory DemoObservation.fromJson(Map<String, Object?> json) =>
      DemoObservation(
        id: _str(json['id']),
        stage: DemoStage.parse(json['stage'] as String?) ?? DemoStage.sown,
        side: _str(json['side']).isEmpty ? 'demo' : _str(json['side']),
        observedAt: _time(json['observed_at']) ?? DateTime.utc(1970),
        note: json['note'] as String?,
        photoUris: <String>[
          if (json['photo_uris'] is List)
            for (final u in json['photo_uris']! as List) '$u',
        ],
        pending: json['_pending'] == true,
      );

  /// Observation id.
  final String id;

  /// Crop stage.
  final DemoStage stage;

  /// `demo` | `practice` | `both`.
  final String side;

  /// When it was observed (UTC).
  final DateTime observedAt;

  /// Officer's note.
  final String? note;

  /// Blob URIs (or `upload:<id>` while queued).
  final List<String> photoUris;

  /// Queued on this device.
  final bool pending;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'stage': stage.name,
    'side': side,
    'observed_at': observedAt.toIso8601String(),
    'note': note,
    'photo_uris': photoUris,
    if (pending) '_pending': true,
  };

  @override
  bool operator ==(Object other) =>
      other is DemoObservation && other.id == id && other.pending == pending;

  @override
  int get hashCode => Object.hash(id, pending);
}

/// A demo plot with its observations and yield (`DemoPlotDetailOut`).
@immutable
class DemoPlot {
  /// Creates the demo plot.
  const DemoPlot({
    required this.id,
    required this.farmerId,
    required this.cropPlotId,
    required this.treatment,
    this.farmerName,
    this.baseline = 'farmer_practice',
    this.status = DemoStatus.created,
    this.stage,
    this.demoYieldKgPerAcre,
    this.practiceYieldKgPerAcre,
    this.yieldGainPct,
    this.observations = const <DemoObservation>[],
    this.pending = false,
  });

  /// Parses the wire shape.
  factory DemoPlot.fromJson(Map<String, Object?> json) => DemoPlot(
    id: _str(json['id']),
    farmerId: _str(json['farmer_id']),
    cropPlotId: _str(json['crop_plot_id']),
    treatment: _str(json['treatment']),
    farmerName: json['farmer_name'] as String?,
    baseline: _str(json['baseline']).isEmpty
        ? 'farmer_practice'
        : _str(json['baseline']),
    status: DemoStatus.parse(json['status'] as String?),
    stage: DemoStage.parse(json['stage'] as String?),
    demoYieldKgPerAcre: _num(json['demo_yield_kg_per_acre']),
    practiceYieldKgPerAcre: _num(json['practice_yield_kg_per_acre']),
    yieldGainPct: _num(json['yield_gain_pct']),
    observations: <DemoObservation>[
      for (final o in _rows(json['observations'])) DemoObservation.fromJson(o),
    ],
    pending: json['_pending'] == true,
  );

  /// Demo plot id (client uuid).
  final String id;

  /// Farmer.
  final String farmerId;

  /// Crop plot under demo.
  final String cropPlotId;

  /// Product or practice being demonstrated.
  final String treatment;

  /// Farmer name for display.
  final String? farmerName;

  /// `farmer_practice` | `comparison_plot`.
  final String baseline;

  /// Lifecycle state.
  final DemoStatus status;

  /// Latest observed stage.
  final DemoStage? stage;

  /// Demo yield.
  final double? demoYieldKgPerAcre;

  /// Farmer-practice yield.
  final double? practiceYieldKgPerAcre;

  /// Server-computed gain in percent.
  final double? yieldGainPct;

  /// Stage observations, oldest first.
  final List<DemoObservation> observations;

  /// Created offline.
  final bool pending;

  /// Gain the screen shows (server value, else computed locally).
  double? get gainPct {
    if (yieldGainPct != null) return yieldGainPct;
    final d = demoYieldKgPerAcre;
    final p = practiceYieldKgPerAcre;
    if (d == null || p == null || p == 0) return null;
    return (d - p) / p * 100;
  }

  /// Transitions the officer may take from here.
  List<DemoStatus> get nextStates => switch (status) {
    DemoStatus.created => <DemoStatus>[DemoStatus.active],
    DemoStatus.active => const <DemoStatus>[],
    DemoStatus.harvested => <DemoStatus>[DemoStatus.reported],
    DemoStatus.reported => const <DemoStatus>[],
  };

  /// Copy with overrides.
  DemoPlot copyWith({
    DemoStatus? status,
    List<DemoObservation>? observations,
    double? demoYieldKgPerAcre,
    double? practiceYieldKgPerAcre,
  }) => DemoPlot(
    id: id,
    farmerId: farmerId,
    cropPlotId: cropPlotId,
    treatment: treatment,
    farmerName: farmerName,
    baseline: baseline,
    status: status ?? this.status,
    stage: observations != null && observations.isNotEmpty
        ? observations.last.stage
        : stage,
    demoYieldKgPerAcre: demoYieldKgPerAcre ?? this.demoYieldKgPerAcre,
    practiceYieldKgPerAcre:
        practiceYieldKgPerAcre ?? this.practiceYieldKgPerAcre,
    yieldGainPct: demoYieldKgPerAcre != null ? null : yieldGainPct,
    observations: observations ?? this.observations,
    pending: pending,
  );

  /// Wire shape (cache).
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'farmer_id': farmerId,
    'farmer_name': farmerName,
    'crop_plot_id': cropPlotId,
    'treatment': treatment,
    'baseline': baseline,
    'status': status.name,
    'stage': stage?.name,
    'demo_yield_kg_per_acre': demoYieldKgPerAcre,
    'practice_yield_kg_per_acre': practiceYieldKgPerAcre,
    'yield_gain_pct': yieldGainPct,
    'observations': <Object?>[for (final o in observations) o.toJson()],
    if (pending) '_pending': true,
  };

  @override
  bool operator ==(Object other) =>
      other is DemoPlot &&
      other.id == id &&
      other.status == status &&
      listEquals(other.observations, observations);

  @override
  int get hashCode => Object.hash(id, status, Object.hashAll(observations));
}
