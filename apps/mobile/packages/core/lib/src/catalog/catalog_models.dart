import 'package:flutter/foundation.dart' show immutable;

/// Product categories of the catalogue (`ProductCategory`), in filter order.
enum CatalogCategory {
  /// Seeds.
  seed,

  /// Fertilisers.
  fertiliser,

  /// Insecticides / pesticides.
  pesticide,

  /// Fungicides.
  fungicide,

  /// Herbicides.
  herbicide,

  /// Growth promoters.
  growth,

  /// Tools and equipment.
  tool,

  /// Anything else.
  other;

  /// Wire value.
  String get wire => name;

  /// Parses a wire value (unknown values are [other]).
  static CatalogCategory parse(String? value) =>
      CatalogCategory.values.where((c) => c.wire == value).firstOrNull ??
      CatalogCategory.other;
}

/// Stock of one SKU at one store as last seen.
@immutable
class StockLevel {
  /// Creates the level.
  const StockLevel({
    required this.storeId,
    required this.asOf,
    this.available,
    this.onHand,
  });

  /// Store.
  final String storeId;

  /// Available to order (on hand − reserved), when known.
  final double? available;

  /// On hand, when known.
  final double? onHand;

  /// When it was true (UTC).
  final DateTime asOf;

  /// Best figure to show: available, else on hand.
  double? get units => available ?? onHand;

  /// Whole units for display (floored, never negative).
  int? get wholeUnits {
    final u = units;
    if (u == null) return null;
    return u <= 0 ? 0 : u.floor();
  }
}

/// A sellable catalogue line: product + one pack size + the store price and
/// stock snapshot (FA-020 A50 row / cart source).
@immutable
class CatalogItem {
  /// Creates the item.
  const CatalogItem({
    required this.productId,
    required this.skuId,
    required this.name,
    required this.brand,
    required this.ownBrand,
    required this.category,
    required this.packLabel,
    required this.mrpPaise,
    required this.pricePaise,
    this.activeIngredient,
    this.names = const <String, String>{},
    this.imageUri,
    this.gstRateBp = 0,
    this.priceFromStore = false,
    this.stock,
  });

  /// Product id.
  final String productId;

  /// SKU id.
  final String skuId;

  /// Product name.
  final String name;

  /// Localised names by language code.
  final Map<String, String> names;

  /// Brand.
  final String brand;

  /// Own brand (OwnBrandBadge).
  final bool ownBrand;

  /// Category.
  final CatalogCategory category;

  /// Active ingredient.
  final String? activeIngredient;

  /// Pack label.
  final String packLabel;

  /// MRP (paise).
  final int mrpPaise;

  /// Estimated selling price (paise): the store price, else the MRP.
  final int pricePaise;

  /// [pricePaise] came from the store's price list.
  final bool priceFromStore;

  /// GST rate (basis points).
  final int gstRateBp;

  /// Image.
  final String? imageUri;

  /// Stock at the store, if known.
  final StockLevel? stock;

  /// The name in [languageCode], else the default name.
  String nameIn(String languageCode) => names[languageCode] ?? name;

  @override
  bool operator ==(Object other) =>
      other is CatalogItem &&
      other.skuId == skuId &&
      other.pricePaise == pricePaise &&
      other.stock?.units == stock?.units &&
      other.stock?.asOf == stock?.asOf;

  @override
  int get hashCode => Object.hash(skuId, pricePaise, stock?.units);
}

/// What A50 asks the cache for.
@immutable
class CatalogQuery {
  /// Creates the query.
  const CatalogQuery({this.text = '', this.category, this.storeId});

  /// Free text: name, brand, active ingredient (all words must match).
  final String text;

  /// Category filter.
  final CatalogCategory? category;

  /// Store whose prices and stock to attach.
  final String? storeId;

  @override
  bool operator ==(Object other) =>
      other is CatalogQuery &&
      other.text == text &&
      other.category == category &&
      other.storeId == storeId;

  @override
  int get hashCode => Object.hash(text, category, storeId);
}

/// A store as the device knows it.
@immutable
class StoreInfo {
  /// Creates the store.
  const StoreInfo({
    required this.id,
    this.code = '',
    this.name = '',
    this.district = '',
    this.catalogRefreshedAt,
  });

  /// Server id.
  final String id;

  /// Code.
  final String code;

  /// Name.
  final String name;

  /// District.
  final String district;

  /// Last full catalogue refresh for the store (UTC).
  final DateTime? catalogRefreshedAt;
}

/// `GET /v1/stores/nearest` answer.
@immutable
class NearestStore {
  /// Creates the answer.
  const NearestStore({
    required this.farmerId,
    required this.store,
    required this.source,
    this.distanceM,
    this.available = const <String, double>{},
    this.onHand = const <String, double>{},
  });

  /// Farmer asked about.
  final String farmerId;

  /// The store orders go to.
  final StoreInfo store;

  /// `village` or `nearest`.
  final String source;

  /// Village centre to store (m).
  final double? distanceM;

  /// Available units per SKU asked for.
  final Map<String, double> available;

  /// On-hand units per SKU asked for.
  final Map<String, double> onHand;
}

/// One page of `GET /v1/catalog/products` (raw `ProductWithSkusOut` rows).
@immutable
class CatalogPage {
  /// Creates the page.
  const CatalogPage(this.items, this.nextCursor);

  /// Products with SKUs, prices and stock.
  final List<Map<String, Object?>> items;

  /// Next cursor, null on the last page.
  final String? nextCursor;
}

/// The catalogue could not be reached (offline, 5xx, no session).
class CatalogUnavailableException implements Exception {
  /// Creates the exception.
  const CatalogUnavailableException([this.status = 0]);

  /// HTTP status (0 = no answer).
  final int status;

  @override
  String toString() => 'CatalogUnavailableException($status)';
}

/// Parses a decimal quantity sent as a string (or number).
double? parseQty(Object? v) => switch (v) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};
