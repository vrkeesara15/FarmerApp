import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import '../visits/visit_test_support.dart';
import 'field_test_support.dart';

void main() {
  testWidgets('A61 shows km by day, the allowance and the claim list', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.travel));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('travel-day-2026-09-20')), findsOneWidget);
    expect(find.byKey(const Key('travel-day-2026-09-19')), findsOneWidget);
    // The 168 km day is capped at the tenant's 150 km.
    expect(find.text('Capped at 150 km'), findsOneWidget);
    expect(find.text('150.0 km'), findsOneWidget);
    expect(find.byKey(const Key('travel-ta-total')), findsOneWidget);
    expect(find.text('₹480'), findsOneWidget);
    expect(
      find.byKey(const Key('travel-claim-claim-server-1')),
      findsOneWidget,
    );
  });

  testWidgets('a claim with a receipt queues offline, then syncs', (
    tester,
  ) async {
    final deps = AgentDeps(online: false);
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);
    deps.field.offline = true;
    deps.api.offline = true;
    deps.camera.enqueue(testJpeg());
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.travel));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('travel-add-claim')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('claim-type-bus')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('claim-amount')), '120');
    await tester.pumpAndSettle();

    // A claim without a receipt is refused, not silently queued.
    await tester.tap(find.byKey(const Key('claim-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('claim-receipt-missing')), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('claim-take-photo')));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('claim-receipt-ready')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('claim-note')),
      'Bus to Kondapur',
    );
    await tester.tap(find.byKey(const Key('claim-save')));
    await tester.pumpAndSettle();

    // Queued: the op waits for the receipt upload to finish.
    final store = SyncStore(deps.db);
    final rows = await store.opsIn(<String>['queued']);
    final claimRow = rows.firstWhere(
      (r) => r.entity == FieldEntities.travelClaim,
    );
    final op = SyncStore.toOp(claimRow);
    expect(op.action, SyncAction.create);
    expect(op.payload['type'], 'bus');
    expect(op.payload['amount_paise'], 12000);
    expect(op.payload['note'], 'Bus to Kondapur');
    expect('${op.payload['receipt_uri']}', startsWith('upload:'));
    expect(claimRow.dependsOnUploadId, isNotNull);
    expect(deps.api.appliedOps, isEmpty);

    // It shows on A61 straight away, marked as waiting.
    expect(find.text('Waiting to sync'), findsOneWidget);
    expect(find.text('Bus fare · ₹120.00'), findsOneWidget);

    // Back online, the receipt uploads and the claim reaches the server.
    deps.api.offline = false;
    final c = deps.container();
    addTearDown(c.dispose);
    await c.read(syncEngineProvider).syncNow();
    final applied = deps.api.appliedOps.firstWhere(
      (o) => o.entity == FieldEntities.travelClaim,
    );
    expect('${applied.payload['receipt_uri']}', startsWith('blob://'));
    expect(await store.opsIn(<String>['queued']), isEmpty);
  });

  testWidgets('with no statement and no network A61 explains itself', (
    tester,
  ) async {
    final deps = AgentDeps(online: false);
    addTearDown(deps.dispose);
    deps.field.offline = true;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.travel));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('travel-empty')), findsOneWidget);
  });
}
