import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'duty_platform.dart';

/// Notification channel of the persistent duty notification.
const String dutyNotificationChannelId = 'duty';

/// Notification channel of the auto-end prompt and notices.
const String dutyAlertsChannelId = 'duty_alerts';

/// Notification id of the VV-007 prompt.
const int dutyPromptNotificationId = 1010;

/// Notification id of duty notices.
const int dutyNoticeNotificationId = 1011;

/// [ForegroundDutyService] over `flutter_foreground_task`
/// (`foregroundServiceType="location"` in the manifest, Android 8-14).
///
/// The service keeps the process alive and the notification visible; the
/// sampling itself runs in the app isolate (`DutyController`), which the
/// service protects from being killed. `stopWithTask` is false so swiping
/// the app away does not silently end the shift: the notification stays
/// until the officer goes off duty or the auto-end fires.
class FlutterForegroundDutyService implements ForegroundDutyService {
  /// Creates the service wrapper.
  FlutterForegroundDutyService({required this.channelName});

  /// Localised channel name shown in Android settings.
  final String channelName;

  bool _initialised = false;

  void _init() {
    if (_initialised) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: dutyNotificationChannelId,
        channelName: channelName,
        onlyAlertOnce: true,
        showWhen: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        stopWithTask: false,
      ),
    );
    _initialised = true;
  }

  @override
  Future<void> start({required String title, required String text}) async {
    _init();
    if (await FlutterForegroundTask.isRunningService) {
      await update(title: title, text: text);
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 1001,
      serviceTypes: <ForegroundServiceTypes>[ForegroundServiceTypes.location],
      notificationTitle: title,
      notificationText: text,
    );
  }

  @override
  Future<void> update({String? title, String? text}) async {
    _init();
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  @override
  Future<void> stop() async {
    _init();
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<bool> isRunning() {
    _init();
    return FlutterForegroundTask.isRunningService;
  }
}

/// [DutyAlerts] over `flutter_local_notifications` (exact alarm for the
/// prompt; falls back to inexact when the OS refuses exact alarms).
class LocalDutyAlerts implements DutyAlerts {
  /// Creates the alerts.
  LocalDutyAlerts({
    required this.channelName,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Localised channel name.
  final String channelName;

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialised = false;

  Future<void> _init() async {
    if (_initialised) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialised = true;
  }

  NotificationDetails _details() => NotificationDetails(
    android: AndroidNotificationDetails(
      dutyAlertsChannelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  @override
  Future<void> schedulePrompt({
    required DateTime at,
    required String title,
    required String body,
  }) async {
    await _init();
    final when = tz.TZDateTime.from(at.toUtc(), tz.UTC);
    try {
      await _plugin.zonedSchedule(
        id: dutyPromptNotificationId,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } on Exception {
      await _plugin.zonedSchedule(
        id: dutyPromptNotificationId,
        title: title,
        body: body,
        scheduledDate: when,
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> cancelPrompt() async {
    await _init();
    await _plugin.cancel(id: dutyPromptNotificationId);
  }

  @override
  Future<void> notice({required String title, required String body}) async {
    await _init();
    await _plugin.show(
      id: dutyNoticeNotificationId,
      title: title,
      body: body,
      notificationDetails: _details(),
    );
  }
}

/// [DeviceConditionsMonitor] over `connectivity_plus` + `battery_plus`.
class PlusDeviceConditionsMonitor implements DeviceConditionsMonitor {
  /// Creates the monitor.
  PlusDeviceConditionsMonitor({Connectivity? connectivity, Battery? battery})
    : _connectivity = connectivity ?? Connectivity(),
      _battery = battery ?? Battery();

  final Connectivity _connectivity;
  final Battery _battery;

  static bool _charging(BatteryState s) =>
      s == BatteryState.charging || s == BatteryState.full;

  @override
  Future<DeviceConditions> read() async {
    final results = await _connectivity.checkConnectivity();
    int? level;
    try {
      level = await _battery.batteryLevel;
    } on Exception {
      level = null;
    }
    return DeviceConditions(
      onWifi: results.contains(ConnectivityResult.wifi),
      charging: _charging(await _battery.batteryState),
      batteryPct: level,
    );
  }

  @override
  Stream<DeviceConditions> get changes async* {
    final controller = StreamController<void>();
    final subs = <StreamSubscription<Object?>>[
      _connectivity.onConnectivityChanged.listen(controller.add),
      _battery.onBatteryStateChanged.listen(controller.add),
    ];
    try {
      await for (final _ in controller.stream) {
        yield await read();
      }
    } finally {
      for (final s in subs) {
        await s.cancel();
      }
      await controller.close();
    }
  }
}

/// [PermissionGate] over `permission_handler`. Background location is
/// requested only after foreground location is granted (Play policy: the
/// in-app rationale on A06 precedes the system "Allow all the time" page).
class PermissionHandlerGate implements PermissionGate {
  /// Creates the gate.
  const PermissionHandlerGate();

  static Permission _of(AppPermission p) => switch (p) {
    AppPermission.location => Permission.locationWhenInUse,
    AppPermission.backgroundLocation => Permission.locationAlways,
    AppPermission.camera => Permission.camera,
    AppPermission.notifications => Permission.notification,
  };

  static PermissionOutcome _outcome(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return PermissionOutcome.granted;
    if (s.isPermanentlyDenied) return PermissionOutcome.permanentlyDenied;
    return PermissionOutcome.denied;
  }

  @override
  Future<PermissionOutcome> status(AppPermission permission) async =>
      _outcome(await _of(permission).status);

  @override
  Future<PermissionOutcome> request(AppPermission permission) async {
    if (permission == AppPermission.backgroundLocation &&
        !await Permission.locationWhenInUse.isGranted) {
      return PermissionOutcome.denied;
    }
    return _outcome(await _of(permission).request());
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
