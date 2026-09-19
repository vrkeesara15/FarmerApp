import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// NF-002 (farmer app): the last orders, khata, profile and consents are
/// kept in the encrypted database and shown offline with "as of" labels.
void main() {
  late KisanDeps deps;

  setUp(() async {
    deps = KisanDeps()..seedWorld(khataBalance: 420000, marketingConsent: true);
    await deps.signIn();
    deps.kisan.ordersById['o-1'] = <String, Object?>{
      'id': 'o-1',
      'status': 'ready',
      'fulfilment': 'pickup',
      'total_paise': 84000,
      'placed_at': '2026-09-18T05:00:00Z',
      'lines': <Object?>[
        <String, Object?>{
          'sku_id': 'sku-neem',
          'qty': '2',
          'line_total_paise': 84000,
        },
      ],
      'payments': <Object?>[],
      'events': <Object?>[
        <String, Object?>{
          'to_status': 'placed',
          'created_at': '2026-09-18T05:00:00Z',
        },
        <String, Object?>{
          'to_status': 'ready',
          'created_at': '2026-09-18T09:00:00Z',
        },
      ],
    };
    // One online session fills the cache (19-09-2026 10:00 IST).
    final c = deps.container();
    final repo = c.read(kisanRepositoryProvider);
    await repo.refreshProfile();
    await repo.refreshOrders();
    await repo.refreshOrder('o-1');
    await c.read(khataRepositoryProvider).refresh(farmerId);
    c.dispose();
    // Then the phone goes offline for a day.
    deps
      ..kisan.offline = true
      ..khataApi.offline = true
      ..catalogApi.offline = true
      ..connectivity.online = false
      ..now = t0.add(const Duration(days: 1));
  });
  tearDown(() => deps.dispose());

  const asOf = 'Offline. Saved on 19-09-2026 10:00';

  testWidgets('home: crops and dues from the cache', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app());
    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(find.text('Namaste, Lakshmi'), findsOneWidget);
    expect(find.text('You owe ₹4,200.00'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('as-of')));
    expect(find.text(asOf), findsOneWidget);
  });

  testWidgets('orders list and order tracking', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.orders));
    expect(find.byKey(const Key('order-row-o-1')), findsOneWidget);
    expect(find.text('₹840.00'), findsOneWidget);
    expect(find.text(asOf), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('order-row-o-1')));
    expect(
      tester.widget<Text>(find.byKey(const Key('order-status'))).data,
      'Ready',
    );
    await scrollTo(tester, find.byKey(const Key('as-of')));
    expect(find.text(asOf), findsOneWidget);
  });

  testWidgets('khata', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.khata));
    expect(find.text('₹4,200.00'), findsWidgets);
    expect(find.text(asOf), findsOneWidget);
  });

  testWidgets('my crops (profile)', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.crops));
    expect(find.text('Home farm'), findsOneWidget);
    expect(find.text('Cotton'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('as-of')));
    expect(find.text(asOf), findsOneWidget);
  });

  testWidgets('consent settings', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.consentSettings));
    expect(
      tester.widget<Switch>(find.byKey(const Key('consent-marketing'))).value,
      isTrue,
    );
    expect(find.text('Given on 01-09-2026'), findsNWidgets(2));
  });

  test('the cache lives in the app database (encrypted on the phone) under '
      'kisan.cache.*', () async {
    final keys = (await deps.db.select(deps.db.kv).get())
        .map((r) => r.key)
        .where((k) => k.startsWith(KisanCache.prefix))
        .toSet();
    expect(
      keys,
      containsAll(<String>{
        'kisan.cache.profile',
        'kisan.cache.orders',
        'kisan.cache.order.o-1',
      }),
    );
    expect(await deps.db.select(deps.db.khataSnapshots).get(), hasLength(1));
  });
}
