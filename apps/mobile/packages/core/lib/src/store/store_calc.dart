/// Pure store-mode arithmetic: the GST preview (mirrors the server's
/// `invoices/gst.py` so the counter sees the same numbers before the sale),
/// cash denominations, day-close variance and stock form validation.
/// Integer paise only.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'store_models.dart';

/// `a / b` rounded half-up for non-negative integers.
int halfUpDiv(int a, int b) => (2 * a + b) ~/ (2 * b);

/// Local GST preview of a cart (S03). Intra-state (walk-in buyers and
/// farmers of the store's state) splits each line's tax into CGST + SGST at
/// half the rate, rounded half-up per component; inter-state is IGST. The
/// total is rounded half-up to the rupee. The server's invoice is the
/// authority; this preview uses the same rule.
@immutable
class GstPreview {
  /// Creates the preview.
  const GstPreview({
    required this.lines,
    required this.inter,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.roundOffPaise,
    required this.totalPaise,
  });

  /// Computes the preview of [cart].
  factory GstPreview.of(List<StoreCartLine> cart, {bool inter = false}) {
    final lines = <InvoiceLine>[];
    var sl = 0;
    for (final c in cart) {
      final taxable = c.taxablePaise;
      final rate = c.item.gstRateBp;
      final half = inter ? 0 : halfUpDiv(taxable * rate, 20000);
      final igst = inter ? halfUpDiv(taxable * rate, 10000) : 0;
      lines.add(
        InvoiceLine(
          sl: ++sl,
          description: '${c.item.name} ${c.item.packLabel}'.trim(),
          hsn: c.item.hsn ?? '',
          qty: c.qty.toDouble(),
          unitPricePaise: c.item.pricePaise,
          taxablePaise: taxable,
          gstRateBp: rate,
          cgstPaise: half,
          sgstPaise: half,
          igstPaise: igst,
        ),
      );
    }
    final taxable = lines.fold(0, (a, l) => a + l.taxablePaise);
    final cgst = lines.fold(0, (a, l) => a + l.cgstPaise);
    final sgst = lines.fold(0, (a, l) => a + l.sgstPaise);
    final igst = lines.fold(0, (a, l) => a + l.igstPaise);
    final exact = taxable + cgst + sgst + igst;
    final total = halfUpDiv(exact, 100) * 100;
    return GstPreview(
      lines: lines,
      inter: inter,
      taxablePaise: taxable,
      cgstPaise: cgst,
      sgstPaise: sgst,
      igstPaise: igst,
      roundOffPaise: total - exact,
      totalPaise: total,
    );
  }

  /// Lines with HSN and tax split.
  final List<InvoiceLine> lines;

  /// IGST instead of CGST + SGST.
  final bool inter;

  /// Taxable value.
  final int taxablePaise;

  /// CGST.
  final int cgstPaise;

  /// SGST.
  final int sgstPaise;

  /// IGST.
  final int igstPaise;

  /// Round-off.
  final int roundOffPaise;

  /// Total payable.
  final int totalPaise;

  /// Tax total.
  int get taxPaise => cgstPaise + sgstPaise + igstPaise;
}

/// `900` -> `9%`, `250` -> `2.5%`.
String gstRateLabel(int rateBp) {
  final whole = rateBp ~/ 100;
  final frac = rateBp % 100;
  if (frac == 0) return '$whole%';
  final f = frac.toString().padLeft(2, '0').replaceAll(RegExp(r'0+$'), '');
  return '$whole.$f%';
}

/// Cash denominations on the S10 helper, in paise. `coins` is entered as an
/// amount in rupees, the notes as counts.
const List<int> noteDenominationsPaise = <int>[
  50000,
  20000,
  10000,
  5000,
  2000,
  1000,
];

/// Total of a denomination count: `{50000: 3, 10000: 2}` notes plus
/// [coinsPaise].
int denominationTotal(Map<int, int> counts, {int coinsPaise = 0}) {
  var total = coinsPaise;
  counts.forEach((paise, n) => total += paise * n);
  return total;
}

/// Tenant default `day_close_variance_threshold_paise` (Rs 500); the server
/// applies the tenant's own value when it flags.
const int defaultVarianceThresholdPaise = 50000;

/// Counted minus expected.
int cashVariance({required int countedPaise, required int expectedPaise}) =>
    countedPaise - expectedPaise;

/// Whether |variance| exceeds [thresholdPaise] (auditors will be notified).
bool varianceOverThreshold(
  int variancePaise, {
  int thresholdPaise = defaultVarianceThresholdPaise,
}) => variancePaise.abs() > thresholdPaise;

/// Change due for a cash sale; negative when short.
int cashChange({required int tenderedPaise, required int totalPaise}) =>
    tenderedPaise - totalPaise;

/// Parses a rupee amount typed at the counter (`1,250.50`, `1250`) to paise.
int? parseRupees(String text) {
  final t = text.replaceAll(',', '').replaceAll('₹', '').trim();
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final rupees = int.parse(m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  return rupees * 100 + (frac.isEmpty ? 0 : int.parse(frac));
}

/// Problems with a form line (S07 / S08 / write-off).
enum LineProblem {
  /// Quantity missing or not positive.
  qty,

  /// More than the batch has available.
  overAvailable,

  /// Batch number missing.
  batchNo,

  /// Cost missing or negative.
  cost,

  /// Expiry in the past.
  expiry,

  /// No SKU / batch chosen.
  missing,
}

/// Validates a goods receipt line (S07).
Set<LineProblem> validateReceiptLine({
  required StoreItem? item,
  required String batchNo,
  required double? qty,
  required int? costPaise,
  required DateTime? expiry,
  required DateTime today,
}) => <LineProblem>{
  if (item == null) LineProblem.missing,
  if (batchNo.trim().isEmpty) LineProblem.batchNo,
  if (qty == null || qty <= 0) LineProblem.qty,
  if (costPaise == null || costPaise < 0) LineProblem.cost,
  if (expiry != null &&
      expiry.isBefore(DateTime(today.year, today.month, today.day)))
    LineProblem.expiry,
};

/// Validates a batch-quantity line against the batch's available stock
/// (S08 transfer, write-off): qty > 0 and qty <= available.
Set<LineProblem> validateBatchQty(StockBatch? batch, double? qty) =>
    <LineProblem>{
      if (batch == null) LineProblem.missing,
      if (qty == null || qty <= 0) LineProblem.qty,
      if (batch != null && qty != null && qty > batch.available)
        LineProblem.overAvailable,
    };

/// Validates all transfer lines; the same batch on two lines counts once
/// against its available quantity.
Map<int, Set<LineProblem>> validateTransfer(List<BatchQty?> lines) {
  final out = <int, Set<LineProblem>>{};
  final used = <String, double>{};
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final problems = validateBatchQty(l?.batch, l?.qty);
    if (l != null && problems.isEmpty) {
      final sum = (used[l.batch.id] ?? 0) + l.qty;
      used[l.batch.id] = sum;
      if (sum > l.batch.available) problems.add(LineProblem.overAvailable);
    }
    if (problems.isNotEmpty) out[i] = problems;
  }
  return out;
}

/// FEFO suggestion for [qty] units of a SKU from [batches]: earliest expiry
/// first, never an expired batch, never more than available.
List<BatchQty> suggestFefo(List<StockBatch> batches, double qty) {
  final out = <BatchQty>[];
  var left = qty;
  for (final b in fefo(batches)) {
    if (left <= 0) break;
    if ((b.daysToExpiry ?? 1) < 0 || b.available <= 0) continue;
    final take = left < b.available ? left : b.available;
    out.add(BatchQty(batch: b, qty: take));
    left -= take;
  }
  return out;
}

/// The IST business date of [nowUtc] (`YYYY-MM-DD`).
String istBusinessDate(DateTime nowUtc) =>
    isoDate(nowUtc.toUtc().add(const Duration(hours: 5, minutes: 30)));

/// The store manager's credit-limit cap (tenant default
/// `store_manager_max_credit_limit_paise`, ₹50,000); above it the server
/// answers `credit_limit_needs_cluster_head`.
const int storeManagerCreditCapPaise = 5000000;
