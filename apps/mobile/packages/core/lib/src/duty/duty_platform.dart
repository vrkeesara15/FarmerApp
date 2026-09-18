import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;

/// The Android foreground service with the persistent "On duty — location
/// on" notification (FA-010). Started only after a duty session row
/// exists; stopped before the session ends.
abstract interface class ForegroundDutyService {
  /// Starts the service with the notification.
  Future<void> start({required String title, required String text});

  /// Updates the notification (elapsed time).
  Future<void> update({String? title, String? text});

  /// Stops the service and removes the notification.
  Future<void> stop();

  /// Running right now.
  Future<bool> isRunning();
}

/// Records calls for tests.
class FakeForegroundDutyService implements ForegroundDutyService {
  bool _running = false;

  /// Times [start] was called.
  int starts = 0;

  /// Times [stop] was called.
  int stops = 0;

  /// Times [update] was called.
  int updates = 0;

  /// Last notification title.
  String? title;

  /// Last notification text.
  String? text;

  /// Synchronous view of the running flag.
  bool get running => _running;

  @override
  Future<void> start({required String title, required String text}) async {
    starts += 1;
    _running = true;
    this.title = title;
    this.text = text;
  }

  @override
  Future<void> update({String? title, String? text}) async {
    updates += 1;
    if (title != null) this.title = title;
    if (text != null) this.text = text;
  }

  @override
  Future<void> stop() async {
    stops += 1;
    _running = false;
  }

  @override
  Future<bool> isRunning() async => _running;
}

/// Local notifications the duty flow needs (VV-007 "Still on duty?" prompt
/// ten minutes before auto-end, and one-off notices).
abstract interface class DutyAlerts {
  /// Schedules (replacing) the auto-end prompt for [at] (UTC).
  Future<void> schedulePrompt({
    required DateTime at,
    required String title,
    required String body,
  });

  /// Cancels the prompt.
  Future<void> cancelPrompt();

  /// Shows a notice now (auto-ended, ended by the server).
  Future<void> notice({required String title, required String body});
}

/// A scheduled prompt as recorded by [FakeDutyAlerts].
@immutable
class ScheduledPrompt {
  /// Creates the record.
  const ScheduledPrompt(this.at, this.title, this.body);

  /// When.
  final DateTime at;

  /// Title.
  final String title;

  /// Body.
  final String body;
}

/// Records calls for tests.
class FakeDutyAlerts implements DutyAlerts {
  /// The pending prompt, if any.
  ScheduledPrompt? pending;

  /// Every prompt ever scheduled.
  final List<ScheduledPrompt> scheduled = <ScheduledPrompt>[];

  /// Every notice shown.
  final List<ScheduledPrompt> notices = <ScheduledPrompt>[];

  /// Times [cancelPrompt] was called.
  int cancels = 0;

  @override
  Future<void> schedulePrompt({
    required DateTime at,
    required String title,
    required String body,
  }) async {
    pending = ScheduledPrompt(at, title, body);
    scheduled.add(pending!);
  }

  @override
  Future<void> cancelPrompt() async {
    cancels += 1;
    pending = null;
  }

  @override
  Future<void> notice({required String title, required String body}) async {
    notices.add(ScheduledPrompt(DateTime.now().toUtc(), title, body));
  }
}

/// What decides an early batch upload (VV-001: "every 15 min or on
/// Wi-Fi / charging") and the battery level on each point (VV-002).
@immutable
class DeviceConditions {
  /// Creates the snapshot.
  const DeviceConditions({
    this.onWifi = false,
    this.charging = false,
    this.batteryPct,
  });

  /// Connected over Wi-Fi.
  final bool onWifi;

  /// Charging or full on a charger.
  final bool charging;

  /// Battery level 0-100, if known.
  final int? batteryPct;

  /// Cheap upload window.
  bool get uploadFriendly => onWifi || charging;

  @override
  bool operator ==(Object other) =>
      other is DeviceConditions &&
      other.onWifi == onWifi &&
      other.charging == charging &&
      other.batteryPct == batteryPct;

  @override
  int get hashCode => Object.hash(onWifi, charging, batteryPct);
}

/// Reads Wi-Fi / charging / battery and reports changes.
abstract interface class DeviceConditionsMonitor {
  /// Current state.
  Future<DeviceConditions> read();

  /// Emits on every change.
  Stream<DeviceConditions> get changes;
}

/// Scriptable monitor for tests and previews.
class FakeDeviceConditionsMonitor implements DeviceConditionsMonitor {
  /// Creates the monitor.
  FakeDeviceConditionsMonitor([
    this._value = const DeviceConditions(batteryPct: 80),
  ]);

  final StreamController<DeviceConditions> _controller =
      StreamController<DeviceConditions>.broadcast();
  DeviceConditions _value;

  /// Current state.
  DeviceConditions get value => _value;

  /// Sets the state and emits it.
  void set(DeviceConditions next) {
    _value = next;
    _controller.add(next);
  }

  @override
  Future<DeviceConditions> read() async => _value;

  @override
  Stream<DeviceConditions> get changes => _controller.stream;

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}

/// Runtime permissions the onboarding explainer (A06) asks for.
enum AppPermission {
  /// Fine location while in use.
  location,

  /// Background location ("Allow all the time"), asked after [location].
  backgroundLocation,

  /// In-app camera (FA-012 farm photo, FA-015 visit photos).
  camera,

  /// Notifications (persistent duty notification, auto-end prompt).
  notifications,
}

/// Result of one permission request.
enum PermissionOutcome {
  /// Granted.
  granted,

  /// Denied this time; can be asked again.
  denied,

  /// Denied with "don't ask again" (open settings).
  permanentlyDenied,
}

/// Asks the OS for permissions; the fake is scripted.
abstract interface class PermissionGate {
  /// Current status without prompting.
  Future<PermissionOutcome> status(AppPermission permission);

  /// Prompts (or opens the settings page for background location).
  Future<PermissionOutcome> request(AppPermission permission);

  /// Opens the app's system settings page.
  Future<void> openSettings();
}

/// Scriptable gate for tests and previews.
class FakePermissionGate implements PermissionGate {
  /// Creates the gate; everything granted on request by default.
  FakePermissionGate({Map<AppPermission, PermissionOutcome>? answers})
    : answers = <AppPermission, PermissionOutcome>{
        for (final p in AppPermission.values)
          p: answers?[p] ?? PermissionOutcome.granted,
      };

  /// What [request] answers per permission.
  final Map<AppPermission, PermissionOutcome> answers;

  /// Granted so far.
  final Set<AppPermission> granted = <AppPermission>{};

  /// Requests in order.
  final List<AppPermission> requests = <AppPermission>[];

  /// Times [openSettings] was called.
  int settingsOpened = 0;

  @override
  Future<PermissionOutcome> status(AppPermission permission) async =>
      granted.contains(permission)
      ? PermissionOutcome.granted
      : PermissionOutcome.denied;

  @override
  Future<PermissionOutcome> request(AppPermission permission) async {
    requests.add(permission);
    final outcome = answers[permission]!;
    if (outcome == PermissionOutcome.granted) granted.add(permission);
    return outcome;
  }

  @override
  Future<void> openSettings() async => settingsOpened += 1;
}
