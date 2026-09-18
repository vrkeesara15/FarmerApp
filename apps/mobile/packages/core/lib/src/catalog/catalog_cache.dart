import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'catalog_api.dart';
import 'catalog_models.dart';

/// Offline catalogue cache (FA-020). Public API (also used by store mode):
///
/// * [refresh] — pull every product page for a store (prices + on hand).
/// * [nearestStore] — the farmer's order store with live availability.
/// * [storeIdForFarmer] — the store an order for the farmer goes to, offline.
/// * [search] / [watchSearch] — name / brand / ingredient + category.
/// * [item] — one SKU with price and stock at a store.
/// * [store] — store name and last refresh time.
///
/// Reads never touch the network, so A50 works offline; the "as of" time
/// of every stock figure and the store's last refresh drive the stale-data
/// indicator ([isStale]).
class CatalogCache {
  /// Creates the cache over [db] and [api].
  CatalogCache(this.db, this.api, {DateTime Function()? clock})
    : _now = clock ?? (() => DateTime.now().toUtc());

  /// The database.
  final AppDatabase db;

  /// The catalogue endpoints.
  final CatalogApi api;

  final DateTime Function() _now;

  /// Data older than this shows the stale indicator.
  static const Duration staleAfter = Duration(hours: 24);

  static String _farmerStoreKey(String farmerId) =>
      'catalog.nearest_store.$farmerId';

  /// True when [refreshedAt] is missing or older than [staleAfter].
  static bool isStale(DateTime? refreshedAt, DateTime now) =>
      refreshedAt == null || now.difference(refreshedAt) > staleAfter;

  /// Pulls every page of `GET /v1/catalog/products?store_id=` and stores
  /// products, SKUs, the store's prices and on-hand stock. Throws
  /// [CatalogUnavailableException] offline (the cache is left as it was).
  /// Returns the number of products stored.
  Future<int> refresh({required String storeId}) async {
    final pages = <Map<String, Object?>>[];
    String? cursor;
    do {
      final page = await api.products(storeId: storeId, cursor: cursor);
      pages.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    final now = _now();
    await db.transaction(() async {
      for (final p in pages) {
        await _writeProduct(p, storeId: storeId, now: now);
      }
      final existing = await store(storeId);
      await db
          .into(db.catalogStores)
          .insertOnConflictUpdate(
            CatalogStoreRow(
              id: storeId,
              code: existing?.code ?? '',
              name: existing?.name ?? '',
              district: existing?.district ?? '',
              catalogRefreshedAt: now,
            ),
          );
    });
    return pages.length;
  }

  Future<void> _writeProduct(
    Map<String, Object?> p, {
    required String storeId,
    required DateTime now,
  }) async {
    final id = '${p['id']}';
    final names = p['names'] is Map
        ? <String, String>{
            for (final e in (p['names']! as Map).entries)
              if (e.value is String) '${e.key}': e.value as String,
          }
        : const <String, String>{};
    final search = <String>[
      (p['name'] as String?) ?? '',
      (p['brand'] as String?) ?? '',
      (p['active_ingredient'] as String?) ?? '',
      ...names.values,
    ].join(' ').toLowerCase();
    await db
        .into(db.catalogProducts)
        .insertOnConflictUpdate(
          CatalogProductRow(
            id: id,
            name: (p['name'] as String?) ?? '',
            brand: (p['brand'] as String?) ?? '',
            ownBrand: p['own_brand'] == true,
            category: CatalogCategory.parse(p['category'] as String?).wire,
            activeIngredient: p['active_ingredient'] as String?,
            formulation: p['formulation'] as String?,
            names: jsonEncode(names),
            imageUri: p['image_uri'] as String?,
            gstRateBp: (p['gst_rate_bp'] as num?)?.toInt() ?? 0,
            active: p['active'] != false,
            searchText: search,
            version: (p['version'] as num?)?.toInt() ?? 0,
            fetchedAt: now,
          ),
        );
    for (final raw in (p['skus'] as List?) ?? const <Object?>[]) {
      if (raw is! Map) continue;
      final s = Map<String, Object?>.from(raw);
      final skuId = '${s['id']}';
      await db
          .into(db.catalogSkus)
          .insertOnConflictUpdate(
            CatalogSkuRow(
              id: skuId,
              productId: id,
              packLabel: (s['pack_label'] as String?) ?? '',
              barcode: s['barcode'] as String?,
              mrpPaise: (s['mrp_paise'] as num?)?.toInt() ?? 0,
              active: s['active'] != false,
              version: (s['version'] as num?)?.toInt() ?? 0,
              fetchedAt: now,
            ),
          );
      final price = s['price_paise'];
      if (price is num) {
        await db
            .into(db.catalogPrices)
            .insertOnConflictUpdate(
              CatalogPriceRow(
                storeId: storeId,
                skuId: skuId,
                pricePaise: price.toInt(),
                fetchedAt: now,
              ),
            );
      }
      final onHand = parseQty(s['stock_qty']);
      if (onHand != null) {
        await _writeStock(storeId, skuId, onHand: onHand, asOf: now);
      }
    }
  }

  Future<void> _writeStock(
    String storeId,
    String skuId, {
    required DateTime asOf,
    double? onHand,
    double? available,
  }) async {
    final existing =
        await (db.select(db.stockSnapshots)
              ..where((t) => t.storeId.equals(storeId) & t.skuId.equals(skuId)))
            .getSingleOrNull();
    // A catalogue page only knows on hand; keep a same-age availability.
    await db
        .into(db.stockSnapshots)
        .insertOnConflictUpdate(
          StockSnapshotRow(
            storeId: storeId,
            skuId: skuId,
            onHand: onHand ?? existing?.onHand,
            available: available,
            asOf: asOf,
          ),
        );
  }

  /// `GET /v1/stores/nearest` for [farmerId] with availability of
  /// [skuIds]; remembers the store for offline use and stores the stock
  /// snapshot. Null when offline or the farmer is unknown to the server.
  Future<NearestStore?> nearestStore(
    String farmerId, {
    List<String> skuIds = const <String>[],
  }) async {
    final NearestStore? nearest;
    try {
      nearest = await api.nearestStore(farmerId: farmerId, skuIds: skuIds);
    } on CatalogUnavailableException {
      return null;
    }
    if (nearest == null) return null;
    final now = _now();
    final s = nearest.store;
    await db.transaction(() async {
      final existing = await store(s.id);
      await db
          .into(db.catalogStores)
          .insertOnConflictUpdate(
            CatalogStoreRow(
              id: s.id,
              code: s.code,
              name: s.name,
              district: s.district,
              catalogRefreshedAt: existing?.catalogRefreshedAt,
            ),
          );
      await db.setValue(_farmerStoreKey(farmerId), s.id);
      for (final skuId in nearest!.available.keys) {
        await _writeStock(
          s.id,
          skuId,
          onHand: nearest.onHand[skuId],
          available: nearest.available[skuId],
          asOf: now,
        );
      }
    });
    return nearest;
  }

  /// The store an order for [farmerId] goes to, without the network: the
  /// last nearest-store answer, else the farmer's village store.
  Future<String?> storeIdForFarmer(String farmerId) async {
    final remembered = await db.getValue(_farmerStoreKey(farmerId));
    if (remembered != null) return remembered;
    final farmer = await (db.select(
      db.farmers,
    )..where((t) => t.id.equals(farmerId))).getSingleOrNull();
    final villageId = farmer?.villageId;
    if (villageId == null) return null;
    final village = await (db.select(
      db.villages,
    )..where((t) => t.id.equals(villageId))).getSingleOrNull();
    return village?.storeId;
  }

  /// A store as known on the device.
  Future<StoreInfo?> store(String id) async {
    final row = await (db.select(
      db.catalogStores,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null
        ? null
        : StoreInfo(
            id: row.id,
            code: row.code,
            name: row.name,
            district: row.district,
            catalogRefreshedAt: row.catalogRefreshedAt?.toUtc(),
          );
  }

  /// Live [store].
  Stream<StoreInfo?> watchStore(String id) =>
      _watch(<TableInfo<Table, Object?>>[db.catalogStores], () => store(id));

  /// Any product cached at all.
  Future<bool> isEmpty() async =>
      (await (db.select(db.catalogProducts)..limit(1)).get()).isEmpty;

  /// One SKU with price and stock at [storeId].
  Future<CatalogItem?> item(String skuId, {String? storeId}) async {
    final sku = await (db.select(
      db.catalogSkus,
    )..where((t) => t.id.equals(skuId))).getSingleOrNull();
    if (sku == null) return null;
    final product = await (db.select(
      db.catalogProducts,
    )..where((t) => t.id.equals(sku.productId))).getSingleOrNull();
    if (product == null) return null;
    final prices = storeId == null
        ? const <String, CatalogPriceRow>{}
        : await _prices(storeId);
    final stock = storeId == null
        ? const <String, StockSnapshotRow>{}
        : await _stock(storeId);
    return _item(product, sku, prices[sku.id], stock[sku.id]);
  }

  Future<Map<String, CatalogPriceRow>> _prices(String storeId) async =>
      <String, CatalogPriceRow>{
        for (final r in await (db.select(
          db.catalogPrices,
        )..where((t) => t.storeId.equals(storeId))).get())
          r.skuId: r,
      };

  Future<Map<String, StockSnapshotRow>> _stock(String storeId) async =>
      <String, StockSnapshotRow>{
        for (final r in await (db.select(
          db.stockSnapshots,
        )..where((t) => t.storeId.equals(storeId))).get())
          r.skuId: r,
      };

  CatalogItem _item(
    CatalogProductRow p,
    CatalogSkuRow s,
    CatalogPriceRow? price,
    StockSnapshotRow? stock,
  ) => CatalogItem(
    productId: p.id,
    skuId: s.id,
    name: p.name,
    names: Map<String, String>.from(jsonDecode(p.names) as Map),
    brand: p.brand,
    ownBrand: p.ownBrand,
    category: CatalogCategory.parse(p.category),
    activeIngredient: p.activeIngredient,
    packLabel: s.packLabel,
    mrpPaise: s.mrpPaise,
    pricePaise: price?.pricePaise ?? s.mrpPaise,
    priceFromStore: price != null,
    gstRateBp: p.gstRateBp,
    imageUri: p.imageUri,
    stock: stock == null
        ? null
        : StockLevel(
            storeId: stock.storeId,
            available: stock.available,
            onHand: stock.onHand,
            asOf: stock.asOf.toUtc(),
          ),
  );

  /// Active SKUs matching [query]: every word of the text must appear in
  /// the name, brand, active ingredient or a localised name; own brand
  /// first, then by name and pack.
  Future<List<CatalogItem>> search(CatalogQuery query) async {
    final words = query.text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
    final products =
        await (db.select(db.catalogProducts)..where((t) {
              var cond = t.active.equals(true);
              if (query.category != null) {
                cond = cond & t.category.equals(query.category!.wire);
              }
              for (final w in words) {
                cond = cond & t.searchText.like('%${_escapeLike(w)}%');
              }
              return cond;
            }))
            .get();
    if (products.isEmpty) return const <CatalogItem>[];
    final byId = <String, CatalogProductRow>{for (final p in products) p.id: p};
    final skus = await (db.select(
      db.catalogSkus,
    )..where((t) => t.active.equals(true) & t.productId.isIn(byId.keys))).get();
    final prices = query.storeId == null
        ? const <String, CatalogPriceRow>{}
        : await _prices(query.storeId!);
    final stock = query.storeId == null
        ? const <String, StockSnapshotRow>{}
        : await _stock(query.storeId!);
    final items = <CatalogItem>[
      for (final s in skus)
        _item(byId[s.productId]!, s, prices[s.id], stock[s.id]),
    ];
    items.sort((a, b) {
      if (a.ownBrand != b.ownBrand) return a.ownBrand ? -1 : 1;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) return byName;
      return a.mrpPaise.compareTo(b.mrpPaise);
    });
    return items;
  }

  static String _escapeLike(String w) =>
      w.replaceAll('%', '').replaceAll('_', '');

  /// [search] now and after every catalogue change.
  Stream<List<CatalogItem>> watchSearch(CatalogQuery query) =>
      _watch(<TableInfo<Table, Object?>>[
        db.catalogProducts,
        db.catalogSkus,
        db.catalogPrices,
        db.stockSnapshots,
      ], () => search(query));

  Stream<T> _watch<T>(
    List<TableInfo<Table, Object?>> tables,
    Future<T> Function() load,
  ) async* {
    yield await load();
    await for (final _ in db.tableUpdates(
      TableUpdateQuery.onAllTables(tables),
    )) {
      yield await load();
    }
  }
}
