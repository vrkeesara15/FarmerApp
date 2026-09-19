/// Store mode (ST-001 .. ST-007) models: the tablet counter's view of the
/// catalogue, stock, POS sales, GST invoices, the order queue, credit
/// approvals and the day close. Money is integer paise throughout.
library;

import 'package:flutter/foundation.dart' show immutable, listEquals;

/// Parses an API decimal (`"12.000"`, `12`, `12.5`) to a double.
double parseStoreQty(Object? v) => switch (v) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s) ?? 0,
  _ => 0,
};

/// Formats a quantity without trailing zeros (`12.0` -> `12`, `2.50` -> `2.5`).
String formatQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  var s = q.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

DateTime? _date(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

int _int(Object? v) => v is num ? v.toInt() : 0;

String? _str(Object? v) => v is String ? v : null;

List<Map<String, Object?>> _maps(Object? v) => v is List
    ? <Map<String, Object?>>[
        for (final e in v)
          if (e is Map) Map<String, Object?>.from(e),
      ]
    : const <Map<String, Object?>>[];

/// A store the user can work in (`/v1/catalog/stores`).
@immutable
class StoreBrief {
  /// Creates the store.
  const StoreBrief({required this.id, required this.code, required this.name});

  /// Parses `StoreBriefOut`.
  factory StoreBrief.fromJson(Map<String, Object?> j) => StoreBrief(
    id: j['id']! as String,
    code: (j['code'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
  );

  /// Store id.
  final String id;

  /// Short code (`KND`).
  final String code;

  /// Display name.
  final String name;
}

/// A store stock can be sent to (`GET /v1/stock/transfer-destinations`):
/// the other stores of the origin's cluster for a store manager, nearest
/// first.
@immutable
class TransferDestination {
  /// Creates the destination.
  const TransferDestination({
    required this.id,
    required this.code,
    required this.name,
    this.district = '',
    this.distanceM,
  });

  /// Parses one `items[]` entry.
  factory TransferDestination.fromJson(Map<String, Object?> j) =>
      TransferDestination(
        id: j['id']! as String,
        code: (j['code'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        district: (j['district'] as String?) ?? '',
        distanceM: (j['distance_m'] as num?)?.toDouble(),
      );

  /// Store id.
  final String id;

  /// Short code.
  final String code;

  /// Display name.
  final String name;

  /// District.
  final String district;

  /// Straight-line metres from the origin store; null without an origin.
  final double? distanceM;
}

/// One sellable SKU with its product and the store's price.
@immutable
class StoreItem {
  /// Creates the item.
  const StoreItem({
    required this.skuId,
    required this.productId,
    required this.name,
    required this.packLabel,
    required this.pricePaise,
    this.brand = '',
    this.ownBrand = false,
    this.category = 'other',
    this.hsn,
    this.gstRateBp = 0,
    this.barcode,
    this.mrpPaise = 0,
    this.stockQty,
  });

  /// From a `ProductWithSkusOut` and one of its `SkuOut`s.
  factory StoreItem.fromProductSku(
    Map<String, Object?> product,
    Map<String, Object?> sku,
  ) => StoreItem(
    skuId: sku['id']! as String,
    productId: product['id']! as String,
    name: (product['name'] as String?) ?? '',
    brand: (product['brand'] as String?) ?? '',
    ownBrand: product['own_brand'] == true,
    category: (product['category'] as String?) ?? 'other',
    hsn: _str(product['hsn']),
    gstRateBp: _int(product['gst_rate_bp']),
    packLabel: (sku['pack_label'] as String?) ?? '',
    barcode: _str(sku['barcode']),
    mrpPaise: _int(sku['mrp_paise']),
    pricePaise: _int(sku['price_paise'] ?? sku['mrp_paise']),
    stockQty: sku['stock_qty'] == null ? null : parseStoreQty(sku['stock_qty']),
  );

  /// From `BarcodeLookupOut` (SKU with its product nested).
  factory StoreItem.fromBarcode(Map<String, Object?> j) =>
      StoreItem.fromProductSku(
        Map<String, Object?>.from(j['product']! as Map),
        j,
      );

  /// SKU id.
  final String skuId;

  /// Product id.
  final String productId;

  /// Product name.
  final String name;

  /// Brand.
  final String brand;

  /// FCC own brand.
  final bool ownBrand;

  /// Product category (`seed`, `fertiliser`, ...).
  final String category;

  /// HSN code.
  final String? hsn;

  /// GST rate in basis points (1800 = 18 %).
  final int gstRateBp;

  /// Pack label (`250 ml`).
  final String packLabel;

  /// Barcode on the pack.
  final String? barcode;

  /// MRP in paise.
  final int mrpPaise;

  /// Store price (pre-tax) in paise.
  final int pricePaise;

  /// Units in stock at the store, when asked for.
  final double? stockQty;
}

/// A stock batch of a store with its reservations (`StockBatchOut`).
@immutable
class StockBatch {
  /// Creates the batch.
  const StockBatch({
    required this.id,
    required this.skuId,
    required this.batchNo,
    required this.onHand,
    required this.reserved,
    required this.available,
    this.expiry,
    this.daysToExpiry,
    this.costPaise = 0,
  });

  /// Parses `StockBatchOut`.
  factory StockBatch.fromJson(Map<String, Object?> j) {
    final onHand = parseStoreQty(j['on_hand'] ?? j['qty']);
    final reserved = parseStoreQty(j['reserved']);
    return StockBatch(
      id: j['id']! as String,
      skuId: j['sku_id']! as String,
      batchNo: (j['batch_no'] as String?) ?? '',
      expiry: _date(j['expiry']),
      onHand: onHand,
      reserved: reserved,
      available: j['available'] == null
          ? onHand - reserved
          : parseStoreQty(j['available']),
      daysToExpiry: (j['days_to_expiry'] as num?)?.toInt(),
      costPaise: _int(j['cost_paise']),
    );
  }

  /// Batch id.
  final String id;

  /// SKU id.
  final String skuId;

  /// Batch number printed on the pack.
  final String batchNo;

  /// Expiry date, if any.
  final DateTime? expiry;

  /// On hand.
  final double onHand;

  /// Reserved by open orders.
  final double reserved;

  /// On hand minus reserved.
  final double available;

  /// Days until expiry (negative = expired).
  final int? daysToExpiry;

  /// Unit cost in paise.
  final int costPaise;
}

/// Expiry band used for the S06 highlight (ST-004 thresholds 30 / 60 days).
enum ExpiryBand {
  /// Expired already.
  expired,

  /// Expires within 30 days.
  within30,

  /// Expires within 60 days.
  within60,

  /// Later, or no expiry.
  ok,
}

/// The band for a batch with [daysToExpiry] days left.
ExpiryBand expiryBandFor(int? daysToExpiry) {
  if (daysToExpiry == null) return ExpiryBand.ok;
  if (daysToExpiry < 0) return ExpiryBand.expired;
  if (daysToExpiry <= 30) return ExpiryBand.within30;
  if (daysToExpiry <= 60) return ExpiryBand.within60;
  return ExpiryBand.ok;
}

/// Available units at or below which a SKU counts as low stock on S01 / S06
/// (no reorder level exists in the product master yet).
const double lowStockThreshold = 10;

/// S06 row: one SKU with its batches (FEFO order).
@immutable
class StockRow {
  /// Creates the row.
  const StockRow({required this.skuId, required this.batches, this.item});

  /// SKU id.
  final String skuId;

  /// Catalogue data, when the SKU is in the catalogue.
  final StoreItem? item;

  /// Batches, earliest expiry first.
  final List<StockBatch> batches;

  /// Units on hand.
  double get onHand => batches.fold(0, (a, b) => a + b.onHand);

  /// Units reserved.
  double get reserved => batches.fold(0, (a, b) => a + b.reserved);

  /// Units available.
  double get available => batches.fold(0, (a, b) => a + b.available);

  /// Low stock ([lowStockThreshold]).
  bool get isLow => available <= lowStockThreshold;

  /// The worst expiry band among batches with stock.
  ExpiryBand get expiryBand {
    var worst = ExpiryBand.ok;
    for (final b in batches) {
      if (b.onHand <= 0) continue;
      final band = expiryBandFor(b.daysToExpiry);
      if (band.index < worst.index) worst = band;
    }
    return worst;
  }

  /// Any batch with stock expiring within 60 days (or expired).
  bool get isExpiring => expiryBand != ExpiryBand.ok;
}

/// Sorts batches first-expiry-first-out (no expiry last).
List<StockBatch> fefo(Iterable<StockBatch> batches) {
  final list = batches.toList();
  list.sort((a, b) {
    final ea = a.expiry;
    final eb = b.expiry;
    if (ea == null && eb == null) return a.batchNo.compareTo(b.batchNo);
    if (ea == null) return 1;
    if (eb == null) return -1;
    return ea.compareTo(eb);
  });
  return list;
}

/// Groups [batches] into S06 rows joined with the catalogue.
List<StockRow> stockRows(
  Iterable<StockBatch> batches,
  Map<String, StoreItem> catalog,
) {
  final bySku = <String, List<StockBatch>>{};
  for (final b in batches) {
    bySku.putIfAbsent(b.skuId, () => <StockBatch>[]).add(b);
  }
  final rows = <StockRow>[
    for (final e in bySku.entries)
      StockRow(skuId: e.key, item: catalog[e.key], batches: fefo(e.value)),
  ];
  rows.sort(
    (a, b) => (a.item?.name ?? a.skuId).compareTo(b.item?.name ?? b.skuId),
  );
  return rows;
}

/// S06 filters.
@immutable
class StockFilter {
  /// Creates the filter.
  const StockFilter({
    this.query = '',
    this.category,
    this.lowOnly = false,
    this.expiringOnly = false,
  });

  /// Name / brand / pack / barcode search.
  final String query;

  /// Product category, or all.
  final String? category;

  /// Only low-stock SKUs.
  final bool lowOnly;

  /// Only SKUs with a batch expiring within 60 days.
  final bool expiringOnly;

  /// Copy with overrides; [clearCategory] resets the category.
  StockFilter copyWith({
    String? query,
    String? category,
    bool? lowOnly,
    bool? expiringOnly,
    bool clearCategory = false,
  }) => StockFilter(
    query: query ?? this.query,
    category: clearCategory ? null : (category ?? this.category),
    lowOnly: lowOnly ?? this.lowOnly,
    expiringOnly: expiringOnly ?? this.expiringOnly,
  );

  /// Applies the filter.
  List<StockRow> apply(List<StockRow> rows) {
    final q = query.trim().toLowerCase();
    return <StockRow>[
      for (final r in rows)
        if ((category == null || r.item?.category == category) &&
            (!lowOnly || r.isLow) &&
            (!expiringOnly || r.isExpiring) &&
            (q.isEmpty || matchesItem(r.item, q)))
          r,
    ];
  }
}

/// Case-insensitive match of [q] (lowercase) on name, brand, pack, barcode.
bool matchesItem(StoreItem? item, String q) {
  if (item == null) return false;
  return item.name.toLowerCase().contains(q) ||
      item.brand.toLowerCase().contains(q) ||
      item.packLabel.toLowerCase().contains(q) ||
      (item.barcode ?? '').contains(q);
}

/// One cart line (whole packs).
@immutable
class StoreCartLine {
  /// Creates the line.
  const StoreCartLine({required this.item, required this.qty});

  /// The SKU.
  final StoreItem item;

  /// Packs.
  final int qty;

  /// Pre-tax line value (qty x store price).
  int get taxablePaise => item.pricePaise * qty;

  /// Copy with another quantity.
  StoreCartLine withQty(int q) => StoreCartLine(item: item, qty: q);
}

/// Payment modes at the counter (ST-002).
enum SaleMode {
  /// Dynamic UPI QR, polled until paid / failed.
  upiQr('upi_qr'),

  /// Card on the store's existing terminal; manual reference.
  card('card_terminal'),

  /// Cash; amount tendered and change.
  cash('cash'),

  /// Farmer khata, within the credit limit (ST-007).
  credit('credit');

  const SaleMode(this.wire);

  /// API value.
  final String wire;

  /// From the API value.
  static SaleMode? fromWire(String? w) {
    for (final m in values) {
      if (m.wire == w) return m;
    }
    return null;
  }
}

/// Body of `POST /v1/stores/{id}/pos/sales`.
@immutable
class PosSaleRequest {
  /// Creates the request.
  const PosSaleRequest({
    required this.lines,
    required this.mode,
    this.farmerId,
    this.farmerPhone,
    this.referenceNote,
    this.creditApprovalRequestId,
  });

  /// Cart lines.
  final List<StoreCartLine> lines;

  /// Payment mode.
  final SaleMode mode;

  /// Known farmer.
  final String? farmerId;

  /// E.164 phone of a buyer without a local farmer record.
  final String? farmerPhone;

  /// Card terminal reference.
  final String? referenceNote;

  /// ST-007 retry key: the `approval_request_id` of an earlier 402
  /// `credit_limit_exceeded` (credit sales only).
  final String? creditApprovalRequestId;

  /// Copy for another payment mode (the POS preview prices the same cart).
  PosSaleRequest withMode(SaleMode mode) => PosSaleRequest(
    lines: lines,
    mode: mode,
    farmerId: farmerId,
    farmerPhone: farmerPhone,
    referenceNote: referenceNote,
    creditApprovalRequestId: creditApprovalRequestId,
  );

  /// JSON body.
  Map<String, Object?> toJson() => <String, Object?>{
    'farmer_id': ?farmerId,
    if (farmerId == null && farmerPhone != null) 'farmer_phone': farmerPhone,
    'lines': <Map<String, Object?>>[
      for (final l in lines)
        <String, Object?>{'sku_id': l.item.skuId, 'qty': l.qty},
    ],
    'payment': <String, Object?>{
      'mode': mode.wire,
      if (referenceNote != null && referenceNote!.isNotEmpty)
        'reference_note': referenceNote,
    },
    if (mode == SaleMode.credit && creditApprovalRequestId != null)
      'credit_approval_request_id': creditApprovalRequestId,
  };
}

/// One GST invoice line (`InvoiceLineOut`, or the local preview).
@immutable
class InvoiceLine {
  /// Creates the line.
  const InvoiceLine({
    required this.sl,
    required this.description,
    required this.hsn,
    required this.qty,
    required this.unitPricePaise,
    required this.taxablePaise,
    required this.gstRateBp,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    this.unit = '',
  });

  /// Parses `InvoiceLineOut`.
  factory InvoiceLine.fromJson(Map<String, Object?> j) => InvoiceLine(
    sl: _int(j['sl']),
    description: (j['description'] as String?) ?? '',
    hsn: (j['hsn'] as String?) ?? '',
    qty: parseStoreQty(j['qty']),
    unit: (j['unit'] as String?) ?? '',
    unitPricePaise: _int(j['unit_price_paise']),
    taxablePaise: _int(j['taxable_paise']),
    gstRateBp: _int(j['gst_rate_bp']),
    cgstPaise: _int(j['cgst_paise']),
    sgstPaise: _int(j['sgst_paise']),
    igstPaise: _int(j['igst_paise']),
  );

  /// Serial number.
  final int sl;

  /// Product and pack.
  final String description;

  /// HSN code.
  final String hsn;

  /// Quantity.
  final double qty;

  /// Unit.
  final String unit;

  /// Pre-tax unit price.
  final int unitPricePaise;

  /// Taxable value.
  final int taxablePaise;

  /// GST rate (bp).
  final int gstRateBp;

  /// CGST.
  final int cgstPaise;

  /// SGST.
  final int sgstPaise;

  /// IGST.
  final int igstPaise;

  /// Line total with tax.
  int get totalPaise => taxablePaise + cgstPaise + sgstPaise + igstPaise;
}

/// A GST tax invoice (`InvoiceOut`).
@immutable
class Invoice {
  /// Creates the invoice.
  const Invoice({
    required this.id,
    required this.orderId,
    required this.invoiceNo,
    required this.issuedAt,
    required this.sellerName,
    required this.sellerGstin,
    required this.buyerName,
    required this.inter,
    required this.lines,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.roundOffPaise,
    required this.totalPaise,
    required this.amountInWords,
    this.sellerAddress = '',
    this.buyerGstin,
    this.placeOfSupply = '',
    this.farmerId,
    this.hasPdf = false,
  });

  /// Parses `InvoiceOut`.
  factory Invoice.fromJson(Map<String, Object?> j) => Invoice(
    id: j['id']! as String,
    orderId: (j['order_id'] as String?) ?? '',
    invoiceNo: (j['invoice_no'] as String?) ?? '',
    issuedAt: _date(j['issued_at']) ?? DateTime.utc(1970),
    sellerName: (j['seller_name'] as String?) ?? '',
    sellerGstin: (j['seller_gstin'] as String?) ?? '',
    sellerAddress: (j['seller_address'] as String?) ?? '',
    buyerName: (j['buyer_name'] as String?) ?? '',
    buyerGstin: _str(j['buyer_gstin']),
    placeOfSupply: (j['place_of_supply'] as String?) ?? '',
    inter: j['supply_type'] == 'inter',
    farmerId: _str(j['farmer_id']),
    lines: <InvoiceLine>[
      for (final l in _maps(j['lines'])) InvoiceLine.fromJson(l),
    ],
    taxablePaise: _int(j['taxable_paise']),
    cgstPaise: _int(j['cgst_paise']),
    sgstPaise: _int(j['sgst_paise']),
    igstPaise: _int(j['igst_paise']),
    roundOffPaise: _int(j['round_off_paise']),
    totalPaise: _int(j['total_paise']),
    amountInWords: (j['amount_in_words'] as String?) ?? '',
    hasPdf: j['has_pdf'] == true,
  );

  /// Invoice id.
  final String id;

  /// Order id.
  final String orderId;

  /// `FCC/KND/2026-27/000123`.
  final String invoiceNo;

  /// Issued (UTC).
  final DateTime issuedAt;

  /// Seller legal name.
  final String sellerName;

  /// Seller GSTIN.
  final String sellerGstin;

  /// Seller address.
  final String sellerAddress;

  /// Buyer name (farmer or walk-in).
  final String buyerName;

  /// Buyer GSTIN.
  final String? buyerGstin;

  /// Place of supply.
  final String placeOfSupply;

  /// Inter-state (IGST) rather than CGST + SGST.
  final bool inter;

  /// Farmer, if known.
  final String? farmerId;

  /// Lines.
  final List<InvoiceLine> lines;

  /// Taxable value.
  final int taxablePaise;

  /// CGST.
  final int cgstPaise;

  /// SGST.
  final int sgstPaise;

  /// IGST.
  final int igstPaise;

  /// Round-off to the rupee.
  final int roundOffPaise;

  /// Invoice total.
  final int totalPaise;

  /// Total in words (Indian numbering, from the server).
  final String amountInWords;

  /// The PDF exists in the blob store.
  final bool hasPdf;
}

/// `PaymentCreated` (sale or `POST /v1/payments`).
@immutable
class PaymentCreated {
  /// Creates the payment.
  const PaymentCreated({
    required this.paymentId,
    required this.mode,
    required this.status,
    required this.amountPaise,
    this.orderId,
    this.qrPayload,
    this.expiresAt,
  });

  /// Parses `PaymentCreated`.
  factory PaymentCreated.fromJson(Map<String, Object?> j) => PaymentCreated(
    paymentId: j['payment_id']! as String,
    mode: SaleMode.fromWire(j['mode'] as String?) ?? SaleMode.cash,
    status: (j['status'] as String?) ?? 'created',
    amountPaise: _int(j['amount_paise']),
    orderId: _str(j['order_id']),
    qrPayload: _str(j['qr_payload']),
    expiresAt: _date(j['expires_at']),
  );

  /// Payment id.
  final String paymentId;

  /// Mode.
  final SaleMode mode;

  /// Server status (`paid`, `pending`, `pending_reconciliation`, ...).
  final String status;

  /// Amount.
  final int amountPaise;

  /// Order.
  final String? orderId;

  /// UPI intent for the QR.
  final String? qrPayload;

  /// QR expiry.
  final DateTime? expiresAt;

  /// Already settled at the counter.
  bool get settled =>
      status == 'paid' ||
      status == 'pending_reconciliation' ||
      status == 'reconciled';
}

/// A67 / S03 poll state of a payment (`PaymentStatusOut.state`).
enum PaymentPollState {
  /// Waiting for the farmer.
  waiting,

  /// Paid.
  paid,

  /// Failed or expired.
  failed,
}

/// `GET /v1/payments/{id}`.
@immutable
class PaymentStatus {
  /// Creates the status.
  const PaymentStatus({
    required this.id,
    required this.state,
    required this.amountPaise,
    this.qrPayload,
    this.expiresAt,
    this.failureReason,
  });

  /// Parses `PaymentStatusOut`.
  factory PaymentStatus.fromJson(Map<String, Object?> j) => PaymentStatus(
    id: j['id']! as String,
    state: switch (j['state']) {
      'paid' => PaymentPollState.paid,
      'failed' => PaymentPollState.failed,
      _ => PaymentPollState.waiting,
    },
    amountPaise: _int(j['amount_paise']),
    qrPayload: _str(j['qr_payload']),
    expiresAt: _date(j['expires_at']),
    failureReason: _str(j['failure_reason']),
  );

  /// Payment id.
  final String id;

  /// Waiting / paid / failed.
  final PaymentPollState state;

  /// Amount.
  final int amountPaise;

  /// UPI intent.
  final String? qrPayload;

  /// QR expiry.
  final DateTime? expiresAt;

  /// Why it failed.
  final String? failureReason;
}

/// `POST /v1/stores/{id}/pos/sales` result.
@immutable
class PosSaleResult {
  /// Creates the result.
  const PosSaleResult({
    required this.orderId,
    required this.invoice,
    required this.payment,
  });

  /// Parses `PosSaleOut`.
  factory PosSaleResult.fromJson(Map<String, Object?> j) => PosSaleResult(
    orderId: j['order_id']! as String,
    invoice: Invoice.fromJson(Map<String, Object?>.from(j['invoice']! as Map)),
    payment: PaymentCreated.fromJson(
      Map<String, Object?>.from(j['payment']! as Map),
    ),
  );

  /// Order id.
  final String orderId;

  /// The GST invoice.
  final Invoice invoice;

  /// The payment.
  final PaymentCreated payment;
}

/// Order statuses (server `OrderStatus`).
enum OrderStatus {
  /// Draft.
  draft('draft'),

  /// Placed, stock not yet reserved (or waiting for a prepaid payment).
  placed('placed'),

  /// Stock reserved.
  reserved('reserved'),

  /// Packed.
  packed('packed'),

  /// Ready for pick-up.
  ready('ready'),

  /// Handed over at the counter.
  handedOver('handed_over'),

  /// Delivered.
  delivered('delivered'),

  /// Cancelled.
  cancelled('cancelled');

  const OrderStatus(this.wire);

  /// API value.
  final String wire;

  /// From the API value.
  static OrderStatus fromWire(String? w) {
    for (final s in values) {
      if (s.wire == w) return s;
    }
    return OrderStatus.placed;
  }
}

/// The server's `TRANSITIONS` table (ST-005).
const Map<OrderStatus, Set<OrderStatus>> orderTransitions =
    <OrderStatus, Set<OrderStatus>>{
      OrderStatus.placed: <OrderStatus>{
        OrderStatus.reserved,
        OrderStatus.cancelled,
      },
      OrderStatus.reserved: <OrderStatus>{
        OrderStatus.packed,
        OrderStatus.cancelled,
      },
      OrderStatus.packed: <OrderStatus>{
        OrderStatus.ready,
        OrderStatus.cancelled,
      },
      OrderStatus.ready: <OrderStatus>{
        OrderStatus.handedOver,
        OrderStatus.delivered,
        OrderStatus.cancelled,
      },
    };

/// Whether [from] -> [to] is allowed.
bool canTransition(OrderStatus from, OrderStatus to) =>
    orderTransitions[from]?.contains(to) ?? false;

/// S05 tabs.
enum QueueTab {
  /// Placed and reserved.
  fresh(<OrderStatus>{OrderStatus.placed, OrderStatus.reserved}),

  /// Packed.
  packing(<OrderStatus>{OrderStatus.packed}),

  /// Ready.
  ready(<OrderStatus>{OrderStatus.ready}),

  /// Handed over or delivered.
  handedOver(<OrderStatus>{OrderStatus.handedOver, OrderStatus.delivered});

  const QueueTab(this.statuses);

  /// Statuses shown in the tab.
  final Set<OrderStatus> statuses;

  /// The tab an order in [s] belongs to, if any.
  static QueueTab? of(OrderStatus s) {
    for (final t in values) {
      if (t.statuses.contains(s)) return t;
    }
    return null;
  }
}

/// Actions offered in a tab; each is enabled only when [canTransition].
List<OrderStatus> queueActions(QueueTab tab) => switch (tab) {
  QueueTab.fresh => <OrderStatus>[OrderStatus.reserved, OrderStatus.packed],
  QueueTab.packing => <OrderStatus>[OrderStatus.ready],
  QueueTab.ready => <OrderStatus>[
    OrderStatus.handedOver,
    OrderStatus.delivered,
  ],
  QueueTab.handedOver => const <OrderStatus>[],
};

/// One order line in the queue.
@immutable
class QueueLine {
  /// Creates the line.
  const QueueLine({
    required this.skuId,
    required this.qty,
    required this.lineTotalPaise,
  });

  /// Parses `OrderLineOut`.
  factory QueueLine.fromJson(Map<String, Object?> j) => QueueLine(
    skuId: j['sku_id']! as String,
    qty: parseStoreQty(j['qty']),
    lineTotalPaise: _int(j['line_total_paise']),
  );

  /// SKU.
  final String skuId;

  /// Quantity.
  final double qty;

  /// Line total.
  final int lineTotalPaise;
}

/// S05 order (`OrderQueueItemOut` / `OrderDetailOut`).
@immutable
class QueueOrder {
  /// Creates the order.
  const QueueOrder({
    required this.id,
    required this.status,
    required this.channel,
    required this.totalPaise,
    required this.lines,
    this.farmerId,
    this.placedAt,
    this.notes,
    this.fulfilment = 'pickup',
  });

  /// Parses the API shape.
  factory QueueOrder.fromJson(Map<String, Object?> j) => QueueOrder(
    id: j['id']! as String,
    status: OrderStatus.fromWire(j['status'] as String?),
    channel: (j['channel'] as String?) ?? '',
    fulfilment: (j['fulfilment'] as String?) ?? 'pickup',
    totalPaise: _int(j['total_paise']),
    farmerId: _str(j['farmer_id']),
    placedAt: _date(j['placed_at']) ?? _date(j['created_at']),
    notes: _str(j['notes']),
    lines: <QueueLine>[
      for (final l in _maps(j['lines'])) QueueLine.fromJson(l),
    ],
  );

  /// Order id.
  final String id;

  /// Status.
  final OrderStatus status;

  /// `officer`, `farmer_app`, `pos`.
  final String channel;

  /// `pickup` or `delivery`.
  final String fulfilment;

  /// Total with tax.
  final int totalPaise;

  /// Farmer.
  final String? farmerId;

  /// Placed at (UTC).
  final DateTime? placedAt;

  /// Notes.
  final String? notes;

  /// Lines.
  final List<QueueLine> lines;

  /// Short reference for the counter (last 6 of the id, upper case).
  String get shortRef {
    final s = id.replaceAll('-', '');
    return (s.length <= 6 ? s : s.substring(s.length - 6)).toUpperCase();
  }

  /// Copy with a new status.
  QueueOrder withStatus(OrderStatus s) => QueueOrder(
    id: id,
    status: s,
    channel: channel,
    fulfilment: fulfilment,
    totalPaise: totalPaise,
    farmerId: farmerId,
    placedAt: placedAt,
    notes: notes,
    lines: lines,
  );
}

/// S09 credit approval request (`CreditApprovalOut`).
@immutable
class CreditApproval {
  /// Creates the request.
  const CreditApproval({
    required this.id,
    required this.farmerId,
    required this.storeId,
    required this.amountPaise,
    required this.balancePaise,
    required this.limitPaise,
    required this.shortfallPaise,
    required this.status,
    this.orderId,
    this.createdAt,
    this.decisionNote,
  });

  /// Parses `CreditApprovalOut`.
  factory CreditApproval.fromJson(Map<String, Object?> j) => CreditApproval(
    id: j['id']! as String,
    farmerId: j['farmer_id']! as String,
    storeId: j['store_id']! as String,
    orderId: _str(j['order_id']),
    amountPaise: _int(j['amount_paise']),
    balancePaise: _int(j['balance_paise']),
    limitPaise: _int(j['limit_paise']),
    shortfallPaise: _int(j['shortfall_paise']),
    status: (j['status'] as String?) ?? 'pending',
    createdAt: _date(j['created_at']),
    decisionNote: _str(j['decision_note']),
  );

  /// Request id.
  final String id;

  /// Farmer.
  final String farmerId;

  /// Store.
  final String storeId;

  /// Order.
  final String? orderId;

  /// Sale amount.
  final int amountPaise;

  /// Khata balance before the sale.
  final int balancePaise;

  /// Credit limit.
  final int limitPaise;

  /// Amount beyond the limit.
  final int shortfallPaise;

  /// `pending`, `approved`, `rejected`.
  final String status;

  /// Requested at.
  final DateTime? createdAt;

  /// Decision note.
  final String? decisionNote;

  /// Copy with a decision.
  CreditApproval decided(String newStatus, String? note) => CreditApproval(
    id: id,
    farmerId: farmerId,
    storeId: storeId,
    orderId: orderId,
    amountPaise: amountPaise,
    balancePaise: balancePaise,
    limitPaise: limitPaise,
    shortfallPaise: shortfallPaise,
    status: newStatus,
    createdAt: createdAt,
    decisionNote: note,
  );
}

/// A day close (`DayCloseOut`).
@immutable
class DayClose {
  /// Creates the close.
  const DayClose({
    required this.id,
    required this.businessDate,
    required this.status,
    required this.expectedPaise,
    required this.countedPaise,
    required this.variancePaise,
    required this.flagged,
    this.depositSlipUri,
    this.notes,
    this.closedAt,
  });

  /// Parses `DayCloseOut`.
  factory DayClose.fromJson(Map<String, Object?> j) => DayClose(
    id: j['id']! as String,
    businessDate: (j['business_date'] as String?) ?? '',
    status: (j['status'] as String?) ?? 'closed',
    expectedPaise: _int(j['cash_expected_paise']),
    countedPaise: _int(j['cash_counted_paise']),
    variancePaise: _int(j['variance_paise']),
    flagged: j['variance_flagged'] == true,
    depositSlipUri: _str(j['deposit_slip_uri']),
    notes: _str(j['notes']),
    closedAt: _date(j['closed_at']),
  );

  /// Close id.
  final String id;

  /// IST business date (`2026-09-20`).
  final String businessDate;

  /// `closed` or `reopened`.
  final String status;

  /// Expected cash.
  final int expectedPaise;

  /// Counted cash.
  final int countedPaise;

  /// Counted minus expected.
  final int variancePaise;

  /// Beyond the tenant threshold (auditors notified).
  final bool flagged;

  /// Deposit slip blob.
  final String? depositSlipUri;

  /// Notes.
  final String? notes;

  /// Closed at (UTC).
  final DateTime? closedAt;

  /// Still closed (not reopened).
  bool get isClosed => status == 'closed';
}

/// Count and amount.
@immutable
class CountAmount {
  /// Creates the pair.
  const CountAmount(this.count, this.amountPaise);

  /// Parses `CountAmount`.
  factory CountAmount.fromJson(Object? j) => j is Map
      ? CountAmount(_int(j['count']), _int(j['amount_paise']))
      : const CountAmount(0, 0);

  /// Count.
  final int count;

  /// Amount.
  final int amountPaise;
}

/// `GET /v1/stores/{id}/day-summary` (ST-002).
@immutable
class DaySummary {
  /// Creates the summary.
  const DaySummary({
    required this.businessDate,
    required this.byMode,
    required this.totalReceivedPaise,
    required this.expectedCashPaise,
    this.waiting = const CountAmount(0, 0),
    this.failed = const CountAmount(0, 0),
    this.refunds = const CountAmount(0, 0),
    this.cashPendingPaise = 0,
    this.dayClose,
  });

  /// Parses `DaySummaryOut`.
  factory DaySummary.fromJson(Map<String, Object?> j) => DaySummary(
    businessDate: (j['business_date'] as String?) ?? '',
    byMode: <String, CountAmount>{
      for (final m in _maps(j['by_mode']))
        (m['mode'] as String?) ?? '': CountAmount.fromJson(m),
    },
    totalReceivedPaise: _int(j['total_received_paise']),
    waiting: CountAmount.fromJson(j['waiting']),
    failed: CountAmount.fromJson(j['failed']),
    refunds: CountAmount.fromJson(j['refunds']),
    expectedCashPaise: _int(j['expected_cash_paise']),
    cashPendingPaise: _int(j['cash_pending_reconciliation_paise']),
    dayClose: j['day_close'] is Map
        ? DayClose.fromJson(Map<String, Object?>.from(j['day_close']! as Map))
        : null,
  );

  /// IST business date.
  final String businessDate;

  /// Totals by payment mode wire name.
  final Map<String, CountAmount> byMode;

  /// Money received (credit excluded).
  final int totalReceivedPaise;

  /// UPI / links still waiting.
  final CountAmount waiting;

  /// Failed payments.
  final CountAmount failed;

  /// Refunds.
  final CountAmount refunds;

  /// Cash the drawer should hold.
  final int expectedCashPaise;

  /// Cash not yet reconciled by a close.
  final int cashPendingPaise;

  /// Today's close, if any.
  final DayClose? dayClose;

  /// Amount for [mode].
  int amountFor(SaleMode mode) => byMode[mode.wire]?.amountPaise ?? 0;

  /// Sales total incl. credit (S01 "today's sales").
  int get salesPaise => byMode.values.fold(0, (a, b) => a + b.amountPaise);

  /// Number of payments today (all modes).
  int get salesCount => byMode.values.fold(0, (a, b) => a + b.count);
}

/// Goods receipt line (S07).
@immutable
class ReceiptLine {
  /// Creates the line.
  const ReceiptLine({
    required this.item,
    required this.batchNo,
    required this.qty,
    required this.costPaise,
    this.expiry,
  });

  /// SKU.
  final StoreItem item;

  /// Batch number.
  final String batchNo;

  /// Expiry date.
  final DateTime? expiry;

  /// Quantity received.
  final double qty;

  /// Unit cost.
  final int costPaise;

  /// JSON line.
  Map<String, Object?> toJson() => <String, Object?>{
    'sku_id': item.skuId,
    'batch_no': batchNo,
    if (expiry != null) 'expiry': isoDate(expiry!),
    'qty': formatQty(qty),
    'cost_paise': costPaise,
  };
}

/// `YYYY-MM-DD` for a calendar date.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Batch + qty for transfers / write-offs.
@immutable
class BatchQty {
  /// Creates the pair.
  const BatchQty({required this.batch, required this.qty});

  /// The batch.
  final StockBatch batch;

  /// Quantity.
  final double qty;

  @override
  bool operator ==(Object other) =>
      other is BatchQty && other.batch.id == batch.id && other.qty == qty;

  @override
  int get hashCode => Object.hash(batch.id, qty);
}

/// Write-off reasons.
enum WriteOffReason {
  /// Damaged.
  damage,

  /// Expired.
  expiry,

  /// Other.
  other,
}

/// Result of a stock write (`StockWriteOut`).
@immutable
class StockWriteResult {
  /// Creates the result.
  const StockWriteResult({required this.refId, required this.movementCount});

  /// Parses `StockWriteOut`.
  factory StockWriteResult.fromJson(Map<String, Object?> j) => StockWriteResult(
    refId: (j['ref_id'] as String?) ?? '',
    movementCount: j['movements'] is List
        ? (j['movements']! as List).length
        : 0,
  );

  /// Receipt / transfer / write-off id.
  final String refId;

  /// Movements written.
  final int movementCount;
}

/// Equality helper for lists of cart lines (tests).
bool sameLines(List<StoreCartLine> a, List<StoreCartLine> b) => listEquals(
  <String>[for (final l in a) '${l.item.skuId}:${l.qty}'],
  <String>[for (final l in b) '${l.item.skuId}:${l.qty}'],
);
