import 'catalog_models.dart';
import 'rest_json_client.dart';

/// Catalogue read endpoints (FA-020). The catalogue is not in the sync
/// change feed; the device pulls it with these calls and caches it.
abstract interface class CatalogApi {
  /// `GET /v1/catalog/products?store_id=&cursor=&limit=`.
  Future<CatalogPage> products({
    required String storeId,
    String? cursor,
    int limit = 200,
  });

  /// `GET /v1/stores/nearest?farmer_id=&sku_id=...`; null when the
  /// farmer is unknown to the server (still queued).
  Future<NearestStore?> nearestStore({
    required String farmerId,
    List<String> skuIds = const <String>[],
  });
}

/// Parses a `NearestStoreOut`.
NearestStore parseNearestStore(Map<String, Object?> body) {
  final store = Map<String, Object?>.from(body['store']! as Map);
  final stock = body['stock'] is List
      ? (body['stock']! as List).whereType<Map<Object?, Object?>>()
      : const <Map<Object?, Object?>>[];
  return NearestStore(
    farmerId: '${body['farmer_id']}',
    store: StoreInfo(
      id: '${store['id']}',
      code: (store['code'] as String?) ?? '',
      name: (store['name'] as String?) ?? '',
      district: (store['district'] as String?) ?? '',
    ),
    source: (body['source'] as String?) ?? 'nearest',
    distanceM: (body['distance_m'] as num?)?.toDouble(),
    available: <String, double>{
      for (final s in stock) '${s['sku_id']}': parseQty(s['available']) ?? 0,
    },
    onHand: <String, double>{
      for (final s in stock) '${s['sku_id']}': parseQty(s['on_hand']) ?? 0,
    },
  );
}

/// [CatalogApi] over HTTP.
class HttpCatalogApi implements CatalogApi {
  /// Creates the client.
  HttpCatalogApi(this._rest);

  final RestJsonClient _rest;

  @override
  Future<CatalogPage> products({
    required String storeId,
    String? cursor,
    int limit = 200,
  }) async {
    final r = await _rest.get(
      '/v1/catalog/products',
      query: <String, Object?>{
        'store_id': storeId,
        'cursor': cursor,
        'limit': limit,
      },
    );
    if (!r.ok) throw CatalogUnavailableException(r.status);
    return CatalogPage(<Map<String, Object?>>[
      for (final i in (r.body['items'] as List?) ?? const <Object?>[])
        if (i is Map) Map<String, Object?>.from(i),
    ], r.body['next_cursor'] as String?);
  }

  @override
  Future<NearestStore?> nearestStore({
    required String farmerId,
    List<String> skuIds = const <String>[],
  }) async {
    final r = await _rest.get(
      '/v1/stores/nearest',
      query: <String, Object?>{
        'farmer_id': farmerId,
        if (skuIds.isNotEmpty) 'sku_id': skuIds.take(50).toList(),
      },
    );
    if (r.status == 404) return null;
    if (!r.ok) throw CatalogUnavailableException(r.status);
    return parseNearestStore(r.body);
  }
}

/// In-memory catalogue server for tests and previews.
class FakeCatalogApi implements CatalogApi {
  /// Creates the fake.
  FakeCatalogApi({this.pageSize = 2});

  /// Products per page.
  int pageSize;

  /// Every call throws [CatalogUnavailableException] while true.
  bool offline = false;

  /// `ProductWithSkusOut` rows per store id (`price_paise`, `stock_qty`
  /// already resolved for that store).
  final Map<String, List<Map<String, Object?>>> productsByStore =
      <String, List<Map<String, Object?>>>{};

  /// Nearest store per farmer id.
  final Map<String, StoreInfo> nearestByFarmer = <String, StoreInfo>{};

  /// Available units per `storeId/skuId`.
  final Map<String, double> available = <String, double>{};

  /// Calls made, e.g. `products:store-1:null`, `nearest:f-1`.
  final List<String> calls = <String>[];

  @override
  Future<CatalogPage> products({
    required String storeId,
    String? cursor,
    int limit = 200,
  }) async {
    calls.add('products:$storeId:$cursor');
    if (offline) throw const CatalogUnavailableException();
    final all = productsByStore[storeId] ?? const <Map<String, Object?>>[];
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + pageSize).clamp(0, all.length);
    return CatalogPage(
      all.sublist(start, end),
      end < all.length ? '$end' : null,
    );
  }

  @override
  Future<NearestStore?> nearestStore({
    required String farmerId,
    List<String> skuIds = const <String>[],
  }) async {
    calls.add('nearest:$farmerId');
    if (offline) throw const CatalogUnavailableException();
    final store = nearestByFarmer[farmerId];
    if (store == null) return null;
    return NearestStore(
      farmerId: farmerId,
      store: store,
      source: 'village',
      available: <String, double>{
        for (final id in skuIds) id: available['${store.id}/$id'] ?? 0,
      },
      onHand: <String, double>{
        for (final id in skuIds) id: available['${store.id}/$id'] ?? 0,
      },
    );
  }
}
