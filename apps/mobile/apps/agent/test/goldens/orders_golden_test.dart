// Goldens for A50, A51, A52, A53 (waiting / paid / failed), A56, A57 and
// A58 in Light and Sunlight at 360x800.
// Regenerate with: flutter test --update-goldens test/goldens
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import '../orders/commerce_test_support.dart';

void main() {
  for (final mode in <AppThemeMode>[
    AppThemeMode.light,
    AppThemeMode.sunlight,
  ]) {
    group(mode.name, () {
      late AgentDeps deps;
      late FakeCommerceServer server;

      setUp(() async {
        deps = AgentDeps();
        server = await seedCommerceWorld(deps);
        await preloadCatalog(deps);
      });

      tearDown(() => deps.dispose());

      Future<void> shoot(WidgetTester tester, String name) => expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/${name}_${mode.name}.png'),
      );

      Future<void> open(WidgetTester tester, String location) async {
        usePhoneSurface(tester);
        await tester.pumpWidget(
          deps.app(initialLocation: location, theme: mode),
        );
        await tester.pumpAndSettle();
      }

      Future<void> add(WidgetTester tester, String skuId, String q) async {
        await tester.enterText(find.byKey(const Key('catalog-search')), q);
        await tester.pumpAndSettle();
        await tapIt(
          tester,
          find.descendant(
            of: find.byKey(Key('product-$skuId')),
            matching: find.byType(AppButton),
          ),
        );
        await tester.enterText(find.byKey(const Key('catalog-search')), '');
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }

      Future<void> tapCart(WidgetTester tester) => tapIt(
        tester,
        find.descendant(
          of: find.byKey(const Key('cart-bar')),
          matching: find.byType(AppButton),
        ),
      );

      /// An order placed and synced (priced by the fake server).
      Future<String> syncedOrder({int qty = 2}) async {
        final c = deps.container();
        addTearDown(c.dispose);
        final item = (await c
            .read(catalogCacheProvider)
            .item('sku-cora-150', storeId: storeId))!;
        final neem = (await c
            .read(catalogCacheProvider)
            .item('sku-neem-500', storeId: storeId))!;
        final id = await c
            .read(orderRepositoryProvider)
            .place(
              farmerId: 'f-1',
              storeId: storeId,
              fulfilment: Fulfilment.pickup,
              lines: <CartLine>[
                CartLine(item: item, qty: qty),
                CartLine(item: neem, qty: 1),
              ],
              paymentMode: PaymentModes.cash,
              now: deps.now,
            );
        await c.read(syncEngineProvider).syncNow();
        return id;
      }

      testWidgets('a50_catalogue', (tester) async {
        await open(tester, '/orders/new?farmerId=f-1');
        await add(tester, 'sku-neem-500', 'neem');
        await shoot(tester, 'a50_catalogue');
      });

      testWidgets('a51_cart', (tester) async {
        await open(tester, '/orders/new?farmerId=f-1');
        await add(tester, 'sku-cora-150', 'coragen');
        await add(tester, 'sku-neem-500', 'neem');
        await tapCart(tester);
        await tapIt(tester, find.byKey(const Key('cart-inc-sku-cora-150')));
        await shoot(tester, 'a51_cart');
      });

      testWidgets('a52_payment_method', (tester) async {
        await open(tester, '/orders/new?farmerId=f-1');
        await add(tester, 'sku-neem-500', 'neem');
        await tapCart(tester);
        await tapCart(tester);
        await tapIt(tester, find.byKey(const Key('payment-method-upiQr')));
        await shoot(tester, 'a52_payment_method');
      });

      for (final state in <String>['waiting', 'paid', 'failed']) {
        testWidgets('a53_upi_$state', (tester) async {
          final orderId = await syncedOrder();
          final c = deps.container();
          addTearDown(c.dispose);
          final out = await c
              .read(paymentRepositoryProvider)
              .createOnline(
                PaymentTarget.order(orderId: orderId, farmerId: 'f-1'),
                mode: PaymentModes.upiQr,
              );
          deps.payApi.states[out.paymentId!] = state;
          deps.now = deps.now.add(const Duration(minutes: 4, seconds: 25));
          await open(tester, '/payments/${out.paymentId}/upi');
          await shoot(tester, 'a53_upi_$state');
        });
      }

      testWidgets('a56_credit_approval_needed', (tester) async {
        server
          ..creditLimitPaise = 200000
          ..balancePaise = 150000;
        final orderId = await syncedOrder(qty: 1);
        final c = deps.container();
        addTearDown(c.dispose);
        final payId = await c
            .read(paymentRepositoryProvider)
            .collectCredit(
              PaymentTarget.order(
                orderId: orderId,
                farmerId: 'f-1',
                storeId: storeId,
              ),
              expectedPaise: 186320,
            );
        await c.read(syncEngineProvider).syncNow();
        await open(tester, '/payments/$payId/credit');
        await shoot(tester, 'a56_credit_approval_needed');
      });

      testWidgets('a57_order_success', (tester) async {
        final orderId = await syncedOrder();
        final c = deps.container();
        addTearDown(c.dispose);
        await c
            .read(paymentRepositoryProvider)
            .collectCash(
              PaymentTarget.order(
                orderId: orderId,
                farmerId: 'f-1',
                storeId: storeId,
              ),
              receiptJpeg: Uint8List.fromList(List<int>.filled(512, 7)),
              expectedPaise: 0,
            );
        await c.read(syncEngineProvider).syncNow();
        await open(tester, '/orders/$orderId');
        await shoot(tester, 'a57_order_success');
      });

      testWidgets('a58_khata', (tester) async {
        await open(tester, '/farmers/f-1/khata');
        await shoot(tester, 'a58_khata');
      });
    });
  }
}
