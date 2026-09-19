import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

import '../db/app_database.dart';
import '../farmers/photo_store.dart';
import '../sync/outbox.dart';
import '../sync/sync_models.dart';
import '../sync/sync_store.dart';
import 'payment_models.dart';
import 'payments_api.dart';
import 'upi_poller.dart';

/// What a payment is for: an order, or khata dues at a store.
@immutable
class PaymentTarget {
  /// An order payment (the server computes the amount due).
  const PaymentTarget.order({
    required String this.orderId,
    required this.farmerId,
    this.storeId,
  }) : duesAmountPaise = null;

  /// A dues payment of [duesAmountPaise] (partial allowed up to the
  /// balance) at [storeId].
  const PaymentTarget.dues({
    required String this.farmerId,
    required String this.storeId,
    required int this.duesAmountPaise,
  }) : orderId = null;

  /// Order paid for.
  final String? orderId;

  /// Farmer.
  final String? farmerId;

  /// Store (dues: required).
  final String? storeId;

  /// Dues amount (paise); null for an order.
  final int? duesAmountPaise;

  /// Dues rather than an order.
  bool get isDues => orderId == null;

  /// `PaymentCreate` target fields (+ the amount for dues).
  Map<String, Object?> get body => isDues
      ? <String, Object?>{
          'farmer_id': farmerId,
          'store_id': storeId,
          'amount_paise': duesAmountPaise,
        }
      : <String, Object?>{'order_id': orderId};
}

/// Outcome of an online UPI QR / payment link creation.
@immutable
class OnlinePaymentOutcome {
  /// Creates the outcome.
  const OnlinePaymentOutcome(this.result, {this.paymentId, this.code});

  /// What happened.
  final PaymentCallResult result;

  /// Local + server id of the payment on success.
  final String? paymentId;

  /// Problem code when refused.
  final String? code;
}

/// FA-021 payment collection on the officer's phone.
///
/// * Cash and credit are outbox `payment` creates (offline capture; the
///   payload is exactly `PaymentCreate`: no id, no amount for an order).
///   Cash carries the receipt photo as an upload placeholder; the op waits
///   for the upload's `blob_uri`.
/// * UPI QR and payment links need the provider: they are created online
///   (`POST /v1/payments`) and stored locally for A53 / A54 / A59.
class PaymentRepository {
  /// Creates the repository.
  PaymentRepository({
    required this.db,
    required this.outbox,
    required this.api,
    required this.photos,
    required String Function() ids,
    required DateTime Function() clock,
  }) : _newId = ids,
       _now = clock;

  /// The database.
  final AppDatabase db;

  /// The outbox.
  final Outbox outbox;

  /// Online calls.
  final PaymentsApi api;

  /// Receipt photo files.
  final PhotoStore photos;

  final String Function() _newId;
  final DateTime Function() _now;

  SyncStore get _store => outbox.store;

  /// A55: queues a cash collection with its processed receipt photo
  /// (NF-004 JPEG). [expectedPaise] is what the officer collected (shown
  /// until the server's amount arrives). Works offline.
  Future<String> collectCash(
    PaymentTarget target, {
    required Uint8List receiptJpeg,
    required int expectedPaise,
  }) async {
    final id = _newId();
    final path = await photos.save('receipt_$id.jpg', receiptJpeg);
    final uploadId = await outbox.enqueueUpload(
      filePath: path,
      bytes: receiptJpeg,
      purpose: 'receipt',
    );
    await outbox.enqueueCreate(SyncEntities.payment, id, <String, Object?>{
      ...target.body,
      'mode': PaymentModes.cash,
      'receipt_uri': Outbox.uploadRef(uploadId),
    }, local: _local(target, expectedPaise, receiptPath: path));
    return id;
  }

  /// A56: queues a credit sale of an order (the server's limit check
  /// decides; `credit_limit_exceeded` rejects the op and keeps the
  /// approval request).
  Future<String> collectCredit(
    PaymentTarget target, {
    required int expectedPaise,
  }) async {
    if (target.isDues) {
      throw ArgumentError.value(target, 'target', 'credit is for orders');
    }
    final id = _newId();
    await outbox.enqueueCreate(SyncEntities.payment, id, <String, Object?>{
      ...target.body,
      'mode': PaymentModes.credit,
    }, local: _local(target, expectedPaise));
    return id;
  }

  Map<String, Object?> _local(
    PaymentTarget target,
    int expectedPaise, {
    String? receiptPath,
  }) => <String, Object?>{
    'collected_at': _now().toIso8601String(),
    'expected_amount_paise': expectedPaise,
    'receipt_path': ?receiptPath,
    'farmer_id': target.farmerId,
    'store_id': target.storeId,
  };

  /// A53 / A54: creates a UPI QR or a payment link online and stores it.
  Future<OnlinePaymentOutcome> createOnline(
    PaymentTarget target, {
    required String mode,
    String channel = 'sms',
  }) async {
    final out = await api.create(<String, Object?>{
      ...target.body,
      'mode': mode,
      if (mode == PaymentModes.paymentLink) 'channel': channel,
    });
    if (out.result != PaymentCallResult.ok) {
      return OnlinePaymentOutcome(out.result, code: out.code);
    }
    final b = out.body;
    final id = '${b['payment_id']}';
    await _store.entities.write(
      SyncEntities.payment,
      id,
      <String, Object?>{
        'order_id': b['order_id'],
        'farmer_id': b['farmer_id'] ?? target.farmerId,
        'store_id': b['store_id'],
        'mode': b['mode'],
        'amount_paise': b['amount_paise'],
        'status': b['status'],
        'short_url': b['short_url'],
        'expires_at': b['expires_at'],
        '_local': <String, Object?>{
          'collected_at': _now().toIso8601String(),
          'qr_payload': b['qr_payload'],
          'sent_via': b['sent_via'],
        },
      },
      version: 1,
      dirty: false,
      now: _now(),
    );
    return OnlinePaymentOutcome(PaymentCallResult.ok, paymentId: id);
  }

  /// A53 poller over [api] for [paymentId].
  UpiPoller poller(
    String paymentId, {
    required DateTime? expiresAt,
    required Future<void> Function(Duration) sleep,
  }) => UpiPoller(
    fetch: () => api.status(paymentId),
    clock: _now,
    sleep: sleep,
    expiresAt: expiresAt,
  );

  /// Records a final poll state on the local row (the next pull brings
  /// the server's row; server wins).
  Future<void> applyPoll(String paymentId, UpiPollState state) async {
    final status = switch (state.phase) {
      UpiPollPhase.paid => PaymentStatuses.paid,
      UpiPollPhase.failed || UpiPollPhase.expired => PaymentStatuses.failed,
      UpiPollPhase.waiting => null,
    };
    if (status == null) return;
    await _store.entities.merge(
      SyncEntities.payment,
      paymentId,
      <String, Object?>{
        'status': status,
        if (state.phase == UpiPollPhase.paid)
          'paid_at': _now().toIso8601String(),
        'failure_reason': ?(state.phase == UpiPollPhase.expired
            ? 'expired'
            : state.failureReason),
      },
      now: _now(),
    );
  }

  /// A54 "Resend": a new link for the same target through [channel].
  Future<OnlinePaymentOutcome> resendLink(
    String paymentId, {
    required String channel,
  }) async {
    final row = await (db.select(
      db.payments,
    )..where((t) => t.id.equals(paymentId))).getSingleOrNull();
    if (row == null) {
      return const OnlinePaymentOutcome(
        PaymentCallResult.refused,
        code: 'not_found',
      );
    }
    return createOnline(
      row.orderId != null
          ? PaymentTarget.order(
              orderId: row.orderId!,
              farmerId: row.farmerId,
              storeId: row.storeId,
            )
          : PaymentTarget.dues(
              farmerId: row.farmerId ?? '',
              storeId: row.storeId ?? '',
              duesAmountPaise: row.amountPaise,
            ),
      mode: PaymentModes.paymentLink,
      channel: channel,
    );
  }

  /// A56 "Check approval" (manual fallback of the change-feed update):
  /// requeues the rejected credit op with `credit_approval_request_id` =
  /// the blocked sale's approval request, so an approved request lets the
  /// sale through once (a pending one is refreshed, not duplicated).
  /// Returns false when there is nothing to recheck.
  Future<bool> recheckCredit(String paymentId) async {
    final op = await _store.firstOpenOp(paymentId);
    if (op == null || op.state != OutboxState.rejected.name) return false;
    final approvalId = SyncStore.errorOf(op)?.approvalRequestId;
    await _store.requeue(
      op.opId,
      payload: approvalId == null
          ? null
          : <String, Object?>{
              ...SyncStore.payloadOf(op),
              creditApprovalRequestIdKey: approvalId,
            },
    );
    return true;
  }

  /// The pulled state of a credit approval request (ST-007; the change feed
  /// brings it to the officer who asked), or null before the first pull.
  Future<CreditApprovalState?> creditApproval(String approvalRequestId) async {
    final data = await _store.entities.readRef(
      SyncEntities.creditApprovalRequest,
      approvalRequestId,
    );
    return data == null ? null : CreditApprovalState.fromJson(data);
  }

  /// [creditApproval] now and after every pull.
  Stream<CreditApprovalState?> watchCreditApproval(String approvalRequestId) =>
      _watchTables(
        () => creditApproval(approvalRequestId),
        <TableInfo<Table, Object?>>[db.syncedRefs],
      );

  /// Drops a rejected payment op (e.g. the officer switched to cash).
  Future<void> discard(String paymentId) async {
    final op = await _store.firstOpenOp(paymentId);
    if (op != null) await _store.discard(op.opId);
    await _store.entities.delete(SyncEntities.payment, paymentId);
  }

  /// One payment with its outbox state.
  Future<PaymentView?> payment(String id) async {
    final row = await (db.select(
      db.payments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _view(row);
  }

  Future<PaymentView> _view(PaymentRow row) async {
    final open = await _store.firstOpenOp(row.id);
    return PaymentView(
      payment: row,
      opId: open?.opId,
      rejection: open != null && open.state == OutboxState.rejected.name
          ? SyncStore.errorOf(open)
          : null,
    );
  }

  /// [payment] now and after every change.
  Stream<PaymentView?> watchPayment(String id) => _watch(() => payment(id));

  /// Payments of an order, newest first.
  Stream<List<PaymentView>> watchOrderPayments(String orderId) =>
      _watch(() => _views((t) => t.orderId.equals(orderId)));

  /// A59: payments collected in [from, to) by [collectedBy] (or on this
  /// device when the server has not said who), newest first.
  Stream<CollectionsSummary> watchCollections(
    DateTime from,
    DateTime to, {
    String? collectedBy,
  }) => _watch(() async {
    final views = await _views(
      (t) =>
          t.collectedAt.isBiggerOrEqualValue(from) &
          t.collectedAt.isSmallerThanValue(to) &
          (collectedBy == null
              ? const Constant<bool>(true)
              : (t.collectedBy.isNull() | t.collectedBy.equals(collectedBy))),
    );
    return CollectionsSummary.of(views);
  });

  Future<List<PaymentView>> _views(
    Expression<bool> Function($PaymentsTable t) where,
  ) async {
    final rows =
        await (db.select(db.payments)
              ..where(where)
              ..orderBy(<OrderClauseGenerator<$PaymentsTable>>[
                (t) => OrderingTerm(
                  expression: t.collectedAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    return <PaymentView>[for (final r in rows) await _view(r)];
  }

  Stream<T> _watch<T>(Future<T> Function() load) => _watchTables(
    load,
    <TableInfo<Table, Object?>>[db.payments, db.outboxTable],
  );

  Stream<T> _watchTables<T>(
    Future<T> Function() load,
    List<TableInfo<Table, Object?>> tables,
  ) async* {
    yield await load();
    await for (final _ in db.tableUpdates(
      TableUpdateQuery.onAllTables(tables),
    )) {
      yield await load();
    }
  }
}
