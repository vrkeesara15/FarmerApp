// Goldens for store mode S01, S02, S03, S05, S06 and S10 at 800 x 1280 dp
// (tablet portrait) in Light and Sunlight.
// Regenerate with: flutter test --update-goldens test/goldens
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../store/store_harness.dart';

void main() {
  for (final mode in AppThemeMode.values) {
    group(mode.name, () {
      late StoreDeps deps;
      setUp(() => deps = StoreDeps());
      tearDown(() => deps.dispose());

      Future<void> open(WidgetTester tester, String location) async {
        useTabletSurface(tester);
        await pumpStore(tester, deps, location: location, theme: mode);
      }

      Future<void> golden(String name) => expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/${name}_${mode.name}.png'),
      );

      testWidgets('s01_store_home', (tester) async {
        await open(tester, '/store');
        await golden('s01_store_home');
      });

      testWidgets('s02_pos', (tester) async {
        await open(tester, '/store/pos');
        deps.scanner
          ..enqueue('8901234500011')
          ..enqueue('8901234500035');
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byKey(const Key('pos-scan')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('cart-inc-sku-urea-45')));
        // Let the snackbar time out.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await golden('s02_pos');
      });

      testWidgets('s03_checkout', (tester) async {
        await open(tester, '/store/pos');
        deps.scanner
          ..enqueue('8901234500011')
          ..enqueue('8901234500035');
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byKey(const Key('pos-scan')));
          await tester.pumpAndSettle();
        }
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('pos-checkout')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('mode-cash')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('checkout-cash-tendered')),
            matching: find.byType(TextField),
          ),
          '800',
        );
        await tester.pumpAndSettle();
        await golden('s03_checkout');
      });

      testWidgets('s05_order_queue', (tester) async {
        await open(tester, '/store/queue');
        await tester.tap(
          find.byKey(
            const Key('queue-order-0b6f1c2e-0000-4000-8000-00000000a102'),
          ),
        );
        await tester.pumpAndSettle();
        await golden('s05_order_queue');
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('s06_stock', (tester) async {
        await open(tester, '/store/stock');
        await tester.tap(find.byKey(const Key('stock-row-sku-imd-250')));
        await tester.pumpAndSettle();
        await golden('s06_stock');
      });

      testWidgets('s10_day_close', (tester) async {
        await open(tester, '/store/day-close');
        for (final (d, n) in <(int, String)>[
          (50000, '20'),
          (20000, '5'),
          (10000, '12'),
          (5000, '3'),
        ]) {
          await tester.enterText(
            find.descendant(
              of: find.byKey(Key('dayclose-note-$d')),
              matching: find.byType(EditableText),
            ),
            n,
          );
          await tester.pumpAndSettle();
        }
        await golden('s10_day_close');
      });
    });
  }
}
