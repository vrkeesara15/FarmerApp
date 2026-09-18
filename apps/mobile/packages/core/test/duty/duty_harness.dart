import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../sync/sync_harness.dart';

/// 2026-09-21 09:00 IST as UTC (a Monday).
final DateTime dutyT0 = DateTime.utc(2026, 9, 21, 3, 30);

/// 20:00 IST that day as UTC.
final DateTime autoEndT0 = DateTime.utc(2026, 9, 21, 14, 30);

/// Everything the duty flow talks to, scriptable.
class DutyDeps {
  /// Creates the dependencies over an in-memory database.
  DutyDeps({DateTime? now})
    : db = newDb(),
      clock = FakeClock(now ?? dutyT0),
      ids = SeqIds(),
      api = FakeSyncApi(),
      sampler = FakeLocationSampler(),
      service = FakeForegroundDutyService(),
      alerts = FakeDutyAlerts(),
      conditions = FakeDeviceConditionsMonitor(),
      probe = FakeDeviceIntegrityProbe(),
      policyApi = FakePolicyApi(),
      permissions = FakePermissionGate(),
      tokens = InMemoryTokenStore(deviceId: 'device-1');

  /// The database.
  final AppDatabase db;

  /// Settable clock.
  final FakeClock clock;

  /// Sequential ids (`op-0001`, ...).
  final SeqIds ids;

  /// Sync server.
  final FakeSyncApi api;

  /// GPS.
  final FakeLocationSampler sampler;

  /// Foreground service.
  final FakeForegroundDutyService service;

  /// Notifications.
  final FakeDutyAlerts alerts;

  /// Wi-Fi / charging / battery.
  final FakeDeviceConditionsMonitor conditions;

  /// Root / mock probes.
  final FakeDeviceIntegrityProbe probe;

  /// Policy endpoints.
  final FakePolicyApi policyApi;

  /// Runtime permissions.
  final FakePermissionGate permissions;

  /// Device id `device-1`.
  final InMemoryTokenStore tokens;

  /// Overrides for a container or a widget test.
  List<Override> overrides() => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock.call),
    idGeneratorProvider.overrideWithValue(ids.call),
    syncApiProvider.overrideWithValue(api),
    locationSamplerProvider.overrideWithValue(sampler),
    foregroundDutyServiceProvider.overrideWithValue(service),
    dutyAlertsProvider.overrideWithValue(alerts),
    deviceConditionsProvider.overrideWithValue(conditions),
    deviceIntegrityProbeProvider.overrideWithValue(probe),
    policyApiProvider.overrideWithValue(policyApi),
    permissionGateProvider.overrideWithValue(permissions),
    tokenStoreProvider.overrideWithValue(tokens),
    appVersionProvider.overrideWithValue('0.1.0+1'),
    dutyTickerProvider.overrideWithValue(const Stream<void>.empty()),
  ];

  /// A bare container.
  ProviderContainer container() => ProviderContainer(overrides: overrides());

  /// Closes everything.
  Future<void> dispose() async {
    await sampler.dispose();
    await conditions.dispose();
    await db.close();
  }
}

/// A fix [east] / [north] metres from the Hyderabad origin at [at].
LocationFix fixAt(
  DateTime at, {
  double east = 0,
  double north = 0,
  double? speedMps,
  double accuracy = 8,
  bool isMock = false,
}) {
  const origin = GeoPoint(17.4, 78.4);
  final dLat = north / metresPerDegreeLatitude;
  final dLon = east / (metresPerDegreeLatitude * 0.954);
  return LocationFix(
    point: GeoPoint(origin.latitude + dLat, origin.longitude + dLon),
    accuracyM: accuracy,
    time: at,
    speedMps: speedMps,
    bearing: 90,
    isMock: isMock,
    provider: 'fused',
  );
}

/// Accepts the bundled policy so the toggle is allowed.
Future<void> acceptPolicy(ProviderContainer c) async {
  final policy = c.read(locationPolicyProvider.notifier);
  await policy.load();
  await policy.accept();
}

/// Queued (or any-state) outbox rows in seq order.
Future<List<OutboxRow>> outboxRows(AppDatabase db) =>
    SyncStore(db).opsIn(OutboxState.values.map((s) => s.name));
