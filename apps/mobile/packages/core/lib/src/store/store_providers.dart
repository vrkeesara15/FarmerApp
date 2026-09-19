import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/open_database.dart';
import '../farmers/farmers_providers.dart';
import '../photo/photo_processor.dart';
import '../sync/sync_providers.dart';
import 'fake_store_api.dart';
import 'store_access.dart';
import 'store_api.dart';
import 'store_calc.dart';
import 'store_models.dart';

/// The store API; apps override it with [HttpStoreApi].
final Provider<StoreApi> storeApiProvider = Provider<StoreApi>(
  (ref) => FakeStoreApi(),
);

/// Opens a URL outside the app (the invoice PDF).
abstract interface class UrlOpener {
  /// Opens [url]; false when nothing could handle it.
  Future<bool> open(String url);
}

/// Reads a barcode with the camera.
abstract interface class BarcodeScanner {
  /// Opens the scanner; the code, or null when cancelled.
  Future<String?> scan(BuildContext context);
}

/// Records what it was asked to open (tests, previews).
class RecordingUrlOpener implements UrlOpener {
  /// URLs opened.
  final List<String> opened = <String>[];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

/// Returns queued codes, then null (tests, previews).
class FakeBarcodeScanner implements BarcodeScanner {
  /// Creates the scanner with [codes] to return in order.
  FakeBarcodeScanner([Iterable<String> codes = const <String>[]])
    : _codes = List<String>.of(codes);

  final List<String> _codes;

  /// Queues a code.
  void enqueue(String code) => _codes.add(code);

  @override
  Future<String?> scan(BuildContext context) async =>
      _codes.isEmpty ? null : _codes.removeAt(0);
}

/// Opens URLs; apps override it with a `url_launcher` implementation.
final Provider<UrlOpener> urlOpenerProvider = Provider<UrlOpener>(
  (ref) => RecordingUrlOpener(),
);

/// Barcode camera; apps override it with a `mobile_scanner` screen.
final Provider<BarcodeScanner> barcodeScannerProvider =
    Provider<BarcodeScanner>((ref) => FakeBarcodeScanner());

/// NF-004 pipeline for store photos (deposit slip, damage): 1280 px JPEG
/// q80. Tests override it with a pass-through.
final Provider<Future<Uint8List> Function(Uint8List raw)>
storePhotoProcessorProvider =
    Provider<Future<Uint8List> Function(Uint8List raw)>(
      (ref) =>
          (raw) async => (await PhotoProcessor.process(raw)).bytes,
    );

/// Stores the user can work in. Nothing is fetched for roles without
/// store mode, so every store provider below stays empty for them.
final FutureProvider<StoreResult<List<StoreBrief>>> storesProvider =
    FutureProvider<StoreResult<List<StoreBrief>>>((ref) async {
      if (!ref.watch(storeRoleProvider).hasStoreMode) {
        return const StoreResult.fail(StoreFailure(403, code: 'forbidden'));
      }
      return ref.watch(storeApiProvider).stores();
    });

/// The store picked in the S01 switcher (cluster heads, accountants).
class SelectedStoreNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Picks [storeId].
  void select(String storeId) => state = storeId;
}

/// Explicit store choice; null = the user's own store.
final NotifierProvider<SelectedStoreNotifier, String?> selectedStoreProvider =
    NotifierProvider<SelectedStoreNotifier, String?>(SelectedStoreNotifier.new);

/// The store the screens work on: the explicit choice, else the user's
/// `store_id`, else the first store the API lists.
final Provider<StoreBrief?> activeStoreProvider = Provider<StoreBrief?>((ref) {
  if (!ref.watch(storeRoleProvider).hasStoreMode) return null;
  final stores = ref.watch(storesProvider).value?.value ?? const <StoreBrief>[];
  final wanted =
      ref.watch(selectedStoreProvider) ??
      ref.watch(storeUserProvider).value?.storeId;
  for (final s in stores) {
    if (s.id == wanted) return s;
  }
  if (wanted != null) return StoreBrief(id: wanted, code: '', name: '');
  return stores.isEmpty ? null : stores.first;
});

/// Today's IST business date.
final Provider<String> storeTodayProvider = Provider<String>(
  (ref) => istBusinessDate(ref.watch(clockProvider)()),
);

const StoreFailure _noStore = StoreFailure(404, code: 'no_store');

/// S01 / S10 day summary for the active store, today.
final FutureProvider<StoreResult<DaySummary>> daySummaryProvider =
    FutureProvider.autoDispose<StoreResult<DaySummary>>((ref) async {
      final store = ref.watch(activeStoreProvider);
      if (store == null) return const StoreResult.fail(_noStore);
      return ref
          .watch(storeApiProvider)
          .daySummary(store.id, date: ref.watch(storeTodayProvider));
    });

/// S05 queue.
final FutureProvider<StoreResult<List<QueueOrder>>> orderQueueProvider =
    FutureProvider.autoDispose<StoreResult<List<QueueOrder>>>((ref) async {
      final store = ref.watch(activeStoreProvider);
      if (store == null) return const StoreResult.fail(_noStore);
      return ref.watch(storeApiProvider).orderQueue(store.id);
    });

/// Catalogue priced for the active store.
final FutureProvider<StoreResult<List<StoreItem>>> storeCatalogProvider =
    FutureProvider.autoDispose<StoreResult<List<StoreItem>>>((ref) async {
      final store = ref.watch(activeStoreProvider);
      if (store == null) return const StoreResult.fail(_noStore);
      return ref.watch(storeApiProvider).catalog(store.id);
    });

/// S06 rows (batches joined with the catalogue).
final FutureProvider<StoreResult<List<StockRow>>> stockRowsProvider =
    FutureProvider.autoDispose<StoreResult<List<StockRow>>>((ref) async {
      final store = ref.watch(activeStoreProvider);
      if (store == null) return const StoreResult.fail(_noStore);
      final api = ref.watch(storeApiProvider);
      final batches = await api.stock(store.id);
      if (!batches.ok) return StoreResult.fail(batches.failure!);
      final catalog = await ref.watch(storeCatalogProvider.future);
      final index = <String, StoreItem>{
        for (final i in catalog.value ?? const <StoreItem>[]) i.skuId: i,
      };
      return StoreResult.ok(stockRows(batches.value!, index));
    });

/// S08 destinations for stock of the active store
/// (`GET /v1/stock/transfer-destinations`): a store manager's cluster,
/// nearest first. Nothing is fetched for roles that cannot move stock.
final FutureProvider<StoreResult<List<TransferDestination>>>
transferDestinationsProvider =
    FutureProvider.autoDispose<StoreResult<List<TransferDestination>>>((
      ref,
    ) async {
      if (!ref.watch(storeRoleProvider).canMoveStock) {
        return const StoreResult.fail(StoreFailure(403, code: 'forbidden'));
      }
      final store = ref.watch(activeStoreProvider);
      if (store == null) return const StoreResult.fail(_noStore);
      return ref
          .watch(storeApiProvider)
          .transferDestinations(fromStoreId: store.id);
    });

/// S09 pending approvals.
final FutureProvider<StoreResult<List<CreditApproval>>>
creditApprovalsProvider =
    FutureProvider.autoDispose<StoreResult<List<CreditApproval>>>((ref) async {
      if (!ref.watch(storeRoleProvider).hasStoreMode) {
        return const StoreResult.fail(StoreFailure(403, code: 'forbidden'));
      }
      return ref.watch(storeApiProvider).creditApprovals();
    });

/// Farmer names on this device (queue and approvals show a name when the
/// farmer is known locally; otherwise a short id).
final FutureProvider<Map<String, String>> storeFarmerNamesProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
      final db = ref.watch(appDatabaseProvider);
      final rows = await db.select(db.farmers).get();
      return <String, String>{for (final r in rows) r.id: r.name};
    });

// --------------------------------------------------------------- POS (S02/S03)

/// A buyer picked by phone on S02.
class PosBuyer {
  /// Creates the buyer.
  const PosBuyer({required this.phone, this.farmerId, this.name});

  /// 10 digits.
  final String phone;

  /// Local farmer, when found.
  final String? farmerId;

  /// Local farmer name.
  final String? name;

  /// Known farmer (else a buyer by phone only).
  bool get known => farmerId != null;
}

/// Outcome of the last scan / code entry.
enum ScanOutcome {
  /// Added to the cart.
  added,

  /// No SKU with that barcode.
  notFound,

  /// Could not reach the server.
  offline,
}

/// Where checkout is.
enum CheckoutPhase {
  /// Choosing mode / entering amounts.
  editing,

  /// Sale request in flight.
  submitting,

  /// No network: the sale cannot be completed; the cart is kept.
  offline,

  /// Card reference missing.
  referenceRequired,

  /// Cash tendered below the total.
  cashShort,

  /// UPI QR shown; polling.
  awaitingUpi,

  /// UPI failed / expired; a new QR can be shown.
  upiFailed,

  /// Credit beyond the limit: approval needed (ST-007); the cart is kept.
  approvalNeeded,

  /// Any other server refusal.
  failed,

  /// Sale complete; S04 next.
  done,
}

/// Where the S03 server preview (`POST /v1/stores/{id}/pos/preview`) is.
enum PreviewStatus {
  /// Nothing to preview (empty cart).
  idle,

  /// Waiting for the debounce / the request.
  loading,

  /// The server's preview is shown.
  ready,

  /// No network: the local estimate is shown, labelled.
  offline,

  /// The server refused the preview (e.g. unknown buyer): the local
  /// estimate is shown, labelled.
  unavailable,
}

/// The last "check approval" of a blocked credit sale (ST-007).
enum ApprovalCheck {
  /// Still waiting for the cluster head.
  pending,

  /// The cluster head rejected the request.
  rejected,

  /// Could not reach the server.
  offline,
}

/// POS state.
class PosState {
  /// Creates the state.
  const PosState({
    this.lines = const <StoreCartLine>[],
    this.query = '',
    this.category,
    this.buyer,
    this.scan,
    this.scannedCode,
    this.mode,
    this.cardReference = '',
    this.tenderedPaise,
    this.phase = CheckoutPhase.editing,
    this.sale,
    this.upiPayment,
    this.failure,
    this.serverPreview,
    this.previewStatus = PreviewStatus.idle,
    this.approvalRequestId,
    this.approvalCheck,
  });

  /// Cart.
  final List<StoreCartLine> lines;

  /// Product search.
  final String query;

  /// Category filter.
  final String? category;

  /// Buyer (null = walk-in).
  final PosBuyer? buyer;

  /// Last scan outcome.
  final ScanOutcome? scan;

  /// Last scanned / entered code.
  final String? scannedCode;

  /// Payment mode.
  final SaleMode? mode;

  /// Card terminal reference.
  final String cardReference;

  /// Cash tendered.
  final int? tenderedPaise;

  /// Checkout phase.
  final CheckoutPhase phase;

  /// Completed sale (invoice + payment).
  final PosSaleResult? sale;

  /// The UPI payment being polled.
  final PaymentCreated? upiPayment;

  /// The last failure.
  final StoreFailure? failure;

  /// The server's invoice preview of the current cart and buyer.
  final GstPreview? serverPreview;

  /// Where the server preview is.
  final PreviewStatus previewStatus;

  /// ST-007: the approval request of the last blocked credit sale, kept with
  /// the cart; a credit retry sends it as `credit_approval_request_id`.
  final String? approvalRequestId;

  /// Result of the last [PosNotifier.checkApproval].
  final ApprovalCheck? approvalCheck;

  /// Items in the cart.
  int get itemCount => lines.fold(0, (a, l) => a + l.qty);

  /// Local GST estimate of the cart (offline fallback only).
  GstPreview get estimate => GstPreview.of(lines);

  /// What S03 shows and cash is checked against: the server's preview when
  /// it is ready, else the local estimate ([GstPreview.estimate] = true).
  GstPreview get preview => serverPreview ?? estimate;

  /// Change for a cash sale (against the invoice once issued).
  int? get changePaise {
    final t = tenderedPaise;
    if (t == null) return null;
    return cashChange(
      tenderedPaise: t,
      totalPaise: sale?.invoice.totalPaise ?? preview.totalPaise,
    );
  }

  /// Copy.
  PosState copyWith({
    List<StoreCartLine>? lines,
    String? query,
    String? category,
    bool clearCategory = false,
    PosBuyer? buyer,
    bool clearBuyer = false,
    ScanOutcome? scan,
    String? scannedCode,
    bool clearScan = false,
    SaleMode? mode,
    String? cardReference,
    int? tenderedPaise,
    bool clearTendered = false,
    CheckoutPhase? phase,
    PosSaleResult? sale,
    PaymentCreated? upiPayment,
    StoreFailure? failure,
    bool clearFailure = false,
    GstPreview? serverPreview,
    bool clearServerPreview = false,
    PreviewStatus? previewStatus,
    String? approvalRequestId,
    ApprovalCheck? approvalCheck,
    bool clearApprovalCheck = false,
  }) => PosState(
    lines: lines ?? this.lines,
    query: query ?? this.query,
    category: clearCategory ? null : (category ?? this.category),
    buyer: clearBuyer ? null : (buyer ?? this.buyer),
    scan: clearScan ? null : (scan ?? this.scan),
    scannedCode: clearScan ? null : (scannedCode ?? this.scannedCode),
    mode: mode ?? this.mode,
    cardReference: cardReference ?? this.cardReference,
    tenderedPaise: clearTendered ? null : (tenderedPaise ?? this.tenderedPaise),
    phase: phase ?? this.phase,
    sale: sale ?? this.sale,
    upiPayment: upiPayment ?? this.upiPayment,
    failure: clearFailure ? null : (failure ?? this.failure),
    serverPreview: clearServerPreview
        ? null
        : (serverPreview ?? this.serverPreview),
    previewStatus: previewStatus ?? this.previewStatus,
    approvalRequestId: approvalRequestId ?? this.approvalRequestId,
    approvalCheck: clearApprovalCheck
        ? null
        : (approvalCheck ?? this.approvalCheck),
  );
}

/// How often S03 polls a UPI payment.
const Duration upiPollInterval = Duration(seconds: 3);

/// Quiet time after a cart / buyer change before the server preview is
/// asked for.
const Duration posPreviewDebounce = Duration(milliseconds: 400);

/// S02 / S03 cart and checkout.
class PosNotifier extends Notifier<PosState> {
  Timer? _poll;
  Timer? _previewTimer;
  int _previewSeq = 0;

  @override
  PosState build() {
    ref.onDispose(() {
      _poll?.cancel();
      _previewTimer?.cancel();
    });
    return const PosState();
  }

  StoreApi get _api => ref.read(storeApiProvider);

  PosSaleRequest _request(SaleMode mode) {
    final buyer = state.buyer;
    return PosSaleRequest(
      lines: state.lines,
      mode: mode,
      farmerId: buyer?.farmerId,
      farmerPhone: buyer == null ? null : '+91${buyer.phone}',
      referenceNote: mode == SaleMode.card ? state.cardReference.trim() : null,
      creditApprovalRequestId: mode == SaleMode.credit
          ? state.approvalRequestId
          : null,
    );
  }

  /// The cart or the buyer changed: the server preview is stale; ask again
  /// after [posPreviewDebounce].
  void _cartChanged() {
    _previewTimer?.cancel();
    _previewSeq += 1;
    if (state.lines.isEmpty) {
      state = state.copyWith(
        clearServerPreview: true,
        previewStatus: PreviewStatus.idle,
      );
      return;
    }
    state = state.copyWith(
      clearServerPreview: true,
      previewStatus: PreviewStatus.loading,
    );
    _previewTimer = Timer(posPreviewDebounce, refreshPreview);
  }

  /// Asks the server for the invoice preview of the cart now (S03 opens it,
  /// the debounce calls it). Offline or refused: the local estimate stays,
  /// labelled; the sale itself is always priced by the server.
  Future<PreviewStatus> refreshPreview() async {
    _previewTimer?.cancel();
    final seq = ++_previewSeq;
    if (state.lines.isEmpty) {
      state = state.copyWith(
        clearServerPreview: true,
        previewStatus: PreviewStatus.idle,
      );
      return PreviewStatus.idle;
    }
    final store = ref.read(activeStoreProvider);
    if (store == null) return _previewDone(seq, PreviewStatus.unavailable);
    if (state.previewStatus != PreviewStatus.loading) {
      state = state.copyWith(previewStatus: PreviewStatus.loading);
    }
    if (!await ref.read(connectivityMonitorProvider).isOnline()) {
      return _previewDone(seq, PreviewStatus.offline);
    }
    if (!ref.mounted || seq != _previewSeq) return PreviewStatus.loading;
    // Totals do not depend on the payment mode; a mode the server would
    // refuse for this buyer (credit for a walk-in) is previewed as cash.
    final mode = state.mode;
    final previewMode =
        mode == null || (mode == SaleMode.credit && state.buyer?.known != true)
        ? SaleMode.cash
        : mode;
    final result = await _api.posPreview(store.id, _request(previewMode));
    if (!ref.mounted || seq != _previewSeq) return PreviewStatus.loading;
    if (!result.ok) {
      return _previewDone(
        seq,
        result.failure!.isOffline
            ? PreviewStatus.offline
            : PreviewStatus.unavailable,
      );
    }
    state = state.copyWith(
      serverPreview: result.value,
      previewStatus: PreviewStatus.ready,
    );
    return PreviewStatus.ready;
  }

  PreviewStatus _previewDone(int seq, PreviewStatus status) {
    if (ref.mounted && seq == _previewSeq) {
      state = state.copyWith(clearServerPreview: true, previewStatus: status);
    }
    return status;
  }

  /// Adds one pack of [item].
  void add(StoreItem item) {
    final lines = <StoreCartLine>[...state.lines];
    final i = lines.indexWhere((l) => l.item.skuId == item.skuId);
    if (i < 0) {
      lines.add(StoreCartLine(item: item, qty: 1));
    } else {
      lines[i] = lines[i].withQty(lines[i].qty + 1);
    }
    state = state.copyWith(lines: lines, phase: CheckoutPhase.editing);
    _cartChanged();
  }

  /// Sets the quantity of [skuId]; 0 removes the line.
  void setQty(String skuId, int qty) {
    final lines = <StoreCartLine>[
      for (final l in state.lines)
        if (l.item.skuId != skuId) l else if (qty > 0) l.withQty(qty),
    ];
    state = state.copyWith(lines: lines, phase: CheckoutPhase.editing);
    _cartChanged();
  }

  /// Search text.
  void setQuery(String q) => state = state.copyWith(query: q);

  /// Category filter (null = all).
  void setCategory(String? c) => c == null
      ? state = state.copyWith(clearCategory: true)
      : state = state.copyWith(category: c);

  /// Barcode from the camera or typed: found = one pack added.
  Future<ScanOutcome> scan(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return ScanOutcome.notFound;
    final store = ref.read(activeStoreProvider);
    final result = store == null
        ? const StoreResult<StoreItem>.fail(StoreFailure(404))
        : await _api.barcode(trimmed, store.id);
    if (!ref.mounted) return ScanOutcome.offline;
    final outcome = result.ok
        ? ScanOutcome.added
        : (result.failure!.isOffline
              ? ScanOutcome.offline
              : ScanOutcome.notFound);
    if (result.ok) add(result.value!);
    state = state.copyWith(scan: outcome, scannedCode: trimmed);
    return outcome;
  }

  /// Clears the scan message.
  void clearScan() => state = state.copyWith(clearScan: true);

  /// Farmer lookup by a 10-digit phone in the local farmer table; unknown
  /// numbers are still sent (`farmer_phone`) so the server can match them.
  Future<PosBuyer?> lookupBuyer(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) return null;
    final farmer = await ref
        .read(farmerRepositoryProvider)
        .findByPhone('+91$digits');
    if (!ref.mounted) return null;
    final buyer = PosBuyer(
      phone: digits,
      farmerId: farmer?.id,
      name: farmer?.name,
    );
    state = state.copyWith(buyer: buyer);
    _cartChanged();
    return buyer;
  }

  /// Walk-in buyer.
  void clearBuyer() {
    state = state.copyWith(clearBuyer: true);
    _cartChanged();
  }

  /// Payment mode.
  void setMode(SaleMode mode) => state = state.copyWith(
    mode: mode,
    phase: CheckoutPhase.editing,
    clearFailure: true,
  );

  /// Card reference.
  void setCardReference(String ref) =>
      state = state.copyWith(cardReference: ref, phase: CheckoutPhase.editing);

  /// Cash tendered (null clears).
  void setTendered(int? paise) => paise == null
      ? state = state.copyWith(
          clearTendered: true,
          phase: CheckoutPhase.editing,
        )
      : state = state.copyWith(
          tenderedPaise: paise,
          phase: CheckoutPhase.editing,
        );

  /// Confirms the sale. The network is required: the server prices, taxes
  /// and numbers the invoice. Offline or refused sales keep the cart.
  Future<CheckoutPhase> confirm() async {
    final mode = state.mode;
    if (mode == null || state.lines.isEmpty) return state.phase;
    if (mode == SaleMode.card && state.cardReference.trim().isEmpty) {
      return _set(CheckoutPhase.referenceRequired);
    }
    if (mode == SaleMode.cash &&
        (state.tenderedPaise ?? 0) < state.preview.totalPaise) {
      return _set(CheckoutPhase.cashShort);
    }
    if (mode == SaleMode.credit && state.buyer?.known != true) {
      return _set(
        CheckoutPhase.failed,
        const StoreFailure(422, code: 'farmer_required'),
      );
    }
    final store = ref.read(activeStoreProvider);
    if (store == null) return _set(CheckoutPhase.failed, _noStore);
    if (!await ref.read(connectivityMonitorProvider).isOnline()) {
      if (!ref.mounted) return CheckoutPhase.offline;
      return _set(CheckoutPhase.offline, StoreFailure.offline);
    }
    state = state.copyWith(
      phase: CheckoutPhase.submitting,
      clearFailure: true,
      clearApprovalCheck: true,
    );
    final result = await _api.posSale(store.id, _request(mode));
    if (!ref.mounted) return CheckoutPhase.failed;
    if (!result.ok) {
      final f = result.failure!;
      if (f.isOffline) return _set(CheckoutPhase.offline, f);
      if (f.code == 'credit_limit_exceeded') {
        // Keep the request with the cart: once approved, the retry names it.
        state = state.copyWith(
          approvalRequestId: f.body['approval_request_id'] as String?,
        );
        return _set(CheckoutPhase.approvalNeeded, f);
      }
      if (f.code == 'reference_required') {
        return _set(CheckoutPhase.referenceRequired, f);
      }
      return _set(CheckoutPhase.failed, f);
    }
    final sale = result.value!;
    if (mode == SaleMode.upiQr && !sale.payment.settled) {
      state = state.copyWith(
        sale: sale,
        upiPayment: sale.payment,
        phase: CheckoutPhase.awaitingUpi,
      );
      _startPolling();
      return CheckoutPhase.awaitingUpi;
    }
    state = state.copyWith(sale: sale, phase: CheckoutPhase.done);
    return CheckoutPhase.done;
  }

  CheckoutPhase _set(CheckoutPhase phase, [StoreFailure? failure]) {
    state = failure == null
        ? state.copyWith(phase: phase, clearFailure: true)
        : state.copyWith(phase: phase, failure: failure);
    return phase;
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(upiPollInterval, (_) => pollUpi());
  }

  /// One poll of the UPI payment (also driven by the timer).
  Future<PaymentPollState?> pollUpi() async {
    final payment = state.upiPayment;
    if (payment == null || state.phase != CheckoutPhase.awaitingUpi) {
      return null;
    }
    final result = await _api.payment(payment.paymentId);
    if (!ref.mounted || !result.ok) return null;
    final s = result.value!.state;
    if (s == PaymentPollState.paid) {
      _poll?.cancel();
      state = state.copyWith(phase: CheckoutPhase.done);
    } else if (s == PaymentPollState.failed) {
      _poll?.cancel();
      state = state.copyWith(phase: CheckoutPhase.upiFailed);
    }
    return s;
  }

  /// A new QR for the same order after a failure.
  Future<void> retryUpi() async {
    final orderId = state.sale?.orderId;
    if (orderId == null) return;
    final result = await _api.newUpiQr(orderId);
    if (!ref.mounted) return;
    if (!result.ok) {
      _set(
        result.failure!.isOffline
            ? CheckoutPhase.upiFailed
            : CheckoutPhase.failed,
        result.failure,
      );
      return;
    }
    state = state.copyWith(
      upiPayment: result.value,
      phase: CheckoutPhase.awaitingUpi,
      clearFailure: true,
    );
    _startPolling();
  }

  /// ST-007 "Check approval": when the cluster head approved the kept
  /// request, the credit sale is retried with it (`credit_approval_request_id`);
  /// otherwise the check says pending / rejected. The cart is kept.
  Future<ApprovalCheck?> checkApproval() async {
    final id = state.approvalRequestId;
    if (id == null || state.phase != CheckoutPhase.approvalNeeded) return null;
    final farmerId = state.buyer?.farmerId;
    final approved = await _api.creditApprovals(
      status: 'approved',
      farmerId: farmerId,
    );
    if (!ref.mounted) return null;
    if (approved.ok && approved.value!.any((a) => a.id == id)) {
      await confirm();
      return null;
    }
    var check = ApprovalCheck.offline;
    if (approved.ok) {
      final rejected = await _api.creditApprovals(
        status: 'rejected',
        farmerId: farmerId,
      );
      if (!ref.mounted) return null;
      check = !rejected.ok
          ? ApprovalCheck.offline
          : rejected.value!.any((a) => a.id == id)
          ? ApprovalCheck.rejected
          : ApprovalCheck.pending;
    }
    state = state.copyWith(approvalCheck: check);
    return check;
  }

  /// Back to editing (after offline / approval / failure), cart kept.
  void backToEditing() => state = state.copyWith(
    phase: CheckoutPhase.editing,
    clearFailure: true,
    clearApprovalCheck: true,
  );

  /// Starts the next sale.
  void newSale() {
    _poll?.cancel();
    _previewTimer?.cancel();
    _previewSeq += 1;
    state = const PosState();
  }
}

/// S02 / S03 state.
final NotifierProvider<PosNotifier, PosState> posProvider =
    NotifierProvider<PosNotifier, PosState>(PosNotifier.new);

// -------------------------------------------------------------- Day close (S10)

/// S10 phase.
enum DayClosePhase {
  /// Counting.
  editing,

  /// Photo upload / close request in flight.
  submitting,

  /// Counted cash but no deposit slip photo.
  slipRequired,

  /// Closed now (summary shown).
  closed,

  /// Already closed today (409 `day_already_closed`).
  alreadyClosed,

  /// No network.
  offline,

  /// Other refusal.
  failed,
}

/// S10 state.
class DayCloseState {
  /// Creates the state.
  const DayCloseState({
    this.counts = const <int, int>{},
    this.coinsPaise = 0,
    this.notes = '',
    this.slip,
    this.slipUri,
    this.phase = DayClosePhase.editing,
    this.result,
    this.failure,
  });

  /// Notes by denomination (paise -> count).
  final Map<int, int> counts;

  /// Coins total.
  final int coinsPaise;

  /// Notes.
  final String notes;

  /// Processed deposit slip photo.
  final Uint8List? slip;

  /// Uploaded slip blob.
  final String? slipUri;

  /// Phase.
  final DayClosePhase phase;

  /// The close.
  final DayClose? result;

  /// Last failure.
  final StoreFailure? failure;

  /// Counted total.
  int get countedPaise => denominationTotal(counts, coinsPaise: coinsPaise);

  /// Copy.
  DayCloseState copyWith({
    Map<int, int>? counts,
    int? coinsPaise,
    String? notes,
    Uint8List? slip,
    String? slipUri,
    bool clearSlipUri = false,
    DayClosePhase? phase,
    DayClose? result,
    StoreFailure? failure,
  }) => DayCloseState(
    counts: counts ?? this.counts,
    coinsPaise: coinsPaise ?? this.coinsPaise,
    notes: notes ?? this.notes,
    slip: slip ?? this.slip,
    slipUri: clearSlipUri ? null : (slipUri ?? this.slipUri),
    phase: phase ?? this.phase,
    result: result ?? this.result,
    failure: failure,
  );
}

/// S10 cash count and close.
class DayCloseNotifier extends Notifier<DayCloseState> {
  @override
  DayCloseState build() => const DayCloseState();

  /// Count of notes of [denominationPaise].
  void setCount(int denominationPaise, int count) => state = state.copyWith(
    counts: <int, int>{
      ...state.counts,
      denominationPaise: count < 0 ? 0 : count,
    },
    phase: DayClosePhase.editing,
  );

  /// Coins total.
  void setCoins(int paise) => state = state.copyWith(
    coinsPaise: paise < 0 ? 0 : paise,
    phase: DayClosePhase.editing,
  );

  /// Notes.
  void setNotes(String notes) => state = state.copyWith(notes: notes);

  /// In-app camera -> NF-004 pipeline; the upload happens on submit.
  Future<bool> captureSlip() async {
    final raw = await ref.read(cameraSourceProvider).capture();
    if (raw == null || !ref.mounted) return false;
    final processed = await ref.read(storePhotoProcessorProvider)(raw);
    if (!ref.mounted) return false;
    state = state.copyWith(
      slip: processed,
      clearSlipUri: true,
      phase: DayClosePhase.editing,
    );
    return true;
  }

  /// Uploads the slip (once) and closes the day.
  Future<DayClosePhase> submit() async {
    final store = ref.read(activeStoreProvider);
    if (store == null) return state.phase;
    if (state.countedPaise > 0 && state.slip == null) {
      state = state.copyWith(phase: DayClosePhase.slipRequired);
      return state.phase;
    }
    state = state.copyWith(phase: DayClosePhase.submitting);
    final api = ref.read(storeApiProvider);
    var uri = state.slipUri;
    if (state.slip != null && uri == null) {
      final up = await api.uploadPhoto(state.slip!);
      if (!ref.mounted) return DayClosePhase.failed;
      if (!up.ok) return _fail(up.failure!);
      uri = up.value;
      state = state.copyWith(slipUri: uri, phase: DayClosePhase.submitting);
    }
    final result = await api.closeDay(
      store.id,
      DayCloseRequest(
        businessDate: ref.read(storeTodayProvider),
        cashCountedPaise: state.countedPaise,
        depositSlipUri: uri,
        notes: state.notes,
      ),
    );
    if (!ref.mounted) return DayClosePhase.failed;
    if (!result.ok) return _fail(result.failure!);
    state = state.copyWith(phase: DayClosePhase.closed, result: result.value);
    ref.invalidate(daySummaryProvider);
    return DayClosePhase.closed;
  }

  DayClosePhase _fail(StoreFailure f) {
    final phase = f.isOffline
        ? DayClosePhase.offline
        : f.code == 'day_already_closed'
        ? DayClosePhase.alreadyClosed
        : f.code == 'deposit_slip_required'
        ? DayClosePhase.slipRequired
        : DayClosePhase.failed;
    state = state.copyWith(phase: phase, failure: f);
    if (phase == DayClosePhase.alreadyClosed) {
      ref.invalidate(daySummaryProvider);
    }
    return phase;
  }
}

/// S04 invoice by id (the sale just made is served from [posProvider]).
final invoiceProvider = FutureProvider.autoDispose
    .family<StoreResult<Invoice>, String>((ref, id) async {
      final sale = ref.read(posProvider).sale;
      if (sale != null && sale.invoice.id == id) {
        return StoreResult.ok(sale.invoice);
      }
      return ref.watch(storeApiProvider).invoice(id);
    });

/// S10 state.
final NotifierProvider<DayCloseNotifier, DayCloseState> dayCloseProvider =
    NotifierProvider<DayCloseNotifier, DayCloseState>(DayCloseNotifier.new);
