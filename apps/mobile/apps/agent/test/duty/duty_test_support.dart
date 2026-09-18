import 'package:farmerapp_core/farmerapp_core.dart';

import '../farmers/agent_harness.dart';

/// 2026-09-21 09:00 IST as UTC.
final DateTime dutyT0 = DateTime.utc(2026, 9, 21, 3, 30);

/// A fix at the Hyderabad origin shifted [east] metres.
LocationFix fixAt(DateTime at, {double east = 0, double? speedMps}) =>
    LocationFix(
      point: GeoPoint(17.4, 78.4 + east / (metresPerDegreeLatitude * 0.954)),
      accuracyM: 8,
      time: at,
      speedMps: speedMps,
      bearing: 90,
      provider: 'fused',
    );

/// Accepts the bundled policy on [deps]' database (A05 done earlier).
Future<void> acceptPolicy(AgentDeps deps) async {
  final c = deps.container();
  final policy = c.read(locationPolicyProvider.notifier);
  await policy.load();
  await policy.accept();
  c.dispose();
}

/// Starts a duty session on [deps]' database and buffers [points] fixes.
Future<String> seedOnDuty(AgentDeps deps, {int points = 0}) async {
  deps.sampler.initial = fixAt(deps.now);
  final c = deps.container();
  final duty = c.read(dutyControllerProvider.notifier);
  await duty.goOnDuty();
  final id = c.read(dutyControllerProvider).active!.id;
  final repo = c.read(dutyRepositoryProvider);
  for (var i = 0; i < points; i++) {
    await repo.insertPoint(
      sessionId: id,
      fix: fixAt(deps.now.add(Duration(minutes: 2 * i)), east: 150.0 * i),
      integrity: const IntegritySnapshot(clockDriftS: 2),
      batteryPct: 80 - i,
    );
  }
  await repo.addDistance(id, 150.0 * (points - 1).clamp(0, points));
  c.dispose();
  return id;
}

/// The container behind the running app.
