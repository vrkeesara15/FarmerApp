import 'dart:async';

import 'package:drift/drift.dart' show Table, TableInfo;

import '../db/app_database.dart';
import '../kisan/kisan_cache.dart';
import '../kisan/kisan_models.dart' show Cached, KisanWrite;
import '../push/push_controller.dart';
import '../push/push_service.dart';
import '../sync/outbox.dart';
import '../sync/sync_models.dart';
import 'advisory_api.dart';
import 'advisory_models.dart';

/// The farmer app's advisory data (FM-007, FM-008, FM-009) and the FA-007
/// inbox: online first, cached in the encrypted database with the time it
/// was fetched so every screen can say "as of" and keep working offline
/// (NF-002). Task changes go out over `PATCH /v1/calendar/tasks/{id}` and
/// fall back to a queued `crop_plot_task` update op.
///
/// It is also the farmer app's [PushTokenRegistry]: the shared FA-007
/// controller (`src/push/`) registers and withdraws this device's token
/// through it.
class AdvisoryRepository implements PushTokenRegistry {
  /// Creates the repository.
  AdvisoryRepository({
    required this.db,
    required this.api,
    required this.outbox,
    required DateTime Function() clock,
    required String Function() ids,
    this.onQueued,
  }) : cache = KisanCache(db, clock: clock),
       _now = clock,
       _newId = ids;

  /// The database.
  final AppDatabase db;

  /// REST calls.
  final AdvisoryApi api;

  /// Offline writes.
  final Outbox outbox;

  /// JSON snapshots with "as of" (shared with the M6 farmer cache).
  final KisanCache cache;

  /// Called after an op was queued, so the app flushes when online.
  final void Function()? onQueued;

  final DateTime Function() _now;
  // ignore: unused_field
  final String Function() _newId;

  /// Cache key of the crop calendar.
  static const String calendarKey = 'calendar';

  /// Cache key of the F42 "what changed" notes, by crop plot.
  static const String calendarChangesKey = 'calendar_changes';

  /// Cache key of the district alerts.
  static const String alertsKey = 'alerts';

  /// Cache key of the dismissed alert ids.
  static const String alertsDismissedKey = 'alerts_dismissed';

  /// Cache key of the notification inbox.
  static const String inboxKey = 'inbox';

  /// `kv` key of the push token registered with the server.
  static const String pushTokenKey = 'kisan.push_token';

  /// Cache key of a farm's forecast.
  static String weatherKey(String farmId) => 'weather.$farmId';

  // --- FM-007 crop calendar -------------------------------------------------

  /// Fetches the calendar and records a "what changed" note per plot whose
  /// pending tasks moved (the sowing date changed). False when offline:
  /// the cache stays.
  Future<bool> refreshCalendar() async {
    final r = await api.calendar();
    if (!r.ok) return false;
    final before = (await _calendar())?.value;
    final after = CropCalendar.fromJson(r.body);
    final now = _now();
    final notes = <String, CalendarChange>{
      for (final n in await _changes().then((m) => m.values)) n.cropPlotId: n,
    };
    for (final plot in after.plots) {
      final change = diffPlotCalendar(
        before?.plot(plot.cropPlotId),
        plot,
        at: now,
      );
      if (change != null) notes[plot.cropPlotId] = change;
    }
    await cache.put(calendarKey, after.toJson());
    await cache.put(calendarChangesKey, <String, Object?>{
      for (final e in notes.entries) e.key: e.value.toJson(),
    });
    return true;
  }

  Future<Cached<CropCalendar>?> _calendar() async =>
      _calendarOf(await cache.get(calendarKey));

  Cached<CropCalendar>? _calendarOf(Snapshot? s) {
    final data = s?.data;
    if (s == null || data is! Map) return null;
    return Cached<CropCalendar>(
      CropCalendar.fromJson(Map<String, Object?>.from(data)),
      s.fetchedAt,
    );
  }

  /// The cached calendar, live (works offline).
  Stream<Cached<CropCalendar>?> watchCalendar() =>
      cache.watch(calendarKey).map(_calendarOf).distinct();

  Future<Map<String, CalendarChange>> _changes() async {
    final data = (await cache.get(calendarChangesKey))?.data;
    if (data is! Map) return <String, CalendarChange>{};
    return <String, CalendarChange>{
      for (final e in data.entries)
        if (e.value is Map)
          '${e.key}': CalendarChange.fromJson(
            Map<String, Object?>.from(e.value! as Map),
          ),
    };
  }

  /// The unseen "what changed" note of [cropPlotId], live.
  Stream<CalendarChange?> watchCalendarChange(String cropPlotId) => cache
      .watch(calendarChangesKey)
      .asyncMap((_) async => (await _changes())[cropPlotId])
      .distinct();

  /// Clears the "what changed" note of [cropPlotId] (the farmer read it).
  Future<void> dismissCalendarChange(String cropPlotId) async {
    final notes = await _changes()
      ..remove(cropPlotId);
    await cache.put(calendarChangesKey, <String, Object?>{
      for (final e in notes.entries) e.key: e.value.toJson(),
    });
  }

  /// F42 mark done / not done.
  Future<KisanWrite> setTaskDone(CalendarTask task, {required bool done}) =>
      _writeTask(task, <String, Object?>{'status': done ? 'done' : 'pending'});

  /// F42 reminder on / off for one task.
  Future<KisanWrite> setTaskReminder(CalendarTask task, {required bool on}) =>
      _writeTask(task, <String, Object?>{'reminder_enabled': on});

  Future<KisanWrite> _writeTask(
    CalendarTask task,
    Map<String, Object?> change,
  ) async {
    final r = await api.updateTask(task.id, <String, Object?>{
      ...change,
      'version': task.version,
    });
    if (r.ok) {
      await _patchCachedTask(
        task.id,
        CalendarTask.fromJson(r.body, cropPlotId: task.cropPlotId),
      );
      return KisanWrite.done;
    }
    if (!r.isNetworkFailure) {
      if (r.code == 'version_conflict') await refreshCalendar();
      return KisanWrite.refused;
    }
    // Offline: apply locally and queue the `crop_plot_task` update op.
    await _patchCachedTask(
      task.id,
      task.copyWith(
        status: change['status'] as String?,
        doneAt: change['status'] == 'done' ? _now() : null,
        reminderEnabled: change['reminder_enabled'] as bool?,
        pending: true,
      ),
    );
    await outbox.enqueueUpdate(
      SyncEntities.cropPlotTask,
      task.id,
      <String, Object?>{...change},
    );
    onQueued?.call();
    return KisanWrite.queued;
  }

  Future<void> _patchCachedTask(String id, CalendarTask updated) async {
    final snap = await cache.get(calendarKey);
    final data = snap?.data;
    if (snap == null || data is! Map) return;
    final calendar = CropCalendar.fromJson(Map<String, Object?>.from(data));
    await cache.put(
      calendarKey,
      CropCalendar(
        farmerId: calendar.farmerId,
        today: calendar.today,
        plots: <CropPlotCalendar>[
          for (final p in calendar.plots)
            CropPlotCalendar(
              cropPlotId: p.cropPlotId,
              farmId: p.farmId,
              cropId: p.cropId,
              cropCode: p.cropCode,
              cropNames: p.cropNames,
              season: p.season,
              sowingDate: p.sowingDate,
              tasks: <CalendarTask>[
                for (final t in p.tasks)
                  if (t.id == id) updated else t,
              ],
            ),
        ],
      ).toJson(),
      fetchedAt: snap.fetchedAt,
    );
  }

  // --- FM-008 weather --------------------------------------------------------

  /// Fetches the forecast of [farmId]; false when offline or when the
  /// provider is down (503 `weather_unavailable`) — the cache stays.
  Future<bool> refreshWeather(String farmId) async {
    final r = await api.weather(farmId);
    if (!r.ok) return false;
    await cache.put(weatherKey(farmId), FarmWeather.fromJson(r.body).toJson());
    return true;
  }

  /// The cached forecast of [farmId], live.
  Stream<Cached<FarmWeather>?> watchWeather(String farmId) =>
      cache.watch(weatherKey(farmId)).map((s) {
        final data = s?.data;
        if (s == null || data is! Map) return null;
        return Cached<FarmWeather>(
          FarmWeather.fromJson(Map<String, Object?>.from(data)),
          s.fetchedAt,
        );
      }).distinct();

  // --- FM-009 alerts ---------------------------------------------------------

  /// Fetches the district alerts; false when offline.
  Future<bool> refreshAlerts() async {
    final r = await api.alerts();
    if (!r.ok) return false;
    await cache.put(alertsKey, r.body['items'] ?? const <Object?>[]);
    return true;
  }

  Future<Set<String>> _dismissedAlerts() async {
    final data = (await cache.get(alertsDismissedKey))?.data;
    return <String>{
      for (final v in (data is List ? data : const <Object?>[])) '$v',
    };
  }

  /// Hides [alertId] on this phone (F44 dismiss); it stays hidden across
  /// restarts and refreshes.
  Future<void> dismissAlert(String alertId) async {
    final done = await _dismissedAlerts()
      ..add(alertId);
    await cache.put(alertsDismissedKey, done.toList()..sort());
  }

  /// Cached alerts the farmer has not dismissed, most severe first, live.
  Stream<Cached<List<OutbreakAlert>>?> watchAlerts() => watchTables(
    db,
    <TableInfo<Table, Object?>>[db.kv],
    () async {
      final snap = await cache.get(alertsKey);
      if (snap == null) return null;
      final dismissed = await _dismissedAlerts();
      final items =
          <OutbreakAlert>[
            for (final a
                in (snap.data is List ? snap.data! as List : const <Object?>[]))
              if (a is Map)
                OutbreakAlert.fromJson(Map<String, Object?>.from(a)),
          ].where((a) => !dismissed.contains(a.id)).toList()..sort((a, b) {
            final s = a.severity.index.compareTo(b.severity.index);
            return s != 0 ? s : b.weekStart.compareTo(a.weekStart);
          });
      return Cached<List<OutbreakAlert>>(items, snap.fetchedAt);
    },
  );

  // --- FA-007 inbox and push -------------------------------------------------

  /// Fetches the inbox; false when offline.
  ///
  /// Rows filed from a push that the server has not listed yet are kept
  /// (a push can arrive before the row shows up in the page), so the
  /// badge never flickers back down after a refresh.
  Future<bool> refreshInbox() async {
    final r = await api.notifications();
    if (!r.ok) return false;
    final server = <AppNotification>[
      for (final n
          in (r.body['items'] is List
              ? r.body['items']! as List
              : const <Object?>[]))
        if (n is Map) AppNotification.fromJson(Map<String, Object?>.from(n)),
    ];
    final ids = <String>{for (final n in server) n.id};
    final local = <AppNotification>[
      for (final n in await _inbox())
        if (!ids.contains(n.id)) n,
    ];
    await _putInbox(<AppNotification>[...server, ...local]);
    return true;
  }

  Future<List<AppNotification>> _inbox() async {
    final data = (await cache.get(inboxKey))?.data;
    return <AppNotification>[
      for (final n in (data is List ? data : const <Object?>[]))
        if (n is Map) AppNotification.fromJson(Map<String, Object?>.from(n)),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _putInbox(List<AppNotification> rows) =>
      cache.put(inboxKey, <Object?>[for (final n in rows) n.toJson()]);

  /// The inbox, newest first, live (works offline).
  Stream<List<AppNotification>> watchInbox() =>
      watchTables(db, <TableInfo<Table, Object?>>[db.kv], _inbox);

  /// Unread count for the home badge, live.
  Stream<int> watchUnreadCount() =>
      watchInbox().map((rows) => rows.where((n) => n.unread).length).distinct();

  /// Marks one row read: online `POST /notifications/{id}/read`, else the
  /// row is marked locally and a `notification` update op is queued.
  Future<KisanWrite> markRead(String id) async {
    final rows = await _inbox();
    final now = _now();
    await _putInbox(<AppNotification>[
      for (final n in rows)
        if (n.id == id) n.readNow(now) else n,
    ]);
    final r = await api.markNotificationRead(id);
    if (r.ok) return KisanWrite.done;
    if (!r.isNetworkFailure) return KisanWrite.refused;
    await outbox.enqueueUpdate(SyncEntities.notification, id, <String, Object?>{
      'read_at': now.toIso8601String(),
    });
    onQueued?.call();
    return KisanWrite.queued;
  }

  /// Marks every row read.
  Future<KisanWrite> markAllRead() async {
    final rows = await _inbox();
    final now = _now();
    await _putInbox(<AppNotification>[for (final n in rows) n.readNow(now)]);
    final r = await api.markAllNotificationsRead();
    if (r.ok) return KisanWrite.done;
    if (!r.isNetworkFailure) return KisanWrite.refused;
    for (final n in rows.where((n) => n.unread)) {
      await outbox.enqueueUpdate(
        SyncEntities.notification,
        n.id,
        <String, Object?>{'read_at': now.toIso8601String()},
      );
    }
    onQueued?.call();
    return KisanWrite.queued;
  }

  /// Files an arriving push in the inbox straight away, so the badge and
  /// F-inbox are right before the next refresh. Returns the row.
  Future<AppNotification> receivePush(PushMessage message) async {
    final row = AppNotification(
      id: message.notificationId ?? 'push-${message.kind}-${_now()}',
      kind: message.kind,
      titleKey: message.titleKey ?? '',
      bodyKey: message.bodyKey ?? '',
      data: message.data,
      route: message.route,
      createdAt: _now(),
    );
    final rows = await _inbox();
    if (rows.any((n) => n.id == row.id)) return row;
    await _putInbox(<AppNotification>[row, ...rows]);
    return row;
  }

  // --- FA-007 push token ------------------------------------------------------

  /// The token last registered with the server, if any.
  Future<String?> registeredPushToken() => db.getValue(pushTokenKey);

  /// Registers [token] with `POST /v1/devices/me/push-token` (after login
  /// and on every FCM rotation). The token is remembered so logout and a
  /// remote wipe can withdraw it.
  @override
  Future<PushRegistration> registerPushToken(
    String token, {
    String platform = 'android',
    String? deviceId,
    String? appVersion,
  }) async {
    final r = await api.registerPushToken(
      token: token,
      platform: platform,
      deviceId: deviceId,
      appVersion: appVersion,
    );
    if (!r.ok) {
      return r.isNetworkFailure
          ? PushRegistration.offline
          : PushRegistration.refused;
    }
    await db.setValue(pushTokenKey, token);
    return PushRegistration.done;
  }

  /// Withdraws the registered token (logout, remote wipe). The token this
  /// phone last registered is used when the controller has none. The local
  /// note is dropped whatever the server answers, so the token is never
  /// reused by the next session on this phone.
  @override
  Future<PushRegistration> clearPushToken([String? token]) async {
    final registered = await registeredPushToken() ?? token;
    await db.removeValue(pushTokenKey);
    if (registered == null) return PushRegistration.done;
    final r = await api.removePushToken(registered);
    if (r.ok) return PushRegistration.done;
    return r.isNetworkFailure
        ? PushRegistration.offline
        : PushRegistration.refused;
  }
}
