import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_models.dart';
import 'order_models.dart';

/// The A50 → A51 → A52 cart for one farmer (FA-020).
@immutable
class CartState {
  /// Creates the state.
  const CartState({
    this.farmerId,
    this.storeId,
    this.lines = const <CartLine>[],
    this.fulfilment = Fulfilment.pickup,
    this.editingOrderId,
    this.shortfalls = const <StockShortfall>[],
  });

  /// Farmer the order is for.
  final String? farmerId;

  /// Store the order goes to.
  final String? storeId;

  /// Lines, in the order they were added.
  final List<CartLine> lines;

  /// Pickup or delivery.
  final Fulfilment fulfilment;

  /// Set while editing a rejected order (A51 after `insufficient_stock`).
  final String? editingOrderId;

  /// Short lines from the server's rejection.
  final List<StockShortfall> shortfalls;

  /// Estimated totals.
  CartTotals get totals => CartTotals.of(lines);

  /// Quantity of [skuId] in the cart (0 when absent).
  int qtyOf(String skuId) =>
      lines.where((l) => l.item.skuId == skuId).firstOrNull?.qty ?? 0;

  /// The server's available quantity for [skuId] after a rejection.
  StockShortfall? shortfallOf(String skuId) =>
      shortfalls.where((s) => s.skuId == skuId).firstOrNull;

  /// Lines still above what the store has.
  bool get hasShortLines => lines.any((l) {
    final s = shortfallOf(l.item.skuId);
    return s != null && l.qty > s.available;
  });

  /// Copy with overrides.
  CartState copyWith({
    String? farmerId,
    String? storeId,
    List<CartLine>? lines,
    Fulfilment? fulfilment,
    String? editingOrderId,
    List<StockShortfall>? shortfalls,
  }) => CartState(
    farmerId: farmerId ?? this.farmerId,
    storeId: storeId ?? this.storeId,
    lines: lines ?? this.lines,
    fulfilment: fulfilment ?? this.fulfilment,
    editingOrderId: editingOrderId ?? this.editingOrderId,
    shortfalls: shortfalls ?? this.shortfalls,
  );

  @override
  bool operator ==(Object other) =>
      other is CartState &&
      other.farmerId == farmerId &&
      other.storeId == storeId &&
      listEquals(other.lines, lines) &&
      other.fulfilment == fulfilment &&
      other.editingOrderId == editingOrderId &&
      listEquals(other.shortfalls, shortfalls);

  @override
  int get hashCode => Object.hash(
    farmerId,
    storeId,
    Object.hashAll(lines),
    fulfilment,
    editingOrderId,
  );
}

/// Cart state holder.
class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  /// Starts a cart for [farmerId] (keeps it when it is the same farmer).
  void start(String farmerId, {String? storeId}) {
    if (state.farmerId == farmerId && state.editingOrderId == null) {
      if (storeId != null && state.storeId != storeId) {
        state = state.copyWith(storeId: storeId);
      }
      return;
    }
    state = CartState(farmerId: farmerId, storeId: storeId);
  }

  /// Sets the store (nearest-store answer).
  void setStore(String storeId) => state = state.copyWith(storeId: storeId);

  /// Adds one pack of [item] (or one more).
  void add(CatalogItem item) => setQty(item, state.qtyOf(item.skuId) + 1);

  /// Sets the quantity of [item]; 0 removes the line.
  void setQty(CatalogItem item, int qty) {
    final lines = <CartLine>[...state.lines];
    final i = lines.indexWhere((l) => l.item.skuId == item.skuId);
    if (qty <= 0) {
      if (i >= 0) lines.removeAt(i);
    } else if (i >= 0) {
      lines[i] = lines[i].withQty(qty);
    } else {
      lines.add(CartLine(item: item, qty: qty));
    }
    state = state.copyWith(lines: lines);
  }

  /// Pickup or delivery.
  void setFulfilment(Fulfilment f) => state = state.copyWith(fulfilment: f);

  /// Loads a rejected order back into the cart for editing.
  void editRejected({
    required String orderId,
    required String farmerId,
    required String? storeId,
    required List<CartLine> lines,
    required Fulfilment fulfilment,
    required List<StockShortfall> shortfalls,
  }) {
    state = CartState(
      farmerId: farmerId,
      storeId: storeId,
      lines: lines,
      fulfilment: fulfilment,
      editingOrderId: orderId,
      shortfalls: shortfalls,
    );
  }

  /// Empties the cart (after placing).
  void clear() => state = const CartState();
}

/// The cart.
final NotifierProvider<CartNotifier, CartState> cartProvider =
    NotifierProvider<CartNotifier, CartState>(CartNotifier.new);
