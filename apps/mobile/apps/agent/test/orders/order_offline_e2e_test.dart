import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import '../visits/visit_test_support.dart' show testJpeg;
import 'commerce_test_support.dart';

/// FA-020 / FA-021 / FA-025 end to end, offline first: the officer takes an
/// order and a cash payment with the receipt photo in airplane mode; back
/// online, one sync uploads the receipt and the fake server applies the
/// order (priced server-side) and then the payment (pending store
/// reconciliation). Server wins for money on the device afterwards.
void main() {
  testWidgets('offline order + cash → online sync applies both', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final deps = AgentDeps(online: false);
    addTearDown(deps.dispose);
    final server = await seedCommerceWorld(deps);
    // The store's price moved since the catalogue was cached (₹420 → ₹440).
    server.prices['sku-neem-500'] = 44000;
    await preloadCatalog(deps);
    deps.api.offline = true;

    await tester.pumpWidget(
      deps.app(initialLocation: '/orders/new?farmerId=f-1'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('catalog-search')), 'neem');
    await tester.pumpAndSettle();
    await tapIt(
      tester,
      find.descendant(
        of: find.byKey(const Key('product-sku-neem-500')),
        matching: find.byType(AppButton),
      ),
    );
    await tapIt(
      tester,
      find.descendant(
        of: find.byKey(const Key('product-sku-neem-500')),
        matching: find.byType(AppButton),
      ),
    );
    Future<void> tapCart() => tapIt(
      tester,
      find.descendant(
        of: find.byKey(const Key('cart-bar')),
        matching: find.byType(AppButton),
      ),
    );
    await tapCart();
    await tapCart();
    await tapIt(tester, find.byKey(const Key('payment-method-cash')));
    await tapIt(tester, find.byKey(const Key('checkout-submit')));
    deps.camera.enqueue(testJpeg());
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('cash-capture')));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
    await tapIt(tester, find.byKey(const Key('cash-save')));
    expect(find.byKey(const Key('order-queued')), findsOneWidget);
    // Estimate from the cached price: 2 x (420 + 12 %) = ₹940.80.
    expect(find.text('₹940.80', skipOffstage: false), findsWidgets);
    expect(deps.api.requests, isEmpty, reason: 'nothing left the phone');

    // Back online: one sync.
    deps.connectivity.online = true;
    deps.api.offline = false;
    final report = await containerOf(tester).read(syncEngineProvider).syncNow();
    await tester.pumpAndSettle();
    expect(report.ok, isTrue);
    expect(report.uploads, 1);
    expect(report.applied, 2);

    final orderId = server.orders.keys.single;
    final sentOps = deps.api.requests.expand((r) => r.ops).toList();
    expect(sentOps.map((o) => o.entity), <String>['order', 'payment']);
    expect(sentOps.first.payload.containsKey('expected_total_paise'), isFalse);
    final payment = server.payments.values.single;
    expect(payment['order_id'], orderId);
    expect(payment['status'], 'pending_reconciliation');
    expect('${payment['receipt_uri']}', startsWith('blob://fake/receipt/'));
    // Server wins for money: 2 x (440 + 12 %) = ₹985.60.
    expect(payment['amount_paise'], 98560);
    expect(find.byKey(const Key('order-placed')), findsOneWidget);
    expect(find.text('₹985.60', skipOffstage: false), findsWidgets);

    final container = containerOf(tester);
    final view = (await container
        .read(orderRepositoryProvider)
        .order(orderId))!;
    expect(view.order.totalPaise, 98560);
    expect(view.order.status, 'reserved');
    final collections = await container
        .read(paymentRepositoryProvider)
        .watchCollections(
          t0.subtract(const Duration(days: 1)),
          t0.add(const Duration(days: 1)),
        )
        .first;
    expect(
      collections.items.single.state,
      CollectionState.pendingReconciliation,
    );
    expect(collections.totalsByMode, <String, int>{'cash': 98560});
    expect(
      (await container.read(syncEngineProvider).status()).kind,
      SyncStatusKind.synced,
    );
  });
}
