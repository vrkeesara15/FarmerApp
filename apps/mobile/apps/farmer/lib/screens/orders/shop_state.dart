import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The farmer's store (nearest / village store) and a catalogue refresh
/// for it; offline it is the last answer the phone remembers.
final FutureProvider<String?> kisanStoreIdProvider = FutureProvider<String?>((
  ref,
) async {
  final farmerId = await ref.watch(kisanFarmerIdProvider.future);
  if (farmerId == null) return null;
  final cache = ref.watch(catalogCacheProvider);
  final nearest = await cache.nearestStore(farmerId);
  final storeId = nearest?.store.id ?? await cache.storeIdForFarmer(farmerId);
  if (storeId != null) {
    try {
      await cache.refresh(storeId: storeId);
    } on CatalogUnavailableException {
      // Offline: the cached catalogue stays.
    }
    ref.read(cartProvider.notifier).start(farmerId, storeId: storeId);
  }
  return storeId;
});

/// Localised label of a catalogue category.
String categoryLabel(CoreLocalizations l10n, CatalogCategory c) => switch (c) {
  CatalogCategory.seed => l10n.catalogCategorySeed,
  CatalogCategory.fertiliser => l10n.catalogCategoryFertiliser,
  CatalogCategory.pesticide => l10n.catalogCategoryPesticide,
  CatalogCategory.fungicide => l10n.catalogCategoryFungicide,
  CatalogCategory.herbicide => l10n.catalogCategoryHerbicide,
  CatalogCategory.growth => l10n.catalogCategoryGrowth,
  CatalogCategory.tool => l10n.catalogCategoryTool,
  CatalogCategory.other => l10n.catalogCategoryOther,
};

/// Pictogram of a catalogue category.
IconData categoryIcon(CatalogCategory c) => switch (c) {
  CatalogCategory.seed => Icons.grass,
  CatalogCategory.fertiliser => Icons.science_outlined,
  CatalogCategory.pesticide => Icons.bug_report_outlined,
  CatalogCategory.fungicide => Icons.coronavirus_outlined,
  CatalogCategory.herbicide => Icons.content_cut,
  CatalogCategory.growth => Icons.trending_up,
  CatalogCategory.tool => Icons.handyman_outlined,
  CatalogCategory.other => Icons.category_outlined,
};

/// Localised label of an order status on F33 / F34.
String orderStatusLabel(CoreLocalizations l10n, String status) =>
    switch (status) {
      'packed' => l10n.orderStatusPacked,
      'ready' => l10n.orderStatusReady,
      'handed_over' || 'delivered' => l10n.kisanOrderCollected,
      'cancelled' => l10n.orderStatusCancelled,
      _ => l10n.orderStatusPlaced,
    };
