import 'dart:math';
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'commerce_harness.dart';

CatalogItem item(String sku, int price, {int gst = 1800, String name = 'X'}) =>
    CatalogItem(
      productId: 'p-$sku',
      skuId: sku,
      name: name,
      brand: 'B',
      ownBrand: false,
      category: CatalogCategory.pesticide,
      packLabel: '150 ml',
      mrpPaise: price,
      pricePaise: price,
      gstRateBp: gst,
    );

final CatalogItem coragen = item('sku-cora-150', 118000, name: 'Coragen');
final CatalogItem neem = item(
  'sku-neem-500',
  42000,
  gst: 1200,
  name: 'Mitra Neem Shakti',
);

/// Minimal JPEG-ish bytes for the receipt (the pipeline is tested in
/// `photo/`; here only the upload + op plumbing matters).
final Uint8List receipt = Uint8List.fromList(
  List<int>.generate(2048, (i) => i % 251),
);

class World {
  World({bool online = true}) {
    db = openInMemoryDatabase();
    api = FakeSyncApi()..offline = !online;
    server = FakeCommerceServer(
      api: api,
      prices: <String, int>{'sku-cora-150': 120000, 'sku-neem-500': 42000},
      gstBp: <String, int>{'sku-cora-150': 1800, 'sku-neem-500': 1200},
      clock: () => now,
    );
    var n = 0;
    ids = () => 'id-${(++n).toString().padLeft(4, '0')}';
    outbox = Outbox(db, clock: () => now, ids: ids);
    photos = MemoryPhotoStore();
    engine = SyncEngine(
      db: db,
      api: api,
      deviceId: () async => 'device-1',
      clock: () => now,
      random: Random(1),
      readFile: (path) async => photos.files[path]!,
    );
    payApi = FakePaymentsApi(clock: () => now);
    orders = OrderRepository(db, outbox, ids: ids);
    payments = PaymentRepository(
      db: db,
      outbox: outbox,
      api: payApi,
      photos: photos,
      ids: ids,
      clock: () => now,
    );
  }

  late final AppDatabase db;
  late final FakeSyncApi api;
  late final FakeCommerceServer server;
  late final String Function() ids;
  late final Outbox outbox;
  late final MemoryPhotoStore photos;
  late final SyncEngine engine;
  late final FakePaymentsApi payApi;
  late final OrderRepository orders;
  late final PaymentRepository payments;
  DateTime now = t0;

  Future<String> place(List<CartLine> lines, {String? mode}) => orders.place(
    farmerId: 'f-1',
    storeId: storeId,
    fulfilment: Fulfilment.pickup,
    lines: lines,
    paymentMode: mode,
    now: now,
  );

  Future<SyncOp> opFor(String entityId) async {
    final rows = await outbox.store.opsIn(
      OutboxState.values.map((s) => s.name),
    );
    return SyncStore.toOp(rows.firstWhere((r) => r.entityId == entityId));
  }

  Future<void> close() async {
    await engine.dispose();
    await db.close();
  }
}

void main() {
  group('cart math (estimates; the server prices on placing)', () {
    test('line = qty x unit, GST half-up per line, total = sum', () {
      final totals = CartTotals.of(<CartLine>[
        CartLine(item: coragen, qty: 2),
        CartLine(item: neem, qty: 3),
      ]);
      expect(totals.subtotalPaise, 236000 + 126000);
      expect(totals.taxPaise, 42480 + 15120);
      expect(totals.totalPaise, 419600);
      expect(totals.itemCount, 5);
    });

    test('half-up rounding of the tax matches the server rule', () {
      final odd = CartLine(item: item('s', 33333), qty: 1);
      // 33333 x 18 % = 5999.94 → 6000.
      expect(odd.estimatedTaxPaise, 6000);
      expect(
        CartLine(item: item('s', 2778, gst: 500), qty: 1).estimatedTaxPaise,
        139,
      );
      expect(roundHalfUp(5, 10), 1);
      expect(roundHalfUp(4, 10), 0);
    });

    test('the cart notifier adds, sets and removes lines', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final cart = c.read(cartProvider.notifier)
        ..start('f-1', storeId: storeId);
      cart
        ..add(coragen)
        ..add(coragen)
        ..add(neem)
        ..setQty(neem, 0);
      final s = c.read(cartProvider);
      expect(s.lines.single.qty, 2);
      expect(s.totals.totalPaise, 2 * 118000 + 42480);
      cart.start('f-2');
      expect(c.read(cartProvider).lines, isEmpty);
    });
  });

  group('order op', () {
    late World w;
    setUp(() => w = World());
    tearDown(() => w.close());

    test(
      'payload is OrderCreate without prices (client_order_id = id)',
      () async {
        final id = await w.place(<CartLine>[
          CartLine(item: coragen, qty: 2),
          CartLine(item: neem, qty: 1),
        ], mode: PaymentModes.cash);
        final op = await w.opFor(id);
        expect(op.entity, 'order');
        expect(op.action, SyncAction.create);
        expect(op.payload, <String, Object?>{
          'farmer_id': 'f-1',
          'store_id': storeId,
          'fulfilment': 'pickup',
          'payment_mode': 'cash',
          'lines': <Object?>[
            <String, Object?>{'sku_id': 'sku-cora-150', 'qty': 2},
            <String, Object?>{'sku_id': 'sku-neem-500', 'qty': 1},
          ],
          'id': id,
        });
        final view = (await w.orders.order(id))!;
        expect(view.pendingSync, isTrue);
        expect(view.serverPriced, isFalse);
        expect(view.order.totalPaise, isNull, reason: 'money is server-owned');
        expect(view.displayTotalPaise, 2 * 118000 + 42480 + 42000 + 5040);
        expect(view.lines.map((l) => l.productName), <String>[
          'Coragen',
          'Mitra Neem Shakti',
        ]);
      },
    );

    test('applied: server totals and lines replace the estimate', () async {
      final id = await w.place(<CartLine>[CartLine(item: coragen, qty: 2)]);
      final report = await w.engine.syncNow();
      expect(report.applied, 1);
      final view = (await w.orders.order(id))!;
      // Server price 1,200.00 (not the cached 1,180.00) + 18 % GST.
      expect(view.order.subtotalPaise, 240000);
      expect(view.order.taxPaise, 43200);
      expect(view.order.totalPaise, 283200);
      expect(view.displayTotalPaise, 283200);
      expect(view.order.status, OrderStatuses.reserved);
      expect(view.order.version, 2);
      expect(view.pendingSync, isFalse);
      expect(view.lines.single.id, '$id-line-0');
      expect(view.lines.single.unitPricePaise, 120000);
      expect(view.lines.single.productName, 'Coragen');
      expect(view.events.map((e) => e.toStatus), <String>[
        'placed',
        'reserved',
      ]);
    });

    test(
      'insufficient_stock: per-line available, edit, resend the same op',
      () async {
        w.server.stock['sku-cora-150'] = 1;
        final id = await w.place(<CartLine>[
          CartLine(item: coragen, qty: 3),
          CartLine(item: neem, qty: 1),
        ]);
        final cash = await w.payments.collectCash(
          PaymentTarget.order(orderId: id, farmerId: 'f-1', storeId: storeId),
          receiptJpeg: receipt,
          expectedPaise: 1000,
        );
        final opId = (await w.opFor(id)).opId;
        await w.engine.syncNow();
        var view = (await w.orders.order(id))!;
        expect(view.rejection!.code, OrderErrorCodes.insufficientStock);
        expect(view.shortfalls.single.skuId, 'sku-cora-150');
        expect(view.shortfalls.single.requested, 3);
        expect(view.shortfalls.single.available, 1);
        // The payment failed behind it (no order on the server).
        expect((await w.payments.payment(cash))!.rejection!.code, 'not_found');

        await w.orders.resubmit(id, <CartLine>[
          CartLine(item: coragen, qty: 1),
          CartLine(item: neem, qty: 1),
        ], now: w.now);
        expect((await w.opFor(id)).opId, opId, reason: 'same op, requeued');
        expect((await w.opFor(id)).payload['lines'], <Object?>[
          <String, Object?>{'sku_id': 'sku-cora-150', 'qty': 1},
          <String, Object?>{'sku_id': 'sku-neem-500', 'qty': 1},
        ]);
        await w.engine.syncNow();
        view = (await w.orders.order(id))!;
        expect(view.rejection, isNull);
        expect(view.order.totalPaise, 120000 + 21600 + 42000 + 5040);
        final pay = (await w.payments.payment(cash))!;
        expect(pay.rejection, isNull);
        expect(pay.payment.status, PaymentStatuses.pendingReconciliation);
      },
    );

    test('sku_not_recommendable is kept on the order for A57', () async {
      w.api.script = (op) => op.entity == 'order'
          ? SyncOpResult(
              opId: op.opId,
              status: SyncResultStatus.rejected,
              entityId: op.entityId,
              error: const SyncError(
                'sku_not_recommendable',
                'No approved label claim for this crop and pest.',
              ),
            )
          : null;
      final id = await w.place(<CartLine>[CartLine(item: coragen, qty: 1)]);
      await w.engine.syncNow();
      final view = (await w.orders.order(id))!;
      expect(view.rejection!.code, OrderErrorCodes.skuNotRecommendable);
      expect(view.shortfalls, isEmpty);
      await w.orders.discard(id);
      expect(await w.orders.order(id), isNull);
    });

    test('pulled status changes move the timeline; lines by id', () async {
      final id = await w.place(<CartLine>[CartLine(item: coragen, qty: 2)]);
      await w.engine.syncNow();
      w.api
        ..addChange(
          entity: 'order',
          action: SyncAction.update,
          entityId: id,
          version: 3,
          data: <String, Object?>{
            ...w.server.orders[id]!..remove('lines'),
            'status': 'packed',
            'invoice_no': 'KDP/2026-27/0001',
            'invoice_id': 'inv-1',
          },
        )
        ..addChange(
          entity: 'order_line',
          action: SyncAction.update,
          entityId: '$id-line-0',
          version: 2,
          data: <String, Object?>{
            'id': '$id-line-0',
            'order_id': id,
            'sku_id': 'sku-cora-150',
            'qty': '2.000',
            'unit_price_paise': 120000,
            'line_total_paise': 240000,
          },
        );
      await w.engine.syncNow();
      final view = (await w.orders.order(id))!;
      expect(view.order.status, 'packed');
      expect(OrderStatuses.stepOf(view.order.status), 2);
      expect(view.order.invoiceId, 'inv-1');
      expect(view.lines.single.productName, 'Coragen');
      expect(view.events, hasLength(2), reason: 'history kept');
    });
  });

  group('payments', () {
    late World w;
    setUp(() => w = World());
    tearDown(() => w.close());

    test(
      'cash offline: receipt upload + op, then pending reconciliation',
      () async {
        w.api.offline = true;
        final id = await w.place(<CartLine>[CartLine(item: coragen, qty: 1)]);
        final payId = await w.payments.collectCash(
          PaymentTarget.order(orderId: id, farmerId: 'f-1', storeId: storeId),
          receiptJpeg: receipt,
          expectedPaise: 139240,
        );
        final op = await w.opFor(payId);
        expect(op.entity, 'payment');
        expect(op.payload.containsKey('id'), isFalse);
        expect(op.payload.containsKey('amount_paise'), isFalse);
        expect(op.payload['mode'], 'cash');
        expect(op.payload['order_id'], id);
        expect('${op.payload['receipt_uri']}', startsWith('upload:'));
        var view = (await w.payments.payment(payId))!;
        expect(view.state, CollectionState.waitingToSync);
        expect(view.payment.amountPaise, 139240);
        expect(view.payment.farmerId, 'f-1');
        expect(view.payment.receiptPath, 'memory://photos/receipt_$payId.jpg');

        await w.engine.syncNow();
        expect(
          (await w.payments.payment(payId))!.state,
          CollectionState.waitingToSync,
        );

        w.api.offline = false;
        final report = await w.engine.syncNow();
        expect(report.uploads, 1);
        final sent = w.api.requests
            .expand((r) => r.ops)
            .lastWhere((o) => o.entity == 'payment');
        expect(
          '${sent.payload['receipt_uri']}',
          startsWith('blob://fake/receipt/'),
        );
        view = (await w.payments.payment(payId))!;
        expect(view.payment.status, PaymentStatuses.pendingReconciliation);
        expect(view.state, CollectionState.pendingReconciliation);
        expect(view.payment.amountPaise, 141600, reason: 'server amount wins');
        expect(view.payment.collectedBy, 'officer-1');
      },
    );

    test('dues cash carries farmer, store and the amount', () async {
      final payId = await w.payments.collectCash(
        const PaymentTarget.dues(
          farmerId: 'f-1',
          storeId: storeId,
          duesAmountPaise: 250000,
        ),
        receiptJpeg: receipt,
        expectedPaise: 250000,
      );
      final op = await w.opFor(payId);
      expect(op.payload['farmer_id'], 'f-1');
      expect(op.payload['store_id'], storeId);
      expect(op.payload['amount_paise'], 250000);
      expect(op.payload.containsKey('order_id'), isFalse);
      await w.engine.syncNow();
      expect(
        (await w.payments.payment(payId))!.payment.status,
        PaymentStatuses.pendingReconciliation,
      );
    });

    test(
      'credit over the limit → approval needed → proceeds after approval',
      () async {
        w.server
          ..creditLimitPaise = 200000
          ..balancePaise = 150000;
        final id = await w.place(<CartLine>[CartLine(item: coragen, qty: 1)]);
        final payId = await w.payments.collectCredit(
          PaymentTarget.order(orderId: id, farmerId: 'f-1', storeId: storeId),
          expectedPaise: 139240,
        );
        final op = await w.opFor(payId);
        expect(op.payload, <String, Object?>{'order_id': id, 'mode': 'credit'});
        await w.engine.syncNow();
        var view = (await w.payments.payment(payId))!;
        final block = view.creditBlock!;
        expect(block.limitPaise, 200000);
        expect(block.balancePaise, 150000);
        expect(block.shortfallPaise, 150000 + 141600 - 200000);
        expect(block.approvalRequestId, 'approval-$id');
        expect(block.headroomPaise, 50000);
        expect(view.state, CollectionState.approvalNeeded);

        // Re-check before the cluster head decided: still blocked.
        expect(await w.payments.recheckCredit(payId), isTrue);
        await w.engine.syncNow();
        expect((await w.payments.payment(payId))!.creditBlock, isNotNull);

        w.server.approve(id);
        expect(await w.payments.recheckCredit(payId), isTrue);
        await w.engine.syncNow();
        view = (await w.payments.payment(payId))!;
        expect(view.rejection, isNull);
        expect(view.state, CollectionState.onKhata);
        expect(await w.payments.recheckCredit(payId), isFalse);
      },
    );

    test('credit is only for orders', () async {
      expect(
        () => w.payments.collectCredit(
          const PaymentTarget.dues(
            farmerId: 'f-1',
            storeId: storeId,
            duesAmountPaise: 100,
          ),
          expectedPaise: 100,
        ),
        throwsArgumentError,
      );
    });

    test(
      'UPI QR created online is stored with its payload and expiry',
      () async {
        final out = await w.payments.createOnline(
          const PaymentTarget.order(orderId: 'o-1', farmerId: 'f-1'),
          mode: PaymentModes.upiQr,
        );
        expect(out.result, PaymentCallResult.ok);
        final p = (await w.payments.payment(out.paymentId!))!.payment;
        expect(p.qrPayload, startsWith('upi://pay'));
        expect(p.expiresAt!.toUtc(), t0.add(const Duration(minutes: 15)));
        expect(p.version, 1);
        expect(w.payApi.created.single, <String, Object?>{
          'order_id': 'o-1',
          'mode': 'upi_qr',
        });
        w.payApi.offline = true;
        final offline = await w.payments.createOnline(
          const PaymentTarget.order(orderId: 'o-1', farmerId: 'f-1'),
          mode: PaymentModes.upiQr,
        );
        expect(offline.result, PaymentCallResult.network);
        expect(offline.paymentId, isNull);
      },
    );

    test(
      'payment link: sent state with the channel, resend by WhatsApp',
      () async {
        final out = await w.payments.createOnline(
          const PaymentTarget.dues(
            farmerId: 'f-1',
            storeId: storeId,
            duesAmountPaise: 50000,
          ),
          mode: PaymentModes.paymentLink,
        );
        final p = (await w.payments.payment(out.paymentId!))!.payment;
        expect(p.sentVia, 'sms');
        expect(p.shortUrl, startsWith('https://rzp.io/'));
        final again = await w.payments.resendLink(
          out.paymentId!,
          channel: 'whatsapp',
        );
        expect(w.payApi.created.last['channel'], 'whatsapp');
        expect(w.payApi.created.last['amount_paise'], 50000);
        expect(
          (await w.payments.payment(again.paymentId!))!.payment.sentVia,
          'whatsapp',
        );
      },
    );
  });

  group('UPI polling (fake clock)', () {
    late DateTime now;
    late List<Duration> waits;
    late FakePaymentsApi api;

    setUp(() {
      now = t0;
      waits = <Duration>[];
      api = FakePaymentsApi(clock: () => now)..states['pay-1'] = 'waiting';
    });

    UpiPoller poller({DateTime? expiresAt}) => UpiPoller(
      fetch: () => api.status('pay-1'),
      clock: () => now,
      sleep: (d) async {
        waits.add(d);
        now = now.add(d);
      },
      expiresAt: expiresAt,
    );

    test('every 3 s, backing off to 10 s', () {
      final p = poller();
      expect(
        <int>[for (var n = 1; n <= 14; n++) p.intervalAfter(n).inMilliseconds],
        <int>[
          3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, //
          4500, 6750, 10000, 10000, 10000,
        ],
      );
    });

    test('paid after a few polls', () async {
      final p = poller(expiresAt: t0.add(const Duration(minutes: 15)));
      final states = <UpiPollPhase>[];
      await for (final s in p.run()) {
        states.add(s.phase);
        if (s.polls == 3) api.states['pay-1'] = 'paid';
      }
      expect(states, <UpiPollPhase>[
        UpiPollPhase.waiting,
        UpiPollPhase.waiting,
        UpiPollPhase.waiting,
        UpiPollPhase.paid,
      ]);
      expect(waits, List<Duration>.filled(3, const Duration(seconds: 3)));
    });

    test('failed ends polling with the reason', () async {
      api.states['pay-1'] = 'failed';
      final last = await poller().run().last;
      expect(last.phase, UpiPollPhase.failed);
      expect(last.failureReason, 'payment_failed');
      expect(waits, isEmpty);
    });

    test('stops at expiry without polling past it', () async {
      final expiry = t0.add(const Duration(minutes: 2));
      final all = await poller(expiresAt: expiry).run().toList();
      expect(all.last.phase, UpiPollPhase.expired);
      expect(now, expiry);
      // 9 x 3 s + 4.5 + 6.75 + 10 x ... until 120 s.
      expect(api.polls['pay-1'], all.length - 1);
      expect(waits.every((d) => d <= const Duration(seconds: 10)), isTrue);
    });

    test('a network failure keeps waiting', () async {
      api.offline = true;
      final p = poller(expiresAt: t0.add(const Duration(seconds: 7)));
      final all = await p.run().toList();
      expect(all.map((s) => s.phase), <UpiPollPhase>[
        UpiPollPhase.waiting,
        UpiPollPhase.waiting,
        UpiPollPhase.waiting,
        UpiPollPhase.expired,
      ]);
    });
  });

  group('collections (A59)', () {
    late World w;
    setUp(() => w = World());
    tearDown(() => w.close());

    test('totals by mode count collected money only', () async {
      w.server.creditLimitPaise = 100;
      final o1 = await w.place(<CartLine>[CartLine(item: coragen, qty: 1)]);
      final o2 = await w.place(<CartLine>[CartLine(item: neem, qty: 1)]);
      await w.engine.syncNow();
      await w.payments.collectCash(
        PaymentTarget.order(orderId: o1, farmerId: 'f-1', storeId: storeId),
        receiptJpeg: receipt,
        expectedPaise: 0,
      );
      final blocked = await w.payments.collectCredit(
        PaymentTarget.order(orderId: o2, farmerId: 'f-1', storeId: storeId),
        expectedPaise: 47040,
      );
      await w.engine.syncNow();
      final upi = await w.payments.createOnline(
        const PaymentTarget.dues(
          farmerId: 'f-1',
          storeId: storeId,
          duesAmountPaise: 30000,
        ),
        mode: PaymentModes.upiQr,
      );
      await w.payments.applyPoll(
        upi.paymentId!,
        const UpiPollState(UpiPollPhase.paid),
      );
      final failed = await w.payments.createOnline(
        const PaymentTarget.dues(
          farmerId: 'f-1',
          storeId: storeId,
          duesAmountPaise: 99900,
        ),
        mode: PaymentModes.upiQr,
      );
      await w.payments.applyPoll(
        failed.paymentId!,
        const UpiPollState(UpiPollPhase.expired),
      );
      // Offline cash still queued (dues).
      w.api.offline = true;
      await w.payments.collectCash(
        const PaymentTarget.dues(
          farmerId: 'f-1',
          storeId: storeId,
          duesAmountPaise: 20000,
        ),
        receiptJpeg: receipt,
        expectedPaise: 20000,
      );
      final (from, to) = istDayBounds(w.now);
      final summary = await w.payments.watchCollections(from, to).first;
      expect(summary.items, hasLength(5));
      final byState = <String, CollectionState>{
        for (final v in summary.items) v.payment.id: v.state,
      };
      expect(byState[blocked], CollectionState.approvalNeeded);
      expect(byState[failed.paymentId], CollectionState.failed);
      expect(byState[upi.paymentId], CollectionState.paid);
      expect(summary.totalsByMode, <String, int>{
        'cash': 141600 + 20000,
        'upi_qr': 30000,
      });
      expect(summary.collectedPaise, 191600);
      // Yesterday's window is empty.
      final empty = await w.payments
          .watchCollections(from.subtract(const Duration(days: 1)), from)
          .first;
      expect(empty.items, isEmpty);
    });
  });

  test('SyncError keeps every errors[] entry through the outbox', () {
    final e = SyncError.fromJson(<String, Object?>{
      'code': 'insufficient_stock',
      'detail': 'short',
      'errors': <Object?>[
        <String, Object?>{'index': 0, 'sku_id': 'a', 'available': '1'},
        <String, Object?>{'index': 2, 'sku_id': 'b', 'available': '0'},
      ],
    })!;
    expect(e.errors, hasLength(2));
    final back = SyncError.fromJson(e.toJson())!;
    expect(back.errors.map((x) => x['sku_id']), <String>['a', 'b']);
    expect(StockShortfall.fromError(back).map((s) => s.index), <int>[0, 2]);
  });
}
