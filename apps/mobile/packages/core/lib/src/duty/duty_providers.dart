import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/open_database.dart';
import '../i18n/generated/core_localizations.dart';
import '../state/settings.dart';
import '../sync/sync_providers.dart';
import '../utils/format.dart';
import 'device_integrity.dart';
import 'duty_controller.dart';
import 'duty_platform.dart';
import 'duty_repository.dart';
import 'location_policy_controller.dart';
import 'location_sampler.dart';
import 'policy_api.dart';

/// Copy the duty flow needs outside the widget tree (foreground
/// notification, VV-007 prompt, notices), taken from the ARB files at the
/// current locale.
@immutable
class DutyCopy {
  /// Creates the copy.
  const DutyCopy(this._l10n);

  /// Copy at [locale].
  factory DutyCopy.forLocale(Locale locale) =>
      DutyCopy(lookupCoreLocalizations(locale));

  final CoreLocalizations _l10n;

  /// Persistent notification title.
  String get notificationTitle => _l10n.dutyNotificationTitle;

  /// Persistent notification text with the elapsed time.
  String notificationText(Duration elapsed) =>
      _l10n.dutyElapsed(formatElapsed(elapsed));

  /// Notification channel name (Android settings).
  String get channelName => _l10n.dutyChannelName;

  /// Alerts channel name (Android settings).
  String get alertsChannelName => _l10n.dutyAlertsChannelName;

  /// "Still on duty?"
  String get promptTitle => _l10n.dutyPromptTitle;

  /// "Ending at 20:00"
  String promptBody(DateTime autoEndUtc) =>
      _l10n.dutyPromptBody(formatTimeIst(autoEndUtc));

  /// "Duty ended"
  String get endedTitle => _l10n.dutyEndedTitle;

  /// "Your day ended automatically at 20:00."
  String autoEndedBody(DateTime atUtc) =>
      _l10n.dutyAutoEndedBody(formatTimeIst(atUtc));

  /// "The server ended your duty (idle or end of day)."
  String get serverEndedBody => _l10n.dutyServerEndedBody;
}

/// GPS sampler; the agent app overrides it with [GeolocatorLocationSampler].
final Provider<LocationSampler> locationSamplerProvider =
    Provider<LocationSampler>((ref) => FakeLocationSampler());

/// Foreground service; the agent app overrides it with
/// `FlutterForegroundDutyService`.
final Provider<ForegroundDutyService> foregroundDutyServiceProvider =
    Provider<ForegroundDutyService>((ref) => FakeForegroundDutyService());

/// Local notifications; the agent app overrides it with `LocalDutyAlerts`.
final Provider<DutyAlerts> dutyAlertsProvider = Provider<DutyAlerts>(
  (ref) => FakeDutyAlerts(),
);

/// Wi-Fi / charging / battery; the agent app overrides it with
/// `PlusDeviceConditionsMonitor`.
final Provider<DeviceConditionsMonitor> deviceConditionsProvider =
    Provider<DeviceConditionsMonitor>((ref) => FakeDeviceConditionsMonitor());

/// Runtime permissions; the agent app overrides it with
/// `PermissionHandlerGate`.
final Provider<PermissionGate> permissionGateProvider =
    Provider<PermissionGate>((ref) => FakePermissionGate());

/// Root / mock probes; the agent app overrides it with
/// [SafeDeviceIntegrityProbe].
final Provider<DeviceIntegrityProbe> deviceIntegrityProbeProvider =
    Provider<DeviceIntegrityProbe>((ref) => FakeDeviceIntegrityProbe());

/// `kv` key of the persisted clock drift.
const String clockDriftKey = 'integrity.clock_drift_s';

/// Clock drift tracker, persisted to `kv` on every change; the app's HTTP
/// clients feed it through `onServerDate`.
final Provider<ClockDriftTracker> clockDriftTrackerProvider =
    Provider<ClockDriftTracker>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return ClockDriftTracker(
        onChanged: (drift) => db.setValue(clockDriftKey, '$drift'),
      );
    });

/// Restores the persisted drift into the tracker (once per app start).
Future<void> restoreClockDrift(Ref ref) async {
  final raw = await ref.read(appDatabaseProvider).getValue(clockDriftKey);
  final drift = raw == null ? null : int.tryParse(raw);
  if (drift != null) ref.read(clockDriftTrackerProvider).restore(drift);
}

/// FA-028 signals for duty starts, points and visits.
final Provider<DeviceIntegrity> deviceIntegrityProvider =
    Provider<DeviceIntegrity>(
      (ref) => DeviceIntegrity(
        probe: ref.watch(deviceIntegrityProbeProvider),
        clock: ref.watch(clockDriftTrackerProvider),
      ),
    );

/// Policy endpoints; the agent app overrides it with [HttpPolicyApi].
final Provider<PolicyApi> policyApiProvider = Provider<PolicyApi>(
  (ref) => FakePolicyApi(),
);

/// App version sent with duty sessions and acceptances; the apps override
/// it with their pubspec version.
final Provider<String> appVersionProvider = Provider<String>((ref) => '0.1.0');

/// Drives [DutyController.tick] every 30 s; tests override it with an
/// empty stream and call `tick()` themselves.
final Provider<Stream<void>> dutyTickerProvider = Provider<Stream<void>>(
  (ref) => Stream<void>.periodic(const Duration(seconds: 30)),
);

/// Copy for notifications at the current app language.
final Provider<DutyCopy> dutyCopyProvider = Provider<DutyCopy>(
  (ref) => DutyCopy.forLocale(
    ref.watch(settingsProvider).locale ?? const Locale('en'),
  ),
);

/// Duty sessions and the location buffer.
final Provider<DutyRepository> dutyRepositoryProvider =
    Provider<DutyRepository>(
      (ref) => DutyRepository(ref.watch(appDatabaseProvider)),
    );

/// A05 / VV-010 policy state.
final NotifierProvider<LocationPolicyController, LocationPolicyState>
locationPolicyProvider =
    NotifierProvider<LocationPolicyController, LocationPolicyState>(
      LocationPolicyController.new,
    );

/// The DutyToggle state.
final NotifierProvider<DutyController, DutyState> dutyControllerProvider =
    NotifierProvider<DutyController, DutyState>(DutyController.new);

/// IST day bounds `[from, to)` of [nowUtc] as UTC instants.
(DateTime, DateTime) istDayBounds(DateTime nowUtc) {
  final local = nowUtc.toUtc().add(istOffset);
  final from = DateTime.utc(
    local.year,
    local.month,
    local.day,
  ).subtract(istOffset);
  return (from, from.add(const Duration(days: 1)));
}

/// A12 today (IST), live.
final StreamProvider<MyDay> myDayProvider = StreamProvider<MyDay>((ref) {
  final (from, to) = istDayBounds(ref.watch(clockProvider)());
  return ref.watch(dutyRepositoryProvider).watchDay(from, to);
});
