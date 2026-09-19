import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../catalog/catalog_models.dart';
import '../db/app_database.dart';
import '../sync/sync_models.dart';

/// Problem codes the order flow explains (FA-020).
abstract final class OrderErrorCodes {
  /// 409: a line is short at the store; `errors[]` per line.
  static const String insufficientStock = 'insufficient_stock';

  /// 422: a line's label claim does not allow the SKU (DX-007).
  static const String skuNotRecommendable = 'sku_not_recommendable';

  /// 409: the device's price / total differs from the server's.
  static const String amountMismatch = 'amount_mismatch';

  /// 402: a credit sale beyond the farmer's limit (approval requested).
  static const String creditLimitExceeded = 'credit_limit_exceeded';
}

/// Order statuses (ST-005) in timeline order.
abstract final class OrderStatuses {
  /// Draft (not used by the officer app).
  static const String draft = 'draft';

  /// Placed.
  static const String placed = 'placed';

  /// Stock reserved.
  static const String reserved = 'reserved';

  /// Packed at the store.
  static const String packed = 'packed';

  /// Ready for pickup / dispatch.
  static const String ready = 'ready';

  /// Handed over at the store.
  static const String handedOver = 'handed_over';

  /// Delivered.
  static const String delivered = 'delivered';

  /// Cancelled.
  static const String cancelled = 'cancelled';

  /// A57 timeline steps (the last is `handed_over` or `delivered`).
  static const List<String> timeline = <String>[
    placed,
    reserved,
    packed,
    ready,
    handedOver,
  ];

  /// Index of [status] on [timeline] (delivered = the last step).
  static int stepOf(String status) => switch (status) {
    delivered => timeline.length - 1,
    draft => 0,
    cancelled => -1,
    _ => timeline.indexOf(status).clamp(0, timeline.length - 1),
  };
}

/// `pickup` | `delivery`.
enum Fulfilment {
  /// Farmer collects at the store.
  pickup,

  /// Store delivers to the farmer.
  delivery;

  /// Parses the wire value.
  static Fulfilment parse(String? v) => v == delivery.name ? delivery : pickup;
}

/// One cart line: a catalogue item and a quantity. Prices are estimates.
@immutable
class CartLine {
  /// Creates the line.
  const CartLine({required this.item, required this.qty, this.labelClaimId});

  /// The SKU with its cached price.
  final CatalogItem item;

  /// Quantity (packs).
  final int qty;

  /// The label claim behind a crop-doctor recommendation (DX-007); sent as
  /// the order line's `label_claim_id` so FA-020 checks it again.
  final String? labelClaimId;

  /// `qty x unit` (half-up), before tax — same rule as the server.
  int get estimatedLinePaise => item.pricePaise * qty;

  /// Estimated GST on the line (half-up).
  int get estimatedTaxPaise =>
      roundHalfUp(estimatedLinePaise * item.gstRateBp, 10000);

  /// Copy with a new quantity.
  CartLine withQty(int value) =>
      CartLine(item: item, qty: value, labelClaimId: labelClaimId);
}

/// `a / b` rounded half-up (non-negative inputs).
int roundHalfUp(int a, int b) => (2 * a + b) ~/ (2 * b);

/// Estimated totals of a cart (the server recomputes on placing).
@immutable
class CartTotals {
  /// Creates the totals.
  const CartTotals({
    required this.subtotalPaise,
    required this.taxPaise,
    required this.itemCount,
  });

  /// Sums [lines] exactly as the server does per line.
  factory CartTotals.of(List<CartLine> lines) => CartTotals(
    subtotalPaise: lines.fold(0, (a, l) => a + l.estimatedLinePaise),
    taxPaise: lines.fold(0, (a, l) => a + l.estimatedTaxPaise),
    itemCount: lines.fold(0, (a, l) => a + l.qty),
  );

  /// Sum of line totals.
  final int subtotalPaise;

  /// Sum of line taxes.
  final int taxPaise;

  /// Units in the cart.
  final int itemCount;

  /// Estimated total.
  int get totalPaise => subtotalPaise + taxPaise;
}

/// A short line of an `insufficient_stock` rejection.
@immutable
class StockShortfall {
  /// Creates the shortfall.
  const StockShortfall({
    required this.skuId,
    required this.requested,
    required this.available,
    this.index,
  });

  /// SKU.
  final String skuId;

  /// Line index in the order.
  final int? index;

  /// Quantity asked for.
  final double requested;

  /// Quantity the store can give.
  final double available;

  /// Parses `error.errors[]` of an `insufficient_stock` rejection.
  static List<StockShortfall> fromError(SyncError? error) {
    if (error == null || error.code != OrderErrorCodes.insufficientStock) {
      return const <StockShortfall>[];
    }
    final rows = error.errors.isNotEmpty
        ? error.errors
        : <Map<String, Object?>>[error.extra];
    return <StockShortfall>[
      for (final e in rows)
        if (e['sku_id'] != null)
          StockShortfall(
            skuId: '${e['sku_id']}',
            index: (e['index'] as num?)?.toInt(),
            requested: parseQty(e['requested']) ?? 0,
            available: parseQty(e['available']) ?? 0,
          ),
    ];
  }
}

/// One status change of an order (ST-005 history).
@immutable
class OrderEvent {
  /// Creates the event.
  const OrderEvent({required this.toStatus, this.at});

  /// New status.
  final String toStatus;

  /// When (UTC).
  final DateTime? at;
}

/// An order with its lines and sync state (A57, A22 Orders tab).
@immutable
class OrderView {
  /// Creates the view.
  const OrderView({
    required this.order,
    required this.lines,
    this.rejection,
    this.opId,
  });

  /// The row.
  final OrderRow order;

  /// Lines in order.
  final List<OrderLineRow> lines;

  /// The server's rejection of the queued `order` op, if any.
  final SyncError? rejection;

  /// The outbox op of the create while it is open.
  final String? opId;

  /// Still waiting for the server (queued create).
  bool get pendingSync => order.version == 0 && rejection == null;

  /// The server has priced the order (money fields are the server's).
  bool get serverPriced => order.totalPaise != null;

  /// Total to show: the server's once known, else the device estimate.
  int get displayTotalPaise => order.totalPaise ?? order.estimatedTotalPaise;

  /// Short lines when the rejection is `insufficient_stock`.
  List<StockShortfall> get shortfalls => StockShortfall.fromError(rejection);

  /// Status history from the server, oldest first.
  List<OrderEvent> get events {
    final raw = jsonDecode(order.events);
    if (raw is! List) return const <OrderEvent>[];
    return <OrderEvent>[
      for (final e in raw)
        if (e is Map && e['to_status'] is String)
          OrderEvent(
            toStatus: e['to_status']! as String,
            at: e['created_at'] is String
                ? DateTime.tryParse(e['created_at']! as String)?.toUtc()
                : null,
          ),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is OrderView &&
      other.order == order &&
      listEquals(other.lines, lines) &&
      other.rejection == rejection &&
      other.opId == opId;

  @override
  int get hashCode => Object.hash(order, Object.hashAll(lines), rejection);
}
