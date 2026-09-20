import '../catalog/rest_json_client.dart';
import 'field_models.dart';

/// The read endpoints behind the M7 officer screens answered with a
/// non-2xx or never answered at all. Every screen falls back to its cache.
class FieldUnavailableException implements Exception {
  /// Creates the exception.
  const FieldUnavailableException([this.status = 0, this.code]);

  /// HTTP status; 0 = the request never completed.
  final int status;

  /// Problem `code`, when the server sent one.
  final String? code;

  /// The device could not reach the server (or it failed with 5xx).
  bool get offline => status == 0 || status >= 500;

  @override
  String toString() => 'FieldUnavailableException($status, $code)';
}

/// What the officer's own FCM registration looks like on the wire.
enum PushPlatform {
  /// Android.
  android,

  /// iOS.
  ios,

  /// Web.
  web,
}

/// The M7 field endpoints the officer app reads (writes go through the
/// outbox, except the ones that need connectivity by design: attendance
/// OTP, flag explanations, push token registration).
///
/// Contracts: docs/prs/M7-field-p1-api.md, docs/prs/M7-rules.md (VA-005).
abstract interface class FieldApi {
  /// FA-007 `POST /v1/devices/me/push-token`.
  Future<void> registerPushToken(
    String token, {
    PushPlatform platform = PushPlatform.android,
    String? appVersion,
  });

  /// FA-007 `POST /v1/devices/me/push-token/remove` (logout, wipe).
  Future<void> removePushToken(String token);

  /// FA-007 `GET /v1/notifications` (every page merged, newest first).
  Future<Inbox> notifications();

  /// FA-007 `POST /v1/notifications/read-all`.
  Future<void> markAllRead();

  /// VV-008 `GET /v1/me/day?date=`.
  Future<DayTimeline> day(String date);

  /// FA-018 `GET /v1/me/beat?date=`; null when the day has no plan.
  Future<BeatPlan?> beat(String date);

  /// FA-018 `PUT /v1/me/beat?date=`.
  Future<BeatPlan> putBeat(String date, BeatPlan plan);

  /// FA-024 `GET /v1/me/performance?from=&to=` with `GET /v1/targets`.
  Future<Performance> performance({required String from, required String to});

  /// FA-023 `GET /v1/travel/statement?month=YYYY-MM`.
  Future<TravelStatement> travelStatement(String month);

  /// VA-005 `GET /v1/flags/mine` (both states, resolved last).
  Future<List<MyFlag>> myFlags();

  /// VA-005 `POST /v1/flags/mine/{id}/explanations`.
  Future<MyFlag> explainFlag(String flagId, String body);

  /// FA-027 `GET /v1/meetings` (newest first) and `GET /v1/meetings/{id}`.
  Future<List<Meeting>> meetings();

  /// FA-027 `GET /v1/meetings/{id}`.
  Future<Meeting> meeting(String id);

  /// FA-027 `POST /v1/meetings/{id}/attendance/otp` — sends the farmer a
  /// code; returns the masked phone.
  Future<String> sendAttendanceOtp(String meetingId, String farmerId);

  /// FA-026 `GET /v1/demo-plots` and `GET /v1/demo-plots/{id}`.
  Future<List<DemoPlot>> demoPlots();

  /// FA-026 `GET /v1/demo-plots/{id}`.
  Future<DemoPlot> demoPlot(String id);
}

/// [FieldApi] over [RestJsonClient].
class HttpFieldApi implements FieldApi {
  /// Creates the client.
  HttpFieldApi(this._rest);

  final RestJsonClient _rest;

  Map<String, Object?> _ok(RestResponse r) {
    if (!r.ok) throw FieldUnavailableException(r.status, r.code);
    return r.body;
  }

  @override
  Future<void> registerPushToken(
    String token, {
    PushPlatform platform = PushPlatform.android,
    String? appVersion,
  }) async {
    _ok(
      await _rest.post('/v1/devices/me/push-token', <String, Object?>{
        'token': token,
        'platform': platform.name,
        'app_version': ?appVersion,
      }),
    );
  }

  @override
  Future<void> removePushToken(String token) async {
    _ok(
      await _rest.post('/v1/devices/me/push-token/remove', <String, Object?>{
        'token': token,
      }),
    );
  }

  @override
  Future<Inbox> notifications() async {
    final items = <InboxItem>[];
    var unread = 0;
    String? cursor;
    var page = 0;
    do {
      final body = _ok(
        await _rest.get(
          '/v1/notifications',
          query: <String, Object?>{'cursor': cursor, 'limit': 100},
        ),
      );
      if (page == 0) unread = (body['unread'] as num?)?.toInt() ?? 0;
      for (final row in (body['items'] as List?) ?? const <Object?>[]) {
        if (row is! Map) continue;
        items.add(InboxItem.fromJson(Map<String, Object?>.from(row)));
      }
      cursor = body['next_cursor'] as String?;
      page += 1;
    } while (cursor != null && page < 10);
    return Inbox(items: items, unread: unread);
  }

  @override
  Future<void> markAllRead() async {
    _ok(
      await _rest.post('/v1/notifications/read-all', const <String, Object?>{}),
    );
  }

  @override
  Future<DayTimeline> day(String date) async => DayTimeline.fromJson(
    _ok(await _rest.get('/v1/me/day', query: <String, Object?>{'date': date})),
  );

  @override
  Future<BeatPlan?> beat(String date) async {
    final r = await _rest.get(
      '/v1/me/beat',
      query: <String, Object?>{'date': date},
    );
    if (r.status == 404) return null;
    return BeatPlan.fromJson(_ok(r));
  }

  @override
  Future<BeatPlan> putBeat(String date, BeatPlan plan) async =>
      BeatPlan.fromJson(
        _ok(
          await _rest.put(
            '/v1/me/beat',
            plan.toUpdate(),
            query: <String, Object?>{'date': date},
          ),
        ),
      );

  @override
  Future<Performance> performance({
    required String from,
    required String to,
  }) async {
    final base = Performance.fromJson(
      _ok(
        await _rest.get(
          '/v1/me/performance',
          query: <String, Object?>{'from': from, 'to': to},
        ),
      ),
    );
    // Targets are a separate (WC-009) endpoint; a tenant without targets
    // simply shows actuals.
    final r = await _rest.get(
      '/v1/targets',
      query: <String, Object?>{
        'month': from.substring(0, 7),
        'subject_type': 'officer',
      },
    );
    if (!r.ok) return base;
    final rows = (r.body['items'] as List?) ?? const <Object?>[];
    if (rows.isEmpty || rows.first is! Map) return base;
    return base.with2(
      targets: PerformanceTargets.fromJson(
        Map<String, Object?>.from(rows.first! as Map),
      ),
    );
  }

  @override
  Future<TravelStatement> travelStatement(String month) async =>
      TravelStatement.fromJson(
        month,
        _ok(
          await _rest.get(
            '/v1/travel/statement',
            query: <String, Object?>{'month': month},
          ),
        ),
      );

  @override
  Future<List<MyFlag>> myFlags() async {
    final out = <MyFlag>[];
    for (final state in const <String>['open', 'resolved']) {
      final body = _ok(
        await _rest.get(
          '/v1/flags/mine',
          query: <String, Object?>{'state': state, 'limit': 50},
        ),
      );
      for (final row in (body['items'] as List?) ?? const <Object?>[]) {
        if (row is! Map) continue;
        out.add(MyFlag.fromJson(Map<String, Object?>.from(row)));
      }
    }
    return out;
  }

  @override
  Future<MyFlag> explainFlag(String flagId, String body) async {
    _ok(
      await _rest.post('/v1/flags/mine/$flagId/explanations', <String, Object?>{
        'body': body,
      }),
    );
    return MyFlag.fromJson(_ok(await _rest.get('/v1/flags/mine/$flagId')));
  }

  @override
  Future<List<Meeting>> meetings() async {
    final body = _ok(
      await _rest.get('/v1/meetings', query: <String, Object?>{'limit': 50}),
    );
    return <Meeting>[
      for (final row in (body['items'] as List?) ?? const <Object?>[])
        if (row is Map) Meeting.fromJson(Map<String, Object?>.from(row)),
    ];
  }

  @override
  Future<Meeting> meeting(String id) async =>
      Meeting.fromJson(_ok(await _rest.get('/v1/meetings/$id')));

  @override
  Future<String> sendAttendanceOtp(String meetingId, String farmerId) async {
    final body = _ok(
      await _rest.post(
        '/v1/meetings/$meetingId/attendance/otp',
        <String, Object?>{'farmer_id': farmerId},
      ),
    );
    return (body['phone_masked'] as String?) ?? '';
  }

  @override
  Future<List<DemoPlot>> demoPlots() async {
    final body = _ok(
      await _rest.get('/v1/demo-plots', query: <String, Object?>{'limit': 50}),
    );
    return <DemoPlot>[
      for (final row in (body['items'] as List?) ?? const <Object?>[])
        if (row is Map) DemoPlot.fromJson(Map<String, Object?>.from(row)),
    ];
  }

  @override
  Future<DemoPlot> demoPlot(String id) async =>
      DemoPlot.fromJson(_ok(await _rest.get('/v1/demo-plots/$id')));
}

/// In-memory field server for tests, goldens and previews.
class FakeFieldApi implements FieldApi {
  /// Every call throws [FieldUnavailableException] while true.
  bool offline = false;

  /// What `GET /v1/notifications` answers.
  Inbox inbox = const Inbox();

  /// What `GET /v1/me/day` answers per date.
  final Map<String, DayTimeline> days = <String, DayTimeline>{};

  /// What `GET /v1/me/beat` answers per date.
  final Map<String, BeatPlan> beats = <String, BeatPlan>{};

  /// What `GET /v1/me/performance` answers.
  Performance? performanceOut;

  /// What `GET /v1/travel/statement` answers per month.
  final Map<String, TravelStatement> statements = <String, TravelStatement>{};

  /// What `GET /v1/flags/mine` answers.
  List<MyFlag> flags = const <MyFlag>[];

  /// What `GET /v1/meetings` answers.
  List<Meeting> meetingRows = const <Meeting>[];

  /// What `GET /v1/demo-plots` answers.
  List<DemoPlot> demoPlotRows = const <DemoPlot>[];

  /// Tokens registered through [registerPushToken].
  final List<String> registeredTokens = <String>[];

  /// Tokens cleared through [removePushToken].
  final List<String> removedTokens = <String>[];

  /// `read-all` calls.
  int readAllCalls = 0;

  /// Beat plans written through [putBeat].
  final List<BeatPlan> putBeats = <BeatPlan>[];

  /// Explanations posted, as `(flagId, body)`.
  final List<(String, String)> explanations = <(String, String)>[];

  /// Attendance OTPs sent, as `(meetingId, farmerId)`.
  final List<(String, String)> otps = <(String, String)>[];

  /// Masked phone [sendAttendanceOtp] answers.
  String phoneMasked = '+91 ••••• ••210';

  void _check() {
    if (offline) throw const FieldUnavailableException();
  }

  @override
  Future<void> registerPushToken(
    String token, {
    PushPlatform platform = PushPlatform.android,
    String? appVersion,
  }) async {
    _check();
    registeredTokens.add(token);
  }

  @override
  Future<void> removePushToken(String token) async {
    _check();
    removedTokens.add(token);
  }

  @override
  Future<Inbox> notifications() async {
    _check();
    return inbox;
  }

  @override
  Future<void> markAllRead() async {
    _check();
    readAllCalls += 1;
    inbox = Inbox(
      items: <InboxItem>[
        for (final i in inbox.items)
          InboxItem(
            id: i.id,
            kind: i.kind,
            titleKey: i.titleKey,
            bodyKey: i.bodyKey,
            route: i.route,
            createdAt: i.createdAt,
            readAt: i.readAt ?? DateTime.utc(2026, 9, 21),
            data: i.data,
          ),
      ],
    );
  }

  @override
  Future<DayTimeline> day(String date) async {
    _check();
    return days[date] ?? DayTimeline(date: date, fromServer: true);
  }

  @override
  Future<BeatPlan?> beat(String date) async {
    _check();
    return beats[date];
  }

  @override
  Future<BeatPlan> putBeat(String date, BeatPlan plan) async {
    _check();
    putBeats.add(plan);
    final stored = BeatPlan(
      id: plan.id,
      planDate: plan.planDate,
      status: 'edited',
      target: plan.target,
      items: plan.items,
      version: plan.version + 1,
    );
    beats[date] = stored;
    return stored;
  }

  @override
  Future<Performance> performance({
    required String from,
    required String to,
  }) async {
    _check();
    return performanceOut ?? Performance(from: from, to: to);
  }

  @override
  Future<TravelStatement> travelStatement(String month) async {
    _check();
    return statements[month] ?? TravelStatement(month: month);
  }

  @override
  Future<List<MyFlag>> myFlags() async {
    _check();
    return flags;
  }

  @override
  Future<MyFlag> explainFlag(String flagId, String body) async {
    _check();
    explanations.add((flagId, body));
    final flag = flags.firstWhere((f) => f.id == flagId);
    final updated = MyFlag(
      id: flag.id,
      ruleId: flag.ruleId,
      severity: flag.severity,
      title: flag.title,
      state: flag.state,
      createdAt: flag.createdAt,
      ruleTitle: flag.ruleTitle,
      canExplain: flag.canExplain,
      outcome: flag.outcome,
      explanations: <FlagExplanation>[
        ...flag.explanations,
        FlagExplanation(
          id: 'exp-${flag.explanations.length + 1}',
          body: body,
          createdAt: DateTime.utc(2026, 9, 21),
        ),
      ],
      metrics: flag.metrics,
    );
    flags = <MyFlag>[for (final f in flags) f.id == flagId ? updated : f];
    return updated;
  }

  @override
  Future<List<Meeting>> meetings() async {
    _check();
    return meetingRows;
  }

  @override
  Future<Meeting> meeting(String id) async {
    _check();
    return meetingRows.firstWhere((m) => m.id == id);
  }

  @override
  Future<String> sendAttendanceOtp(String meetingId, String farmerId) async {
    _check();
    otps.add((meetingId, farmerId));
    return phoneMasked;
  }

  @override
  Future<List<DemoPlot>> demoPlots() async {
    _check();
    return demoPlotRows;
  }

  @override
  Future<DemoPlot> demoPlot(String id) async {
    _check();
    return demoPlotRows.firstWhere((d) => d.id == id);
  }
}
