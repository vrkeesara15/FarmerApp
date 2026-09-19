import '../sync/sync_api.dart';
import '../sync/sync_models.dart';

/// In-memory money rules of the API for tests and previews (FA-020 /
/// FA-021): plug [script] into [FakeSyncApi.script]. `order` creates are
/// priced from [prices] (+ [gstBp], half-up per line, like
/// `orders.service`), checked against [stock] (`insufficient_stock` with one
/// `errors[]` entry per short line) and echoed as `OrderDetailOut`;
/// `payment` creates are echoed as `PaymentOut` (cash →
/// `pending_reconciliation`, credit → `paid` on the khata) or rejected:
/// UPI / link → `requires_network`, credit over [creditLimitPaise] →
/// `credit_limit_exceeded` (402) until [approve] is called. Like the API,
/// the approval request is in the change feed (`credit_approval_request`:
/// pending when blocked, approved by [approve]); a retry naming an approved
/// request (`credit_approval_request_id`) goes through. [handOver] issues
/// the order's invoice (`invoice_id` in the order change).
class FakeCommerceServer {
  /// Creates the server.
  FakeCommerceServer({
    required this.api,
    this.prices = const <String, int>{},
    this.gstBp = const <String, int>{},
    Map<String, double>? stock,
    this.creditLimitPaise,
    this.balancePaise = 0,
    this.officerId = 'officer-1',
    this.storeId = 'store-1',
    DateTime Function()? clock,
  }) : stock = stock ?? <String, double>{},
       _now = clock ?? (() => DateTime.now().toUtc()) {
    api.script = script;
  }

  /// The sync fake this server scripts.
  final FakeSyncApi api;

  /// Server unit price per SKU (paise).
  final Map<String, int> prices;

  /// GST per SKU (basis points).
  final Map<String, int> gstBp;

  /// Available units per SKU (missing = unlimited).
  final Map<String, double> stock;

  /// Credit limit; null = unlimited.
  int? creditLimitPaise;

  /// Khata balance before the sale.
  int balancePaise;

  /// `collected_by` / `placed_by`.
  final String officerId;

  /// Store orders go to.
  final String storeId;

  final DateTime Function() _now;

  /// Server rows by id.
  final Map<String, Map<String, Object?>> orders =
      <String, Map<String, Object?>>{};

  /// Server payments by id.
  final Map<String, Map<String, Object?>> payments =
      <String, Map<String, Object?>>{};

  /// Order ids whose credit sale the cluster head approved.
  final Set<String> approved = <String>{};

  /// Approves the pending credit request of [orderId] and puts the decision
  /// in the change feed.
  void approve(String orderId) {
    approved.add(orderId);
    final id = approvalIdFor(orderId);
    api.addChange(
      entity: SyncEntities.creditApprovalRequest,
      action: SyncAction.update,
      entityId: id,
      version: 2,
      data: _approvalRow(orderId, 'approved'),
    );
  }

  /// The approval request id of [orderId]'s blocked credit sale.
  static String approvalIdFor(String? orderId) => 'approval-$orderId';

  Map<String, Object?> _approvalRow(String? orderId, String status) =>
      <String, Object?>{
        'id': approvalIdFor(orderId),
        'order_id': orderId,
        'store_id': storeId,
        'requested_by': officerId,
        'status': status,
        'version': status == 'pending' ? 1 : 2,
      };

  /// The store hands the order over: status `handed_over` and its GST
  /// invoice ([invoiceId], [invoiceNo]) in the order's change.
  void handOver(
    String orderId, {
    required String invoiceId,
    required String invoiceNo,
  }) {
    final row = <String, Object?>{
      ...orders[orderId]!,
      'status': 'handed_over',
      'invoice_id': invoiceId,
      'invoice_no': invoiceNo,
      'version': 3,
    }..remove('lines');
    orders[orderId] = row;
    api.addChange(
      entity: SyncEntities.order,
      action: SyncAction.update,
      entityId: orderId,
      version: 3,
      data: row,
    );
  }

  static int _halfUp(num v) => (v + 0.5).floor();

  /// Result for an op (null = let the fake apply it).
  SyncOpResult? script(SyncOp op) {
    if (op.action != SyncAction.create) return null;
    return switch (op.entity) {
      SyncEntities.order => _order(op),
      SyncEntities.payment => _payment(op),
      _ => null,
    };
  }

  SyncOpResult _rejected(SyncOp op, SyncError error) => SyncOpResult(
    opId: op.opId,
    status: SyncResultStatus.rejected,
    entityId: op.entityId,
    error: error,
  );

  SyncOpResult _order(SyncOp op) {
    final lines = <Map<String, Object?>>[
      for (final l in (op.payload['lines'] as List?) ?? const <Object?>[])
        Map<String, Object?>.from(l! as Map),
    ];
    final short = <Map<String, Object?>>[];
    for (final (i, l) in lines.indexed) {
      final sku = '${l['sku_id']}';
      final qty = (l['qty']! as num).toDouble();
      final have = stock[sku];
      if (have != null && have < qty) {
        short.add(<String, Object?>{
          'index': i,
          'sku_id': sku,
          'requested': qty.toString(),
          'available': have.toString(),
        });
      }
    }
    if (short.isNotEmpty) {
      return _rejected(
        op,
        SyncError(
          'insufficient_stock',
          'Not enough unreserved, unexpired stock at the store.',
          const <String, Object?>{},
          short,
        ),
      );
    }
    var subtotal = 0;
    var tax = 0;
    final out = <Map<String, Object?>>[];
    for (final (i, l) in lines.indexed) {
      final sku = '${l['sku_id']}';
      final qty = (l['qty']! as num).toDouble();
      final unit = prices[sku] ?? 0;
      final total = _halfUp(qty * unit);
      final lineTax = _halfUp(total * (gstBp[sku] ?? 0) / 10000);
      subtotal += total;
      tax += lineTax;
      out.add(<String, Object?>{
        'id': '${op.entityId}-line-$i',
        'order_id': op.entityId,
        'sku_id': sku,
        'qty': qty.toStringAsFixed(3),
        'unit_price_paise': unit,
        'gst_rate_bp': gstBp[sku] ?? 0,
        'line_total_paise': total,
        'label_claim_id': l['label_claim_id'],
        'version': 1,
      });
      final have = stock[sku];
      if (have != null) stock[sku] = have - qty;
    }
    final now = _now().toIso8601String();
    final row = <String, Object?>{
      'id': op.entityId,
      'farmer_id': op.payload['farmer_id'],
      'store_id': op.payload['store_id'] ?? storeId,
      'channel': 'officer',
      'status': 'reserved',
      'fulfilment': op.payload['fulfilment'] ?? 'pickup',
      'subtotal_paise': subtotal,
      'discount_paise': 0,
      'tax_paise': tax,
      'total_paise': subtotal + tax,
      'placed_by': officerId,
      'placed_at': now,
      'notes': op.payload['notes'],
      'invoice_no': null,
      'client_order_id': op.entityId,
      'version': 2,
      'lines': out,
      'payments': const <Object?>[],
      'events': <Map<String, Object?>>[
        <String, Object?>{'to_status': 'placed', 'created_at': now},
        <String, Object?>{'to_status': 'reserved', 'created_at': now},
      ],
    };
    orders[op.entityId] = row;
    api.rows['order/${op.entityId}'] = FakeServerRow(version: 2, data: row);
    return SyncOpResult(
      opId: op.opId,
      status: SyncResultStatus.applied,
      entityId: op.entityId,
      version: 2,
      server: row,
    );
  }

  SyncOpResult _payment(SyncOp op) {
    final p = op.payload;
    final mode = p['mode'] as String?;
    if (p.containsKey('id')) {
      return _rejected(
        op,
        const SyncError('validation_error', 'extra field: id'),
      );
    }
    if (mode == 'upi_qr' || mode == 'payment_link') {
      return _rejected(
        op,
        const SyncError(
          'requires_network',
          'UPI QR and payment links need the network: collect online.',
        ),
      );
    }
    final orderId = p['order_id'] as String?;
    final order = orderId == null ? null : orders[orderId];
    if (orderId != null && order == null) {
      return _rejected(op, const SyncError('not_found', 'Order not found.'));
    }
    if (mode == 'cash' && !'${p['receipt_uri']}'.startsWith('blob://')) {
      return _rejected(
        op,
        const SyncError('receipt_required', 'Cash needs the receipt photo.'),
      );
    }
    final amount = order == null
        ? (p['amount_paise'] as num?)?.toInt() ?? 0
        : (order['total_paise']! as num).toInt();
    if (mode == 'credit') {
      final limit = creditLimitPaise;
      // The API lets an approved sale through when the retry names the
      // request (or, as before, for the same order id).
      if (limit != null &&
          balancePaise + amount > limit &&
          !approved.contains(orderId)) {
        if (!approved.contains(orderId)) {
          api.addChange(
            entity: SyncEntities.creditApprovalRequest,
            action: SyncAction.create,
            entityId: approvalIdFor(orderId),
            data: _approvalRow(orderId, 'pending'),
          );
        }
        return _rejected(
          op,
          SyncError(
            'credit_limit_exceeded',
            'The credit sale is beyond the farmer’s limit; approval requested.',
            const <String, Object?>{},
            <Map<String, Object?>>[
              <String, Object?>{
                'shortfall_paise': balancePaise + amount - limit,
                'approval_request_id': approvalIdFor(orderId),
                'balance_paise': balancePaise,
                'limit_paise': limit,
              },
            ],
          ),
        );
      }
      balancePaise += amount;
    }
    final row = <String, Object?>{
      'id': op.entityId,
      'order_id': orderId,
      'farmer_id': order?['farmer_id'] ?? p['farmer_id'],
      'store_id': order?['store_id'] ?? p['store_id'] ?? storeId,
      'mode': mode,
      'amount_paise': amount,
      'provider': mode == 'credit' ? 'khata' : 'cash',
      'status': mode == 'cash' ? 'pending_reconciliation' : 'paid',
      'receipt_uri': p['receipt_uri'],
      'collected_by': officerId,
      'paid_at': mode == 'cash' ? null : _now().toIso8601String(),
      'created_at': _now().toIso8601String(),
      'version': 1,
    };
    payments[op.entityId] = row;
    api.rows['payment/${op.entityId}'] = FakeServerRow(version: 1, data: row);
    return SyncOpResult(
      opId: op.opId,
      status: SyncResultStatus.applied,
      entityId: op.entityId,
      version: 1,
      server: row,
    );
  }
}
