import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AuthSession _session(String role, {String? storeId = 'store-knd'}) =>
    AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.utc(2030),
      user: AuthUser(
        id: 'u',
        tenantId: 't',
        phone: '+919000000001',
        name: 'Suresh',
        role: role,
        language: 'en',
        status: 'active',
        storeId: storeId,
      ),
    );

class _World {
  _World({String role = 'store_manager', String? storeId = 'store-knd'})
    : db = openInMemoryDatabase(),
      api = FakeStoreApi(),
      net = FakeConnectivityMonitor(),
      camera = FakeCameraSource() {
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        storeApiProvider.overrideWithValue(api),
        connectivityMonitorProvider.overrideWithValue(net),
        cameraSourceProvider.overrideWithValue(camera),
        storePhotoProcessorProvider.overrideWithValue((b) async => b),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 9, 20, 5)),
        tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(
            deviceId: 'd',
            session: _session(role, storeId: storeId),
          ),
        ),
      ],
    );
  }

  final AppDatabase db;
  final FakeStoreApi api;
  final FakeConnectivityMonitor net;
  final FakeCameraSource camera;
  late final ProviderContainer container;

  PosNotifier get pos => container.read(posProvider.notifier);
  PosState get state => container.read(posProvider);

  Future<void> ready() async {
    await container.read(storeUserProvider.future);
    await container.read(storesProvider.future);
  }

  Future<void> dispose() async {
    container.dispose();
    await net.dispose();
    await db.close();
  }
}

void main() {
  late _World w;

  setUp(() async {
    w = _World();
    await w.ready();
  });
  tearDown(() => w.dispose());

  test('active store is the user\'s store; role from the session', () {
    expect(w.container.read(activeStoreProvider)!.name, 'Kondapur FCC');
    expect(w.container.read(storeRoleProvider), StoreRole.manager);
    w.container.read(selectedStoreProvider.notifier).select('store-sgr');
    expect(w.container.read(activeStoreProvider)!.code, 'SGR');
  });

  test('accountant without a store works in the first listed store', () async {
    final a = _World(role: 'accountant', storeId: null);
    addTearDown(a.dispose);
    await a.ready();
    expect(a.container.read(activeStoreProvider)!.id, 'store-knd');
    expect(a.container.read(storeRoleProvider), StoreRole.accountant);
  });

  test('cart: add, merge, qty edit, remove, totals', () {
    final imd = demoCatalog[0];
    final urea = demoCatalog[2];
    w.pos
      ..add(imd)
      ..add(imd)
      ..add(urea);
    expect(w.state.lines.map((l) => l.qty), <int>[2, 1]);
    expect(w.state.itemCount, 3);
    expect(w.state.preview.taxablePaise, 2 * 42000 + 26650);
    w.pos.setQty(urea.skuId, 4);
    expect(w.state.preview.taxablePaise, 2 * 42000 + 4 * 26650);
    w.pos.setQty(imd.skuId, 0);
    expect(w.state.lines.single.item.skuId, urea.skuId);
    // 4 x 266.50 = 1066.00 + 5 % (26.65 + 26.65) = 1119.30 -> 1119.
    expect(w.state.preview.totalPaise, 111900);
  });

  test('barcode found adds a pack; not found and offline do not', () async {
    expect(await w.pos.scan('8901234500028'), ScanOutcome.added);
    expect(w.state.lines.single.item.name, 'Mancozeb 75% WP');
    expect(await w.pos.scan('0000000000000'), ScanOutcome.notFound);
    expect(w.state.scannedCode, '0000000000000');
    w.api.offline = true;
    expect(await w.pos.scan('8901234500028'), ScanOutcome.offline);
    expect(w.state.lines.single.qty, 1);
  });

  test(
    'farmer lookup: local farmer found, unknown phone kept as buyer',
    () async {
      await LocalEntities(w.db).write(
        SyncEntities.farmer,
        'f-ramesh',
        <String, Object?>{'name': 'Ramesh Reddy', 'phone': '+919876543210'},
        version: 1,
        dirty: false,
        now: DateTime.utc(2026, 9, 2),
      );
      final known = await w.pos.lookupBuyer('98765 43210');
      expect(known!.farmerId, 'f-ramesh');
      expect(known.name, 'Ramesh Reddy');
      final walkIn = await w.pos.lookupBuyer('9000011122');
      expect(walkIn!.known, isFalse);
      expect(await w.pos.lookupBuyer('12345'), isNull);
    },
  );

  test('offline: sale blocked, cart kept, then completes online', () async {
    w.pos
      ..add(demoCatalog[0])
      ..setMode(SaleMode.card)
      ..setCardReference('TID 88');
    w.net.online = false;
    expect(await w.pos.confirm(), CheckoutPhase.offline);
    expect(w.state.lines, hasLength(1));
    expect(w.api.calls.where((c) => c.startsWith('posSale')), isEmpty);
    w.net.online = true;
    expect(await w.pos.confirm(), CheckoutPhase.done);
    expect(w.state.sale!.invoice.invoiceNo, startsWith('FCC/KND/'));
  });

  test('server unreachable mid-sale is offline too; cart kept', () async {
    w.pos
      ..add(demoCatalog[0])
      ..setMode(SaleMode.card)
      ..setCardReference('TID 88');
    w.api.offline = true;
    expect(await w.pos.confirm(), CheckoutPhase.offline);
    expect(w.state.lines, hasLength(1));
  });

  test('card needs a reference', () async {
    w.pos
      ..add(demoCatalog[0])
      ..setMode(SaleMode.card);
    expect(await w.pos.confirm(), CheckoutPhase.referenceRequired);
    expect(w.api.calls.where((c) => c.startsWith('posSale')), isEmpty);
    w.pos.setCardReference('4471');
    expect(await w.pos.confirm(), CheckoutPhase.done);
    expect(w.api.lastSale!.referenceNote, '4471');
  });

  test('cash: short tender refused; change from the invoice total', () async {
    w.pos
      ..add(demoCatalog[0])
      ..setMode(SaleMode.cash)
      ..setTendered(40000);
    // 420 + 18 % = 495.60 -> 496.
    expect(w.state.preview.totalPaise, 49600);
    expect(await w.pos.confirm(), CheckoutPhase.cashShort);
    w.pos.setTendered(50000);
    expect(w.state.changePaise, 400);
    expect(await w.pos.confirm(), CheckoutPhase.done);
    expect(w.state.changePaise, 400);
  });

  test('UPI: QR then polling until paid; failed offers a new QR', () async {
    w.pos
      ..add(demoCatalog[2])
      ..setMode(SaleMode.upiQr);
    w.api.upiPolls.addAll(<PaymentPollState>[
      PaymentPollState.waiting,
      PaymentPollState.failed,
      PaymentPollState.paid,
    ]);
    expect(await w.pos.confirm(), CheckoutPhase.awaitingUpi);
    expect(w.state.upiPayment!.qrPayload, startsWith('upi://'));
    expect(await w.pos.pollUpi(), PaymentPollState.waiting);
    expect(w.state.phase, CheckoutPhase.awaitingUpi);
    expect(await w.pos.pollUpi(), PaymentPollState.failed);
    expect(w.state.phase, CheckoutPhase.upiFailed);
    await w.pos.retryUpi();
    expect(w.state.phase, CheckoutPhase.awaitingUpi);
    expect(w.state.upiPayment!.paymentId, startsWith('pay-retry'));
    expect(await w.pos.pollUpi(), PaymentPollState.paid);
    expect(w.state.phase, CheckoutPhase.done);
  });

  test('credit beyond the limit: approval needed, cart kept', () async {
    await LocalEntities(w.db).write(
      SyncEntities.farmer,
      'f-ramesh',
      <String, Object?>{'name': 'Ramesh Reddy', 'phone': '+919876543210'},
      version: 1,
      dirty: false,
      now: DateTime.utc(2026, 9, 2),
    );
    w.pos
      ..add(demoCatalog[6])
      ..setMode(SaleMode.credit);
    expect(await w.pos.confirm(), CheckoutPhase.failed);
    expect(w.state.failure!.code, 'farmer_required');
    await w.pos.lookupBuyer('9876543210');
    w.api.creditExceeded = true;
    expect(await w.pos.confirm(), CheckoutPhase.approvalNeeded);
    expect(w.state.failure!.intExtra('limit_paise'), 2000000);
    expect(w.state.lines, hasLength(1));
    w.api.creditExceeded = false;
    w.pos.backToEditing();
    expect(await w.pos.confirm(), CheckoutPhase.done);
    expect(w.api.lastSale!.farmerId, 'f-ramesh');
  });

  test('new sale clears everything', () async {
    w.pos
      ..add(demoCatalog[0])
      ..setMode(SaleMode.card)
      ..setCardReference('1');
    await w.pos.confirm();
    w.pos.newSale();
    expect(w.state.lines, isEmpty);
    expect(w.state.sale, isNull);
    expect(w.state.mode, isNull);
  });

  group('day close', () {
    DayCloseNotifier close() => w.container.read(dayCloseProvider.notifier);
    DayCloseState state() => w.container.read(dayCloseProvider);

    test('counted total from denominations; slip required for cash', () async {
      close()
        ..setCount(50000, 20)
        ..setCount(20000, 5)
        ..setCount(10000, 14)
        ..setCoins(0);
      expect(state().countedPaise, 1240000);
      expect(await close().submit(), DayClosePhase.slipRequired);
      w.camera.enqueue(Uint8List.fromList(<int>[1, 2, 3]));
      expect(await close().captureSlip(), isTrue);
      expect(await close().submit(), DayClosePhase.closed);
      expect(state().result!.variancePaise, -5000);
      expect(state().result!.flagged, isFalse);
      expect(w.api.lastClose!.depositSlipUri, startsWith('gs://'));
      expect(w.api.lastClose!.businessDate, '2026-09-20');
      expect(
        w.api.calls,
        containsAllInOrder(<String>['uploadPhoto', 'closeDay']),
      );
    });

    test('repeat close is blocked (409 day_already_closed)', () async {
      w.camera.enqueue(Uint8List.fromList(<int>[1]));
      close().setCount(50000, 25);
      await close().captureSlip();
      expect(await close().submit(), DayClosePhase.closed);
      expect(await close().submit(), DayClosePhase.alreadyClosed);
    });

    test('offline close keeps the count', () async {
      w.api.offline = true;
      expect(await close().submit(), DayClosePhase.offline);
      close().setCount(1000, 3);
      expect(state().countedPaise, 3000);
    });
  });
}
