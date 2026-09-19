import 'package:flutter/foundation.dart' show immutable;

import '../db/app_database.dart';
import '../sync/sync_models.dart';
import '../widgets/payment_method_selector.dart' show PaymentMethod;

/// Wire payment modes (`PaymentMode`).
abstract final class PaymentModes {
  /// Dynamic UPI QR.
  static const String upiQr = 'upi_qr';

  /// Payment link by SMS / WhatsApp.
  static const String paymentLink = 'payment_link';

  /// Cash with receipt photo.
  static const String cash = 'cash';

  /// Card on the store terminal (store mode only).
  static const String cardTerminal = 'card_terminal';

  /// On the farmer's khata.
  static const String credit = 'credit';

  /// Wire value of a selector option.
  static String of(PaymentMethod m) => switch (m) {
    PaymentMethod.upiQr => upiQr,
    PaymentMethod.paymentLink => paymentLink,
    PaymentMethod.cash => cash,
    PaymentMethod.credit => credit,
  };

  /// Selector option of a wire value (card maps to cash for display).
  static PaymentMethod method(String mode) => switch (mode) {
    upiQr => PaymentMethod.upiQr,
    paymentLink => PaymentMethod.paymentLink,
    credit => PaymentMethod.credit,
    _ => PaymentMethod.cash,
  };

  /// Modes that need the provider online (`requires_network` offline).
  static const Set<String> online = <String>{upiQr, paymentLink};
}

/// Payment statuses (`PaymentStatus`) plus the device-only `queued`.
abstract final class PaymentStatuses {
  /// Device only: the create op is still in the outbox.
  static const String queued = 'queued';

  /// QR / link created, waiting.
  static const String created = 'created';

  /// Provider pending.
  static const String pending = 'pending';

  /// Cash waiting for the store's day close.
  static const String pendingReconciliation = 'pending_reconciliation';

  /// Paid.
  static const String paid = 'paid';

  /// Failed / expired.
  static const String failed = 'failed';

  /// Refunded.
  static const String refunded = 'refunded';

  /// Reconciled at the day close.
  static const String reconciled = 'reconciled';
}

/// How A59 groups a payment.
enum CollectionState {
  /// Still in the outbox (offline capture).
  waitingToSync,

  /// Cash waiting for the store's day close.
  pendingReconciliation,

  /// UPI / link not paid yet.
  waiting,

  /// Paid (or reconciled).
  paid,

  /// Put on the farmer's khata.
  onKhata,

  /// Credit beyond the limit: waiting for the cluster head (A56).
  approvalNeeded,

  /// Failed, expired or refunded.
  failed;

  /// Counts towards the A59 totals (money in hand, on its way or on khata).
  bool get counts =>
      this == waitingToSync ||
      this == pendingReconciliation ||
      this == paid ||
      this == onKhata;

  /// State of [row].
  static CollectionState of(PaymentRow row) {
    if (row.status == PaymentStatuses.queued || row.version == 0) {
      return waitingToSync;
    }
    if (row.mode == PaymentModes.credit &&
        row.status != PaymentStatuses.failed) {
      return onKhata;
    }
    return switch (row.status) {
      PaymentStatuses.pendingReconciliation => pendingReconciliation,
      PaymentStatuses.paid || PaymentStatuses.reconciled => paid,
      PaymentStatuses.failed || PaymentStatuses.refunded => failed,
      _ => waiting,
    };
  }
}

/// The farmer's limit situation of a blocked credit sale (A56), from the
/// 402 `credit_limit_exceeded` problem (`errors[0]`).
@immutable
class CreditBlock {
  /// Creates the block.
  const CreditBlock({
    required this.limitPaise,
    required this.balancePaise,
    required this.shortfallPaise,
    this.approvalRequestId,
  });

  /// Parses a rejection; null when it is not `credit_limit_exceeded`.
  static CreditBlock? fromError(SyncError? error) {
    if (error == null || error.code != 'credit_limit_exceeded') return null;
    final e = <String, Object?>{
      ...error.extra,
      if (error.errors.isNotEmpty) ...error.errors.first,
    };
    int n(String k) => (e[k] as num?)?.toInt() ?? 0;
    return CreditBlock(
      limitPaise: n('limit_paise'),
      balancePaise: n('balance_paise'),
      shortfallPaise: n('shortfall_paise'),
      approvalRequestId: e['approval_request_id'] as String?,
    );
  }

  /// The farmer's credit limit at the store.
  final int limitPaise;

  /// Khata balance at the store before the sale.
  final int balancePaise;

  /// How much the sale is over the limit.
  final int shortfallPaise;

  /// The approval request sent to the cluster head.
  final String? approvalRequestId;

  /// Limit left before the sale (never negative).
  int get headroomPaise {
    final left = limitPaise - balancePaise;
    return left < 0 ? 0 : left;
  }
}

/// A credit approval request as pulled from the change feed (ST-007,
/// `CreditApprovalOut`): `pending`, `approved`, `rejected` or `consumed`.
@immutable
class CreditApprovalState {
  /// Creates the state.
  const CreditApprovalState({
    required this.id,
    required this.status,
    this.decisionNote,
  });

  /// Parses the pulled row.
  factory CreditApprovalState.fromJson(Map<String, Object?> j) =>
      CreditApprovalState(
        id: '${j['id']}',
        status: (j['status'] as String?) ?? 'pending',
        decisionNote: j['decision_note'] as String?,
      );

  /// Request id.
  final String id;

  /// Wire status.
  final String status;

  /// The cluster head's note.
  final String? decisionNote;

  /// Approved (and not yet used by the sale).
  bool get approved => status == 'approved';

  /// Rejected by the cluster head.
  bool get rejected => status == 'rejected';

  /// Used by the sale it was approved for.
  bool get consumed => status == 'consumed';

  @override
  bool operator ==(Object other) =>
      other is CreditApprovalState &&
      other.id == id &&
      other.status == status &&
      other.decisionNote == decisionNote;

  @override
  int get hashCode => Object.hash(id, status, decisionNote);
}

/// A payment with its outbox state (A53–A56, A59).
@immutable
class PaymentView {
  /// Creates the view.
  const PaymentView({required this.payment, this.rejection, this.opId});

  /// The row.
  final PaymentRow payment;

  /// The server's rejection of the queued op, if any.
  final SyncError? rejection;

  /// Open outbox op id.
  final String? opId;

  /// A56: the credit sale is waiting for approval.
  CreditBlock? get creditBlock => CreditBlock.fromError(rejection);

  /// A59 grouping.
  CollectionState get state => creditBlock != null
      ? CollectionState.approvalNeeded
      : rejection != null
      ? CollectionState.failed
      : CollectionState.of(payment);

  @override
  bool operator ==(Object other) =>
      other is PaymentView &&
      other.payment == payment &&
      other.rejection == rejection &&
      other.opId == opId;

  @override
  int get hashCode => Object.hash(payment, rejection, opId);
}

/// A59 totals: per mode, of the payments that count as collected.
@immutable
class CollectionsSummary {
  /// Creates the summary.
  const CollectionsSummary({required this.items, required this.totalsByMode});

  /// Builds totals from [items]: only [CollectionState.counts] states.
  factory CollectionsSummary.of(List<PaymentView> items) {
    final totals = <String, int>{};
    for (final v in items) {
      if (!v.state.counts) continue;
      totals.update(
        v.payment.mode,
        (a) => a + v.payment.amountPaise,
        ifAbsent: () => v.payment.amountPaise,
      );
    }
    return CollectionsSummary(items: items, totalsByMode: totals);
  }

  /// Payments, newest first.
  final List<PaymentView> items;

  /// Amount per wire mode.
  final Map<String, int> totalsByMode;

  /// Money in hand or on its way (credit excluded: it is not collected).
  int get collectedPaise => totalsByMode.entries
      .where((e) => e.key != PaymentModes.credit)
      .fold(0, (a, e) => a + e.value);
}
