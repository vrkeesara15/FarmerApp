import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-012 F45: mandi prices for the farmer's crops.
///
/// The acceptance criterion is *prices shown with date and source*, so both
/// are asserted on the screen, together with the "indicative" note, the
/// offline "as of" and the entry point next to My crops (F40).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('model', () {
    test('parses the wire shape and keeps paise as integers', () {
      final prices = MandiPrices.fromJson(mandiPricesBody());
      expect(prices.asOf, DateTime.utc(2026, 9, 20));
      expect(prices.district, 'Medak');
      expect(prices.indicativeNoteKey, 'mandi.indicative');
      final crop = prices.crops.single;
      expect(crop.cropCode, 'paddy');
      expect(crop.name('te'), 'వరి');
      expect(crop.name('kn'), 'Paddy', reason: 'falls back to English');
      expect(crop.sourceName, 'Agmarknet (data.gov.in)');
      expect(crop.priceDate, DateTime.utc(2026, 9, 20));
      expect(crop.quotes.first.modalPricePaise, 215050);
      expect(crop.quotes.first.market, 'Medak Main Yard');
    });

    test('a round trip through the cache keeps every field', () {
      final prices = MandiPrices.fromJson(mandiPricesBody());
      expect(MandiPrices.fromJson(prices.toJson()), prices);
      expect(
        MandiPrices.fromJson(prices.toJson()).crops.single.sourceName,
        'Agmarknet (data.gov.in)',
      );
    });

    test('a crop with no price is kept but reports empty', () {
      final body = mandiPricesBody();
      (body['crops']! as List<Object?>).add(<String, Object?>{
        'crop_id': 'crop-cotton',
        'crop_code': 'cotton',
        'crop_name': 'Cotton',
        'price_date': null,
        'source_name': null,
        'quotes': <Object?>[],
      });
      final prices = MandiPrices.fromJson(body);
      expect(prices.crops.length, 2);
      expect(prices.priced.length, 1);
      expect(prices.crops.last.isEmpty, isTrue);
    });
  });

  group('repository', () {
    late KisanDeps deps;

    setUp(() async {
      deps = KisanDeps()..seedWorld();
      deps.seedMarket();
      await deps.signIn();
    });
    tearDown(() => deps.dispose());

    test('caches the prices with the time they were fetched', () async {
      final c = deps.container();
      final repo = c.read(marketRepositoryProvider);
      expect(await repo.refreshPrices(), isTrue);
      final cached = await repo.watchPrices().first;
      expect(cached, isNotNull);
      expect(cached!.asOf, deps.now);
      expect(cached.value.asOf, DateTime.utc(2026, 9, 20));
      c.dispose();
    });

    test('an offline refresh leaves the cache alone', () async {
      final c = deps.container();
      final repo = c.read(marketRepositoryProvider);
      await repo.refreshPrices();
      deps.market.offline = true;
      expect(await repo.refreshPrices(), isFalse);
      final cached = await repo.watchPrices().first;
      expect(cached!.value.crops.single.quotes.length, 2);
      c.dispose();
    });
  });

  group('F45 screen', () {
    late KisanDeps deps;

    setUp(() async {
      deps = KisanDeps()..seedWorld();
      deps.seedMarket();
      deps.seedAdvisory();
      await deps.signIn();
      await deps.primeAdvisory();
      await deps.primeMarket();
    });
    tearDown(() => deps.dispose());

    testWidgets('shows the price with its date and its source', (tester) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.mandiPrices));

      expect(find.byKey(const Key('mandi-crop-paddy')), findsOneWidget);
      expect(find.text('Paddy'), findsWidgets);
      // FM-012 acceptance: the date and the source travel with the price.
      expect(find.text('Price of 20-09-2026'), findsOneWidget);
      expect(find.text('From Agmarknet (data.gov.in)'), findsOneWidget);
      expect(find.text('Medak Main Yard'), findsOneWidget);
      expect(find.text('Sangareddy Yard'), findsOneWidget);
      expect(find.text('per quintal'), findsWidgets);
      expect(find.text('₹2,150.50'), findsOneWidget);

      // ...and the "these are indicative" note, plus the offline "as of".
      await scrollTo(tester, find.byKey(const Key('mandi-indicative')));
      expect(find.byKey(const Key('mandi-indicative')), findsOneWidget);
      expect(find.byKey(const Key('as-of')), findsOneWidget);
    });

    testWidgets('an empty cache shows the empty state, not a blank screen', (
      tester,
    ) async {
      final empty = KisanDeps()..seedWorld();
      await empty.signIn();
      usePhoneSurface(tester);
      await pumpApp(tester, empty.app(initialLocation: AppRoutes.mandiPrices));
      expect(find.text('No prices yet'), findsOneWidget);
      await empty.dispose();
    });

    testWidgets('the cached prices still show offline', (tester) async {
      deps.connectivity.online = false;
      deps.market.offline = true;
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.mandiPrices));

      expect(find.text('From Agmarknet (data.gov.in)'), findsOneWidget);
      expect(find.byKey(const Key('as-of')), findsOneWidget);
    });

    testWidgets('My crops opens the prices', (tester) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.crops));
      await scrollTo(tester, find.byKey(const Key('crops-mandi')));
      await tapIt(tester, find.byKey(const Key('crops-mandi')));
      expect(find.byKey(const Key('mandi-crop-paddy')), findsOneWidget);
    });
  });
}
