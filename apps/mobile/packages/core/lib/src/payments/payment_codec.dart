import 'dart:convert';

import '../db/app_database.dart';

/// Wire <-> row mapping for the `payment` entity (used by `LocalEntities`;
/// FA-021, FA-025 "server wins for money").
///
/// The data map is the wire shape (`PaymentCreate` payload, `PaymentOut`
/// echo / feed row). Device-only fields sit under `_local`:
/// `receipt_path`, `collected_at`, `expected_amount_paise` (the amount the
/// device expects for an order payment, whose payload carries none: the
/// server computes it), `qr_payload`, `sent_via`, and `farmer_id` /
/// `store_id` of an order payment (its payload may only name the order).
abstract final class PaymentCodec {
  static const String _localKey = '_local';

  static const Set<String> _keys = <String>{
    'id',
    'order_id',
    'farmer_id',
    'store_id',
    'mode',
    'amount_paise',
    'status',
    'receipt_uri',
    'collected_by',
    'paid_at',
    'expires_at',
    'short_url',
    'failure_reason',
    'created_at',
    'version',
    'channel',
    'phone',
    _localKey,
  };

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toUtc() : null;

  /// Reads a payment as wire data, or null.
  static Future<Map<String, Object?>?> read(AppDatabase db, String id) async {
    final row = await (db.select(
      db.payments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : toData(row);
  }

  /// Wire data of a row.
  static Map<String, Object?> toData(PaymentRow r) => <String, Object?>{
    ...Map<String, Object?>.from(jsonDecode(r.extra) as Map),
    'id': r.id,
    'order_id': r.orderId,
    'farmer_id': r.farmerId,
    'store_id': r.storeId,
    'mode': r.mode,
    'amount_paise': r.amountPaise,
    'status': r.status,
    'receipt_uri': r.receiptUri,
    'collected_by': r.collectedBy,
    'paid_at': r.paidAt?.toUtc().toIso8601String(),
    'expires_at': r.expiresAt?.toUtc().toIso8601String(),
    'short_url': r.shortUrl,
    'failure_reason': r.failureReason,
    'version': r.version,
    _localKey: <String, Object?>{
      'receipt_path': r.receiptPath,
      'collected_at': r.collectedAt.toUtc().toIso8601String(),
      'qr_payload': r.qrPayload,
      'sent_via': r.sentVia,
    },
  };

  /// Writes the payment. A server row (no `_local`) keeps the device-only
  /// fields already stored.
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
      db.payments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    final local = data[_localKey] is Map
        ? Map<String, Object?>.from(data[_localKey]! as Map)
        : const <String, Object?>{};
    final extra = <String, Object?>{
      for (final e in data.entries)
        if (!_keys.contains(e.key)) e.key: e.value,
    };
    final amount = data['amount_paise'];
    await db
        .into(db.payments)
        .insertOnConflictUpdate(
          PaymentRow(
            id: id,
            orderId: data['order_id'] as String? ?? existing?.orderId,
            farmerId:
                data['farmer_id'] as String? ??
                existing?.farmerId ??
                local['farmer_id'] as String?,
            storeId:
                data['store_id'] as String? ??
                existing?.storeId ??
                local['store_id'] as String?,
            mode: (data['mode'] as String?) ?? existing?.mode ?? 'cash',
            amountPaise: amount is num
                ? amount.toInt()
                : ((local['expected_amount_paise'] as num?)?.toInt() ??
                      existing?.amountPaise ??
                      0),
            status: (data['status'] as String?) ?? existing?.status ?? 'queued',
            receiptUri: data['receipt_uri'] as String? ?? existing?.receiptUri,
            receiptPath:
                local['receipt_path'] as String? ?? existing?.receiptPath,
            collectedBy:
                data['collected_by'] as String? ?? existing?.collectedBy,
            collectedAt:
                _time(local['collected_at']) ??
                existing?.collectedAt ??
                _time(data['created_at']) ??
                now,
            paidAt: _time(data['paid_at']) ?? existing?.paidAt,
            expiresAt: _time(data['expires_at']) ?? existing?.expiresAt,
            shortUrl: data['short_url'] as String? ?? existing?.shortUrl,
            sentVia:
                local['sent_via'] as String? ??
                data['channel'] as String? ??
                existing?.sentVia,
            qrPayload: local['qr_payload'] as String? ?? existing?.qrPayload,
            failureReason:
                data['failure_reason'] as String? ?? existing?.failureReason,
            extra: jsonEncode(extra),
            version: version,
            updatedAt: now,
            dirty: dirty,
            deleted: deleted,
          ),
        );
  }

  /// Deletes the payment.
  static Future<void> delete(AppDatabase db, String id) =>
      (db.delete(db.payments)..where((t) => t.id.equals(id))).go();
}
