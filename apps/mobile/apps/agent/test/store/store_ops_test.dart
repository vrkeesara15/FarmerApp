import 'dart:typed_data';

import 'package:farmerapp_agent/screens/store/order_queue_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import 'store_harness.dart';

/// S05 queue, S06 stock (+ write-off / adjust), S07 receipt, S08 transfer,
/// S09 credit and S10 day close at 800 x 1280.
void main() {
  late StoreDeps deps;

  setUp(() => deps = StoreDeps());
  tearDown(() => deps.dispose());

  Future<void> open(
    WidgetTester tester,
    String location, {
    String role = 'store_manager',
  }) async {
    useTabletSurface(tester);
    await pumpStore(tester, deps, location: location, role: role);
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  AppButton button(WidgetTester tester, String key) =>
      tester.widget<AppButton>(find.byKey(Key(key)));

  group('S05 order queue', () {
    const placed = '0b6f1c2e-0000-4000-8000-00000000a101';
    const reserved = '0b6f1c2e-0000-4000-8000-00000000a102';
    const ready = '0b6f1c2e-0000-4000-8000-00000000a105';

    testWidgets('tabs show counts', (tester) async {
      await open(tester, '/store/queue');
      expect(find.text('New (3)'), findsOneWidget);
      expect(find.text('Packing (1)'), findsOneWidget);
      expect(find.text('Ready (1)'), findsOneWidget);
      expect(find.text('Handed over (1)'), findsOneWidget);
      // Leave so the refresh timer stops.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('only allowed transitions are enabled', (tester) async {
      await open(tester, '/store/queue');
      await tester.tap(find.byKey(const Key('queue-order-$placed')));
      await tester.pumpAndSettle();
      // placed -> reserved allowed; placed -> packed is not.
      expect(button(tester, 'queue-action-reserved').onPressed, isNotNull);
      expect(button(tester, 'queue-action-packed').onPressed, isNull);
      expect(button(tester, 'queue-action-cancelled').onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('queue-order-$reserved')));
      await tester.pumpAndSettle();
      expect(button(tester, 'queue-action-reserved').onPressed, isNull);
      expect(button(tester, 'queue-action-packed').onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('queue-action-packed')));
      await tester.pumpAndSettle();
      expect(deps.api.calls, contains('setOrderStatus:packed'));
      expect(find.text('Packing (2)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ready: hand over or deliver; cancel needs a reason', (
      tester,
    ) async {
      await open(tester, '/store/queue');
      await tester.tap(find.byKey(const Key('queue-tab-ready')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue-order-$ready')));
      await tester.pumpAndSettle();
      expect(button(tester, 'queue-action-handed_over').onPressed, isNotNull);
      expect(button(tester, 'queue-action-delivered').onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('queue-action-cancelled')));
      await tester.pumpAndSettle();
      final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('queue-cancel-confirm')),
      );
      expect(confirm.onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('queue-cancel-reason')),
        'Farmer changed mind',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('queue-cancel-confirm')));
      await tester.pumpAndSettle();
      expect(deps.api.calls, contains('setOrderStatus:cancelled'));
      expect(find.text('Ready (0)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a refused transition (409) is reported', (tester) async {
      await open(tester, '/store/queue');
      await tester.tap(find.byKey(const Key('queue-order-$reserved')));
      await tester.pumpAndSettle();
      // Someone else packed it meanwhile.
      deps.api.orders = <QueueOrder>[
        for (final o in deps.api.orders)
          o.id == reserved ? o.withStatus(OrderStatus.ready) : o,
      ];
      await tester.tap(find.byKey(const Key('queue-action-packed')));
      await tester.pumpAndSettle();
      expect(
        find.text('This change is not allowed now. The list was refreshed.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('refreshes every 30 s while visible', (tester) async {
      await open(tester, '/store/queue');
      final before = deps.api.calls.where((c) => c == 'orderQueue').length;
      await tester.pump(queueRefreshInterval);
      await tester.pumpAndSettle();
      final after = deps.api.calls.where((c) => c == 'orderQueue').length;
      expect(after, before + 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(queueRefreshInterval);
      expect(deps.api.calls.where((c) => c == 'orderQueue').length, after);
    });

    testWidgets('cluster head sees the queue without actions', (tester) async {
      await open(tester, '/store/queue', role: 'cluster_head');
      await tester.tap(find.byKey(const Key('queue-order-$placed')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('queue-action-reserved')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('S06 stock', () {
    testWidgets('expiry highlight and filters', (tester) async {
      await open(tester, '/store/stock');
      expect(find.byKey(const Key('stock-expiry-sku-imd-250')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('stock-expiry-sku-imd-250')),
          matching: find.text('Expires within 30 days'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('stock-expiry-sku-mnz-1kg')),
          matching: find.text('Expires within 60 days'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('stock-expiry-sku-urea-45')), findsNothing);

      await tester.tap(find.byKey(const Key('stock-filter-low')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock-row-sku-dap-50')), findsOneWidget);
      expect(find.byKey(const Key('stock-row-sku-urea-45')), findsNothing);

      await tester.tap(find.byKey(const Key('stock-filter-low')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stock-filter-expiring')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock-row-sku-imd-250')), findsOneWidget);
      expect(find.byKey(const Key('stock-row-sku-dap-50')), findsNothing);

      await tester.tap(find.byKey(const Key('stock-filter-expiring')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('stock-cat-fertiliser')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock-row-sku-urea-45')), findsOneWidget);
      expect(find.byKey(const Key('stock-row-sku-imd-250')), findsNothing);

      await tapVisible(tester, find.byKey(const Key('stock-cat-all')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('stock-search')), 'teja');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock-row-sku-teja-10')), findsOneWidget);
      expect(find.byKey(const Key('stock-row-sku-urea-45')), findsNothing);
    });

    testWidgets('write-off: qty <= available, reason, photo', (tester) async {
      await open(tester, '/store/stock');
      await tester.tap(find.byKey(const Key('stock-row-sku-imd-250')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('batch-writeoff-b-imd-1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('writeoff-qty')), '21');
      await tester.tap(find.byKey(const Key('writeoff-submit')));
      await tester.pumpAndSettle();
      expect(find.text('More than available (20)'), findsOneWidget);
      expect(deps.api.calls.where((c) => c.startsWith('writeOff')), isEmpty);

      await tester.enterText(find.byKey(const Key('writeoff-qty')), '2');
      await tester.tap(find.byKey(const Key('writeoff-reason-expiry')));
      deps.agent.camera.enqueue(Uint8List.fromList(<int>[1, 2, 3]));
      await tester.tap(find.byKey(const Key('writeoff-photo')));
      await tester.pumpAndSettle();
      expect(find.text('Photo added'), findsOneWidget);
      await tester.tap(find.byKey(const Key('writeoff-submit')));
      await tester.pumpAndSettle();
      expect(
        deps.api.calls,
        contains('writeOff:expiry:gs://farmerapp-dev/receipts/slip-1.jpg'),
      );
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('adjustment needs a count and a reason', (tester) async {
      await open(tester, '/store/stock');
      await tester.enterText(find.byKey(const Key('stock-search')), 'urea');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stock-row-sku-urea-45')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('batch-adjust-b-urea-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adjust-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a reason'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('adjust-qty')), '118');
      await tester.enterText(
        find.byKey(const Key('adjust-reason')),
        'Torn bags',
      );
      await tester.tap(find.byKey(const Key('adjust-submit')));
      await tester.pumpAndSettle();
      expect(deps.api.calls, contains('adjust:118'));
    });

    testWidgets('accountant sees stock read-only', (tester) async {
      await open(tester, '/store/stock', role: 'accountant');
      await tester.tap(find.byKey(const Key('stock-row-sku-imd-250')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('batch-writeoff-b-imd-1')), findsNothing);
      expect(find.byKey(const Key('stock-receipt')), findsNothing);
    });
  });

  group('S07 goods receipt', () {
    testWidgets('validation, then success summary', (tester) async {
      await open(tester, '/store/stock/receipt');
      await tester.tap(find.byKey(const Key('receipt-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Choose an item'), findsOneWidget);
      expect(find.text('Enter the batch number'), findsOneWidget);
      expect(find.text('Enter a quantity above zero'), findsOneWidget);
      expect(find.text('Enter the cost'), findsOneWidget);
      expect(deps.api.calls, isNot(contains('receiveStock')));

      deps.scanner.enqueue('8901234500011');
      await tester.tap(find.byKey(const Key('receipt-scan-0')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('receipt-batch-0')),
        'IMD2609',
      );
      await tester.enterText(find.byKey(const Key('receipt-qty-0')), '24');
      await tester.enterText(find.byKey(const Key('receipt-cost-0')), '330');
      await tester.tap(find.byKey(const Key('receipt-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt-done')), findsOneWidget);
      final line = deps.api.lastReceipt!.single;
      expect(line.item.skuId, 'sku-imd-250');
      expect(line.batchNo, 'IMD2609');
      expect(line.qty, 24);
      expect(line.costPaise, 33000);
    });
  });

  group('S08 stock transfer', () {
    testWidgets('FEFO batch suggested; qty must be <= available', (
      tester,
    ) async {
      await open(tester, '/store/stock/transfer');
      await tester.tap(find.byKey(const Key('transfer-to')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sangareddy FCC').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('transfer-sku-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Imidacloprid 17.8% SL 250 ml').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('transfer-fefo-0')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('transfer-qty-0')), '25');
      await tester.tap(find.byKey(const Key('transfer-submit')));
      await tester.pumpAndSettle();
      expect(find.text('More than available (20)'), findsOneWidget);
      expect(deps.api.lastTransfer, isNull);

      await tester.enterText(find.byKey(const Key('transfer-qty-0')), '12');
      await tester.tap(find.byKey(const Key('transfer-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('transfer-done')), findsOneWidget);
      expect(deps.api.lastTransfer!.single.batch.id, 'b-imd-1');
      expect(deps.api.calls, contains('transferStock:store-sgr'));
    });

    testWidgets('destination required', (tester) async {
      await open(tester, '/store/stock/transfer');
      await tester.tap(find.byKey(const Key('transfer-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Choose the destination store'), findsOneWidget);
    });
  });

  group('S09 credit', () {
    testWidgets('cluster head approves and rejects with a note', (
      tester,
    ) async {
      await open(tester, '/store/credit', role: 'cluster_head');
      expect(find.byKey(const Key('approval-apr-1')), findsOneWidget);
      expect(find.text('₹6,500.00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('approval-approve-apr-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('approval-note')),
        'Harvest next week',
      );
      await tester.tap(find.byKey(const Key('approval-confirm')));
      await tester.pumpAndSettle();
      expect(deps.api.calls, contains('decideCredit:approve'));
      expect(find.byKey(const Key('approval-apr-1')), findsNothing);

      await tester.tap(find.byKey(const Key('approval-reject-apr-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approval-confirm')));
      await tester.pumpAndSettle();
      expect(deps.api.calls, contains('decideCredit:reject'));
      expect(find.byKey(const Key('credit-empty')), findsOneWidget);
    });

    testWidgets('store manager: sets a limit; above ₹50,000 goes to the '
        'cluster head', (tester) async {
      await seedVillage(deps.agent.db);
      await seedSyncedFarmer(deps.agent.db, id: 'f-1', phone: '+919876543210');
      await open(tester, '/store/credit');
      expect(find.byKey(const Key('approval-approve-apr-1')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('credit-phone')),
        '9876543210',
      );
      await tester.tap(find.byKey(const Key('credit-find')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('credit-farmer')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('credit-amount')), '60000');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('credit-over-cap')), findsOneWidget);
      await tester.tap(find.byKey(const Key('credit-save')));
      await tester.pumpAndSettle();
      expect(deps.api.calls, contains('setCreditLimit:6000000'));
      expect(
        tester.widget<Text>(find.byKey(const Key('credit-message'))).data,
        startsWith('Limits above ₹50,000 need a cluster head'),
      );
      await tester.enterText(find.byKey(const Key('credit-amount')), '25000');
      await tester.tap(find.byKey(const Key('credit-save')));
      await tester.pumpAndSettle();
      expect(find.text('Limit saved: ₹25,000'), findsOneWidget);
    });
  });

  group('S10 day close', () {
    Future<void> count(WidgetTester tester, int denomination, String n) async {
      final field = find.descendant(
        of: find.byKey(Key('dayclose-note-$denomination')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(field, n);
      await tester.pumpAndSettle();
    }

    String variance(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('dayclose-variance')),
            matching: find.byType(Text),
          ),
        )
        .last
        .data!;

    testWidgets('variance from denominations, threshold, photo, close', (
      tester,
    ) async {
      await open(tester, '/store/day-close');
      expect(find.text('₹12,450.00'), findsWidgets);
      await count(tester, 50000, '20');
      await count(tester, 20000, '5');
      // 10,000 + 1,000 = 11,000 -> -1,450 (over ₹500).
      expect(variance(tester), '-₹1,450.00');
      expect(find.byKey(const Key('dayclose-over-threshold')), findsOneWidget);
      await count(tester, 10000, '14');
      // 12,400 -> -50: within the threshold.
      expect(variance(tester), '-₹50.00');
      expect(find.byKey(const Key('dayclose-over-threshold')), findsNothing);

      await tester.tap(find.byKey(const Key('dayclose-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dayclose-slip-required')), findsOneWidget);
      expect(deps.api.calls, isNot(contains('closeDay')));

      deps.agent.camera.enqueue(Uint8List.fromList(<int>[1, 2, 3]));
      await tester.tap(find.byKey(const Key('dayclose-photo')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('dayclose-notes')),
        'Rs 50 short, torn note',
      );
      await tester.tap(find.byKey(const Key('dayclose-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dayclose-closed')), findsOneWidget);
      expect(deps.api.lastClose!.cashCountedPaise, 1240000);
      expect(deps.api.lastClose!.depositSlipUri, isNotNull);
      expect(deps.api.lastClose!.notes, 'Rs 50 short, torn note');
    });

    testWidgets('repeat close is blocked (409 day_already_closed)', (
      tester,
    ) async {
      // Another tablet closed the day after this one loaded the summary.
      await deps.api.closeDay(
        'store-knd',
        const DayCloseRequest(
          businessDate: '2026-09-20',
          cashCountedPaise: 1245000,
          depositSlipUri: 'gs://x',
        ),
      );
      final closedSummary = deps.api.summary;
      deps.api.summary = demoSummary('2026-09-20');
      await open(tester, '/store/day-close');
      expect(find.byKey(const Key('dayclose-count')), findsOneWidget);
      deps.api.summary = closedSummary;
      await count(tester, 50000, '1');
      deps.agent.camera.enqueue(Uint8List.fromList(<int>[1]));
      await tester.tap(find.byKey(const Key('dayclose-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dayclose-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dayclose-already')), findsOneWidget);
      expect(find.byKey(const Key('dayclose-closed')), findsOneWidget);
      expect(find.byKey(const Key('dayclose-submit')), findsNothing);
    });

    testWidgets('closed day shows its summary, no form', (tester) async {
      await deps.api.closeDay(
        'store-knd',
        const DayCloseRequest(
          businessDate: '2026-09-20',
          cashCountedPaise: 1100000,
          depositSlipUri: 'gs://x',
        ),
      );
      await open(tester, '/store/day-close');
      expect(find.byKey(const Key('dayclose-closed')), findsOneWidget);
      expect(find.byKey(const Key('dayclose-flagged')), findsOneWidget);
      expect(find.byKey(const Key('dayclose-submit')), findsNothing);
    });
  });
}
