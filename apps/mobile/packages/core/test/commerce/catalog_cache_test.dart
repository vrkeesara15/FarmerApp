import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'commerce_harness.dart';

/// FA-020 offline catalogue cache: pulled page by page for a store,
/// searched offline by name / brand / ingredient / localised name, filtered
/// by category, prices from the store (MRP fallback), stock with its "as
/// of" time, the nearest store remembered per farmer.
void main() {
  late AppDatabase db;
  late FakeCatalogApi api;
  late DateTime now;
  late CatalogCache cache;

  setUp(() {
    db = openInMemoryDatabase();
    api = sampleCatalogApi();
    now = t0;
    cache = CatalogCache(db, api, clock: () => now);
  });

  tearDown(() => db.close());

  Future<List<String>> skus(CatalogQuery q) async => <String>[
    for (final i in await cache.search(q)) i.skuId,
  ];

  test(
    'refresh pulls every page and stores products, prices and stock',
    () async {
      expect(await cache.refresh(storeId: storeId), 4);
      // Four products at page size 2 → two calls, the second from the cursor.
      expect(api.calls, <String>[
        'products:store-1:null',
        'products:store-1:2',
      ]);
      final store = await cache.store(storeId);
      expect(store!.catalogRefreshedAt, t0);
      expect(await cache.isEmpty(), isFalse);
    },
  );

  test(
    'search works offline by name, brand, ingredient and local name',
    () async {
      await cache.refresh(storeId: storeId);
      api.offline = true;
      const q = CatalogQuery(storeId: storeId);
      expect(await skus(q.copy(text: 'coragen')), <String>['sku-cora-150']);
      expect(await skus(q.copy(text: 'fmc')), <String>['sku-cora-150']);
      expect(await skus(q.copy(text: 'chlorantraniliprole')), <String>[
        'sku-cora-150',
      ]);
      expect(await skus(q.copy(text: 'కొరాజెన్')), <String>['sku-cora-150']);
      expect(await skus(q.copy(text: 'neem azadirachtin')), <String>[
        'sku-neem-500',
        'sku-neem-1l',
      ]);
      expect(await skus(q.copy(text: 'nothing like this')), isEmpty);
    },
  );

  test('category filter and own brand first', () async {
    await cache.refresh(storeId: storeId);
    expect(
      await skus(
        const CatalogQuery(
          storeId: storeId,
          category: CatalogCategory.fertiliser,
        ),
      ),
      <String>['sku-dap-50'],
    );
    final all = await cache.search(const CatalogQuery(storeId: storeId));
    expect(all.first.ownBrand, isTrue);
    expect(all.map((i) => i.skuId), <String>[
      'sku-neem-500',
      'sku-neem-1l',
      'sku-seed-450',
      'sku-cora-150',
      'sku-dap-50',
    ]);
  });

  test('store price wins over the MRP; stock carries its as-of time', () async {
    await cache.refresh(storeId: storeId);
    final cora = (await cache.item('sku-cora-150', storeId: storeId))!;
    expect(cora.pricePaise, 118000);
    expect(cora.priceFromStore, isTrue);
    expect(cora.stock!.wholeUnits, 12);
    expect(cora.stock!.asOf, t0);
    final out = (await cache.item('sku-neem-1l', storeId: storeId))!;
    expect(out.stock!.wholeUnits, 0);
    // Another store has no prices cached: MRP, no stock.
    final elsewhere = (await cache.item('sku-cora-150', storeId: 'store-9'))!;
    expect(elsewhere.pricePaise, 125000);
    expect(elsewhere.priceFromStore, isFalse);
    expect(elsewhere.stock, isNull);
  });

  test(
    'nearest store: availability snapshot and the farmer remembered',
    () async {
      await cache.refresh(storeId: storeId);
      api.available['$storeId/sku-cora-150'] = 7;
      now = t0.add(const Duration(minutes: 5));
      final nearest = await cache.nearestStore(
        'f-1',
        skuIds: <String>['sku-cora-150'],
      );
      expect(nearest!.store.name, 'Kondapur Agri Store');
      final cora = (await cache.item('sku-cora-150', storeId: storeId))!;
      expect(cora.stock!.available, 7);
      expect(cora.stock!.onHand, 7);
      expect(cora.stock!.asOf, now);
      expect((await cache.store(storeId))!.name, 'Kondapur Agri Store');
      // Offline afterwards: the remembered store answers.
      api.offline = true;
      expect(await cache.nearestStore('f-1'), isNull);
      expect(await cache.storeIdForFarmer('f-1'), storeId);
    },
  );

  test('without a nearest answer the village store is used', () async {
    await LocalEntities(db).writeRef(
      SyncEntities.village,
      'village-1',
      <String, Object?>{'name': 'Kondapur', 'store_id': 'store-7'},
      version: 1,
      now: t0,
    );
    await LocalEntities(db).write(
      SyncEntities.farmer,
      'f-2',
      <String, Object?>{'name': 'Lakshmi', 'village_id': 'village-1'},
      version: 1,
      dirty: false,
      now: t0,
    );
    expect(await cache.storeIdForFarmer('f-2'), 'store-7');
    expect(await cache.storeIdForFarmer('unknown'), isNull);
  });

  test(
    'offline refresh throws and keeps the cache; stale after 24 h',
    () async {
      await cache.refresh(storeId: storeId);
      api.offline = true;
      await expectLater(
        cache.refresh(storeId: storeId),
        throwsA(isA<CatalogUnavailableException>()),
      );
      expect(await skus(const CatalogQuery(storeId: storeId)), hasLength(5));
      final refreshed = (await cache.store(storeId))!.catalogRefreshedAt;
      expect(
        CatalogCache.isStale(refreshed, t0.add(const Duration(hours: 23))),
        isFalse,
      );
      expect(
        CatalogCache.isStale(refreshed, t0.add(const Duration(hours: 25))),
        isTrue,
      );
      expect(CatalogCache.isStale(null, t0), isTrue);
    },
  );

  test('watchSearch emits again after a refresh', () async {
    final done = expectLater(
      cache.watchSearch(const CatalogQuery()).map((items) => items.length),
      emitsInOrder(<Object>[0, emitsThrough(5)]),
    );
    await Future<void>.delayed(Duration.zero);
    await cache.refresh(storeId: storeId);
    await done;
  });
}

extension on CatalogQuery {
  CatalogQuery copy({String? text}) => CatalogQuery(
    text: text ?? this.text,
    category: category,
    storeId: storeId,
  );
}
