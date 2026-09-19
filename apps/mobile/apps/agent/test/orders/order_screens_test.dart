import 'dart:async';

import 'package:farmerapp_agent/screens/orders/catalog_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import '../visits/visit_test_support.dart' show testJpeg;
import 'commerce_test_support.dart';

/// FA-020 / FA-021 / FA-022 officer screens: A50 catalogue (offline search,
/// categories, stock + as of, stale indicator), A51 cart estimates, A52
/// methods (offline reasons), A55 cash → A57 queued, insufficient stock →
/// edit → resend, A53 UPI paid / failed / expired, A54 link, A56 credit
/// approval, A57 invoice share, A58 khata, A59 collections, A10 / A22
/// wiring.
void main() {
  late AgentDeps deps;
  late FakeCommerceServer server;

  Future<void> setUpWorld({bool online = true}) async {
    deps = AgentDeps(online: online);
    deps.api.offline = !online;
    deps.catalogApi.offline = !online;
    deps.payApi.offline = !online;
    deps.khataApi.offline = !online;
    server = await seedCommerceWorld(deps);
  }

  tearDown(() => deps.dispose());

  Future<void> open(WidgetTester tester, String location) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app(initialLocation: location));
    await tester.pumpAndSettle();
  }

  Future<List<OutboxRow>> ops(String entity) async =>
      (await deps.db.select(deps.db.outboxTable).get())
          .where((o) => o.entity == entity)
          .toList();

  group('A50 catalogue', () {
    testWidgets('offline: cached search, categories, stock as of, stale', (
      tester,
    ) async {
      await setUpWorld(online: false);
      await preloadCatalog(deps);
      await open(tester, '/orders/new?farmerId=f-1');
      expect(find.text('For Ramesh Reddy'), findsOneWidget);
      expect(find.byKey(const Key('catalog-freshness')), findsOneWidget);
      expect(
        find.textContaining('may be out of date (as of 20-09-2026 06:00)'),
        findsOneWidget,
      );
      // Own brand first, with the badge.
      expect(find.byType(ProductCard), findsWidgets);
      final first = tester.widget<ProductCard>(find.byType(ProductCard).first);
      expect(first.name, 'Mitra Neem Shakti');
      expect(first.ownBrand, isTrue);
      expect(find.text('Own brand'), findsOneWidget);
      expect(
        find.text('30 in stock at Kondapur Agri Store, as of 06:00'),
        findsOneWidget,
      );
      expect(find.text('Estimated price'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('catalog-search')),
        'chlorant',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('product-sku-cora-150')), findsOneWidget);
      expect(find.byType(ProductCard), findsOneWidget);

      await tester.enterText(find.byKey(const Key('catalog-search')), '');
      await tapIt(tester, find.byKey(const Key('catalog-category-fertiliser')));
      expect(find.byType(ProductCard), findsOneWidget);
      expect(find.byKey(const Key('product-sku-dap-50')), findsOneWidget);

      await tapIt(tester, find.byKey(const Key('catalog-category-seed')));
      expect(find.text('Out of stock, as of 06:00'), findsOneWidget);
      final seed = tester.widget<AppButton>(
        find.descendant(
          of: find.byKey(const Key('product-sku-seed-450')),
          matching: find.byType(AppButton),
        ),
      );
      expect(seed.onPressed, isNull);

      await tapIt(tester, find.byKey(const Key('catalog-category-all')));
      await tapIt(
        tester,
        find.descendant(
          of: find.byKey(const Key('product-sku-neem-500')),
          matching: find.byType(AppButton),
        ),
      );
      expect(find.byKey(const Key('cart-bar')), findsOneWidget);
      expect(find.text('1 in cart'), findsOneWidget);
      expect(find.text('Estimated total ₹470.40'), findsOneWidget);
      // Offline: nothing was fetched.
      expect(deps.catalogApi.calls, isEmpty);
    });

    testWidgets('online first open downloads the catalogue', (tester) async {
      await setUpWorld();
      await open(tester, '/orders/new?farmerId=f-1');
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(deps.catalogApi.calls.first, 'nearest:f-1');
      expect(deps.catalogApi.calls, contains('products:store-1:null'));
      expect(find.byType(ProductCard), findsWidgets);
      expect(
        find.textContaining('Prices and stock as of 20-09-2026 06:00'),
        findsOneWidget,
      );
      expect(find.byType(CatalogScreen), findsOneWidget);
    });

    testWidgets('never downloaded and offline: empty state explains', (
      tester,
    ) async {
      await setUpWorld(online: false);
      await open(tester, '/orders/new?farmerId=f-1');
      expect(find.byKey(const Key('catalog-never')), findsOneWidget);
      expect(
        find.text('The catalogue is not on this phone yet'),
        findsOneWidget,
      );
    });
  });

  Future<void> tapCart(WidgetTester tester) => tapIt(
    tester,
    find.descendant(
      of: find.byKey(const Key('cart-bar')),
      matching: find.byType(AppButton),
    ),
  );

  Future<void> addToCart(
    WidgetTester tester,
    String skuId, {
    int times = 1,
  }) async {
    // Search first, as an officer does; the list is lazy.
    await tester.enterText(
      find.byKey(const Key('catalog-search')),
      const <String, String>{
        'sku-cora-150': 'Coragen',
        'sku-neem-500': 'Neem',
        'sku-dap-50': 'DAP',
      }[skuId]!,
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < times; i++) {
      await tapIt(
        tester,
        find.descendant(
          of: find.byKey(Key('product-$skuId')),
          matching: find.byType(AppButton),
        ),
      );
    }
  }

  group('A51 → A52 → A55 → A57 offline order with cash', () {
    testWidgets('estimates, pickup / delivery, cash receipt, queued order', (
      tester,
    ) async {
      await setUpWorld(online: false);
      await preloadCatalog(deps);
      await open(tester, '/orders/new?farmerId=f-1');
      await addToCart(tester, 'sku-cora-150', times: 2);
      await addToCart(tester, 'sku-neem-500');
      await tapCart(tester);
      // A51: 2 x 1,180 + 18 % and 1 x 420 + 12 %.
      expect(find.text('Cart'), findsOneWidget);
      expect(find.text('Estimated total ₹3,255.20'), findsOneWidget);
      await tapIt(tester, find.byKey(const Key('cart-dec-sku-cora-150')));
      expect(find.text('Estimated total ₹1,862.80'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Prices are estimates'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const Key('cart-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subtotal (estimate)'), findsOneWidget);
      expect(find.text('₹1,862.80'), findsWidgets);
      await tapIt(tester, find.text('Delivery'));
      await tapCart(tester);

      // A52 offline: UPI and link explain why; cash and credit available.
      expect(find.text('Payment'), findsOneWidget);
      expect(find.text('Needs internet: use cash or credit'), findsNWidgets(2));
      expect(find.byKey(const Key('checkout-offline-note')), findsOneWidget);
      await tapIt(tester, find.byKey(const Key('payment-method-upiQr')));
      final submit = tester.widget<AppButton>(
        find.byKey(const Key('checkout-submit')),
      );
      expect(submit.onPressed, isNull, reason: 'UPI cannot be picked offline');
      await tapIt(tester, find.byKey(const Key('payment-method-cash')));
      await tapIt(tester, find.byKey(const Key('checkout-submit')));

      // The order op is queued with sku + qty only.
      final orderOp = (await ops('order')).single;
      final payload = SyncStore.payloadOf(orderOp);
      expect(payload['fulfilment'], 'delivery');
      expect(payload['payment_mode'], 'cash');
      expect(payload['lines'], <Object?>[
        <String, Object?>{'sku_id': 'sku-cora-150', 'qty': 1},
        <String, Object?>{'sku_id': 'sku-neem-500', 'qty': 1},
      ]);

      // A55: in-app camera through NF-004, then save.
      expect(find.text('Cash receipt'), findsOneWidget);
      expect(find.byKey(const Key('cash-amount')), findsOneWidget);
      expect(find.text('₹1,862.80'), findsOneWidget);
      deps.camera.enqueue(testJpeg());
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('cash-capture')));
        await Future<void>.delayed(const Duration(seconds: 3));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cash-preview')), findsOneWidget);
      await tapIt(tester, find.byKey(const Key('cash-save')));
      final payOp = (await ops('payment')).single;
      final pay = SyncStore.payloadOf(payOp);
      expect(pay['mode'], 'cash');
      expect(pay['order_id'], orderOp.entityId);
      expect('${pay['receipt_uri']}', startsWith('upload:'));
      expect(payOp.dependsOnUploadId, isNotNull);

      // A57 queued.
      expect(find.byKey(const Key('order-queued')), findsOneWidget);
      expect(find.text('Order saved, waiting to sync'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('order-share-reason')),
        200,
        scrollable: find.descendant(
          of: find.byKey(const Key('order-body')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total (estimate)'), findsOneWidget);
      expect(find.text('Waiting to sync'), findsOneWidget);
      final share = tester.widget<AppButton>(
        find.byKey(const Key('order-share')),
      );
      expect(share.onPressed, isNull);
      expect(
        find.text(
          'The invoice is issued when the store hands over the order.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    });
  });

  group('A57 insufficient stock', () {
    testWidgets('per-line available, edit with "Use N", resend', (
      tester,
    ) async {
      await setUpWorld();
      await preloadCatalog(deps);
      server.stock['sku-cora-150'] = 2;
      await open(tester, '/orders/new?farmerId=f-1');
      await addToCart(tester, 'sku-cora-150', times: 3);
      await tapCart(tester);
      await tapCart(tester);
      await tapIt(tester, find.byKey(const Key('payment-method-credit')));
      await tapIt(tester, find.byKey(const Key('checkout-submit')));
      // A56 opened on top of A57; the order itself was refused.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-rejected')), findsOneWidget);
      expect(
        find.byKey(const Key('order-rejection-insufficient_stock')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Coragen: 2 available, 3 asked'),
        findsOneWidget,
      );
      await tapIt(tester, find.byKey(const Key('order-edit')));
      expect(find.byKey(const Key('cart-short-notice')), findsOneWidget);
      expect(
        find.text('Only 2 available at the store (asked 3).'),
        findsOneWidget,
      );
      final bar = tester.widget<CartBar>(find.byKey(const Key('cart-bar')));
      expect(bar.onCheckout, isNull, reason: 'short lines block checkout');
      await tapIt(
        tester,
        find.byKey(const Key('cart-use-available-sku-cora-150')),
      );
      expect(find.byKey(const Key('cart-qty-sku-cora-150')), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      await tapCart(tester);
      await tapIt(tester, find.byKey(const Key('payment-method-cash')));
      await tapIt(tester, find.byKey(const Key('checkout-submit')));
      final orderOps = await ops('order');
      expect(orderOps, hasLength(1), reason: 'same op resent');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await containerOf(tester).read(syncEngineProvider).syncNow();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-placed')), findsOneWidget);
      expect(find.text('₹2,784.80'), findsWidgets);
      expect(find.byKey(const Key('order-step-reserved')), findsOneWidget);
    });

    testWidgets('sku_not_recommendable is explained', (tester) async {
      await setUpWorld();
      await preloadCatalog(deps);
      final orders = OrderRepository(
        deps.db,
        Outbox(deps.db, clock: () => deps.now, ids: deps.ids.call),
        ids: deps.ids.call,
      );
      final item = (await CatalogCache(
        deps.db,
        deps.catalogApi,
      ).item('sku-cora-150', storeId: storeId))!;
      final id = await orders.place(
        farmerId: 'f-1',
        storeId: storeId,
        fulfilment: Fulfilment.pickup,
        lines: <CartLine>[CartLine(item: item, qty: 1)],
      );
      deps.api.script = (op) => SyncOpResult(
        opId: op.opId,
        status: SyncResultStatus.rejected,
        entityId: op.entityId,
        error: const SyncError('sku_not_recommendable', 'label claim'),
      );
      await open(tester, '/orders/$id');
      await containerOf(tester).read(syncEngineProvider).syncNow();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('order-rejection-sku_not_recommendable')),
        findsOneWidget,
      );
      expect(find.textContaining('label claim'), findsWidgets);
    });
  });

  group('A53 UPI QR', () {
    Future<String> upiFor(WidgetTester tester) async {
      await preloadCatalog(deps);
      await open(tester, '/orders/new?farmerId=f-1');
      await addToCart(tester, 'sku-neem-500');
      await tapCart(tester);
      await tapCart(tester);
      await tapIt(tester, find.byKey(const Key('payment-method-upiQr')));
      await tapIt(tester, find.byKey(const Key('checkout-submit')));
      return deps.payApi.states.keys.single;
    }

    testWidgets('waiting → paid by polling; the order op synced first', (
      tester,
    ) async {
      await setUpWorld();
      final polled = Completer<void>();
      var polls = 0;
      deps.upiSleep = (d) async {
        polls += 1;
        deps.now = deps.now.add(d);
        if (polls == 2) {
          deps.payApi.states['pay-1'] = 'paid';
          polled.complete();
        }
      };
      final id = await upiFor(tester);
      expect(server.orders, hasLength(1), reason: 'order placed before UPI');
      expect(deps.payApi.created.single['order_id'], server.orders.keys.single);
      await tester.runAsync(() => polled.future);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('upi-panel-paid')), findsOneWidget);
      expect(find.text('Payment received'), findsOneWidget);
      expect(deps.payApi.polls[id], greaterThanOrEqualTo(3));
      await tapIt(tester, find.byKey(const Key('upi-done')));
      expect(find.byKey(const Key('order-placed')), findsOneWidget);
    });

    testWidgets('failed → new QR or cash', (tester) async {
      await setUpWorld();
      deps.upiSleep = (d) async {
        deps.payApi.states['pay-1'] = 'failed';
      };
      await upiFor(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('upi-panel-failed')), findsOneWidget);
      expect(find.text('Payment failed'), findsOneWidget);
      expect(find.text('Show a new QR'), findsOneWidget);
      expect(find.byKey(const Key('upi-cash-instead')), findsOneWidget);
    });

    testWidgets('expired QR stops polling', (tester) async {
      await setUpWorld();
      deps.upiSleep = (d) async => deps.now = deps.now.add(d);
      final id = await upiFor(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('upi-panel-failed')), findsOneWidget);
      expect(find.text('QR expired'), findsOneWidget);
      expect(deps.now, t0.add(const Duration(minutes: 15)));
      final n = deps.payApi.polls[id]!;
      await tester.pumpAndSettle();
      expect(deps.payApi.polls[id], n);
    });
  });

  testWidgets('A54 payment link: channel, resend by WhatsApp', (tester) async {
    await setUpWorld();
    await preloadKhata(deps);
    await open(tester, '/farmers/f-1/collect');
    await tester.pumpAndSettle();
    expect(find.text('Balance due ₹12,500.00'), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('payment-method-paymentLink')));
    await tester.enterText(find.byKey(const Key('checkout-amount')), '5000');
    await tapIt(tester, find.byKey(const Key('checkout-submit')));
    expect(deps.payApi.created.single, <String, Object?>{
      'farmer_id': 'f-1',
      'store_id': storeId,
      'amount_paise': 500000,
      'mode': 'payment_link',
      'channel': 'sms',
    });
    expect(find.text('Payment link sent'), findsOneWidget);
    expect(
      find.text('Sent by SMS. Ask the farmer to open the link and pay.'),
      findsOneWidget,
    );
    await tapIt(tester, find.byKey(const Key('link-resend-whatsapp')));
    expect(deps.payApi.created.last['channel'], 'whatsapp');
    expect(
      find.text('Sent by WhatsApp. Ask the farmer to open the link and pay.'),
      findsOneWidget,
    );
  });

  testWidgets('A52 dues: amount over the balance is refused', (tester) async {
    await setUpWorld();
    await preloadKhata(deps);
    await open(tester, '/farmers/f-1/collect');
    await tapIt(tester, find.byKey(const Key('payment-method-cash')));
    expect(find.text('Credit is only for orders'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('checkout-amount')), '20000');
    await tapIt(tester, find.byKey(const Key('checkout-submit')));
    expect(find.text('Enter an amount up to ₹12,500.00'), findsOneWidget);
  });

  testWidgets('A56 credit over the limit → approval → proceeds', (
    tester,
  ) async {
    await setUpWorld();
    server
      ..creditLimitPaise = 50000
      ..balancePaise = 20000;
    await preloadCatalog(deps);
    await open(tester, '/orders/new?farmerId=f-1');
    await addToCart(tester, 'sku-neem-500');
    await tapCart(tester);
    await tapCart(tester);
    await tapIt(tester, find.byKey(const Key('payment-method-credit')));
    await tapIt(tester, find.byKey(const Key('checkout-submit')));
    expect(
      find.byKey(const Key('credit-state-approvalNeeded')),
      findsOneWidget,
    );
    expect(find.text('Approval needed'), findsOneWidget);
    expect(find.text('Sent to cluster head'), findsOneWidget);
    expect(find.text('₹500.00'), findsOneWidget); // limit
    expect(find.text('₹200.00'), findsOneWidget); // balance
    expect(find.text('₹170.40'), findsOneWidget); // 200 + 470.40 − 500
    await tapIt(tester, find.byKey(const Key('credit-recheck')));
    expect(find.text('Not approved yet. Try again later.'), findsOneWidget);
    server.approve(server.orders.keys.single);
    await tapIt(tester, find.byKey(const Key('credit-recheck')));
    expect(find.byKey(const Key('credit-state-onKhata')), findsOneWidget);
    expect(find.text('Added to the farmer’s khata'), findsOneWidget);
  });

  Future<void> blockedCredit(WidgetTester tester) async {
    await setUpWorld();
    server
      ..creditLimitPaise = 50000
      ..balancePaise = 20000;
    await preloadCatalog(deps);
    await open(tester, '/orders/new?farmerId=f-1');
    await addToCart(tester, 'sku-neem-500');
    await tapCart(tester);
    await tapCart(tester);
    await tapIt(tester, find.byKey(const Key('payment-method-credit')));
    await tapIt(tester, find.byKey(const Key('checkout-submit')));
    expect(
      find.byKey(const Key('credit-state-approvalNeeded')),
      findsOneWidget,
    );
  }

  testWidgets('A56 approval from the change feed flips to on khata by itself', (
    tester,
  ) async {
    await blockedCredit(tester);
    expect(find.byKey(const Key('credit-sent')), findsOneWidget);
    final orderId = server.orders.keys.single;
    server.approve(orderId);
    // A background sync (no tap): pulls the approval, resends with it.
    await containerOf(tester).read(syncEngineProvider).syncNow();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('credit-state-onKhata')), findsOneWidget);
    final sent = deps.api.requests
        .expand((r) => r.ops)
        .lastWhere((o) => o.entity == SyncEntities.payment);
    expect(
      sent.payload[creditApprovalRequestIdKey],
      FakeCommerceServer.approvalIdFor(orderId),
    );
  });

  testWidgets('A56 rejection from the change feed is shown', (tester) async {
    await blockedCredit(tester);
    final approvalId = FakeCommerceServer.approvalIdFor(
      server.orders.keys.single,
    );
    deps.api.addChange(
      entity: SyncEntities.creditApprovalRequest,
      action: SyncAction.update,
      entityId: approvalId,
      version: 2,
      data: <String, Object?>{'id': approvalId, 'status': 'rejected'},
    );
    await containerOf(tester).read(syncEngineProvider).syncNow();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('credit-rejected')), findsOneWidget);
    expect(
      find.text(
        'The cluster head rejected this credit sale. Collect cash instead.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('credit-cash-instead')), findsOneWidget);
  });

  group('A57 invoice share', () {
    Future<String> syncedOrder() async {
      await preloadCatalog(deps);
      final outbox = Outbox(deps.db, clock: () => deps.now, ids: deps.ids.call);
      final item = (await CatalogCache(
        deps.db,
        deps.catalogApi,
      ).item('sku-dap-50', storeId: storeId))!;
      final id = await OrderRepository(deps.db, outbox, ids: deps.ids.call)
          .place(
            farmerId: 'f-1',
            storeId: storeId,
            fulfilment: Fulfilment.pickup,
            lines: <CartLine>[CartLine(item: item, qty: 2)],
          );
      await LocalEntities(deps.db).write(
        SyncEntities.order,
        id,
        <String, Object?>{
          'farmer_id': 'f-1',
          'store_id': storeId,
          'status': 'handed_over',
          'subtotal_paise': 270000,
          'tax_paise': 13500,
          'total_paise': 283500,
          'invoice_no': 'KDP/2026-27/0042',
          'invoice_id': 'inv-42',
          'placed_at': '2026-09-20T00:30:00Z',
        },
        version: 5,
        dirty: false,
        now: deps.now,
      );
      await deps.db.delete(deps.db.outboxTable).go();
      deps.payApi.invoices.add('inv-42');
      return id;
    }

    testWidgets('online: WhatsApp share gets the signed PDF link', (
      tester,
    ) async {
      await setUpWorld();
      final id = await syncedOrder();
      await open(tester, '/orders/$id');
      expect(find.text('Invoice KDP/2026-27/0042'), findsOneWidget);
      expect(find.byKey(const Key('order-step-handed_over')), findsOneWidget);
      await tapIt(tester, find.byKey(const Key('order-share')));
      expect(deps.sharer.shared.single, contains('inv-42.pdf?sig=test'));
      expect(deps.sharer.shared.single, startsWith('Invoice KDP/2026-27/0042'));
    });

    testWidgets('invoice_id from a pull (handover) enables the share', (
      tester,
    ) async {
      await setUpWorld();
      await preloadCatalog(deps);
      final outbox = Outbox(deps.db, clock: () => deps.now, ids: deps.ids.call);
      final item = (await CatalogCache(
        deps.db,
        deps.catalogApi,
      ).item('sku-dap-50', storeId: storeId))!;
      final id = await OrderRepository(deps.db, outbox, ids: deps.ids.call)
          .place(
            farmerId: 'f-1',
            storeId: storeId,
            fulfilment: Fulfilment.pickup,
            lines: <CartLine>[CartLine(item: item, qty: 1)],
          );
      await open(tester, '/orders/$id');
      await containerOf(tester).read(syncEngineProvider).syncNow();
      await tester.pumpAndSettle();
      expect(server.orders.keys, contains(id));
      expect(
        tester
            .widget<AppButton>(find.byKey(const Key('order-share')))
            .onPressed,
        isNull,
      );
      server.handOver(
        id,
        invoiceId: 'inv-77',
        invoiceNo: 'FCC/KND/2026-27/000077',
      );
      deps.payApi.invoices.add('inv-77');
      await containerOf(tester).read(syncEngineProvider).syncNow();
      await tester.pumpAndSettle();
      expect(find.text('Invoice FCC/KND/2026-27/000077'), findsOneWidget);
      await tapIt(tester, find.byKey(const Key('order-share')));
      expect(deps.sharer.shared.single, contains('inv-77.pdf?sig=test'));
    });

    testWidgets('offline: share disabled with the reason', (tester) async {
      await setUpWorld();
      final id = await syncedOrder();
      deps.connectivity.online = false;
      await open(tester, '/orders/$id');
      final share = tester.widget<AppButton>(
        find.byKey(const Key('order-share')),
      );
      expect(share.onPressed, isNull);
      expect(
        find.text(
          'Connect to the internet to share the invoice.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(deps.sharer.shared, isEmpty);
    });
  });

  group('A58 khata', () {
    testWidgets('balance equals the sum of the entries shown; buckets; '
        'Collect opens A52 in dues mode', (tester) async {
      await setUpWorld();
      await open(tester, '/farmers/f-1/khata');
      expect(deps.khataApi.fetches, 1);
      final ledger = tester.widget<KhataLedger>(
        find.byKey(const Key('khata-ledger')),
      );
      final sum = ledger.entries.fold<int>(
        0,
        (a, e) => a + (e.isCredit ? -e.amountPaise : e.amountPaise),
      );
      expect(ledger.balancePaise, sum);
      expect(ledger.balancePaise, 1250000);
      expect(ledger.entries, hasLength(4));
      expect(find.text('₹12,500.00'), findsOneWidget);
      expect(find.text('Overdue ₹6,500.00'), findsOneWidget);
      expect(find.text('0–30 days: ₹2,500'), findsOneWidget);
      expect(find.text('61–90 days: ₹4,000'), findsOneWidget);
      expect(find.text('90+ days: ₹0'), findsOneWidget);
      expect(find.text('Due 30-11-2026 · harvest 11-2026'), findsOneWidget);
      expect(find.text('As of 20-09-2026 06:00'), findsOneWidget);
      await tapIt(tester, find.text('Collect'));
      expect(find.text('Balance due ₹12,500.00'), findsOneWidget);
    });

    testWidgets('offline: cached khata with its time', (tester) async {
      await setUpWorld();
      await preloadKhata(deps);
      deps.khataApi.offline = true;
      deps.connectivity.online = false;
      deps.now = t0.add(const Duration(hours: 5));
      await open(tester, '/farmers/f-1/khata');
      expect(
        find.text('Offline: showing the khata saved at 20-09-2026 06:00'),
        findsOneWidget,
      );
      expect(find.text('₹12,500.00'), findsOneWidget);
    });
  });

  testWidgets('A59 collections: totals by mode and statuses', (tester) async {
    await setUpWorld();
    final payments = PaymentRepository(
      db: deps.db,
      outbox: Outbox(deps.db, clock: () => deps.now, ids: deps.ids.call),
      api: deps.payApi,
      photos: deps.photos,
      ids: deps.ids.call,
      clock: () => deps.now,
    );
    await payments.collectCash(
      const PaymentTarget.dues(
        farmerId: 'f-1',
        storeId: storeId,
        duesAmountPaise: 150000,
      ),
      receiptJpeg: testJpeg(width: 64, height: 48),
      expectedPaise: 150000,
    );
    final upi = await payments.createOnline(
      const PaymentTarget.dues(
        farmerId: 'f-1',
        storeId: storeId,
        duesAmountPaise: 30000,
      ),
      mode: PaymentModes.upiQr,
    );
    await payments.applyPoll(
      upi.paymentId!,
      const UpiPollState(UpiPollPhase.paid),
    );
    final failed = await payments.createOnline(
      const PaymentTarget.dues(
        farmerId: 'f-1',
        storeId: storeId,
        duesAmountPaise: 70000,
      ),
      mode: PaymentModes.upiQr,
    );
    await payments.applyPoll(
      failed.paymentId!,
      const UpiPollState(UpiPollPhase.expired),
    );
    await open(tester, '/collections');
    expect(find.byKey(const Key('collections-total-cash')), findsOneWidget);
    expect(find.byKey(const Key('collections-total-upi_qr')), findsOneWidget);
    expect(find.text('₹1,800.00'), findsOneWidget);
    expect(find.text('Waiting to sync'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    await tapIt(tester, find.text('This week'));
    expect(find.text('₹1,800.00'), findsOneWidget);
  });

  testWidgets('A10 Collect payment and Orders nav; A22 New order / Collect', (
    tester,
  ) async {
    await setUpWorld();
    await open(tester, '/farmers/f-1');
    await tapIt(tester, find.byKey(const Key('profile-new-order')));
    expect(find.byType(CatalogScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapIt(tester, find.byKey(const Key('profile-collect')));
    expect(find.byKey(const Key('checkout-amount')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapIt(tester, find.text('Khata'));
    expect(find.byKey(const Key('khata-ledger')), findsOneWidget);
    await tapIt(tester, find.text('Orders'));
    expect(find.byKey(const Key('profile-orders-empty')), findsOneWidget);
  });
}
