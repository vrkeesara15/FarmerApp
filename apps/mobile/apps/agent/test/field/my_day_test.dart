import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../duty/duty_test_support.dart';
import '../farmers/agent_harness.dart';
import 'field_test_support.dart';

void main() {
  testWidgets('A12 shows the server track, stops, visits and processed km', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await acceptPolicy(deps);
    await seedOnDuty(deps, points: 5);
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.myDay));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my-day-map')), findsOneWidget);
    expect(find.text('24.5'), findsOneWidget);
    expect(find.text('Processed by the server'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('day-gap-gap-1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('day-gap-gap-1')), findsOneWidget);
    expect(find.text('Your cluster head sees these reasons.'), findsOneWidget);
  });

  testWidgets('a gap reason queues offline and shows on the gap', (
    tester,
  ) async {
    final deps = AgentDeps(online: false);
    addTearDown(deps.dispose);
    await acceptPolicy(deps);
    await seedOnDuty(deps, points: 5);
    await seedFieldCaches(deps);
    deps.field.offline = true;
    deps.api.offline = true;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.myDay));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('day-gap-reason-gap-1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('day-gap-reason-gap-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gap-reason-vehicle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('gap-note')),
      'Puncture near Kondapur',
    );
    await tester.tap(find.byKey(const Key('gap-save')));
    await tester.pumpAndSettle();

    // Queued, not sent.
    final rows = await SyncStore(deps.db).opsIn(<String>['queued']);
    final op = SyncStore.toOp(
      rows.firstWhere((r) => r.entity == FieldEntities.trackGap),
    );
    expect(op.entityId, 'gap-1');
    expect(op.action, SyncAction.create);
    expect(op.payload['reason'], 'vehicle');
    expect(op.payload['note'], 'Puncture near Kondapur');
    expect(deps.api.appliedOps, isEmpty);

    // The screen already shows the reason, with no round trip.
    await tester.scrollUntilVisible(
      find.byKey(const Key('day-gap-gap-1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Vehicle trouble · Puncture near Kondapur'),
      findsOneWidget,
    );

    // It reaches the server when the network comes back.
    deps.api.offline = false;
    final c = deps.container();
    addTearDown(c.dispose);
    await c.read(syncEngineProvider).syncNow();
    expect(
      deps.api.appliedOps
          .where((op) => op.entity == FieldEntities.trackGap)
          .single
          .entityId,
      'gap-1',
    );
  });

  testWidgets('without a server day the km is the client estimate', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await acceptPolicy(deps);
    await seedOnDuty(deps, points: 5);
    deps.field.offline = true;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.myDay));
    await tester.pumpAndSettle();

    expect(find.text('Estimated on this phone'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('my-day-gaps')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('my-day-gaps')), findsOneWidget);
  });
}
