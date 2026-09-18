import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import 'store_harness.dart';

/// Role gating (SPEC 1.2 / 2.6) and the tablet layout.
void main() {
  Future<void> login(WidgetTester tester, StoreDeps deps, String role) async {
    await tester.pumpWidget(
      deps.app(
        initialLocation: '/login',
        extra: [
          authApiProvider.overrideWithValue(
            FakeAuthApi(role: role, storeId: 'store-knd'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '9000000004');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('otp-continue')));
    await tester.pumpAndSettle();
  }

  testWidgets('store manager lands in store mode after login', (tester) async {
    useTabletSurface(tester);
    final deps = StoreDeps();
    addTearDown(deps.dispose);
    await login(tester, deps, 'store_manager');
    expect(find.byKey(const Key('store-home')), findsOneWidget);
    expect(find.byKey(const Key('store-rail')), findsOneWidget);
    expect(find.text('₹38,75,000.00'), findsNothing);
    expect(find.byKey(const Key('store-sales-total')), findsOneWidget);
  });

  testWidgets('accountant lands in store mode too', (tester) async {
    useTabletSurface(tester);
    final deps = StoreDeps();
    addTearDown(deps.dispose);
    await login(tester, deps, 'accountant');
    expect(find.byKey(const Key('store-home')), findsOneWidget);
    // Accountants sell and close the day but do not move stock.
    expect(find.byKey(const Key('store-action-sale')), findsOneWidget);
    expect(find.byKey(const Key('store-action-close')), findsOneWidget);
    expect(find.byKey(const Key('store-action-receipt')), findsNothing);
  });

  testWidgets('field officer never sees store mode', (tester) async {
    usePhoneSurface(tester);
    final deps = StoreDeps();
    addTearDown(deps.dispose);
    await login(tester, deps, 'field_officer');
    // The normal field flow continues (A05 disclosure), not S01.
    expect(find.byKey(const Key('store-home')), findsNothing);
    expect(find.byKey(const Key('store-rail')), findsNothing);
  });

  testWidgets('field officer: no A63 switch, and /store is refused', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final deps = StoreDeps();
    addTearDown(deps.dispose);
    await pumpStore(tester, deps, role: 'field_officer', location: '/settings');
    expect(find.byKey(const Key('store-mode-setting')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(deps.app());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('store-not-allowed')), findsOneWidget);
    expect(find.byKey(const Key('store-home')), findsNothing);
    expect(deps.api.calls, isEmpty);
  });

  testWidgets('cluster head: A63 switch opens a read-only store mode', (
    tester,
  ) async {
    useTabletSurface(tester);
    final deps = StoreDeps();
    addTearDown(deps.dispose);
    await pumpStore(tester, deps, role: 'cluster_head', location: '/settings');
    await tester.tap(find.byKey(const Key('store-mode-setting')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('store-home')), findsOneWidget);
    expect(find.byKey(const Key('store-read-only')), findsOneWidget);
    expect(find.byKey(const Key('store-action-sale')), findsNothing);
    expect(find.byKey(const Key('store-action-close')), findsNothing);
    // No POS in the rail; credit approvals are.
    expect(find.byKey(const Key('store-nav-pos')), findsNothing);
    expect(find.byKey(const Key('store-nav-credit')), findsOneWidget);
  });

  testWidgets('store manager also gets the A63 switch', (tester) async {
    usePhoneSurface(tester);
    final deps = StoreDeps();
    addTearDown(deps.dispose);
    await pumpStore(tester, deps, location: '/settings');
    expect(find.byKey(const Key('store-mode-setting')), findsOneWidget);
  });

  testWidgets('S01 shows sales by mode, queue counts, low stock, day close', (
    tester,
  ) async {
    useTabletSurface(tester);
    final deps = StoreDeps();
    addTearDown(deps.dispose);
    await pumpStore(tester, deps);
    // 18,600 + 12,450 + 4,200 + 3,500 = 38,750.
    expect(
      tester.widget<Text>(find.byKey(const Key('store-sales-total'))).data,
      '₹38,750.00',
    );
    expect(find.text('₹12,450.00'), findsWidgets);
    expect(find.text('Items low: 3'), findsOneWidget);
    expect(find.text('Expiring soon: 3'), findsOneWidget);
    expect(find.text('Open, not closed yet'), findsOneWidget);
    final newCount = find.descendant(
      of: find.byKey(const Key('store-queue-count-fresh')),
      matching: find.text('3'),
    );
    expect(newCount, findsOneWidget);
  });

  testWidgets('tablet 800x1280: two panes (grid + cart) and a rail', (
    tester,
  ) async {
    useTabletSurface(tester);
    final deps = StoreDeps();
    addTearDown(deps.dispose);
    await pumpStore(tester, deps, location: '/store/pos');
    expect(find.byKey(const Key('store-rail')), findsOneWidget);
    expect(find.byKey(const Key('pos-grid-pane')), findsOneWidget);
    expect(find.byKey(const Key('pos-cart-pane')), findsOneWidget);
    expect(find.byKey(const Key('pos-cart-bar')), findsNothing);
    final grid = tester.getRect(find.byKey(const Key('pos-grid-pane')));
    final cart = tester.getRect(find.byKey(const Key('pos-cart-pane')));
    expect(cart.left, greaterThanOrEqualTo(grid.right));
    expect(cart.top, lessThan(grid.bottom));
  });

  testWidgets('phone: single pane with a CartBar and a drawer', (tester) async {
    usePhoneSurface(tester);
    final deps = StoreDeps();
    addTearDown(deps.dispose);
    await pumpStore(tester, deps, location: '/store/pos');
    expect(find.byKey(const Key('store-rail')), findsNothing);
    expect(find.byKey(const Key('pos-cart-pane')), findsNothing);
    expect(find.byKey(const Key('pos-cart-bar')), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('store-drawer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('store-nav-stock')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stock-search')), findsOneWidget);
  });
}
