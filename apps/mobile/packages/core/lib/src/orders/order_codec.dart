import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Wire <-> row mapping for the `order` entity and its `order_line` rows
/// (used by `LocalEntities`; FA-020, FA-025 "server wins for money").
///
/// The data map is the wire shape (`OrderCreate` payload, `OrderDetailOut`
/// echo or `OrderOut` feed row). Device-only fields sit under `_local`:
/// `estimated_total_paise` and `lines` (`{sku_id, product_name, pack_label,
/// est_unit_price_paise}`) so names and estimates survive the server's
/// lines replacing the device's.
abstract final class OrderCodec {
  static const String _localKey = '_local';

  static const Set<String> _keys = <String>{
    'id',
    'farmer_id',
    'store_id',
    'status',
    'fulfilment',
    'payment_mode',
    'subtotal_paise',
    'tax_paise',
    'total_paise',
    'placed_at',
    'invoice_no',
    'invoice_id',
    'notes',
    'events',
    'lines',
    'version',
    'payments',
    'reservations',
    _localKey,
  };

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toUtc() : null;

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  static double _qty(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s) ?? 0,
    _ => 0,
  };

  /// Reads an order as wire data (lines included), or null.
  static Future<Map<String, Object?>?> read(AppDatabase db, String id) async {
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
    return toData(row, lines);
  }

  /// Wire data of a row and its lines.
  static Map<String, Object?> toData(OrderRow r, List<OrderLineRow> lines) =>
      <String, Object?>{
        ...Map<String, Object?>.from(jsonDecode(r.extra) as Map),
        'id': r.id,
        'farmer_id': r.farmerId,
        'store_id': r.storeId,
        'status': r.status,
        'fulfilment': r.fulfilment,
        'payment_mode': r.paymentMode,
        'subtotal_paise': r.subtotalPaise,
        'tax_paise': r.taxPaise,
        'total_paise': r.totalPaise,
        'placed_at': r.placedAt?.toUtc().toIso8601String(),
        'invoice_no': r.invoiceNo,
        'invoice_id': r.invoiceId,
        'notes': r.notes,
        'events': jsonDecode(r.events),
        'version': r.version,
        'lines': <Map<String, Object?>>[
          for (final l in lines)
            <String, Object?>{
              'id': l.id,
              'sku_id': l.skuId,
              'qty': l.qty,
              'unit_price_paise': l.unitPricePaise,
              'line_total_paise': l.lineTotalPaise,
              'label_claim_id': l.labelClaimId,
            },
        ],
        _localKey: <String, Object?>{
          'estimated_total_paise': r.estimatedTotalPaise,
          'lines': <Map<String, Object?>>[
            for (final l in lines)
              <String, Object?>{
                'sku_id': l.skuId,
                'product_name': l.productName,
                'pack_label': l.packLabel,
                'est_unit_price_paise': l.estimatedUnitPricePaise,
              },
          ],
        },
      };

  /// Writes the order (and, when `lines` is present, replaces its lines).
  static Future<void> write(
    AppDatabase db,
    String id,
    Map<String, Object?> data, {
    required int version,
    required bool dirty,
    required bool deleted,
    required DateTime now,
  }) async {
    final existing = await (db.select(
      db.orders,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    final existingLines = existing == null
        ? const <OrderLineRow>[]
        : await (db.select(
            db.orderLines,
          )..where((t) => t.orderId.equals(id))).get();
    final local = data[_localKey] is Map
        ? Map<String, Object?>.from(data[_localKey]! as Map)
        : null;
    // Labels / estimates per SKU: from the incoming local block, else from
    // the lines already stored (a server echo carries none).
    final labels = <String, Map<String, Object?>>{
      for (final l in existingLines)
        l.skuId: <String, Object?>{
          'product_name': l.productName,
          'pack_label': l.packLabel,
          'est_unit_price_paise': l.estimatedUnitPricePaise,
        },
      if (local?['lines'] is List)
        for (final l in local!['lines']! as List)
          if (l is Map) '${l['sku_id']}': Map<String, Object?>.from(l),
    };
    final extra = <String, Object?>{
      for (final e in data.entries)
        if (!_keys.contains(e.key)) e.key: e.value,
    };
    final eventsIn = data['events'];
    await db
        .into(db.orders)
        .insertOnConflictUpdate(
          OrderRow(
            id: id,
            farmerId: data['farmer_id'] as String? ?? existing?.farmerId,
            storeId: data['store_id'] as String? ?? existing?.storeId,
            status: (data['status'] as String?) ?? existing?.status ?? 'placed',
            fulfilment:
                (data['fulfilment'] as String?) ??
                existing?.fulfilment ??
                'pickup',
            paymentMode: data.containsKey('payment_mode')
                ? data['payment_mode'] as String?
                : existing?.paymentMode,
            subtotalPaise: _int(data['subtotal_paise']),
            taxPaise: _int(data['tax_paise']),
            totalPaise: _int(data['total_paise']),
            estimatedTotalPaise:
                _int(local?['estimated_total_paise']) ??
                existing?.estimatedTotalPaise ??
                0,
            placedAt:
                _time(data['placed_at']) ??
                existing?.placedAt ??
                _time(local?['captured_at']),
            invoiceNo: data['invoice_no'] as String? ?? existing?.invoiceNo,
            invoiceId: data['invoice_id'] as String? ?? existing?.invoiceId,
            notes: data['notes'] as String? ?? existing?.notes,
            events: eventsIn is List
                ? jsonEncode(eventsIn)
                : (existing?.events ?? '[]'),
            extra: jsonEncode(extra),
            version: version,
            updatedAt: now,
            dirty: dirty,
            deleted: deleted,
          ),
        );
    final lines = data['lines'];
    if (lines is! List) return;
    await (db.delete(db.orderLines)..where((t) => t.orderId.equals(id))).go();
    for (final (i, raw) in lines.indexed) {
      if (raw is! Map) continue;
      final l = Map<String, Object?>.from(raw);
      final skuId = '${l['sku_id']}';
      final label = labels[skuId] ?? const <String, Object?>{};
      await db
          .into(db.orderLines)
          .insertOnConflictUpdate(
            OrderLineRow(
              id: (l['id'] as String?) ?? '$id:$i',
              orderId: id,
              skuId: skuId,
              qty: _qty(l['qty']),
              unitPricePaise: _int(l['unit_price_paise']),
              lineTotalPaise: _int(l['line_total_paise']),
              estimatedUnitPricePaise: _int(label['est_unit_price_paise']) ?? 0,
              productName: (label['product_name'] as String?) ?? '',
              packLabel: (label['pack_label'] as String?) ?? '',
              labelClaimId: l['label_claim_id'] as String?,
              position: i,
            ),
          );
    }
  }

  /// A pulled `order_line` row (`OrderLineOut`): upserted by id, keeping
  /// the labels of a device line for the same SKU.
  static Future<void> writeLine(
    AppDatabase db,
    String id,
    Map<String, Object?> d,
  ) async {
    final orderId = (d['order_id'] as String?) ?? '';
    final skuId = '${d['sku_id']}';
    final siblings = await (db.select(
      db.orderLines,
    )..where((t) => t.orderId.equals(orderId))).get();
    final same = siblings.where((l) => l.skuId == skuId).firstOrNull;
    if (same != null && same.id != id) {
      await (db.delete(db.orderLines)..where((t) => t.id.equals(same.id))).go();
    }
    await db
        .into(db.orderLines)
        .insertOnConflictUpdate(
          OrderLineRow(
            id: id,
            orderId: orderId,
            skuId: skuId,
            qty: _qty(d['qty']),
            unitPricePaise: _int(d['unit_price_paise']),
            lineTotalPaise: _int(d['line_total_paise']),
            estimatedUnitPricePaise: same?.estimatedUnitPricePaise ?? 0,
            productName: same?.productName ?? '',
            packLabel: same?.packLabel ?? '',
            labelClaimId: d['label_claim_id'] as String?,
            position: same?.position ?? siblings.length,
          ),
        );
  }

  /// Deletes the order and its lines.
  static Future<void> delete(AppDatabase db, String id) async {
    await (db.delete(db.orderLines)..where((t) => t.orderId.equals(id))).go();
    await (db.delete(db.orders)..where((t) => t.id.equals(id))).go();
  }
}
