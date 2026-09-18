import 'package:drift/drift.dart';

import '../db/app_database.dart' show SyncedRow;

/// FA-020 order captured by the officer (sync entity `order`).
///
/// Money columns (`subtotal_paise`, `tax_paise`, `total_paise`) are
/// server-owned (FA-025 "server wins for money"): they stay null until the
/// `order` op is applied or the order is pulled. The device's own estimate
/// lives in `estimated_total_paise` and is never sent.
@DataClassName('OrderRow')
@TableIndex(name: 'orders_farmer', columns: <Symbol>{#farmerId})
class Orders extends Table with SyncedRow {
  /// Farmer the order is for.
  TextColumn get farmerId => text().nullable()();

  /// Store the order goes to.
  TextColumn get storeId => text().nullable()();

  /// Server status (`placed` until the server says otherwise).
  TextColumn get status => text().withDefault(const Constant('placed'))();

  /// `pickup` | `delivery`.
  TextColumn get fulfilment => text().withDefault(const Constant('pickup'))();

  /// Payment mode chosen at placing, if any.
  TextColumn get paymentMode => text().nullable()();

  /// Server subtotal (paise).
  IntColumn get subtotalPaise => integer().nullable()();

  /// Server tax (paise).
  IntColumn get taxPaise => integer().nullable()();

  /// Server total (paise).
  IntColumn get totalPaise => integer().nullable()();

  /// Device estimate from cached prices (paise); display only.
  IntColumn get estimatedTotalPaise =>
      integer().withDefault(const Constant(0))();

  /// When the order was placed (server) or captured (device), UTC.
  DateTimeColumn get placedAt => dateTime().nullable()();

  /// GST invoice number once issued.
  TextColumn get invoiceNo => text().nullable()();

  /// Invoice id once the server exposes it (A57 share).
  TextColumn get invoiceId => text().nullable()();

  /// Notes.
  TextColumn get notes => text().nullable()();

  /// JSON list of `{from_status, to_status, created_at}` (ST-005 history).
  TextColumn get events => text().withDefault(const Constant('[]'))();

  /// JSON of server fields this app does not model.
  TextColumn get extra => text().withDefault(const Constant('{}'))();
}

/// Lines of an order: the device's lines until the op is applied, then the
/// server's (ids, prices and totals from the echo / pull).
@DataClassName('OrderLineRow')
@TableIndex(name: 'order_lines_order', columns: <Symbol>{#orderId})
class OrderLines extends Table {
  /// Line id (device id until applied, then the server's).
  TextColumn get id => text()();

  /// Owning order.
  TextColumn get orderId => text()();

  /// SKU.
  TextColumn get skuId => text()();

  /// Quantity.
  RealColumn get qty => real()();

  /// Server unit price (paise).
  IntColumn get unitPricePaise => integer().nullable()();

  /// Server line total incl. tax (paise).
  IntColumn get lineTotalPaise => integer().nullable()();

  /// Device estimate of the unit price (paise).
  IntColumn get estimatedUnitPricePaise =>
      integer().withDefault(const Constant(0))();

  /// Product name at capture (display).
  TextColumn get productName => text().withDefault(const Constant(''))();

  /// Pack label at capture (display).
  TextColumn get packLabel => text().withDefault(const Constant(''))();

  /// DX-007 claim the SKU was recommended under, if any.
  TextColumn get labelClaimId => text().nullable()();

  /// Position in the order.
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
