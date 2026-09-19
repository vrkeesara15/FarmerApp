import 'package:farmerapp_farmer/router.dart';
import 'package:farmerapp_farmer/screens/khata_screen.dart';
import 'package:farmerapp_farmer/screens/payment_receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-010 khata: F50 balance, due date and history; Pay now → UPI → the
/// client fetches the khata again as soon as the payment shows paid
/// (the server moved the balance in the webhook transaction) → F51.
void main() {
  late KisanDeps deps;

  setUp(() async {
    deps = KisanDeps()..seedWorld(khataBalance: 1250000);
    await deps.signIn();
  });
  tearDown(() => deps.dispose());

  testWidgets('F50 shows balance, due date and history', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.khata));
    expect(find.byType(KhataScreen), findsOneWidget);
    expect(find.text('₹12,500.00'), findsWidgets);
    expect(find.textContaining('30-11-2026'), findsWidgets);
    expect(find.text('Sale on credit'), findsOneWidget);
    expect(find.byKey(const Key('as-of')), findsOneWidget);
  });

  testWidgets('Pay now: UPI intent, then the balance is refreshed the moment '
      'the payment is paid and F51 shows the receipt', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.khata));
    final fetchesBefore = deps.khataApi.fetches;

    await tester.tap(find.text('Pay now'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(deps.payApi.created.single, <String, Object?>{
      'farmer_id': farmerId,
      'store_id': storeId,
      'amount_paise': 1250000,
      'mode': 'upi_qr',
    });
    expect(deps.urls.opened.single, startsWith('upi://pay?'));
    expect(find.byKey(const Key('upi-waiting')), findsOneWidget);

    // Still waiting: one more poll, no khata fetch yet.
    deps.releasePoll();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(deps.khataApi.fetches, fetchesBefore);

    // The webhook lands: the server's khata already has the credit.
    deps.payApi.states['pay-1'] = 'paid';
    deps.khataApi.khatas[farmerId] = khataOf(
      0,
      entries: <Object?>[
        <String, Object?>{
          'id': 'k-2',
          'farmer_id': farmerId,
          'store_id': storeId,
          'type': 'credit',
          'amount_paise': 1250000,
          'signed_paise': -1250000,
          'ref_type': 'payment',
          'created_at': t0.toIso8601String(),
        },
      ],
    );
    deps.releasePoll();
    await settle(tester);

    expect(deps.khataApi.fetches, fetchesBefore + 1);
    expect(deps.payApi.polls['pay-1'], 3);
    expect(find.byType(PaymentReceiptScreen), findsOneWidget);
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.byKey(const Key('receipt-amount')), findsOneWidget);
    expect(find.text('₹12,500.00'), findsOneWidget);
    expect(find.text('Balance now: ₹0.00'), findsOneWidget);
  });

  testWidgets('a failed UPI payment leaves the balance and says so', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.khata));
    await tester.tap(find.text('Pay now'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    deps.payApi.states['pay-1'] = 'failed';
    deps.releasePoll();
    await settle(tester);
    expect(find.byType(KhataScreen), findsOneWidget);
    expect(
      find.text('The payment did not go through. No money was taken.'),
      findsOneWidget,
    );
    expect(find.text('₹12,500.00'), findsWidgets);
  });

  testWidgets('home shows the dues card only when the balance is above 0', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app());
    expect(find.byKey(const Key('home-dues')), findsOneWidget);
    expect(find.text('You owe ₹12,500.00'), findsOneWidget);

    deps.khataApi.khatas[farmerId] = khataOf(0);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.orders));
    await pumpApp(tester, deps.app());
    expect(find.byKey(const Key('home-dues')), findsNothing);
  });
}
