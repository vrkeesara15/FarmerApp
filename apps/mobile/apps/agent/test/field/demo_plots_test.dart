import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import '../visits/visit_test_support.dart';

Future<String> _createDemoPlot(WidgetTester tester, AgentDeps deps) async {
  await tester.tap(find.byKey(const Key('demo-new')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('demo-treatment')),
    'Own-brand NPK schedule',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('demo-create')));
  await tester.pumpAndSettle();
  final c = deps.container();
  addTearDown(c.dispose);
  return (await c.read(fieldRepositoryProvider).demoPlots()).single.id;
}

void main() {
  testWidgets('A36 runs a demo plot from creation to reported', (tester) async {
    final deps = AgentDeps(online: false);
    addTearDown(deps.dispose);
    await seedVillage(deps.db);
    await seedSyncedFarmer(deps.db, id: 'farmer-1', phone: '+919000000001');
    deps.api.offline = true;
    deps.field.offline = true;
    deps.camera.enqueue(testJpeg());
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.demoPlots));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('demo-empty')), findsOneWidget);

    // created ...
    final id = await _createDemoPlot(tester, deps);
    expect(find.text('Registered'), findsOneWidget);

    // ... -> active
    await tester.tap(find.byKey(const Key('demo-transition-active')));
    await tester.pumpAndSettle();
    expect(find.text('Running'), findsOneWidget);

    // A stage observation with a photo (NF-004 pipeline, queued upload).
    await tester.tap(find.byKey(const Key('demo-add-observation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('demo-stage-flowering')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('demo-side-both')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('demo-take-photo')));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('demo-note')),
      'Demo rows are two weeks ahead',
    );
    await tester.tap(find.byKey(const Key('demo-observation-save')));
    await tester.pumpAndSettle();
    expect(find.text('Flowering'), findsWidgets);
    expect(find.text('Demo rows are two weeks ahead'), findsOneWidget);

    // ... -> harvested, with the comparison against farmer practice.
    await tester.tap(find.byKey(const Key('demo-enter-yield')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('demo-yield-demo')), '1200');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('demo-yield-practice')),
      '1000',
    );
    await tester.tap(find.byKey(const Key('demo-yield-save')));
    await tester.pumpAndSettle();
    expect(find.text('Harvested'), findsOneWidget);
    expect(find.byKey(const Key('demo-comparison')), findsOneWidget);
    expect(find.text('20% more than farmer practice'), findsOneWidget);

    // ... -> reported.
    await tester.scrollUntilVisible(
      find.byKey(const Key('demo-transition-reported')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('demo-transition-reported')));
    await tester.pumpAndSettle();
    expect(find.text('Reported'), findsOneWidget);

    // Everything was queued offline, in order.
    final rows = await SyncStore(deps.db).opsIn(<String>['queued']);
    final ops = <SyncOp>[
      for (final r in rows)
        if (r.entity == FieldEntities.demoPlot ||
            r.entity == FieldEntities.demoObservation)
          SyncStore.toOp(r),
    ];
    expect(ops.map((o) => '${o.entity}/${o.action.name}'), <String>[
      'demo_plot/create',
      'demo_plot/update',
      'demo_observation/create',
      'demo_plot/update',
      'demo_plot/update',
    ]);
    expect(ops.first.payload['farmer_id'], 'farmer-1');
    expect(ops.first.payload['baseline'], 'farmer_practice');
    final observation = ops.firstWhere(
      (o) => o.entity == FieldEntities.demoObservation,
    );
    expect(observation.payload['demo_plot_id'], id);
    expect(observation.payload['stage'], 'flowering');
    expect(observation.payload['side'], 'both');
    expect(
      '${(observation.payload['photo_uris']! as List).single}',
      startsWith('upload:'),
    );
    final yieldOp = ops.lastWhere(
      (o) =>
          o.entity == FieldEntities.demoPlot &&
          o.payload.containsKey('demo_yield_kg_per_acre'),
    );
    expect(yieldOp.payload['demo_yield_kg_per_acre'], 1200.0);
    expect(yieldOp.payload['practice_yield_kg_per_acre'], 1000.0);
  });

  testWidgets('a reported demo plot takes no more observations', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    deps.field.demoPlotRows = <DemoPlot>[
      const DemoPlot(
        id: 'demo-1',
        farmerId: 'farmer-1',
        farmerName: 'Ramesh Reddy',
        cropPlotId: 'plot-1',
        treatment: 'Own-brand NPK schedule',
        status: DemoStatus.reported,
        demoYieldKgPerAcre: 1200,
        practiceYieldKgPerAcre: 1000,
        yieldGainPct: 20,
      ),
    ];
    final c = deps.container();
    addTearDown(c.dispose);
    await c.read(fieldRepositoryProvider).refreshDemoPlots();
    await tester.pumpWidget(
      deps.app(initialLocation: AppRoutes.demoPlotPath('demo-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reported'), findsOneWidget);
    expect(find.text('20% more than farmer practice'), findsOneWidget);
    final button = tester.widget<AppButton>(
      find.byKey(const Key('demo-add-observation')),
    );
    expect(button.onPressed, isNull);
    expect(find.byKey(const Key('demo-transition-active')), findsNothing);
  });
}
