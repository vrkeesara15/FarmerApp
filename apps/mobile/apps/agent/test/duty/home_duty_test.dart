import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_agent/screens/home/home_screen.dart';
import 'package:farmerapp_agent/screens/home/my_day_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import 'duty_test_support.dart';

/// FA-010 on A10: the toggle creates the session, starts the service and
/// the sampler, shows elapsed time and pending points; off ends it. A12
/// lists the session with km and counts.
void main() {
  testWidgets('blocked toggle: no session, no sampling, "Review policy" link', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    deps.now = dutyT0;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.home));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Off duty'), findsOneWidget);
    expect(
      find.text('Accept the location policy to go on duty'),
      findsOneWidget,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Off duty'), findsOneWidget);
    expect(deps.sampler.starts, 0);
    expect(deps.dutyService.starts, 0);
    expect(await SyncStore(deps.db).opsIn(<String>['queued']), isEmpty);
  });

  testWidgets('duty on → session op, service, sampler, elapsed and pending '
      'points; duty off → end op and everything stopped', (tester) async {
    usePhoneSurface(tester);
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    deps.now = dutyT0;
    await acceptPolicy(deps);
    deps.sampler.initial = fixAt(dutyT0);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.home));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('On duty'), findsOneWidget);
    expect(find.text('On duty for 0:00'), findsOneWidget);
    expect(find.text('0 points waiting to upload'), findsOneWidget);
    expect(find.text('Ends automatically at 20:00'), findsOneWidget);
    expect(deps.dutyService.running, isTrue);
    expect(deps.dutyService.title, 'On duty — location on');
    expect(deps.sampler.isRunning, isTrue);
    expect(deps.alerts.pending!.body, 'Ending at 20:00');
    final ops = await SyncStore(deps.db).opsIn(<String>['queued']);
    expect(ops.map((o) => o.entity), <String>[
      'policy_acceptance',
      'duty_session',
    ]);
    expect(SyncStore.payloadOf(ops.last)['policy_version'], '2026-09-v1');

    // Fixes arrive; the pending count follows.
    deps.sampler.emit(fixAt(dutyT0, speedMps: 2));
    await tester.pumpAndSettle();
    deps.sampler.emit(
      fixAt(dutyT0.add(const Duration(minutes: 2)), east: 300, speedMps: 2),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 points waiting to upload'), findsOneWidget);

    // Elapsed time after a tick.
    deps.now = dutyT0.add(const Duration(hours: 1, minutes: 30));
    final ctx = tester.element(find.byType(HomeScreen));
    final container = ProviderScope.containerOf(ctx);
    await container.read(dutyControllerProvider.notifier).tick();
    await tester.pumpAndSettle();
    expect(find.text('On duty for 1:30'), findsOneWidget);

    // A12 shows the active session.
    await tester.tap(find.byKey(const Key('home-my-day')));
    await tester.pumpAndSettle();
    expect(find.byType(MyDayScreen), findsOneWidget);
    expect(find.text('Duty since 09:00'), findsOneWidget);
    expect(find.textContaining('0.3 km today'), findsOneWidget);
    expect(find.byKey(const Key('my-day-gaps')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Off duty'), findsOneWidget);
    expect(deps.dutyService.running, isFalse);
    expect(deps.sampler.isRunning, isFalse);
    expect(deps.alerts.pending, isNull);
    final all = await SyncStore(deps.db).opsIn(<String>['queued']);
    expect(all.map((o) => '${o.entity}/${o.action}'), <String>[
      'policy_acceptance/create',
      'duty_session/create',
      'location_batch/create',
      'duty_session/update',
    ]);
    expect(SyncStore.payloadOf(all.last)['end_reason'], 'manual');
    // Nothing samples after that.
    deps.sampler.emit(fixAt(deps.now.add(const Duration(minutes: 5))));
    await tester.pumpAndSettle();
    expect(deps.sampler.droppedWhileStopped, hasLength(1));
  });

  testWidgets('a notice and the integrity banner show on A10', (tester) async {
    usePhoneSurface(tester);
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    deps.now = dutyT0;
    await acceptPolicy(deps);
    deps.sampler.initial = null; // no fix → notice
    deps.probe.rooted = true;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.home));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('duty-notice')), findsOneWidget);
    expect(
      find.text('Could not get your location. Turn on location and try again.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('banner-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('duty-notice')), findsNothing);
    // A rooted device shows the banner once a start reports it; nothing is
    // blocked.
    deps.sampler.initial = fixAt(dutyT0);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('On duty'), findsOneWidget);
    expect(find.byKey(const Key('integrity-banner')), findsOneWidget);
    expect(
      find.text('Some device checks reported issues; visits may be reviewed.'),
      findsOneWidget,
    );
  });

  testWidgets('A12 empty state and a finished session', (tester) async {
    usePhoneSurface(tester);
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    deps.now = dutyT0;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.myDay));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my-day-empty')), findsOneWidget);
    expect(find.text('No duty today yet'), findsOneWidget);
  });

  testWidgets('bottom nav reaches Farmers and Me', (tester) async {
    usePhoneSurface(tester);
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.home));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Farmers'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('farmers-add')), findsOneWidget);
  });
}
