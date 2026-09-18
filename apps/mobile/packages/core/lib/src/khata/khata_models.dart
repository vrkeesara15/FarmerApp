import 'package:flutter/foundation.dart' show immutable;

/// Overdue ageing buckets (SPEC 5.2 "Credit overdue"), wire keys in order.
enum OverdueBucket {
  /// 1–30 days past due.
  d0to30('0_30'),

  /// 31–60 days.
  d31to60('31_60'),

  /// 61–90 days.
  d61to90('61_90'),

  /// Over 90 days.
  d90plus('90_plus');

  const OverdueBucket(this.wire);

  /// Key in `overdue_buckets`.
  final String wire;
}

/// One ledger row (`KhataEntryOut`).
@immutable
class KhataLine {
  /// Creates the row.
  const KhataLine({
    required this.id,
    required this.storeId,
    required this.isDebit,
    required this.amountPaise,
    required this.signedPaise,
    required this.refType,
    required this.createdAt,
    this.dueDate,
    this.harvestMonth,
    this.note,
    this.refId,
  });

  /// Parses the wire shape.
  factory KhataLine.fromJson(Map<String, Object?> j) {
    final amount = (j['amount_paise'] as num?)?.toInt() ?? 0;
    final isDebit = j['type'] == 'debit';
    return KhataLine(
      id: '${j['id']}',
      storeId: '${j['store_id']}',
      isDebit: isDebit,
      amountPaise: amount,
      signedPaise:
          (j['signed_paise'] as num?)?.toInt() ?? (isDebit ? amount : -amount),
      refType: (j['ref_type'] as String?) ?? '',
      refId: j['ref_id'] as String?,
      note: j['note'] as String?,
      dueDate: _date(j['due_date']),
      harvestMonth: _date(j['harvest_month']),
      createdAt: _time(j['created_at']) ?? DateTime.utc(1970),
    );
  }

  /// Entry id.
  final String id;

  /// Store.
  final String storeId;

  /// Sale on credit (else a payment / adjustment credit).
  final bool isDebit;

  /// Amount (positive).
  final int amountPaise;

  /// +amount for a debit, −amount for a credit.
  final int signedPaise;

  /// `order` | `payment` | `adjustment`.
  final String refType;

  /// Order / payment id.
  final String? refId;

  /// Note.
  final String? note;

  /// Due date of a debit (harvest-linked).
  final DateTime? dueDate;

  /// Harvest month the due date follows.
  final DateTime? harvestMonth;

  /// When it was posted (UTC).
  final DateTime createdAt;
}

/// A payment in the khata's payment history.
@immutable
class KhataPayment {
  /// Creates the payment.
  const KhataPayment({
    required this.id,
    required this.mode,
    required this.amountPaise,
    required this.status,
    this.paidAt,
    this.createdAt,
  });

  /// Parses `PaymentOut`.
  factory KhataPayment.fromJson(Map<String, Object?> j) => KhataPayment(
    id: '${j['id']}',
    mode: (j['mode'] as String?) ?? '',
    amountPaise: (j['amount_paise'] as num?)?.toInt() ?? 0,
    status: (j['status'] as String?) ?? '',
    paidAt: _time(j['paid_at']),
    createdAt: _time(j['created_at']),
  );

  /// Id.
  final String id;

  /// Mode.
  final String mode;

  /// Amount.
  final int amountPaise;

  /// Status.
  final String status;

  /// Paid at.
  final DateTime? paidAt;

  /// Created at.
  final DateTime? createdAt;
}

DateTime? _date(Object? v) {
  if (v is! String) return null;
  final d = DateTime.tryParse(v);
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

DateTime? _time(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

/// A58: the farmer's khata as last fetched (`KhataOut`, every page merged).
@immutable
class KhataView {
  /// Creates the view.
  const KhataView({
    required this.farmerId,
    required this.balancePaise,
    required this.overduePaise,
    required this.entries,
    required this.buckets,
    required this.asOf,
    this.nextDueDate,
    this.payments = const <KhataPayment>[],
    this.balancesByStore = const <String, int>{},
    this.limitsByStore = const <String, int>{},
  });

  /// Parses a merged `KhataOut` fetched at [asOf].
  factory KhataView.fromJson(Map<String, Object?> j, {required DateTime asOf}) {
    final buckets = j['overdue_buckets'] is Map
        ? Map<String, Object?>.from(j['overdue_buckets']! as Map)
        : const <String, Object?>{};
    List<Map<String, Object?>> list(String k) => <Map<String, Object?>>[
      for (final e in (j[k] as List?) ?? const <Object?>[])
        if (e is Map) Map<String, Object?>.from(e),
    ];
    return KhataView(
      farmerId: '${j['farmer_id']}',
      balancePaise: (j['balance_paise'] as num?)?.toInt() ?? 0,
      overduePaise: (j['overdue_paise'] as num?)?.toInt() ?? 0,
      nextDueDate: _date(j['next_due_date']),
      entries: <KhataLine>[
        for (final e in list('entries')) KhataLine.fromJson(e),
      ],
      payments: <KhataPayment>[
        for (final p in list('payment_history')) KhataPayment.fromJson(p),
      ],
      buckets: <OverdueBucket, int>{
        for (final b in OverdueBucket.values)
          b: (buckets[b.wire] as num?)?.toInt() ?? 0,
      },
      balancesByStore: <String, int>{
        for (final b in list('balances'))
          '${b['store_id']}': (b['balance_paise'] as num?)?.toInt() ?? 0,
      },
      limitsByStore: <String, int>{
        for (final l in list('credit_limits'))
          '${l['store_id']}': (l['limit_paise'] as num?)?.toInt() ?? 0,
      },
      asOf: asOf,
    );
  }

  /// Farmer.
  final String farmerId;

  /// Server balance: sum of the ledger (FA-022).
  final int balancePaise;

  /// Overdue amount.
  final int overduePaise;

  /// Earliest unpaid due date still ahead.
  final DateTime? nextDueDate;

  /// Ledger rows, newest first.
  final List<KhataLine> entries;

  /// Payment history, newest first.
  final List<KhataPayment> payments;

  /// Open debit amounts by days past due.
  final Map<OverdueBucket, int> buckets;

  /// Balance per store.
  final Map<String, int> balancesByStore;

  /// Credit limit per store.
  final Map<String, int> limitsByStore;

  /// When it was fetched (UTC).
  final DateTime asOf;

  /// FA-022 acceptance: the balance A58 shows is the sum of the entries it
  /// shows (every page is fetched, so this equals [balancePaise]).
  int get displayedBalancePaise => entries.fold(0, (a, e) => a + e.signedPaise);

  /// The store to collect dues at: the one with the largest balance.
  String? get collectStoreId {
    String? best;
    var max = 0;
    for (final e in balancesByStore.entries) {
      if (e.value > max) {
        max = e.value;
        best = e.key;
      }
    }
    return best;
  }

  /// Balance at [storeId].
  int balanceAt(String storeId) => balancesByStore[storeId] ?? 0;
}

/// The khata could not be fetched.
class KhataUnavailableException implements Exception {
  /// Creates the exception.
  const KhataUnavailableException([this.status = 0]);

  /// HTTP status (0 = no answer).
  final int status;

  @override
  String toString() => 'KhataUnavailableException($status)';
}
