import '../catalog/catalog_cache.dart';
import '../catalog/catalog_models.dart';
import '../widgets/treatment_card.dart';
import 'diagnosis_models.dart';

/// The cart item for a recommended [option] (FM-006 order, A43 "Create
/// order for farmer"): the cached catalogue SKU at [storeId] when the phone
/// has it (tax rate, stock), else one built from the recommendation (the
/// server prices the order either way). The label claim travels on the
/// cart line (`CartNotifier.addRecommended`).
Future<CatalogItem> catalogItemForOption(
  CatalogCache cache,
  ProductOption option, {
  String? storeId,
}) async {
  final cached = await cache.item(option.skuId, storeId: storeId);
  if (cached != null) return cached;
  return CatalogItem(
    productId: option.productId,
    skuId: option.skuId,
    name: option.productName,
    brand: option.brand,
    ownBrand: option.ownBrand,
    category: option.kind == TreatmentKind.organic
        ? CatalogCategory.other
        : CatalogCategory.pesticide,
    packLabel: option.packLabel,
    mrpPaise: option.mrpPaise ?? option.pricePaise,
    pricePaise: option.pricePaise,
    activeIngredient: option.activeIngredient,
    priceFromStore: true,
  );
}
