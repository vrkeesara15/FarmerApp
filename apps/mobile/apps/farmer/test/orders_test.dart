import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:farmerapp_farmer/screens/orders/cart_screen.dart';
import 'package:farmerapp_farmer/screens/orders/my_orders_screen.dart';
import 'package:farmerapp_farmer/screens/orders/order_tracking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-010 orders: F34 → shop → F30 product → F31 cart (pickup / delivery)
/// → F32 pay (UPI opens the UPI apps with the payment intent; pay at
/// store; credit "your store will confirm") → F33 tracking.
void main() {
  late KisanDeps deps;

  setUp(() async {
    deps = KisanDeps()..seedWorld();
    await deps.signIn();
  });
  tearDown(() => deps.dispose());

  Future<void> buyNeem(WidgetTester tester, {int qty = 2}) async {
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.orders));
    expect(find.byType(MyOrdersScreen), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('orders-buy')));
    expect(find.byKey(const Key('shop-product-sku-neem')), findsOneWidget);
    // Category chips filter without typing.
    await tapIt(tester, find.byKey(const Key('shop-category-fertiliser')));
    expect(find.byKey(const Key('shop-product-sku-neem')), findsNothing);
    expect(find.byKey(const Key('shop-product-sku-dap')), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('shop-category-all')));
    await tapIt(tester, find.byKey(const Key('shop-product-sku-neem')));

    expect(find.text('Neem Shakti'), findsOneWidget);
    expect(find.byType(OwnBrandBadge), findsOneWidget);
    for (var i = 1; i < qty; i++) {
      await tapIt(tester, find.byKey(const Key('product-qty-inc')));
    }
    await tapIt(tester, find.byKey(const Key('product-add')));
    expect(find.byType(CartScreen), findsOneWidget);
  }

  testWidgets('UPI: the order is placed, the UPI app opens with the payment '
      'intent and the order shows paid once the webhook lands', (tester) async {
    usePhoneSurface(tester);
    await buyNeem(tester);
    await tapIt(tester, find.byKey(const Key('cart-delivery')));
    await tapIt(
      tester,
      find.descendant(
        of: find.byKey(const Key('cart-bar')),
        matching: find.byType(AppButton),
      ),
    );
    expect(find.text('Total ₹840.00'), findsOneWidget);
    final place = find.byKey(const Key('pay-place'));
    expect(tester.widget<AppButton>(place).onPressed, isNull);
    await tapIt(tester, find.byKey(const Key('pay-upi')));
    await tester.tap(place);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final order = deps.kisan.writes.firstWhere(
      (w) => w.$1 == 'POST /v1/orders',
    );
    expect(order.$2['fulfilment'], 'delivery');
    expect(order.$2['store_id'], storeId);
    expect(order.$2['payment_mode'], isNull);
    expect(order.$2['lines'], <Object?>[
      <String, Object?>{'sku_id': 'sku-neem', 'qty': 2},
    ]);
    final orderId = deps.kisan.ordersById.keys.single;
    expect(deps.payApi.created.single, <String, Object?>{
      'order_id': orderId,
      'mode': 'upi_qr',
    });
    // The UPI intent from the payments API went to the phone's UPI apps.
    expect(deps.urls.opened.single, startsWith('upi://pay?'));
    expect(find.byKey(const Key('upi-waiting')), findsOneWidget);

    // Webhook: the payment is paid; the next poll sees it.
    deps.payApi.states['pay-1'] = 'paid';
    deps.kisan.markOrderPaid(orderId);
    deps.releasePoll();
    await settle(tester);

    expect(find.byType(OrderTrackingScreen), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.byKey(const Key('order-timeline')), findsOneWidget);
    expect(find.text('Neem Shakti · 500 ml × 2'), findsOneWidget);
    expect(find.byKey(const Key('order-pay-upi')), findsNothing);
    expect(deps.payApi.polls['pay-1'], 2);
  });

  testWidgets('Pay at store: order placed without a payment; tracking says '
      'pay when collecting and moves along the timeline', (tester) async {
    usePhoneSurface(tester);
    await buyNeem(tester, qty: 1);
    await tapIt(
      tester,
      find.descendant(
        of: find.byKey(const Key('cart-bar')),
        matching: find.byType(AppButton),
      ),
    );
    await tapIt(tester, find.byKey(const Key('pay-store')));
    await tapIt(tester, find.byKey(const Key('pay-place')));

    expect(deps.payApi.created, isEmpty);
    expect(deps.urls.opened, isEmpty);
    expect(find.byType(OrderTrackingScreen), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('order-payment')));
    expect(
      tester.widget<Text>(find.byKey(const Key('order-payment'))).data,
      'Pay at the store when you collect',
    );
    final orderId = deps.kisan.ordersById.keys.single;
    deps.kisan.advanceOrder(orderId, 'packed');
    deps.kisan.advanceOrder(orderId, 'ready');
    final c = deps.container();
    await real(
      tester,
      () => c.read(kisanRepositoryProvider).refreshOrder(orderId),
    );
    c.dispose();
    await settle(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('order-status'))).data,
      'Ready',
    );
    final timeline = tester.widget<StageTimeline>(
      find.byKey(const Key('order-timeline')),
    );
    expect(timeline.currentIndex, 2);
  });

  testWidgets('Credit request over the limit: "your store will confirm"', (
    tester,
  ) async {
    usePhoneSurface(tester);
    deps.kisan.creditLimitExceeded = true;
    await buyNeem(tester, qty: 1);
    await tapIt(
      tester,
      find.descendant(
        of: find.byKey(const Key('cart-bar')),
        matching: find.byType(AppButton),
      ),
    );
    await tapIt(tester, find.byKey(const Key('pay-credit')));
    await tapIt(tester, find.byKey(const Key('pay-place')));
    expect(deps.kisan.writes.last.$2['payment_mode'], 'credit');
    expect(find.text('Your store will confirm'), findsWidgets);
    expect(find.byType(MyOrdersScreen), findsOneWidget);
  });

  testWidgets('offline: placing needs the network; nothing is sent', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await buyNeem(tester, qty: 1);
    deps.kisan.offline = true;
    await tapIt(
      tester,
      find.descendant(
        of: find.byKey(const Key('cart-bar')),
        matching: find.byType(AppButton),
      ),
    );
    await tapIt(tester, find.byKey(const Key('pay-store')));
    await tapIt(tester, find.byKey(const Key('pay-place')));
    expect(
      find.text('This needs internet. Try again when online.'),
      findsOneWidget,
    );
    expect(deps.kisan.ordersById, isEmpty);
  });
}
