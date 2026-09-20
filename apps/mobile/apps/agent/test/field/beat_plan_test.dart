import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import 'field_test_support.dart';

void main() {
  testWidgets('A11 lists today plan with its reasons and the target', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.beat));
    await tester.pumpAndSettle();

    expect(find.text('Ramesh Reddy'), findsOneWidget);
    expect(find.text('Lakshmi Devi'), findsOneWidget);
    expect(find.byKey(const Key('beat-target')), findsOneWidget);
    expect(find.text('3 of 10 visited'), findsOneWidget);
    expect(find.byKey(const Key('beat-reason-follow_up_due')), findsOneWidget);
    expect(find.byKey(const Key('beat-reason-pest_alert')), findsOneWidget);
    expect(find.byKey(const Key('beat-reason-credit_due')), findsOneWidget);
    expect(
      find.byKey(const Key('beat-reason-demo_plot_stage')),
      findsOneWidget,
    );
  });

  testWidgets('reorder persists locally and queues one sync op', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);
    deps.api.rows['beat_plan/beat-1'] = FakeServerRow(
      version: 3,
      data: <String, Object?>{'id': 'beat-1'},
    );
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.beat));
    await tester.pumpAndSettle();

    // Drag the second farmer above the first.
    final handle = find.byKey(const Key('beat-drag-farmer-2'));
    await tester.timedDrag(
      handle,
      const Offset(0, -120),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();

    final c = deps.container();
    addTearDown(c.dispose);
    final plan = await c.read(fieldRepositoryProvider).beat(testDate);
    expect(
      <String?>[for (final i in plan!.items) i.farmerId],
      <String?>['farmer-2', 'farmer-1', null],
    );
    expect(plan.status, 'edited');

    final ops = await SyncStore(deps.db).opsIn(<String>['queued']);
    final beatOps = <SyncOp>[
      for (final row in ops)
        if (row.entity == FieldEntities.beatPlan) SyncStore.toOp(row),
    ];
    expect(beatOps, hasLength(1));
    expect(beatOps.single.action, SyncAction.update);
    expect(
      <Object?>[
        for (final item in beatOps.single.payload['items']! as List)
          (item as Map<Object?, Object?>)['id'],
      ],
      <Object?>['item-2', 'item-1', 'item-3'],
    );

    // ... and the queued op reaches the server on the next sync.
    await c.read(syncEngineProvider).syncNow();
    expect(
      deps.api.appliedOps
          .where((op) => op.entity == FieldEntities.beatPlan)
          .length,
      1,
    );
  });

  testWidgets('an item can be removed from the beat', (tester) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.beat));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('beat-remove-farmer-2')));
    await tester.pumpAndSettle();

    expect(find.text('Lakshmi Devi'), findsNothing);
    final c = deps.container();
    addTearDown(c.dispose);
    final plan = await c.read(fieldRepositoryProvider).beat(testDate);
    expect(plan!.items, hasLength(2));
  });

  testWidgets('a farmer the officer picks is added to the plan', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedVillage(deps.db);
    await seedSyncedFarmer(deps.db, id: 'farmer-9', phone: '+919000000009');
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.beat));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('beat-add-farmer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('beat-pick-farmer-farmer-9')));
    await tester.pumpAndSettle();

    final c = deps.container();
    addTearDown(c.dispose);
    final plan = await c.read(fieldRepositoryProvider).beat(testDate);
    expect(plan!.items.last.farmerId, 'farmer-9');
    // An officer-added item has no server id yet, so the update sends its
    // kind and farmer id instead (PUT /v1/me/beat contract).
    expect(plan.items.last.toItemIn()['kind'], 'farmer');
    expect(plan.items.last.toItemIn().containsKey('id'), isFalse);
  });

  testWidgets('the map toggle swaps the list for the village map', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedVillage(deps.db);
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.beat));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('beat-map')), findsNothing);
    await tester.tap(find.byKey(const Key('beat-map-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('beat-map')), findsOneWidget);
    expect(find.text('Ramesh Reddy'), findsNothing);
  });

  testWidgets('start visit goes straight to A30 for that farmer', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedVillage(deps.db);
    await seedSyncedFarmer(deps.db, id: 'farmer-1', phone: '+919000000001');
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.beat));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('beat-start-visit-farmer-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('beat-target')), findsNothing);
  });

  testWidgets('the plan renders from the cache with no network', (
    tester,
  ) async {
    final deps = AgentDeps(online: false);
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);
    deps.field.offline = true;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.beat));
    await tester.pumpAndSettle();

    expect(find.text('Ramesh Reddy'), findsOneWidget);
  });
}
