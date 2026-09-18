import 'package:drift/drift.dart';

/// FA-020 offline catalogue: one row per product (`GET /v1/catalog/products`).
@DataClassName('CatalogProductRow')
class CatalogProducts extends Table {
  /// Server id.
  TextColumn get id => text()();

  /// Product name.
  TextColumn get name => text()();

  /// Brand.
  TextColumn get brand => text().withDefault(const Constant(''))();

  /// Tenant's own brand (OwnBrandBadge).
  BoolColumn get ownBrand => boolean().withDefault(const Constant(false))();

  /// `seed` | `fertiliser` | `pesticide` | ... (`ProductCategory`).
  TextColumn get category => text().withDefault(const Constant('other'))();

  /// Active ingredient (search).
  TextColumn get activeIngredient => text().nullable()();

  /// Formulation.
  TextColumn get formulation => text().nullable()();

  /// JSON `{lang: name}` of localised names.
  TextColumn get names => text().withDefault(const Constant('{}'))();

  /// Image URI.
  TextColumn get imageUri => text().nullable()();

  /// GST rate in basis points (estimates only; the server computes tax).
  IntColumn get gstRateBp => integer().withDefault(const Constant(0))();

  /// Active in the catalogue.
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  /// Lower-cased name, brand, ingredient and localised names (search).
  TextColumn get searchText => text().withDefault(const Constant(''))();

  /// Server row version.
  IntColumn get version => integer().withDefault(const Constant(0))();

  /// When the row was pulled (UTC).
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Pack sizes (SKUs) of a product.
@DataClassName('CatalogSkuRow')
@TableIndex(name: 'catalog_skus_product', columns: <Symbol>{#productId})
class CatalogSkus extends Table {
  /// Server id.
  TextColumn get id => text()();

  /// Owning product.
  TextColumn get productId => text()();

  /// Pack label, e.g. `250 ml`.
  TextColumn get packLabel => text().withDefault(const Constant(''))();

  /// Barcode.
  TextColumn get barcode => text().nullable()();

  /// MRP in paise.
  IntColumn get mrpPaise => integer().withDefault(const Constant(0))();

  /// Active.
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  /// Server row version.
  IntColumn get version => integer().withDefault(const Constant(0))();

  /// When the row was pulled (UTC).
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Selling price of a SKU at a store (`price_paise` for `store_id`). Shown
/// as an estimate: the server recomputes every order (SEC-023).
@DataClassName('CatalogPriceRow')
class CatalogPrices extends Table {
  /// Store.
  TextColumn get storeId => text()();

  /// SKU.
  TextColumn get skuId => text()();

  /// Price in paise.
  IntColumn get pricePaise => integer()();

  /// When the price was pulled (UTC).
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{storeId, skuId};
}

/// Stock of a SKU at a store as last seen: `available` from
/// `GET /v1/stores/nearest` (on hand − reserved), else on hand from the
/// catalogue page, with the time it was true.
@DataClassName('StockSnapshotRow')
class StockSnapshots extends Table {
  /// Store.
  TextColumn get storeId => text()();

  /// SKU.
  TextColumn get skuId => text()();

  /// On hand (ledger sum), if known.
  RealColumn get onHand => real().nullable()();

  /// Available to order (on hand − reserved), if known.
  RealColumn get available => real().nullable()();

  /// When the numbers were true (UTC).
  DateTimeColumn get asOf => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{storeId, skuId};
}

/// Stores the device has seen (nearest-store answers).
@DataClassName('CatalogStoreRow')
class CatalogStores extends Table {
  /// Server id.
  TextColumn get id => text()();

  /// Store code.
  TextColumn get code => text().withDefault(const Constant(''))();

  /// Store name.
  TextColumn get name => text().withDefault(const Constant(''))();

  /// District.
  TextColumn get district => text().withDefault(const Constant(''))();

  /// Last complete catalogue refresh for this store (UTC).
  DateTimeColumn get catalogRefreshedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
