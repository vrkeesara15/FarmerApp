import '../catalog/rest_json_client.dart';
import 'advisory_models.dart';

/// The M7 farmer advisory REST calls: crop calendar (FM-007), farm
/// weather (FM-008), district alerts (FM-009) and the FA-007 push token
/// and notification inbox. Every call answers a [RestResponse]; status 0
/// means the request never reached the server.
abstract interface class AdvisoryApi {
  /// `GET /v1/me/calendar`.
  Future<RestResponse> calendar();

  /// `PATCH /v1/calendar/tasks/{id}` `{status?, reminder_enabled?,
  /// version?}`.
  Future<RestResponse> updateTask(String id, Map<String, Object?> body);

  /// `GET /v1/farms/{id}/weather`.
  Future<RestResponse> weather(String farmId);

  /// `GET /v1/alerts` (the farmer's own district).
  Future<RestResponse> alerts({String? district, String? cropId});

  /// `GET /v1/notifications`.
  Future<RestResponse> notifications({
    String? cursor,
    int limit = 50,
    bool unreadOnly = false,
  });

  /// `POST /v1/notifications/{id}/read`.
  Future<RestResponse> markNotificationRead(String id);

  /// `POST /v1/notifications/read-all`.
  Future<RestResponse> markAllNotificationsRead();

  /// `POST /v1/devices/me/push-token`.
  Future<RestResponse> registerPushToken({
    required String token,
    String platform = 'android',
    String? deviceId,
    String? appVersion,
  });

  /// `POST /v1/devices/me/push-token/remove`.
  Future<RestResponse> removePushToken(String token);
}

/// [AdvisoryApi] over HTTP.
class HttpAdvisoryApi implements AdvisoryApi {
  /// Creates the client.
  HttpAdvisoryApi(this._rest);

  final RestJsonClient _rest;

  @override
  Future<RestResponse> calendar() => _rest.get('/v1/me/calendar');

  @override
  Future<RestResponse> updateTask(String id, Map<String, Object?> body) =>
      _rest.patch('/v1/calendar/tasks/$id', body);

  @override
  Future<RestResponse> weather(String farmId) =>
      _rest.get('/v1/farms/$farmId/weather');

  @override
  Future<RestResponse> alerts({String? district, String? cropId}) => _rest.get(
    '/v1/alerts',
    query: <String, Object?>{'district': ?district, 'crop_id': ?cropId},
  );

  @override
  Future<RestResponse> notifications({
    String? cursor,
    int limit = 50,
    bool unreadOnly = false,
  }) => _rest.get(
    '/v1/notifications',
    query: <String, Object?>{
      'cursor': ?cursor,
      'limit': limit,
      if (unreadOnly) 'unread_only': true,
    },
  );

  @override
  Future<RestResponse> markNotificationRead(String id) =>
      _rest.post('/v1/notifications/$id/read', const <String, Object?>{});

  @override
  Future<RestResponse> markAllNotificationsRead() =>
      _rest.post('/v1/notifications/read-all', const <String, Object?>{});

  @override
  Future<RestResponse> registerPushToken({
    required String token,
    String platform = 'android',
    String? deviceId,
    String? appVersion,
  }) => _rest.post('/v1/devices/me/push-token', <String, Object?>{
    'token': token,
    'platform': platform,
    'device_id': ?deviceId,
    'app_version': ?appVersion,
  });

  @override
  Future<RestResponse> removePushToken(String token) => _rest.post(
    '/v1/devices/me/push-token/remove',
    <String, Object?>{'token': token},
  );
}

/// In-memory advisory API for tests and previews. Holds one calendar, one
/// forecast per farm, the district alerts and the caller's inbox, and
/// applies the server rules the screens depend on (task versions, the
/// `version_conflict` answer, read stamps).
class FakeAdvisoryApi implements AdvisoryApi {
  /// Creates the fake.
  FakeAdvisoryApi({DateTime Function()? clock})
    : _now = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _now;

  /// Every call answers status 0 while true.
  bool offline = false;

  /// Calls made, e.g. `GET /v1/me/calendar`.
  final List<String> calls = <String>[];

  /// Bodies of the writes, by call.
  final List<(String, Map<String, Object?>)> writes =
      <(String, Map<String, Object?>)>[];

  /// `CalendarOut` body (null: no calendar yet).
  Map<String, Object?>? calendarBody;

  /// `WeatherOut` per farm id.
  final Map<String, Map<String, Object?>> weatherByFarm =
      <String, Map<String, Object?>>{};

  /// Farms whose forecast is unavailable (503 `weather_unavailable`).
  final Set<String> weatherUnavailable = <String>{};

  /// `OutbreakAlertOut` rows.
  final List<Map<String, Object?>> alertRows = <Map<String, Object?>>[];

  /// Districts the alert list reports.
  final List<String> districts = <String>[];

  /// `NotificationOut` rows, newest first.
  final List<Map<String, Object?>> notificationRows = <Map<String, Object?>>[];

  /// Registered push tokens (newest last).
  final List<Map<String, Object?>> pushTokens = <Map<String, Object?>>[];

  /// Tokens removed with `/push-token/remove`.
  final List<String> removedPushTokens = <String>[];

  int _n = 0;

  RestResponse _answer(int status, [Map<String, Object?>? body]) =>
      RestResponse(status, body ?? const <String, Object?>{});

  Future<RestResponse> _handle(
    String call,
    RestResponse Function() answer, {
    Map<String, Object?>? body,
  }) async {
    calls.add(call);
    if (body != null) writes.add((call, body));
    if (offline) return const RestResponse(0);
    return answer();
  }

  /// Every task of the seeded calendar.
  Iterable<Map<String, Object?>> get taskRows sync* {
    for (final p in (calendarBody?['plots'] as List?) ?? const <Object?>[]) {
      if (p is! Map) continue;
      for (final t in (p['tasks'] as List?) ?? const <Object?>[]) {
        if (t is Map<String, Object?>) yield t;
      }
    }
  }

  /// Moves the sowing date of [cropPlotId] to [sowingDate], the way the
  /// server does (FM-007): pending tasks move with it and keep their ids,
  /// done tasks are never touched.
  void moveSowingDate(String cropPlotId, DateTime sowingDate) {
    for (final p in (calendarBody?['plots'] as List?) ?? const <Object?>[]) {
      if (p is! Map || p['crop_plot_id'] != cropPlotId) continue;
      final old = parseIsoDate(p['sowing_date']);
      p['sowing_date'] = isoDay(sowingDate);
      if (old == null) continue;
      final shift = sowingDate.difference(old).inDays;
      for (final t in (p['tasks'] as List?) ?? const <Object?>[]) {
        if (t is! Map || t['status'] == 'done') continue;
        final due = parseIsoDate(t['due_date']);
        if (due != null) {
          t['due_date'] = isoDay(due.add(Duration(days: shift)));
        }
        final end = parseIsoDate(t['end_date']);
        if (end != null) {
          t['end_date'] = isoDay(end.add(Duration(days: shift)));
        }
        t['basis_sowing_date'] = isoDay(sowingDate);
        t['reminded_at'] = null;
        t['version'] = ((t['version'] as num?)?.toInt() ?? 0) + 1;
      }
    }
  }

  /// Appends a `NotificationOut` row (as the server would).
  Map<String, Object?> addNotification({
    required String kind,
    required String route,
    Map<String, Object?> data = const <String, Object?>{},
    String? id,
    DateTime? createdAt,
    bool read = false,
  }) {
    final row = <String, Object?>{
      'id': id ?? 'notif-${++_n}',
      'tenant_id': 't-1',
      'user_id': 'u-1',
      'kind': kind,
      'title_key': 'notification.$kind.title',
      'body_key': 'notification.$kind.body',
      'data': data,
      'route': route,
      'created_at': (createdAt ?? _now()).toIso8601String(),
      'read_at': read ? _now().toIso8601String() : null,
      'delivery_status': 'delivered',
    };
    notificationRows.insert(0, row);
    return row;
  }

  @override
  Future<RestResponse> calendar() => _handle('GET /v1/me/calendar', () {
    final body = calendarBody;
    if (body == null) {
      return _answer(200, <String, Object?>{
        'farmer_id': 'f-1',
        'today': isoDay(_now()),
        'plots': const <Object?>[],
      });
    }
    return _answer(200, body);
  });

  @override
  Future<RestResponse> updateTask(String id, Map<String, Object?> body) =>
      _handle('PATCH /v1/calendar/tasks/$id', () {
        for (final t in taskRows) {
          if (t['id'] != id) continue;
          final expected = body['version'];
          if (expected is int && expected != t['version']) {
            return _answer(409, <String, Object?>{'code': 'version_conflict'});
          }
          if (body['status'] != null) {
            t['status'] = body['status'];
            t['done_at'] = body['status'] == 'done'
                ? _now().toIso8601String()
                : null;
          }
          if (body['reminder_enabled'] != null) {
            t['reminder_enabled'] = body['reminder_enabled'];
          }
          t['version'] = ((t['version'] as num?)?.toInt() ?? 0) + 1;
          return _answer(200, t);
        }
        return _answer(404, <String, Object?>{'code': 'not_found'});
      }, body: body);

  @override
  Future<RestResponse> weather(String farmId) =>
      _handle('GET /v1/farms/$farmId/weather', () {
        if (weatherUnavailable.contains(farmId)) {
          return _answer(503, <String, Object?>{'code': 'weather_unavailable'});
        }
        final w = weatherByFarm[farmId];
        if (w == null) {
          return _answer(404, <String, Object?>{'code': 'not_found'});
        }
        return _answer(200, w);
      });

  @override
  Future<RestResponse> alerts({String? district, String? cropId}) => _handle(
    'GET /v1/alerts',
    () => _answer(200, <String, Object?>{
      'districts': districts,
      'items': <Object?>[
        for (final a in alertRows)
          if ((district == null || a['district'] == district) &&
              (cropId == null || a['crop_id'] == cropId))
            a,
      ],
    }),
  );

  @override
  Future<RestResponse> notifications({
    String? cursor,
    int limit = 50,
    bool unreadOnly = false,
  }) => _handle('GET /v1/notifications', () {
    final items = <Map<String, Object?>>[
      for (final n in notificationRows)
        if (!unreadOnly || n['read_at'] == null) n,
    ];
    return _answer(200, <String, Object?>{
      'items': items.take(limit).toList(),
      'next_cursor': null,
      'unread': notificationRows.where((n) => n['read_at'] == null).length,
    });
  });

  @override
  Future<RestResponse> markNotificationRead(String id) =>
      _handle('POST /v1/notifications/$id/read', () {
        for (final n in notificationRows) {
          if (n['id'] != id) continue;
          n['read_at'] ??= _now().toIso8601String();
          return _answer(200, n);
        }
        return _answer(404, <String, Object?>{'code': 'not_found'});
      }, body: const <String, Object?>{});

  @override
  Future<RestResponse> markAllNotificationsRead() =>
      _handle('POST /v1/notifications/read-all', () {
        var marked = 0;
        for (final n in notificationRows) {
          if (n['read_at'] == null) {
            n['read_at'] = _now().toIso8601String();
            marked += 1;
          }
        }
        return _answer(200, <String, Object?>{'marked': marked});
      }, body: const <String, Object?>{});

  @override
  Future<RestResponse> registerPushToken({
    required String token,
    String platform = 'android',
    String? deviceId,
    String? appVersion,
  }) {
    final body = <String, Object?>{
      'token': token,
      'platform': platform,
      'device_id': deviceId,
      'app_version': appVersion,
    };
    return _handle('POST /v1/devices/me/push-token', () {
      pushTokens
        ..removeWhere((t) => t['token'] == token)
        ..add(<String, Object?>{
          ...body,
          'id': 'push-${++_n}',
          'token_suffix': token.length <= 6
              ? token
              : token.substring(token.length - 6),
          'last_registered_at': _now().toIso8601String(),
          'active': true,
        });
      return _answer(200, pushTokens.last);
    }, body: body);
  }

  @override
  Future<RestResponse> removePushToken(String token) =>
      _handle('POST /v1/devices/me/push-token/remove', () {
        final before = pushTokens.length;
        pushTokens.removeWhere((t) => t['token'] == token);
        removedPushTokens.add(token);
        return _answer(200, <String, Object?>{
          'removed': before - pushTokens.length,
        });
      }, body: <String, Object?>{'token': token});
}
