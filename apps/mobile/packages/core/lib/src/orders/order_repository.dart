import 'dart:async';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../sync/outbox.dart';
import '../sync/sync_models.dart';
import '../sync/sync_store.dart';
import 'order_models.dart';

/// Local orders and the `order` outbox op (FA-020).
///
/// Placing writes the order + lines (estimates under `_local`) and queues
/// one `order` create whose payload is exactly `OrderCreate` minus prices:
/// `{id, farmer_id, store_id, fulfilment, payment_mode, notes, lines:
/// [{sku_id, qty, label_claim_id?}]}`. The server prices it; the applied
/// echo replaces totals and lines (server wins for money).
class OrderRepository {
  /// Creates the repository.
  OrderRepository(this.db, this.outbox, {required String Function() ids})
    : _newId = ids;

  /// The database.
  final AppDatabase db;

  /// The outbox.
  final Outbox outbox;

  final String Function() _newId;

  SyncStore get _store => outbox.store;

  /// The `order` create payload for [lines] (no prices: the server prices).
  static Map<String, Object?> createPayload({
    required String farmerId,
    required String? storeId,
    required Fulfilment fulfilment,
    required List<CartLine> lines,
    String? paymentMode,
    String? notes,
    Map<String, String> labelClaims = const <String, String>{},
  }) => <String, Object?>{
    'farmer_id': farmerId,
    'store_id': ?storeId,
    'fulfilment': fulfilment.name,
    'payment_mode': paymentMode,
    'notes': ?notes,
    'lines': <Map<String, Object?>>[
      for (final l in lines)
        <String, Object?>{
          'sku_id': l.item.skuId,
          'qty': l.qty,
          'label_claim_id': ?labelClaims[l.item.skuId],
        },
    ],
  };

  static Map<String, Object?> _local(List<CartLine> lines, DateTime now) =>
      <String, Object?>{
        'estimated_total_paise': CartTotals.of(lines).totalPaise,
        'captured_at': now.toUtc().toIso8601String(),
        'lines': <Map<String, Object?>>[
          for (final l in lines)
            <String, Object?>{
              'sku_id': l.item.skuId,
              'product_name': l.item.name,
              'pack_label': l.item.packLabel,
              'est_unit_price_paise': l.item.pricePaise,
            },
        ],
      };

  /// Queues the order; returns its id (the `client_order_id`).
  Future<String> place({
    required String farmerId,
    required String? storeId,
    required Fulfilment fulfilment,
    required List<CartLine> lines,
    String? paymentMode,
    String? notes,
    DateTime? now,
  }) async {
    if (lines.isEmpty) throw ArgumentError.value(lines, 'lines', 'empty');
    final id = _newId();
    await outbox.enqueueCreate(
      SyncEntities.order,
      id,
      createPayload(
        farmerId: farmerId,
        storeId: storeId,
        fulfilment: fulfilment,
        lines: lines,
        paymentMode: paymentMode,
        notes: notes,
      ),
      local: _local(lines, now ?? DateTime.now().toUtc()),
    );
    return id;
  }

  /// A57 "edit and resend" after `insufficient_stock` (or any rejection):
  /// the new lines are folded into the rejected create op (same `op_id`)
  /// and it is requeued; rejected payment ops for the order are requeued
  /// behind it (they failed because the order was not there).
  Future<void> resubmit(
    String orderId,
    List<CartLine> lines, {
    String? paymentMode,
    DateTime? now,
  }) async {
    final open = await _store.firstOpenOp(orderId);
    if (open == null || open.state != OutboxState.rejected.name) {
      throw StateError('order $orderId has no rejected op to resend');
    }
    final payload = SyncStore.payloadOf(open);
    final lineMaps = <Map<String, Object?>>[
      for (final l in lines)
        <String, Object?>{'sku_id': l.item.skuId, 'qty': l.qty},
    ];
    await db.transaction(() async {
      await _store.requeue(
        open.opId,
        payload: <String, Object?>{
          ...payload,
          'lines': lineMaps,
          'payment_mode': ?paymentMode,
        },
      );
      await _store.entities.merge(
        SyncEntities.order,
        orderId,
        <String, Object?>{
          'lines': lineMaps,
          'payment_mode': ?paymentMode,
          '_local': _local(lines, now ?? DateTime.now().toUtc()),
        },
        now: now ?? DateTime.now().toUtc(),
        dirty: true,
      );
      final payments = await (db.select(
        db.payments,
      )..where((t) => t.orderId.equals(orderId))).get();
      for (final p in payments) {
        final op = await _store.firstOpenOp(p.id);
        if (op != null && op.state == OutboxState.rejected.name) {
          await _store.requeue(op.opId);
        }
      }
    });
  }

  /// Drops a rejected order (and its queued payments) the officer gave up on.
  Future<void> discard(String orderId) async {
    await db.transaction(() async {
      for (final p in await (db.select(
        db.payments,
      )..where((t) => t.orderId.equals(orderId))).get()) {
        final op = await _store.firstOpenOp(p.id);
        if (op != null) await _store.discard(op.opId);
        await _store.entities.delete(SyncEntities.payment, p.id);
      }
      final op = await _store.firstOpenOp(orderId);
      if (op != null) await _store.discard(op.opId);
      await _store.entities.delete(SyncEntities.order, orderId);
    });
  }

  /// One order with lines and sync state.
  Future<OrderView?> order(String id) async {
    final row = await (db.select(
      db.orders,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final lines =
        await (db.select(db.orderLines)
              ..where((t) => t.orderId.equals(id))
              ..orderBy(<OrderClauseGenerator<$OrderLinesTable>>[
                (t) => OrderingTerm(expression: t.position),
              ]))
            .get();
    final open = await _store.firstOpenOp(id);
    return OrderView(
      order: row,
      lines: lines,
      opId: open?.opId,
      rejection: open != null && open.state == OutboxState.rejected.name
          ? SyncStore.errorOf(open)
          : null,
    );
  }

  /// [order] now and after every change.
  Stream<OrderView?> watchOrder(String id) => _watch(
    <TableInfo<Table, Object?>>[db.orders, db.orderLines, db.outboxTable],
    () => order(id),
  );

  /// Orders of a farmer (A22 Orders tab), newest first.
  Stream<List<OrderView>> watchFarmerOrders(String farmerId) => _watch(
    <TableInfo<Table, Object?>>[db.orders, db.orderLines, db.outboxTable],
    () => _list((t) => t.farmerId.equals(farmerId)),
  );

  /// Recent orders (Orders tab of the bottom nav), newest first.
  Stream<List<OrderView>> watchRecent({int limit = 50}) => _watch(
    <TableInfo<Table, Object?>>[db.orders, db.orderLines, db.outboxTable],
    () => _list(null, limit: limit),
  );

  Future<List<OrderView>> _list(
    Expression<bool> Function($OrdersTable t)? where, {
    int limit = 200,
  }) async {
    final q = db.select(db.orders)
      ..orderBy(<OrderClauseGenerator<$OrdersTable>>[
        (t) => OrderingTerm(expression: t.placedAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    if (where != null) q.where(where);
    final out = <OrderView>[];
    for (final row in await q.get()) {
      final view = await order(row.id);
      if (view != null) out.add(view);
    }
    return out;
  }

  Stream<T> _watch<T>(
    List<TableInfo<Table, Object?>> tables,
    Future<T> Function() load,
  ) async* {
    yield await load();
    await for (final _ in db.tableUpdates(
      TableUpdateQuery.onAllTables(tables),
    )) {
      yield await load();
    }
  }
}
