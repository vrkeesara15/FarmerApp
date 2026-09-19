import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import 'store_harness.dart';

/// S02 POS, S03 checkout and S04 invoice share at 800 x 1280.
void main() {
  late StoreDeps deps;

  setUp(() => deps = StoreDeps());
  tearDown(() => deps.dispose());

  Future<void> openPos(WidgetTester tester) async {
    useTabletSurface(tester);
    await pumpStore(tester, deps, location: '/store/pos');
  }

  Future<void> addProduct(WidgetTester tester, String skuId) async {
    final card = find.byKey(Key('pos-product-$skuId'));
    await tester.scrollUntilVisible(
      card,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('pos-grid-pane')),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    final add = find.descendant(of: card, matching: find.text('Add'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
  }

  Future<void> toCheckout(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('pos-checkout')));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, Finder f) {
    final texts = tester.widgetList<Text>(
      find.descendant(of: f, matching: find.byType(Text)),
    );
    return texts.map((t) => t.data ?? '').join(' | ');
  }

  testWidgets('barcode scan: found adds a pack, not found says so', (
    tester,
  ) async {
    await openPos(tester);
    deps.scanner
      ..enqueue('8901234500028')
      ..enqueue('0000000000000');
    await tester.tap(find.byKey(const Key('pos-scan')));
    await tester.pumpAndSettle();
    expect(find.text('Mancozeb 75% WP added'), findsOneWidget);
    expect(find.byKey(const Key('cart-line-sku-mnz-1kg')), findsOneWidget);
    expect(deps.api.calls, contains('barcode:8901234500028'));

    await tester.tap(find.byKey(const Key('pos-scan')));
    await tester.pumpAndSettle();
    expect(find.text('No product with code 0000000000000'), findsOneWidget);
    expect(find.byKey(const Key('cart-line-sku-mnz-1kg')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('cart-qty-sku-mnz-1kg'))).data,
      '1',
    );
  });

  testWidgets('manual code entry adds the same SKU twice', (tester) async {
    await openPos(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('pos-enter-code')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pos-code-field')),
        '8901234500011',
      );
      await tester.tap(find.byKey(const Key('pos-code-add')));
      await tester.pumpAndSettle();
    }
    expect(
      tester.widget<Text>(find.byKey(const Key('cart-qty-sku-imd-250'))).data,
      '2',
    );
  });

  testWidgets('cart totals: line totals, GST and grand total', (tester) async {
    await openPos(tester);
    await addProduct(tester, 'sku-imd-250');
    await addProduct(tester, 'sku-urea-45');
    await tester.tap(find.byKey(const Key('cart-inc-sku-urea-45')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('cart-total-sku-urea-45'))).data,
      '₹533.00',
    );
    // 420 + 533 = 953 taxable; 18 % of 420 = 75.60; 5 % of 533 = 26.66
    // (13.33 + 13.33); total 1055.26 -> 1055.
    expect(
      text(tester, find.byKey(const Key('cart-grand-total'))),
      contains('₹1,055.00'),
    );
    await tester.tap(find.byKey(const Key('cart-dec-sku-imd-250')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cart-line-sku-imd-250')), findsNothing);
  });

  testWidgets('category chip and search filter the grid', (tester) async {
    await openPos(tester);
    await tester.tap(find.byKey(const Key('pos-cat-seed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-product-sku-bt-450')), findsOneWidget);
    expect(find.byKey(const Key('pos-product-sku-imd-250')), findsNothing);
    await tester.tap(find.byKey(const Key('pos-cat-all')));
    await tester.enterText(find.byKey(const Key('pos-search')), 'sprayer');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-product-sku-spr-16')), findsOneWidget);
    expect(find.byKey(const Key('pos-product-sku-bt-450')), findsNothing);
  });

  testWidgets('farmer lookup by phone: known farmer and walk-in', (
    tester,
  ) async {
    await seedVillage(deps.agent.db);
    await seedSyncedFarmer(deps.agent.db, id: 'f-1', phone: '+919876543210');
    await openPos(tester);
    await tester.enterText(
      find.byKey(const Key('pos-buyer-phone')),
      '9876543210',
    );
    await tester.tap(find.byKey(const Key('pos-buyer-find')));
    await tester.pumpAndSettle();
    expect(find.text('Ramesh Reddy'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pos-buyer-clear')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('pos-buyer-phone')),
      '9000011122',
    );
    await tester.tap(find.byKey(const Key('pos-buyer-find')));
    await tester.pumpAndSettle();
    expect(
      find.text('New number: the sale is recorded against this phone'),
      findsOneWidget,
    );
  });

  testWidgets('card: reference required, then the invoice is shared', (
    tester,
  ) async {
    await openPos(tester);
    await addProduct(tester, 'sku-imd-250');
    await toCheckout(tester);
    expect(find.byKey(const Key('checkout-preview')), findsOneWidget);
    expect(find.byKey(const Key('invoice-cgst')), findsOneWidget);
    expect(find.byKey(const Key('invoice-sgst')), findsOneWidget);
    expect(find.text('38089199'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mode-card_terminal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkout-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Enter the terminal reference'), findsOneWidget);
    expect(deps.api.calls.where((c) => c.startsWith('posSale')), isEmpty);

    await tester.enterText(
      find.byKey(const Key('checkout-card-ref')).last,
      'TID 4471',
    );
    await tester.tap(find.byKey(const Key('checkout-confirm')));
    await tester.pumpAndSettle();
    // S04 with the server's invoice.
    expect(find.byKey(const Key('invoice-number')), findsOneWidget);
    expect(find.text('Invoice FCC/KND/2026-27/000124'), findsOneWidget);
    expect(find.byKey(const Key('invoice-words')), findsOneWidget);
    expect(deps.api.lastSale!.referenceNote, 'TID 4471');

    await tester.tap(find.byKey(const Key('invoice-whatsapp')));
    await tester.pumpAndSettle();
    expect(deps.api.shares.single.$2, 'whatsapp');
    expect(find.text('Sent to +91 98XXXXX210'), findsOneWidget);

    await tester.tap(find.byKey(const Key('invoice-pdf')));
    await tester.pumpAndSettle();
    expect(deps.opener.opened.single, contains('inv-1.pdf'));

    await tester.tap(find.byKey(const Key('invoice-share')));
    await tester.pumpAndSettle();
    expect(deps.sharer.shared.single, contains('FCC/KND/2026-27/000124'));

    await tester.tap(find.byKey(const Key('invoice-next-sale')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-cart-empty')), findsOneWidget);
  });

  testWidgets('cash: change shown, short tender refused', (tester) async {
    await openPos(tester);
    await addProduct(tester, 'sku-imd-250');
    await toCheckout(tester);
    await tester.tap(find.byKey(const Key('mode-cash')));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byKey(const Key('checkout-cash-tendered')),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '400');
    await tester.tap(find.byKey(const Key('checkout-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Cash received is less than the total'), findsOneWidget);
    await tester.enterText(field, '500');
    await tester.pumpAndSettle();
    // 420 + 18 % = 495.60 -> 496; change 4.
    expect(
      text(tester, find.byKey(const Key('checkout-change'))),
      contains('₹4.00'),
    );
    await tester.tap(find.byKey(const Key('checkout-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invoice-change')), findsOneWidget);
    expect(deps.api.calls, contains('posSale:cash'));
  });

  testWidgets('UPI: QR shown, polled until paid, then the invoice', (
    tester,
  ) async {
    await openPos(tester);
    await addProduct(tester, 'sku-urea-45');
    await toCheckout(tester);
    await tester.tap(find.byKey(const Key('mode-upi_qr')));
    await tester.pumpAndSettle();
    deps.api.upiPolls.addAll(<PaymentPollState>[
      PaymentPollState.waiting,
      PaymentPollState.paid,
    ]);
    await tester.tap(find.byKey(const Key('checkout-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkout-upi')), findsOneWidget);
    expect(find.text('Waiting for payment'), findsOneWidget);
    await tester.pump(upiPollInterval);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkout-upi')), findsOneWidget);
    await tester.pump(upiPollInterval);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invoice-number')), findsOneWidget);
    expect(deps.api.calls.where((c) => c == 'payment'), hasLength(2));
  });

  testWidgets('UPI failed: a new QR can be shown', (tester) async {
    await openPos(tester);
    await addProduct(tester, 'sku-urea-45');
    await toCheckout(tester);
    await tester.tap(find.byKey(const Key('mode-upi_qr')));
    await tester.pumpAndSettle();
    deps.api.upiPolls.add(PaymentPollState.failed);
    await tester.tap(find.byKey(const Key('checkout-confirm')));
    await tester.pumpAndSettle();
    await tester.pump(upiPollInterval);
    await tester.pumpAndSettle();
    expect(find.text('Show a new QR'), findsOneWidget);
    await tester.tap(find.text('Show a new QR'));
    await tester.pumpAndSettle();
    expect(deps.api.calls, contains('newUpiQr'));
    expect(find.text('Waiting for payment'), findsOneWidget);
    // Leave the screen so the poll timer stops.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('credit beyond the limit: approval needed, cart kept', (
    tester,
  ) async {
    await seedVillage(deps.agent.db);
    await seedSyncedFarmer(deps.agent.db, id: 'f-1', phone: '+919876543210');
    deps.api.creditExceeded = true;
    await openPos(tester);
    await addProduct(tester, 'sku-spr-16');
    await tester.enterText(
      find.byKey(const Key('pos-buyer-phone')),
      '9876543210',
    );
    await tester.tap(find.byKey(const Key('pos-buyer-find')));
    await tester.pumpAndSettle();
    await toCheckout(tester);
    await tester.tap(find.byKey(const Key('mode-credit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkout-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkout-approval')), findsOneWidget);
    expect(find.text('Credit approval needed'), findsOneWidget);
    expect(find.text('₹20,000.00'), findsOneWidget);
    expect(find.byKey(const Key('invoice-line-1')), findsOneWidget);
    // Not decided yet: "Check approval" says so; the cart stays.
    await tester.ensureVisible(
      find.byKey(const Key('checkout-check-approval')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkout-check-approval')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkout-approval-pending')), findsOneWidget);
    // The cluster head approves; the check retries the sale with the request.
    final id = deps.api.approvals.last.id;
    await deps.api.decideCredit(id, approve: true);
    await tester.tap(find.byKey(const Key('checkout-check-approval')));
    await tester.pumpAndSettle();
    expect(deps.api.lastSale!.creditApprovalRequestId, id);
    expect(find.byKey(const Key('invoice-number')), findsOneWidget);
  });

  testWidgets('credit rejected: said so, another method still possible', (
    tester,
  ) async {
    await seedVillage(deps.agent.db);
    await seedSyncedFarmer(deps.agent.db, id: 'f-1', phone: '+919876543210');
    deps.api.creditExceeded = true;
    await openPos(tester);
    await addProduct(tester, 'sku-spr-16');
    await tester.enterText(
      find.byKey(const Key('pos-buyer-phone')),
      '9876543210',
    );
    await tester.tap(find.byKey(const Key('pos-buyer-find')));
    await tester.pumpAndSettle();
    await toCheckout(tester);
    await tester.tap(find.byKey(const Key('mode-credit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkout-confirm')));
    await tester.pumpAndSettle();
    await deps.api.decideCredit(deps.api.approvals.last.id, approve: false);
    await tester.ensureVisible(
      find.byKey(const Key('checkout-check-approval')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkout-check-approval')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkout-approval-rejected')), findsOneWidget);
    expect(find.byKey(const Key('checkout-check-approval')), findsNothing);
    await tester.tap(find.byKey(const Key('checkout-other-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkout-approval')), findsNothing);
  });

  testWidgets('S03 shows the server preview; offline an estimate, labelled', (
    tester,
  ) async {
    await openPos(tester);
    await addProduct(tester, 'sku-imd-250');
    await tester.pump(posPreviewDebounce * 2);
    await tester.pumpAndSettle();
    await toCheckout(tester);
    expect(deps.api.calls, contains('posPreview'));
    expect(find.byKey(const Key('checkout-preview-ready')), findsOneWidget);
    expect(find.byKey(const Key('checkout-preview-estimate')), findsNothing);
    expect(find.textContaining('Rupees'), findsOneWidget); // words: server
  });

  testWidgets('S03 offline: preview unavailable, estimate labelled', (
    tester,
  ) async {
    await openPos(tester);
    deps.agent.connectivity.online = false;
    await tester.pumpAndSettle();
    await addProduct(tester, 'sku-imd-250');
    await tester.pump(posPreviewDebounce * 2);
    await tester.pumpAndSettle();
    await toCheckout(tester);
    expect(deps.api.calls, isNot(contains('posPreview')));
    expect(find.byKey(const Key('checkout-preview-offline')), findsOneWidget);
    expect(find.byKey(const Key('checkout-preview-estimate')), findsOneWidget);
    expect(find.text('Estimate'), findsOneWidget);
    expect(find.textContaining('Rupees'), findsNothing);
  });

  testWidgets('credit needs a known farmer (mode disabled for walk-ins)', (
    tester,
  ) async {
    await openPos(tester);
    await addProduct(tester, 'sku-imd-250');
    await toCheckout(tester);
    await tester.tap(find.byKey(const Key('mode-credit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkout-card-ref')), findsNothing);
    await tester.tap(find.byKey(const Key('checkout-confirm')));
    await tester.pumpAndSettle();
    expect(deps.api.calls.where((c) => c.startsWith('posSale')), isEmpty);
  });

  testWidgets('offline: sale blocked with a clear state, cart kept', (
    tester,
  ) async {
    await openPos(tester);
    await addProduct(tester, 'sku-imd-250');
    await toCheckout(tester);
    await tester.tap(find.byKey(const Key('mode-card_terminal')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('checkout-card-ref')).last,
      'TID 1',
    );
    deps.agent.connectivity.online = false;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkout-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkout-offline')), findsOneWidget);
    expect(find.text('Offline: the sale cannot be completed'), findsOneWidget);
    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(deps.api.calls.where((c) => c.startsWith('posSale')), isEmpty);
    expect(find.byKey(const Key('invoice-line-1')), findsOneWidget);

    deps.agent.connectivity.online = true;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('checkout-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invoice-number')), findsOneWidget);
  });
}
