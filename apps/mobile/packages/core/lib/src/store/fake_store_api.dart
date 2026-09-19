import 'dart:typed_data';

import 'store_api.dart';
import 'store_calc.dart';
import 'store_models.dart';

/// In-memory store server for tests, previews and goldens: one Kondapur
/// store with realistic catalogue, stock, queue, approvals and a day
/// summary; the server's rules (transitions, credit gate, card reference,
/// one close per day, qty <= available) are mimicked.
class FakeStoreApi implements StoreApi {
  /// Creates the fake with the demo data.
  FakeStoreApi({this.today = '2026-09-20'}) {
    reset();
  }

  /// The IST business date the fake treats as today.
  final String today;

  /// Every call answers [StoreFailure.offline] while true.
  bool offline = false;

  /// POS credit sales answer 402 `credit_limit_exceeded`.
  bool creditExceeded = false;

  /// Role of the caller for `PUT credit-limit` (the ₹50,000 manager cap).
  String actingRole = 'store_manager';

  /// Poll answers for UPI payments, in order; then [PaymentPollState.waiting].
  final List<PaymentPollState> upiPolls = <PaymentPollState>[];

  /// Call log (`posSale`, `payment`, `setOrderStatus:packed`, ...).
  final List<String> calls = <String>[];

  /// The last POS request.
  PosSaleRequest? lastSale;

  /// The last day close request.
  DayCloseRequest? lastClose;

  /// The last receipt lines.
  List<ReceiptLine>? lastReceipt;

  /// The last transfer lines.
  List<BatchQty>? lastTransfer;

  /// Shares sent `(invoiceId, channel)`.
  final List<(String, String)> shares = <(String, String)>[];

  /// Stores.
  List<StoreBrief> storeList = <StoreBrief>[];

  /// Transfer destinations of the active store (the cluster's other stores).
  List<TransferDestination> destinations = <TransferDestination>[];

  /// `POST /v1/stock/transfers` answers 403 with this code while set
  /// (`transfer_source_not_allowed` / `transfer_destination_not_allowed`).
  String? transferRefusal;

  /// `GET /v1/stock/transfer-destinations` answers 403 with this code.
  String? destinationsRefusal;

  /// The POS preview answers 422 with this code while set.
  String? previewRefusal;

  /// The last POS preview request.
  PosSaleRequest? lastPreview;

  /// Catalogue.
  List<StoreItem> items = <StoreItem>[];

  /// Stock.
  List<StockBatch> batches = <StockBatch>[];

  /// Order queue.
  List<QueueOrder> orders = <QueueOrder>[];

  /// Credit approvals.
  List<CreditApproval> approvals = <CreditApproval>[];

  /// Day summary (its `dayClose` is replaced by a close).
  late DaySummary summary;

  /// Today was closed through [closeDay] (the server's one-close rule,
  /// independent of what [summary] shows).
  bool dayClosed = false;

  /// Invoices issued.
  final Map<String, Invoice> invoices = <String, Invoice>{};

  int _invoiceSeq = 123;
  int _paymentSeq = 0;

  /// Restores the demo data.
  void reset() {
    calls.clear();
    upiPolls.clear();
    storeList = demoStores;
    destinations = demoDestinations;
    transferRefusal = null;
    destinationsRefusal = null;
    previewRefusal = null;
    items = demoCatalog;
    batches = demoStock;
    orders = demoQueue;
    approvals = demoApprovals;
    summary = demoSummary(today);
    dayClosed = false;
    invoices.clear();
  }

  StoreResult<T> _offline<T>() => const StoreResult.fail(StoreFailure.offline);

  StoreResult<T> _problem<T>(
    int status,
    String code, [
    Map<String, Object?> extra = const <String, Object?>{},
  ]) => StoreResult<T>.fail(
    StoreFailure(
      status,
      code: code,
      body: <String, Object?>{'code': code, ...extra},
    ),
  );

  @override
  Future<StoreResult<List<StoreBrief>>> stores() async {
    calls.add('stores');
    if (offline) return _offline();
    return StoreResult.ok(storeList);
  }

  @override
  Future<StoreResult<List<StoreItem>>> catalog(String storeId) async {
    calls.add('catalog');
    if (offline) return _offline();
    return StoreResult.ok(items);
  }

  @override
  Future<StoreResult<StoreItem>> barcode(String code, String storeId) async {
    calls.add('barcode:$code');
    if (offline) return _offline();
    for (final i in items) {
      if (i.barcode == code) return StoreResult.ok(i);
    }
    return _problem(404, 'not_found');
  }

  @override
  Future<StoreResult<List<StockBatch>>> stock(String storeId) async {
    calls.add('stock');
    if (offline) return _offline();
    return StoreResult.ok(batches);
  }

  /// The server's preview: the same numbers the sale would invoice.
  static GstPreview _serverPreview(PosSaleRequest request) {
    final local = GstPreview.of(request.lines);
    return GstPreview(
      lines: local.lines,
      inter: local.inter,
      taxablePaise: local.taxablePaise,
      cgstPaise: local.cgstPaise,
      sgstPaise: local.sgstPaise,
      igstPaise: local.igstPaise,
      roundOffPaise: local.roundOffPaise,
      totalPaise: local.totalPaise,
      estimate: false,
      amountInWords: 'Rupees ${local.totalPaise ~/ 100} only',
    );
  }

  @override
  Future<StoreResult<GstPreview>> posPreview(
    String storeId,
    PosSaleRequest request,
  ) async {
    calls.add('posPreview');
    lastPreview = request;
    if (offline) return _offline();
    final refusal = previewRefusal;
    if (refusal != null) return _problem(422, refusal);
    return StoreResult.ok(_serverPreview(request));
  }

  @override
  Future<StoreResult<PosSaleResult>> posSale(
    String storeId,
    PosSaleRequest request,
  ) async {
    calls.add('posSale:${request.mode.wire}');
    lastSale = request;
    if (offline) return _offline();
    final preview = GstPreview.of(request.lines);
    if (request.mode == SaleMode.card &&
        (request.referenceNote ?? '').trim().isEmpty) {
      return _problem(422, 'reference_required');
    }
    if (request.mode == SaleMode.credit && creditExceeded) {
      // ST-007: an approved request named by the retry lets the sale through
      // once (then `consumed`); a pending one is returned again.
      final named = request.creditApprovalRequestId;
      final i = approvals.indexWhere((a) => a.id == named);
      if (i >= 0 && approvals[i].status == 'approved') {
        approvals = <CreditApproval>[...approvals]
          ..[i] = approvals[i].decided('consumed', approvals[i].decisionNote);
      } else {
        final id = i >= 0 && approvals[i].status == 'pending'
            ? named!
            : 'apr-new-${approvals.length + 1}';
        if (i < 0 || approvals[i].status != 'pending') {
          approvals = <CreditApproval>[
            ...approvals,
            CreditApproval(
              id: id,
              farmerId: request.farmerId ?? '',
              storeId: storeId,
              amountPaise: preview.totalPaise,
              balancePaise: 1800000,
              limitPaise: 2000000,
              shortfallPaise: preview.totalPaise - 200000,
              status: 'pending',
            ),
          ];
        }
        return _problem(402, 'credit_limit_exceeded', <String, Object?>{
          'shortfall_paise': preview.totalPaise - 200000,
          'approval_request_id': id,
          'balance_paise': 1800000,
          'limit_paise': 2000000,
        });
      }
    }
    final orderId = 'order-pos-${++_paymentSeq}';
    final invoice = Invoice(
      id: 'inv-$_paymentSeq',
      orderId: orderId,
      invoiceNo:
          'FCC/KND/2026-27/${(++_invoiceSeq).toString().padLeft(6, '0')}',
      issuedAt: DateTime.utc(2026, 9, 20, 5, 42),
      sellerName: 'Farmers Care Centre',
      sellerGstin: '36AAAAA0000A1Z5',
      sellerAddress: 'Main Road, Kondapur, Sangareddy, Telangana',
      buyerName: request.farmerId != null ? 'Ramesh Reddy' : 'Walk-in customer',
      placeOfSupply: 'Telangana (36)',
      inter: false,
      farmerId: request.farmerId,
      lines: preview.lines,
      taxablePaise: preview.taxablePaise,
      cgstPaise: preview.cgstPaise,
      sgstPaise: preview.sgstPaise,
      igstPaise: preview.igstPaise,
      roundOffPaise: preview.roundOffPaise,
      totalPaise: preview.totalPaise,
      amountInWords: 'Rupees ${preview.totalPaise ~/ 100} only',
      hasPdf: true,
    );
    invoices[invoice.id] = invoice;
    final payment = PaymentCreated(
      paymentId: 'pay-$_paymentSeq',
      mode: request.mode,
      status: switch (request.mode) {
        SaleMode.upiQr => 'created',
        SaleMode.cash => 'pending_reconciliation',
        SaleMode.card || SaleMode.credit => 'paid',
      },
      amountPaise: preview.totalPaise,
      orderId: orderId,
      qrPayload: request.mode == SaleMode.upiQr
          ? 'upi://pay?pa=fcc@razorpay&am=${preview.totalPaise / 100}'
          : null,
      expiresAt: request.mode == SaleMode.upiQr
          ? DateTime.utc(2026, 9, 20, 5, 57)
          : null,
    );
    return StoreResult.ok(
      PosSaleResult(orderId: orderId, invoice: invoice, payment: payment),
    );
  }

  @override
  Future<StoreResult<PaymentStatus>> payment(String paymentId) async {
    calls.add('payment');
    if (offline) return _offline();
    final state = upiPolls.isEmpty
        ? PaymentPollState.waiting
        : upiPolls.removeAt(0);
    return StoreResult.ok(
      PaymentStatus(
        id: paymentId,
        state: state,
        amountPaise: 0,
        failureReason: state == PaymentPollState.failed ? 'expired' : null,
      ),
    );
  }

  @override
  Future<StoreResult<PaymentCreated>> newUpiQr(String orderId) async {
    calls.add('newUpiQr');
    if (offline) return _offline();
    return StoreResult.ok(
      PaymentCreated(
        paymentId: 'pay-retry-${++_paymentSeq}',
        mode: SaleMode.upiQr,
        status: 'created',
        amountPaise: 0,
        orderId: orderId,
        qrPayload: 'upi://pay?pa=fcc@razorpay&tr=$_paymentSeq',
        expiresAt: DateTime.utc(2026, 9, 20, 6, 12),
      ),
    );
  }

  @override
  Future<StoreResult<Invoice>> invoice(String invoiceId) async {
    calls.add('invoice');
    if (offline) return _offline();
    final inv = invoices[invoiceId];
    return inv == null ? _problem(404, 'not_found') : StoreResult.ok(inv);
  }

  @override
  Future<StoreResult<String>> invoicePdfUrl(String invoiceId) async {
    calls.add('invoicePdf');
    if (offline) return _offline();
    return StoreResult.ok('https://blob.example/invoices/$invoiceId.pdf?sig=x');
  }

  @override
  Future<StoreResult<String>> shareInvoice(
    String invoiceId, {
    String channel = 'whatsapp',
    String? phone,
  }) async {
    calls.add('share:$channel');
    if (offline) return _offline();
    shares.add((invoiceId, channel));
    return const StoreResult.ok('+91 98XXXXX210');
  }

  @override
  Future<StoreResult<List<QueueOrder>>> orderQueue(String storeId) async {
    calls.add('orderQueue');
    if (offline) return _offline();
    return StoreResult.ok(orders);
  }

  @override
  Future<StoreResult<QueueOrder>> setOrderStatus(
    String orderId,
    OrderStatus status, {
    String? note,
  }) async {
    calls.add('setOrderStatus:${status.wire}');
    if (offline) return _offline();
    final i = orders.indexWhere((o) => o.id == orderId);
    if (i < 0) return _problem(404, 'not_found');
    if (!canTransition(orders[i].status, status)) {
      return _problem(409, 'invalid_transition');
    }
    final updated = orders[i].withStatus(status);
    orders = <QueueOrder>[...orders]..[i] = updated;
    return StoreResult.ok(updated);
  }

  StoreResult<StockWriteResult>? _checkAvailable(Iterable<BatchQty> lines) {
    final used = <String, double>{};
    for (final l in lines) {
      final b = batches.firstWhere((x) => x.id == l.batch.id);
      used[b.id] = (used[b.id] ?? 0) + l.qty;
      if (used[b.id]! > b.available) {
        return _problem(409, 'negative_stock', <String, Object?>{
          'available': b.available,
        });
      }
    }
    return null;
  }

  @override
  Future<StoreResult<StockWriteResult>> receiveStock(
    String storeId,
    List<ReceiptLine> lines, {
    String? reference,
  }) async {
    calls.add('receiveStock');
    lastReceipt = lines;
    if (offline) return _offline();
    return StoreResult.ok(
      StockWriteResult(refId: 'rcpt-1', movementCount: lines.length),
    );
  }

  @override
  Future<StoreResult<List<TransferDestination>>> transferDestinations({
    String? fromStoreId,
  }) async {
    calls.add('transferDestinations:${fromStoreId ?? '-'}');
    if (offline) return _offline();
    final refusal = destinationsRefusal;
    if (refusal != null) return _problem(403, refusal);
    return StoreResult.ok(destinations);
  }

  @override
  Future<StoreResult<StockWriteResult>> transferStock({
    required String fromStoreId,
    required String toStoreId,
    required List<BatchQty> lines,
    String? note,
  }) async {
    calls.add('transferStock:$toStoreId');
    lastTransfer = lines;
    if (offline) return _offline();
    final refusal = transferRefusal;
    if (refusal != null) return _problem(403, refusal);
    final problem = _checkAvailable(lines);
    if (problem != null) return problem;
    return StoreResult.ok(
      StockWriteResult(refId: 'trf-1', movementCount: lines.length * 2),
    );
  }

  @override
  Future<StoreResult<StockWriteResult>> writeOff(
    String storeId, {
    required BatchQty line,
    required WriteOffReason reason,
    String? note,
    String? photoUri,
  }) async {
    calls.add('writeOff:${reason.name}:${photoUri ?? '-'}');
    if (offline) return _offline();
    final problem = _checkAvailable(<BatchQty>[line]);
    if (problem != null) return problem;
    return const StoreResult.ok(
      StockWriteResult(refId: 'wo-1', movementCount: 1),
    );
  }

  @override
  Future<StoreResult<StockWriteResult>> adjust(
    String storeId, {
    required StockBatch batch,
    required double countedQty,
    required String reason,
  }) async {
    calls.add('adjust:${formatQty(countedQty)}');
    if (offline) return _offline();
    return const StoreResult.ok(
      StockWriteResult(refId: 'adj-1', movementCount: 1),
    );
  }

  @override
  Future<StoreResult<List<CreditApproval>>> creditApprovals({
    String status = 'pending',
    String? farmerId,
  }) async {
    calls.add('creditApprovals');
    if (offline) return _offline();
    return StoreResult.ok(<CreditApproval>[
      for (final a in approvals)
        if (a.status == status && (farmerId == null || a.farmerId == farmerId))
          a,
    ]);
  }

  @override
  Future<StoreResult<CreditApproval>> decideCredit(
    String approvalId, {
    required bool approve,
    String? note,
  }) async {
    calls.add('decideCredit:${approve ? 'approve' : 'reject'}');
    if (offline) return _offline();
    final i = approvals.indexWhere((a) => a.id == approvalId);
    if (i < 0) return _problem(404, 'not_found');
    if (approvals[i].status != 'pending') {
      return _problem(409, 'approval_not_pending');
    }
    final updated = approvals[i].decided(
      approve ? 'approved' : 'rejected',
      note,
    );
    approvals = <CreditApproval>[...approvals]..[i] = updated;
    return StoreResult.ok(updated);
  }

  @override
  Future<StoreResult<int>> setCreditLimit(
    String farmerId, {
    required String storeId,
    required int limitPaise,
  }) async {
    calls.add('setCreditLimit:$limitPaise');
    if (offline) return _offline();
    if (actingRole == 'store_manager' &&
        limitPaise > storeManagerCreditCapPaise) {
      return _problem(403, 'credit_limit_needs_cluster_head');
    }
    return StoreResult.ok(limitPaise);
  }

  @override
  Future<StoreResult<DaySummary>> daySummary(
    String storeId, {
    String? date,
  }) async {
    calls.add('daySummary');
    if (offline) return _offline();
    return StoreResult.ok(summary);
  }

  @override
  Future<StoreResult<DayClose>> closeDay(
    String storeId,
    DayCloseRequest request,
  ) async {
    calls.add('closeDay');
    lastClose = request;
    if (offline) return _offline();
    if (dayClosed || (summary.dayClose?.isClosed ?? false)) {
      return _problem(409, 'day_already_closed');
    }
    if (request.cashCountedPaise > 0 && request.depositSlipUri == null) {
      return _problem(422, 'deposit_slip_required');
    }
    final variance = cashVariance(
      countedPaise: request.cashCountedPaise,
      expectedPaise: summary.expectedCashPaise,
    );
    final close = DayClose(
      id: 'close-1',
      businessDate: request.businessDate,
      status: 'closed',
      expectedPaise: summary.expectedCashPaise,
      countedPaise: request.cashCountedPaise,
      variancePaise: variance,
      flagged: varianceOverThreshold(variance),
      depositSlipUri: request.depositSlipUri,
      notes: request.notes,
      closedAt: DateTime.utc(2026, 9, 20, 14, 30),
    );
    dayClosed = true;
    summary = DaySummary(
      businessDate: summary.businessDate,
      byMode: summary.byMode,
      totalReceivedPaise: summary.totalReceivedPaise,
      expectedCashPaise: summary.expectedCashPaise,
      waiting: summary.waiting,
      failed: summary.failed,
      refunds: summary.refunds,
      dayClose: close,
    );
    return StoreResult.ok(close);
  }

  @override
  Future<StoreResult<String>> uploadPhoto(Uint8List jpeg) async {
    calls.add('uploadPhoto');
    if (offline) return _offline();
    return const StoreResult.ok('gs://farmerapp-dev/receipts/slip-1.jpg');
  }
}

/// Demo store.
const List<StoreBrief> demoStores = <StoreBrief>[
  StoreBrief(id: 'store-knd', code: 'KND', name: 'Kondapur FCC'),
  StoreBrief(id: 'store-sgr', code: 'SGR', name: 'Sangareddy FCC'),
];

/// Demo transfer destinations of Kondapur (its cluster, nearest first).
const List<TransferDestination> demoDestinations = <TransferDestination>[
  TransferDestination(
    id: 'store-sgr',
    code: 'SGR',
    name: 'Sangareddy FCC',
    district: 'Sangareddy',
    distanceM: 38400,
  ),
];

/// Demo catalogue (store prices, pre-tax).
const List<StoreItem> demoCatalog = <StoreItem>[
  StoreItem(
    skuId: 'sku-imd-250',
    productId: 'p-imd',
    name: 'Imidacloprid 17.8% SL',
    brand: 'FCC Shakti',
    ownBrand: true,
    category: 'pesticide',
    hsn: '38089199',
    gstRateBp: 1800,
    packLabel: '250 ml',
    barcode: '8901234500011',
    mrpPaise: 48000,
    pricePaise: 42000,
    stockQty: 50,
  ),
  StoreItem(
    skuId: 'sku-mnz-1kg',
    productId: 'p-mnz',
    name: 'Mancozeb 75% WP',
    brand: 'Indofil M-45',
    category: 'fungicide',
    hsn: '38089290',
    gstRateBp: 1800,
    packLabel: '1 kg',
    barcode: '8901234500028',
    mrpPaise: 62000,
    pricePaise: 56000,
    stockQty: 16,
  ),
  StoreItem(
    skuId: 'sku-urea-45',
    productId: 'p-urea',
    name: 'Urea (neem coated)',
    brand: 'IFFCO',
    category: 'fertiliser',
    hsn: '31021000',
    gstRateBp: 500,
    packLabel: '45 kg',
    barcode: '8901234500035',
    mrpPaise: 26650,
    pricePaise: 26650,
    stockQty: 110,
  ),
  StoreItem(
    skuId: 'sku-dap-50',
    productId: 'p-dap',
    name: 'DAP 18:46:0',
    brand: 'Coromandel',
    category: 'fertiliser',
    hsn: '31053000',
    gstRateBp: 500,
    packLabel: '50 kg',
    barcode: '8901234500042',
    mrpPaise: 135000,
    pricePaise: 135000,
    stockQty: 6,
  ),
  StoreItem(
    skuId: 'sku-bt-450',
    productId: 'p-bt',
    name: 'Cotton seed Bt RCH 659',
    brand: 'Rasi Seeds',
    category: 'seed',
    hsn: '12072000',
    packLabel: '450 g',
    barcode: '8901234500059',
    mrpPaise: 86400,
    pricePaise: 86400,
    stockQty: 28,
  ),
  StoreItem(
    skuId: 'sku-teja-10',
    productId: 'p-teja',
    name: 'Chilli seed Teja',
    brand: 'Syngenta',
    category: 'seed',
    hsn: '12099190',
    packLabel: '10 g',
    barcode: '8901234500066',
    mrpPaise: 52000,
    pricePaise: 45000,
    stockQty: 3,
  ),
  StoreItem(
    skuId: 'sku-spr-16',
    productId: 'p-spr',
    name: 'Knapsack sprayer',
    brand: 'Aspee',
    category: 'tool',
    hsn: '84244100',
    gstRateBp: 1200,
    packLabel: '16 L',
    barcode: '8901234500073',
    mrpPaise: 320000,
    pricePaise: 285000,
    stockQty: 8,
  ),
  StoreItem(
    skuId: 'sku-humic-5',
    productId: 'p-humic',
    name: 'Humic acid granules',
    brand: 'FCC Bhumi',
    ownBrand: true,
    category: 'growth',
    hsn: '31010099',
    gstRateBp: 500,
    packLabel: '5 kg',
    barcode: '8901234500080',
    mrpPaise: 72000,
    pricePaise: 65000,
    stockQty: 0,
  ),
];

/// Demo stock at Kondapur (today 2026-09-20).
final List<StockBatch> demoStock = <StockBatch>[
  StockBatch(
    id: 'b-imd-1',
    skuId: 'sku-imd-250',
    batchNo: 'IMD2601',
    expiry: DateTime(2026, 10, 10),
    daysToExpiry: 20,
    onHand: 24,
    reserved: 4,
    available: 20,
    costPaise: 33000,
  ),
  StockBatch(
    id: 'b-imd-2',
    skuId: 'sku-imd-250',
    batchNo: 'IMD2604',
    expiry: DateTime(2027, 3, 31),
    daysToExpiry: 192,
    onHand: 30,
    reserved: 0,
    available: 30,
    costPaise: 33000,
  ),
  StockBatch(
    id: 'b-mnz-1',
    skuId: 'sku-mnz-1kg',
    batchNo: 'MNZ2511',
    expiry: DateTime(2026, 11, 10),
    daysToExpiry: 51,
    onHand: 18,
    reserved: 2,
    available: 16,
    costPaise: 47000,
  ),
  const StockBatch(
    id: 'b-urea-1',
    skuId: 'sku-urea-45',
    batchNo: 'UR2609',
    onHand: 120,
    reserved: 10,
    available: 110,
    costPaise: 24200,
  ),
  const StockBatch(
    id: 'b-dap-1',
    skuId: 'sku-dap-50',
    batchNo: 'DAP2608',
    onHand: 6,
    reserved: 0,
    available: 6,
    costPaise: 128000,
  ),
  StockBatch(
    id: 'b-bt-1',
    skuId: 'sku-bt-450',
    batchNo: 'BT659-26',
    expiry: DateTime(2027, 1, 31),
    daysToExpiry: 133,
    onHand: 40,
    reserved: 12,
    available: 28,
    costPaise: 78000,
  ),
  StockBatch(
    id: 'b-teja-1',
    skuId: 'sku-teja-10',
    batchNo: 'TEJA2605',
    expiry: DateTime(2026, 9, 15),
    daysToExpiry: -5,
    onHand: 3,
    reserved: 0,
    available: 3,
    costPaise: 39000,
  ),
  const StockBatch(
    id: 'b-spr-1',
    skuId: 'sku-spr-16',
    batchNo: 'SPR001',
    onHand: 8,
    reserved: 0,
    available: 8,
    costPaise: 240000,
  ),
];

/// Demo order queue.
final List<QueueOrder> demoQueue = <QueueOrder>[
  QueueOrder(
    id: '0b6f1c2e-0000-4000-8000-00000000a101',
    status: OrderStatus.placed,
    channel: 'farmer_app',
    totalPaise: 99120,
    farmerId: 'farmer-lakshmi',
    placedAt: DateTime.utc(2026, 9, 20, 3, 10),
    lines: const <QueueLine>[
      QueueLine(skuId: 'sku-imd-250', qty: 2, lineTotalPaise: 84000),
    ],
  ),
  QueueOrder(
    id: '0b6f1c2e-0000-4000-8000-00000000a102',
    status: OrderStatus.reserved,
    channel: 'officer',
    totalPaise: 181440,
    farmerId: 'farmer-ramesh',
    placedAt: DateTime.utc(2026, 9, 20, 3, 25),
    lines: const <QueueLine>[
      QueueLine(skuId: 'sku-bt-450', qty: 2, lineTotalPaise: 172800),
    ],
  ),
  QueueOrder(
    id: '0b6f1c2e-0000-4000-8000-00000000a103',
    status: OrderStatus.reserved,
    channel: 'officer',
    totalPaise: 139913,
    farmerId: 'farmer-venkat',
    placedAt: DateTime.utc(2026, 9, 20, 4, 2),
    lines: const <QueueLine>[
      QueueLine(skuId: 'sku-urea-45', qty: 5, lineTotalPaise: 133250),
    ],
  ),
  QueueOrder(
    id: '0b6f1c2e-0000-4000-8000-00000000a104',
    status: OrderStatus.packed,
    channel: 'officer',
    totalPaise: 66080,
    farmerId: 'farmer-anjali',
    placedAt: DateTime.utc(2026, 9, 19, 11, 40),
    lines: const <QueueLine>[
      QueueLine(skuId: 'sku-mnz-1kg', qty: 1, lineTotalPaise: 56000),
    ],
  ),
  QueueOrder(
    id: '0b6f1c2e-0000-4000-8000-00000000a105',
    status: OrderStatus.ready,
    channel: 'farmer_app',
    fulfilment: 'delivery',
    totalPaise: 319200,
    farmerId: 'farmer-suresh',
    placedAt: DateTime.utc(2026, 9, 19, 9, 5),
    lines: const <QueueLine>[
      QueueLine(skuId: 'sku-spr-16', qty: 1, lineTotalPaise: 285000),
    ],
  ),
  QueueOrder(
    id: '0b6f1c2e-0000-4000-8000-00000000a106',
    status: OrderStatus.handedOver,
    channel: 'officer',
    totalPaise: 141750,
    farmerId: 'farmer-ramesh',
    placedAt: DateTime.utc(2026, 9, 18, 6, 30),
    lines: const <QueueLine>[
      QueueLine(skuId: 'sku-dap-50', qty: 1, lineTotalPaise: 135000),
    ],
  ),
];

/// Demo approvals.
final List<CreditApproval> demoApprovals = <CreditApproval>[
  CreditApproval(
    id: 'apr-1',
    farmerId: 'farmer-ramesh',
    storeId: 'store-knd',
    orderId: 'order-77',
    amountPaise: 1250000,
    balancePaise: 3400000,
    limitPaise: 4000000,
    shortfallPaise: 650000,
    status: 'pending',
    createdAt: DateTime.utc(2026, 9, 20, 4, 15),
  ),
  CreditApproval(
    id: 'apr-2',
    farmerId: 'farmer-venkat',
    storeId: 'store-knd',
    orderId: 'order-78',
    amountPaise: 420000,
    balancePaise: 1900000,
    limitPaise: 2000000,
    shortfallPaise: 320000,
    status: 'pending',
    createdAt: DateTime.utc(2026, 9, 20, 5),
  ),
];

/// Demo day summary: ₹12,450 cash, ₹18,600 UPI, ₹4,200 card, ₹3,500 credit.
DaySummary demoSummary(String date) => DaySummary(
  businessDate: date,
  byMode: const <String, CountAmount>{
    'upi_qr': CountAmount(9, 1860000),
    'payment_link': CountAmount(0, 0),
    'cash': CountAmount(12, 1245000),
    'card_terminal': CountAmount(2, 420000),
    'credit': CountAmount(3, 350000),
  },
  totalReceivedPaise: 3525000,
  expectedCashPaise: 1245000,
  cashPendingPaise: 1245000,
  waiting: const CountAmount(1, 99120),
);
