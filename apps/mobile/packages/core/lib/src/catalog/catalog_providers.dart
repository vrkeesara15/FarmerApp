import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, StreamProviderFamily;

import '../db/open_database.dart';
import '../sync/sync_providers.dart';
import 'catalog_api.dart';
import 'catalog_cache.dart';
import 'catalog_models.dart';

/// Catalogue endpoints; the agent app overrides it with [HttpCatalogApi].
final Provider<CatalogApi> catalogApiProvider = Provider<CatalogApi>(
  (ref) => FakeCatalogApi(),
);

/// The offline catalogue cache.
final Provider<CatalogCache> catalogCacheProvider = Provider<CatalogCache>(
  (ref) => CatalogCache(
    ref.watch(appDatabaseProvider),
    ref.watch(catalogApiProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// A50 rows for a query, live.
final StreamProviderFamily<List<CatalogItem>, CatalogQuery>
catalogSearchProvider = StreamProvider.family<List<CatalogItem>, CatalogQuery>(
  (ref, q) => ref.watch(catalogCacheProvider).watchSearch(q),
);

/// A store as known on the device, live.
final StreamProviderFamily<StoreInfo?, String> catalogStoreProvider =
    StreamProvider.family<StoreInfo?, String>(
      (ref, id) => ref.watch(catalogCacheProvider).watchStore(id),
    );

/// The store an order for the farmer goes to (offline answer).
final FutureProviderFamily<String?, String> farmerStoreIdProvider =
    FutureProvider.family<String?, String>(
      (ref, farmerId) =>
          ref.watch(catalogCacheProvider).storeIdForFarmer(farmerId),
    );
