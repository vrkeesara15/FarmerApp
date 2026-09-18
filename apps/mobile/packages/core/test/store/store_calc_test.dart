import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

StoreItem _item(String id, int price, int rateBp, {String hsn = '3808'}) =>
    StoreItem(
      skuId: id,
      productId: 'p-$id',
      name: 'Item $id',
      packLabel: '1 kg',
      pricePaise: price,
      gstRateBp: rateBp,
      hsn: hsn,
    );

void main() {
  group('GST preview (mirrors invoices/gst.py)', () {
    test('intra-state splits each line into CGST + SGST at half the rate', () {
      final p = GstPreview.of(<StoreCartLine>[
        StoreCartLine(item: _item('a', 42000, 1800), qty: 2),
        StoreCartLine(item: _item('b', 26650, 500), qty: 3),
      ]);
      expect(p.inter, isFalse);
      expect(p.taxablePaise, 84000 + 79950);
      // 84000 x 9 % = 7560 each; 79950 x 2.5 % = 1998.75 -> 1999 each.
      expect(p.lines[0].cgstPaise, 7560);
      expect(p.lines[0].sgstPaise, 7560);
      expect(p.lines[1].cgstPaise, 1999);
      expect(p.lines[1].sgstPaise, 1999);
      expect(p.cgstPaise, p.sgstPaise);
      expect(p.igstPaise, 0);
      const exact = 163950 + 2 * (7560 + 1999);
      expect(p.totalPaise % 100, 0);
      expect(p.totalPaise - exact, p.roundOffPaise);
      expect(p.roundOffPaise.abs(), lessThanOrEqualTo(50));
      expect(p.lines.map((l) => l.hsn), <String>['3808', '3808']);
    });

    test('inter-state is IGST at the full rate', () {
      final p = GstPreview.of(<StoreCartLine>[
        StoreCartLine(item: _item('a', 10000, 1200), qty: 1),
      ], inter: true);
      expect(p.igstPaise, 1200);
      expect(p.cgstPaise + p.sgstPaise, 0);
      expect(p.totalPaise, 11200);
    });

    test('round-off is half-up to the rupee', () {
      final up = GstPreview.of(<StoreCartLine>[
        StoreCartLine(item: _item('a', 1050, 0), qty: 1),
      ]);
      expect(up.totalPaise, 1100);
      expect(up.roundOffPaise, 50);
      final down = GstPreview.of(<StoreCartLine>[
        StoreCartLine(item: _item('a', 1049, 0), qty: 1),
      ]);
      expect(down.totalPaise, 1000);
      expect(down.roundOffPaise, -49);
    });

    test('empty cart is zero', () {
      final p = GstPreview.of(const <StoreCartLine>[]);
      expect(p.totalPaise, 0);
      expect(p.lines, isEmpty);
    });

    test('rate labels', () {
      expect(gstRateLabel(1800), '18%');
      expect(gstRateLabel(250), '2.5%');
      expect(gstRateLabel(0), '0%');
    });
  });

  group('cash and day close', () {
    test('denomination total: notes and coins', () {
      final total = denominationTotal(<int, int>{
        50000: 20,
        20000: 5,
        10000: 12,
        5000: 3,
        2000: 4,
        1000: 7,
      }, coinsPaise: 4500);
      expect(total, 1000000 + 100000 + 120000 + 15000 + 8000 + 7000 + 4500);
      expect(noteDenominationsPaise, <int>[
        50000,
        20000,
        10000,
        5000,
        2000,
        1000,
      ]);
    });

    test('variance = counted - expected; threshold is strict Rs 500', () {
      expect(
        cashVariance(countedPaise: 1240000, expectedPaise: 1245000),
        -5000,
      );
      expect(varianceOverThreshold(-50000), isFalse);
      expect(varianceOverThreshold(50001), isTrue);
      expect(varianceOverThreshold(-50100), isTrue);
    });

    test('change and rupee parsing', () {
      expect(cashChange(tenderedPaise: 200000, totalPaise: 199100), 900);
      expect(parseRupees('1,250.5'), 125050);
      expect(parseRupees('₹ 2000'), 200000);
      expect(parseRupees(''), isNull);
      expect(parseRupees('12.345'), isNull);
      expect(parseRupees('abc'), isNull);
    });

    test('IST business date', () {
      expect(istBusinessDate(DateTime.utc(2026, 9, 19, 18, 29)), '2026-09-19');
      expect(istBusinessDate(DateTime.utc(2026, 9, 19, 18, 30)), '2026-09-20');
    });
  });

  group('stock form validation', () {
    const batch = StockBatch(
      id: 'b1',
      skuId: 's1',
      batchNo: 'B1',
      onHand: 10,
      reserved: 4,
      available: 6,
    );

    test(
      'receipt line needs SKU, batch, qty > 0, cost >= 0, future expiry',
      () {
        final today = DateTime(2026, 9, 20);
        expect(
          validateReceiptLine(
            item: _item('a', 100, 0),
            batchNo: 'B-1',
            qty: 5,
            costPaise: 100,
            expiry: DateTime(2027),
            today: today,
          ),
          isEmpty,
        );
        expect(
          validateReceiptLine(
            item: null,
            batchNo: ' ',
            qty: 0,
            costPaise: null,
            expiry: DateTime(2026, 9, 19),
            today: today,
          ),
          <LineProblem>{
            LineProblem.missing,
            LineProblem.batchNo,
            LineProblem.qty,
            LineProblem.cost,
            LineProblem.expiry,
          },
        );
      },
    );

    test('batch qty must be > 0 and <= available', () {
      expect(validateBatchQty(batch, 6), isEmpty);
      expect(validateBatchQty(batch, 7), <LineProblem>{
        LineProblem.overAvailable,
      });
      expect(validateBatchQty(batch, 0), <LineProblem>{LineProblem.qty});
      expect(validateBatchQty(null, 1), <LineProblem>{LineProblem.missing});
    });

    test('transfer: the same batch twice counts once against available', () {
      final problems = validateTransfer(<BatchQty?>[
        const BatchQty(batch: batch, qty: 4),
        const BatchQty(batch: batch, qty: 3),
      ]);
      expect(problems.keys, <int>[1]);
      expect(problems[1], <LineProblem>{LineProblem.overAvailable});
    });

    test('FEFO suggestion skips expired batches and caps at available', () {
      final batches = <StockBatch>[
        StockBatch(
          id: 'late',
          skuId: 's',
          batchNo: 'L',
          expiry: DateTime(2027, 5),
          daysToExpiry: 220,
          onHand: 50,
          reserved: 0,
          available: 50,
        ),
        StockBatch(
          id: 'expired',
          skuId: 's',
          batchNo: 'X',
          expiry: DateTime(2026, 9),
          daysToExpiry: -19,
          onHand: 5,
          reserved: 0,
          available: 5,
        ),
        StockBatch(
          id: 'soon',
          skuId: 's',
          batchNo: 'S',
          expiry: DateTime(2026, 10),
          daysToExpiry: 11,
          onHand: 8,
          reserved: 2,
          available: 6,
        ),
      ];
      final s = suggestFefo(batches, 10);
      expect(s.map((b) => b.batch.id), <String>['soon', 'late']);
      expect(s.map((b) => b.qty), <double>[6, 4]);
    });
  });

  group('stock rows and filters', () {
    final rows = stockRows(demoStock, <String, StoreItem>{
      for (final i in demoCatalog) i.skuId: i,
    });

    test('rows aggregate batches per SKU in FEFO order', () {
      final imd = rows.firstWhere((r) => r.skuId == 'sku-imd-250');
      expect(imd.onHand, 54);
      expect(imd.reserved, 4);
      expect(imd.available, 50);
      expect(imd.batches.first.batchNo, 'IMD2601');
      expect(imd.expiryBand, ExpiryBand.within30);
    });

    test('expiry bands 30 / 60 days and expired', () {
      expect(expiryBandFor(-1), ExpiryBand.expired);
      expect(expiryBandFor(0), ExpiryBand.within30);
      expect(expiryBandFor(30), ExpiryBand.within30);
      expect(expiryBandFor(31), ExpiryBand.within60);
      expect(expiryBandFor(60), ExpiryBand.within60);
      expect(expiryBandFor(61), ExpiryBand.ok);
      expect(expiryBandFor(null), ExpiryBand.ok);
    });

    test('filters: category, low stock, expiring, search', () {
      expect(
        const StockFilter(category: 'fertiliser')
            .apply(rows)
            .map((r) => r.skuId),
        <String>['sku-dap-50', 'sku-urea-45'],
      );
      expect(
        const StockFilter(lowOnly: true)
            .apply(rows)
            .map((r) => r.skuId)
            .toSet(),
        <String>{'sku-dap-50', 'sku-teja-10', 'sku-spr-16'},
      );
      expect(
        const StockFilter(expiringOnly: true)
            .apply(rows)
            .map((r) => r.skuId)
            .toSet(),
        <String>{'sku-imd-250', 'sku-mnz-1kg', 'sku-teja-10'},
      );
      expect(
        const StockFilter(query: 'mancozeb').apply(rows).single.skuId,
        'sku-mnz-1kg',
      );
      expect(
        const StockFilter(query: '8901234500042').apply(rows).single.skuId,
        'sku-dap-50',
      );
    });
  });

  group('order transitions (server TRANSITIONS)', () {
    test('allowed and blocked', () {
      expect(canTransition(OrderStatus.placed, OrderStatus.reserved), isTrue);
      expect(canTransition(OrderStatus.placed, OrderStatus.packed), isFalse);
      expect(canTransition(OrderStatus.reserved, OrderStatus.packed), isTrue);
      expect(canTransition(OrderStatus.packed, OrderStatus.ready), isTrue);
      expect(canTransition(OrderStatus.ready, OrderStatus.handedOver), isTrue);
      expect(canTransition(OrderStatus.ready, OrderStatus.delivered), isTrue);
      expect(
        canTransition(OrderStatus.packed, OrderStatus.handedOver),
        isFalse,
      );
      expect(
        canTransition(OrderStatus.handedOver, OrderStatus.cancelled),
        isFalse,
      );
      for (final s in <OrderStatus>[
        OrderStatus.placed,
        OrderStatus.reserved,
        OrderStatus.packed,
        OrderStatus.ready,
      ]) {
        expect(canTransition(s, OrderStatus.cancelled), isTrue);
      }
    });

    test('tabs group statuses', () {
      expect(QueueTab.of(OrderStatus.placed), QueueTab.fresh);
      expect(QueueTab.of(OrderStatus.reserved), QueueTab.fresh);
      expect(QueueTab.of(OrderStatus.packed), QueueTab.packing);
      expect(QueueTab.of(OrderStatus.delivered), QueueTab.handedOver);
      expect(QueueTab.of(OrderStatus.cancelled), isNull);
    });
  });

  group('store roles (SPEC 1.2 / 2.6)', () {
    test('field officers and others never get store mode', () {
      for (final r in <String?>[
        'field_officer',
        'farmer',
        'agronomist',
        'auditor',
        'owner',
        null,
      ]) {
        expect(storeRoleFor(r).hasStoreMode, isFalse, reason: '$r');
      }
    });

    test('capabilities per role', () {
      final m = storeRoleFor('store_manager');
      final a = storeRoleFor('accountant');
      final c = storeRoleFor('cluster_head');
      expect(m.opensStoreOnLogin && a.opensStoreOnLogin, isTrue);
      expect(c.opensStoreOnLogin, isFalse);
      expect(
        <bool>[m.canSell, a.canSell, c.canSell],
        <bool>[true, true, false],
      );
      expect(
        <bool>[m.canMoveStock, a.canMoveStock, c.canMoveStock],
        <bool>[true, false, false],
      );
      expect(c.readOnly && c.canApproveCredit, isTrue);
      expect(m.canApproveCredit, isFalse);
      expect(m.canSetCreditLimit, isTrue);
      expect(
        <bool>[m.canCloseDay, a.canCloseDay, c.canCloseDay],
        <bool>[true, true, false],
      );
    });
  });
}
