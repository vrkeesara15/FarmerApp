import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import 'field_test_support.dart';

void main() {
  testWidgets('A60 renders the API numbers against the month targets', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.performance));
    await tester.pumpAndSettle();

    // Verified visits 74 of 100, new farmers 23 of 30 (WC-009 targets).
    expect(find.text('74 of 100'), findsOneWidget);
    expect(find.text('23 of 30'), findsOneWidget);
    expect(find.text('₹12,80,000 of ₹20,00,000'), findsOneWidget);
    expect(find.text('₹4,50,000 of ₹6,00,000'), findsOneWidget);
    // Incentive earned (WC-009 payout through the FA-024 port).
    await tester.scrollUntilVisible(
      find.byKey(const Key('perf-incentive')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('₹691.00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('64%'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('64%'), findsOneWidget);
  });

  testWidgets('the verified-visit trend is drawn from local visits', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedVillage(deps.db);
    await seedSyncedFarmer(deps.db, id: 'farmer-1', phone: '+919000000001');
    final entities = LocalEntities(deps.db);
    for (final (i, status) in <String>[
      'verified',
      'verified',
      'partial',
    ].indexed) {
      await entities.write(
        SyncEntities.visit,
        'visit-$i',
        <String, Object?>{
          'farmer_id': 'farmer-1',
          'purpose': 'advisory',
          'checkin_at': deps.now.subtract(Duration(days: i)).toIso8601String(),
          'checkin_lat': 17.4,
          'checkin_lon': 78.4,
          'status': status,
        },
        version: 1,
        dirty: false,
        now: deps.now,
      );
    }
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.performance));
    await tester.pumpAndSettle();

    final c = deps.container();
    addTearDown(c.dispose);
    final trend = await c.read(fieldRepositoryProvider).verifiedVisitTrend();
    expect(trend, hasLength(14));
    // Only the two verified visits count (VV-005), on their own IST days.
    expect(trend.reduce((a, b) => a + b), 2);
    expect(trend.last, 1);
    await tester.scrollUntilVisible(
      find.byKey(const Key('perf-trend')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('perf-trend')), findsOneWidget);
    expect(find.byKey(const Key('sparkline-bar-13')), findsOneWidget);
  });

  testWidgets('a tenant with no targets shows actuals only', (tester) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    deps.field.performanceOut = const Performance(
      from: '$testMonth-01',
      to: testDate,
      verifiedVisits: 74,
      farmersAdded: 23,
    );
    await seedFieldCaches(deps, performance: false);
    final c = deps.container();
    addTearDown(c.dispose);
    await c
        .read(fieldRepositoryProvider)
        .refreshPerformance(from: '$testMonth-01', to: testDate);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.performance));
    await tester.pumpAndSettle();

    expect(find.text('74'), findsOneWidget);
    expect(find.text('No target set'), findsNWidgets(4));
    await tester.scrollUntilVisible(
      find.text('Shown once your company activates the incentive rules.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Shown once your company activates the incentive rules.'),
      findsOneWidget,
    );
  });

  testWidgets('with no cache and no network A60 explains itself', (
    tester,
  ) async {
    final deps = AgentDeps(online: false);
    addTearDown(deps.dispose);
    deps.field.offline = true;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.performance));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('performance-empty')), findsOneWidget);
  });
}
