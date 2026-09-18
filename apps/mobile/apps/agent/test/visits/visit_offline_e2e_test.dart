import 'package:farmerapp_agent/screens/visits/start_visit_screen.dart';
import 'package:farmerapp_agent/screens/visits/summary_screen.dart';
import 'package:farmerapp_agent/screens/visits/visit_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import 'visit_test_support.dart';

/// FA-014 .. FA-017 end to end, offline: on duty → A22 Start visit → A30
/// check-in → A31 in-app photo → check-out → A33; then the network comes
/// back and every op reaches the FakeSyncApi in order (duty first, then
/// the visit create, its photo, the check-out update) with the photo
/// uploaded before its op.
void main() {
  testWidgets('offline visit, then online sync applies all ops in order', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final deps = AgentDeps(online: false);
    addTearDown(deps.dispose);
    deps.api.offline = true;
    await seedVisitWorld(deps);
    deps.camera.enqueue(testJpeg());

    await tester.pumpWidget(deps.app(initialLocation: '/farmers/f-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-start-visit')));
    await tester.pumpAndSettle();
    expect(find.byType(StartVisitScreen), findsOneWidget);
    expect(
      find.text('You are offline. Your work is saved and will sync later.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('visit-inside')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('visit-purpose-scouting')));
    await tapVisible(tester, find.byKey(const Key('visit-check-in')));
    expect(find.byType(VisitScreen), findsOneWidget);
    expect(find.text('Check-in will sync when online'), findsOneWidget);

    // In-app photo (the NF-004 pipeline runs on a real isolate).
    deps.now = deps.now.add(const Duration(minutes: 2));
    await tester.ensureVisible(find.byKey(const Key('visit-take-photo')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('visit-take-photo')));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Use photo'));
    expect(find.text('1 photos'), findsOneWidget);

    // Eight minutes on the farm, then check out.
    deps.now = deps.now.add(const Duration(minutes: 8));
    await tapVisible(tester, find.byKey(const Key('visit-check-out')));
    expect(find.byType(SummaryScreen), findsOneWidget);
    // Inside + photo + duration + integrity; no farmer confirmation.
    expect(
      tester
          .widget<VisitScoreBadge>(find.byKey(const Key('summary-score')))
          .score,
      70,
    );
    expect(find.byKey(const Key('summary-expected')), findsOneWidget);
    expect(find.byKey(const Key('summary-under-minimum')), findsNothing);
    expect(deps.api.appliedOps, isEmpty);

    // Back online: one sync pushes everything.
    deps.api.offline = false;
    deps.connectivity.online = true;
    final container = appContainer(tester, SummaryScreen);
    final report = await container.read(syncEngineProvider).syncNow();
    await tester.pumpAndSettle();
    expect(report.ok, isTrue);
    expect(report.rejected, 0);
    expect(report.uploads, 1);
    expect(
      deps.api.appliedOps.map((o) => '${o.entity}/${o.action.name}'),
      <String>[
        'policy_acceptance/create',
        'duty_session/create',
        'visit/create',
        'visit_photo/create',
        'visit/update',
      ],
    );
    final photo = deps.api.appliedOps.firstWhere(
      (o) => o.entity == 'visit_photo',
    );
    expect(photo.payload['blob_uri'], startsWith('blob://fake/visit_photo/'));
    expect(photo.payload['taken_in_app'], isTrue);
    final checkout = deps.api.appliedOps.last.payload;
    expect(checkout.containsKey('checkout_at'), isTrue);
    expect(await SyncStore(deps.db).opsIn(<String>['queued']), isEmpty);
    final status = await container.read(syncEngineProvider).status();
    expect(status.kind, SyncStatusKind.synced);
  });
}
