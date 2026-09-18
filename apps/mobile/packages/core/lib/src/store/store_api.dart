import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' as http;

import '../auth/api_config.dart';
import '../auth/auth_api.dart';
import '../auth/token_store.dart';
import '../photo/chunked_upload_planner.dart';
import '../sync/http_sync_api.dart' show ServerDateObserver, reportServerDate;
import 'store_models.dart';

/// A failed store call: HTTP status (0 = no network / timeout), the RFC 9457
/// `code` and the problem body (credit extras, errors[]).
@immutable
class StoreFailure {
  /// Creates the failure.
  const StoreFailure(this.status, {this.code, this.body = const {}});

  /// The request never completed.
  static const StoreFailure offline = StoreFailure(0, code: 'offline');

  /// HTTP status; 0 when offline.
  final int status;

  /// Problem code (`credit_limit_exceeded`, `day_already_closed`, ...).
  final String? code;

  /// Problem body.
  final Map<String, Object?> body;

  /// No network (or timeout / 5xx gateway).
  bool get isOffline => status == 0 || code == 'offline';

  /// Integer extra from the body.
  int intExtra(String key) => (body[key] as num?)?.toInt() ?? 0;
}

/// Value or failure of a store call. Providers hold these as data (they
/// never throw), so screens render error / offline states themselves.
@immutable
class StoreResult<T> {
  /// A success.
  const StoreResult.ok(T this.value) : failure = null;

  /// A failure.
  const StoreResult.fail(StoreFailure this.failure) : value = null;

  /// The value on success.
  final T? value;

  /// The failure.
  final StoreFailure? failure;

  /// Succeeded.
  bool get ok => failure == null;

  /// Maps the value.
  StoreResult<R> map<R>(R Function(T v) f) =>
      ok ? StoreResult<R>.ok(f(value as T)) : StoreResult<R>.fail(failure!);
}

/// Body of `POST /v1/stores/{id}/day-close`.
@immutable
class DayCloseRequest {
  /// Creates the request.
  const DayCloseRequest({
    required this.businessDate,
    required this.cashCountedPaise,
    this.depositSlipUri,
    this.notes,
  });

  /// IST business date.
  final String businessDate;

  /// Counted cash.
  final int cashCountedPaise;

  /// Uploaded deposit slip.
  final String? depositSlipUri;

  /// Notes.
  final String? notes;

  /// JSON body.
  Map<String, Object?> toJson() => <String, Object?>{
    'business_date': businessDate,
    'cash_counted_paise': cashCountedPaise,
    'deposit_slip_uri': ?depositSlipUri,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
  };
}

/// The store-mode API (online-first; the counter has connectivity). Every
/// method answers a [StoreResult]; a request that could not reach the
/// server is [StoreFailure.offline].
abstract interface class StoreApi {
  /// `GET /v1/catalog/stores`.
  Future<StoreResult<List<StoreBrief>>> stores();

  /// `GET /v1/catalog/products?store_id=` flattened to SKUs.
  Future<StoreResult<List<StoreItem>>> catalog(String storeId);

  /// `GET /v1/catalog/barcode/{code}?store_id=`; 404 = not found.
  Future<StoreResult<StoreItem>> barcode(String code, String storeId);

  /// `GET /v1/stores/{id}/stock`.
  Future<StoreResult<List<StockBatch>>> stock(String storeId);

  /// `POST /v1/stores/{id}/pos/sales`.
  Future<StoreResult<PosSaleResult>> posSale(
    String storeId,
    PosSaleRequest request,
  );

  /// `GET /v1/payments/{id}`.
  Future<StoreResult<PaymentStatus>> payment(String paymentId);

  /// `POST /v1/payments {order_id, mode: upi_qr}`: a fresh QR after a
  /// failed / expired one.
  Future<StoreResult<PaymentCreated>> newUpiQr(String orderId);

  /// `GET /v1/invoices/{id}`.
  Future<StoreResult<Invoice>> invoice(String invoiceId);

  /// `GET /v1/invoices/{id}/pdf`: the signed URL.
  Future<StoreResult<String>> invoicePdfUrl(String invoiceId);

  /// `POST /v1/invoices/{id}/share`: returns the masked recipient.
  Future<StoreResult<String>> shareInvoice(
    String invoiceId, {
    String channel = 'whatsapp',
    String? phone,
  });

  /// `GET /v1/stores/{id}/order-queue`.
  Future<StoreResult<List<QueueOrder>>> orderQueue(String storeId);

  /// `POST /v1/orders/{id}/status`.
  Future<StoreResult<QueueOrder>> setOrderStatus(
    String orderId,
    OrderStatus status, {
    String? note,
  });

  /// `POST /v1/stores/{id}/stock/receipts`.
  Future<StoreResult<StockWriteResult>> receiveStock(
    String storeId,
    List<ReceiptLine> lines, {
    String? reference,
  });

  /// `POST /v1/stock/transfers`.
  Future<StoreResult<StockWriteResult>> transferStock({
    required String fromStoreId,
    required String toStoreId,
    required List<BatchQty> lines,
    String? note,
  });

  /// `POST /v1/stores/{id}/stock/write-offs`.
  Future<StoreResult<StockWriteResult>> writeOff(
    String storeId, {
    required BatchQty line,
    required WriteOffReason reason,
    String? note,
    String? photoUri,
  });

  /// `POST /v1/stores/{id}/stock/adjustments`.
  Future<StoreResult<StockWriteResult>> adjust(
    String storeId, {
    required StockBatch batch,
    required double countedQty,
    required String reason,
  });

  /// `GET /v1/credit-approvals?status=`.
  Future<StoreResult<List<CreditApproval>>> creditApprovals({
    String status = 'pending',
  });

  /// `POST /v1/credit-approvals/{id}/approve|reject`.
  Future<StoreResult<CreditApproval>> decideCredit(
    String approvalId, {
    required bool approve,
    String? note,
  });

  /// `PUT /v1/farmers/{id}/credit-limit`.
  Future<StoreResult<int>> setCreditLimit(
    String farmerId, {
    required String storeId,
    required int limitPaise,
  });

  /// `GET /v1/stores/{id}/day-summary?date=`.
  Future<StoreResult<DaySummary>> daySummary(String storeId, {String? date});

  /// `POST /v1/stores/{id}/day-close`.
  Future<StoreResult<DayClose>> closeDay(
    String storeId,
    DayCloseRequest request,
  );

  /// Resumable upload (`/v1/uploads`, purpose `receipt`) of a processed
  /// JPEG; returns the blob URI.
  Future<StoreResult<String>> uploadPhoto(Uint8List jpeg);
}

/// [StoreApi] over HTTP with the bearer token from the [TokenStore]; a 401
/// refreshes once and retries.
class HttpStoreApi implements StoreApi {
  /// Creates the client.
  HttpStoreApi({
    required TokenStore store,
    this.config = const ApiConfig(),
    http.Client? client,
    this.refreshSession,
    this.timeout = const Duration(seconds: 20),
    this.onServerDate,
    String Function()? ids,
  }) : _store = store, // ignore: prefer_initializing_formals
       _client = client ?? http.Client(),
       _ids = ids ?? generateUuidV4;

  final TokenStore _store;
  final http.Client _client;
  final String Function() _ids;

  /// API location.
  final ApiConfig config;

  /// Rotates the session on 401.
  final Future<AuthSession?> Function()? refreshSession;

  /// Per-request timeout.
  final Duration timeout;

  /// Clock-drift observer (FA-028).
  final ServerDateObserver? onServerDate;

  Future<(int, Object?)> _call(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? json,
    Uint8List? bytes,
    Map<String, String> headers = const <String, String>{},
  }) async {
    var session = await _store.read();
    if (session == null) return (401, null);
    if (session.isExpired() && refreshSession != null) {
      session = await refreshSession!() ?? session;
    }
    final q = <String, dynamic>{
      for (final e in (query ?? const <String, Object?>{}).entries)
        if (e.value != null)
          e.key: e.value is List
              ? <String>[for (final v in e.value! as List) '$v']
              : '${e.value}',
    };
    final base = config.resolve(path);
    final uri = q.isEmpty ? base : base.replace(queryParameters: q);
    Future<http.Response> send(String token) {
      final request = http.Request(method, uri)
        ..headers.addAll(<String, String>{
          'Accept': 'application/json, application/problem+json',
          'Authorization': 'Bearer $token',
          ...headers,
        });
      if (bytes != null) {
        request.headers['Content-Type'] = 'application/octet-stream';
        request.bodyBytes = bytes;
      } else if (json != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(json);
      }
      return _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    }

    try {
      var response = await send(session.accessToken);
      if (response.statusCode == 401 && refreshSession != null) {
        final fresh = await refreshSession!();
        if (fresh != null) response = await send(fresh.accessToken);
      }
      reportServerDate(response.headers['date'], onServerDate);
      Object? decoded;
      if (response.body.isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } on FormatException {
          decoded = null;
        }
      }
      return (response.statusCode, decoded);
    } on http.ClientException {
      return (0, null);
    } on SocketException {
      return (0, null);
    } on TimeoutException {
      return (0, null);
    }
  }

  static StoreFailure _failure(int status, Object? body) {
    if (status == 0 || status == 502 || status == 503 || status == 504) {
      return StoreFailure(status, code: 'offline');
    }
    final map = body is Map
        ? Map<String, Object?>.from(body)
        : const <String, Object?>{};
    return StoreFailure(status, code: map['code'] as String?, body: map);
  }

  Future<StoreResult<T>> _json<T>(
    String method,
    String path,
    T Function(Map<String, Object?> j) parse, {
    Map<String, Object?>? query,
    Object? body,
    bool idempotent = false,
  }) async {
    final (status, decoded) = await _call(
      method,
      path,
      query: query,
      json: body,
      headers: idempotent
          ? <String, String>{'Idempotency-Key': _ids()}
          : const <String, String>{},
    );
    if (status >= 200 && status < 300) {
      return StoreResult<T>.ok(
        parse(
          decoded is Map
              ? Map<String, Object?>.from(decoded)
              : const <String, Object?>{},
        ),
      );
    }
    return StoreResult<T>.fail(_failure(status, decoded));
  }

  /// Follows `next_cursor` up to [maxPages] pages.
  Future<StoreResult<List<Map<String, Object?>>>> _pages(
    String path, {
    Map<String, Object?> query = const <String, Object?>{},
    int maxPages = 10,
  }) async {
    final items = <Map<String, Object?>>[];
    String? cursor;
    for (var i = 0; i < maxPages; i++) {
      final page = await _json<Map<String, Object?>>(
        'GET',
        path,
        (j) => j,
        query: <String, Object?>{...query, 'limit': 200, 'cursor': ?cursor},
      );
      if (!page.ok) return StoreResult.fail(page.failure!);
      final body = page.value!;
      final list = body['items'];
      if (list is List) {
        for (final e in list) {
          if (e is Map) items.add(Map<String, Object?>.from(e));
        }
      }
      cursor = body['next_cursor'] as String?;
      if (cursor == null) break;
    }
    return StoreResult.ok(items);
  }

  @override
  Future<StoreResult<List<StoreBrief>>> stores() => _json(
    'GET',
    '/v1/catalog/stores',
    (j) => <StoreBrief>[
      for (final e in (j['items'] as List?) ?? const <Object?>[])
        if (e is Map) StoreBrief.fromJson(Map<String, Object?>.from(e)),
    ],
  );

  @override
  Future<StoreResult<List<StoreItem>>> catalog(String storeId) async {
    final pages = await _pages(
      '/v1/catalog/products',
      query: <String, Object?>{'store_id': storeId},
    );
    return pages.map(
      (products) => <StoreItem>[
        for (final p in products)
          for (final s in (p['skus'] as List?) ?? const <Object?>[])
            if (s is Map && s['active'] != false)
              StoreItem.fromProductSku(p, Map<String, Object?>.from(s)),
      ],
    );
  }

  @override
  Future<StoreResult<StoreItem>> barcode(String code, String storeId) => _json(
    'GET',
    '/v1/catalog/barcode/${Uri.encodeComponent(code)}',
    StoreItem.fromBarcode,
    query: <String, Object?>{'store_id': storeId},
  );

  @override
  Future<StoreResult<List<StockBatch>>> stock(String storeId) async {
    final pages = await _pages('/v1/stores/$storeId/stock');
    return pages.map(
      (rows) => <StockBatch>[for (final r in rows) StockBatch.fromJson(r)],
    );
  }

  @override
  Future<StoreResult<PosSaleResult>> posSale(
    String storeId,
    PosSaleRequest request,
  ) => _json(
    'POST',
    '/v1/stores/$storeId/pos/sales',
    PosSaleResult.fromJson,
    body: request.toJson(),
    idempotent: true,
  );

  @override
  Future<StoreResult<PaymentStatus>> payment(String paymentId) =>
      _json('GET', '/v1/payments/$paymentId', PaymentStatus.fromJson);

  @override
  Future<StoreResult<PaymentCreated>> newUpiQr(String orderId) => _json(
    'POST',
    '/v1/payments',
    PaymentCreated.fromJson,
    body: <String, Object?>{'order_id': orderId, 'mode': SaleMode.upiQr.wire},
    idempotent: true,
  );

  @override
  Future<StoreResult<Invoice>> invoice(String invoiceId) =>
      _json('GET', '/v1/invoices/$invoiceId', Invoice.fromJson);

  @override
  Future<StoreResult<String>> invoicePdfUrl(String invoiceId) => _json(
    'GET',
    '/v1/invoices/$invoiceId/pdf',
    (j) => (j['url'] as String?) ?? '',
  );

  @override
  Future<StoreResult<String>> shareInvoice(
    String invoiceId, {
    String channel = 'whatsapp',
    String? phone,
  }) => _json(
    'POST',
    '/v1/invoices/$invoiceId/share',
    (j) => (j['to'] as String?) ?? '',
    body: <String, Object?>{'channel': channel, 'phone': ?phone},
  );

  @override
  Future<StoreResult<List<QueueOrder>>> orderQueue(String storeId) async {
    final pages = await _pages(
      '/v1/stores/$storeId/order-queue',
      query: <String, Object?>{
        'status': <String>[
          for (final t in QueueTab.values)
            for (final s in t.statuses) s.wire,
        ],
      },
    );
    return pages.map(
      (rows) => <QueueOrder>[for (final r in rows) QueueOrder.fromJson(r)],
    );
  }

  @override
  Future<StoreResult<QueueOrder>> setOrderStatus(
    String orderId,
    OrderStatus status, {
    String? note,
  }) => _json(
    'POST',
    '/v1/orders/$orderId/status',
    QueueOrder.fromJson,
    body: <String, Object?>{'status': status.wire, 'note': ?note},
  );

  @override
  Future<StoreResult<StockWriteResult>> receiveStock(
    String storeId,
    List<ReceiptLine> lines, {
    String? reference,
  }) => _json(
    'POST',
    '/v1/stores/$storeId/stock/receipts',
    StockWriteResult.fromJson,
    body: <String, Object?>{
      'reference': ?reference,
      'lines': <Map<String, Object?>>[for (final l in lines) l.toJson()],
    },
    idempotent: true,
  );

  @override
  Future<StoreResult<StockWriteResult>> transferStock({
    required String fromStoreId,
    required String toStoreId,
    required List<BatchQty> lines,
    String? note,
  }) => _json(
    'POST',
    '/v1/stock/transfers',
    StockWriteResult.fromJson,
    body: <String, Object?>{
      'from_store_id': fromStoreId,
      'to_store_id': toStoreId,
      'note': ?note,
      'lines': <Map<String, Object?>>[
        for (final l in lines)
          <String, Object?>{'batch_id': l.batch.id, 'qty': formatQty(l.qty)},
      ],
    },
    idempotent: true,
  );

  @override
  Future<StoreResult<StockWriteResult>> writeOff(
    String storeId, {
    required BatchQty line,
    required WriteOffReason reason,
    String? note,
    String? photoUri,
  }) => _json(
    'POST',
    '/v1/stores/$storeId/stock/write-offs',
    StockWriteResult.fromJson,
    body: <String, Object?>{
      'note': ?note,
      'photo_blob_uri': ?photoUri,
      'lines': <Map<String, Object?>>[
        <String, Object?>{
          'batch_id': line.batch.id,
          'qty': formatQty(line.qty),
          'reason': reason.name,
        },
      ],
    },
    idempotent: true,
  );

  @override
  Future<StoreResult<StockWriteResult>> adjust(
    String storeId, {
    required StockBatch batch,
    required double countedQty,
    required String reason,
  }) => _json(
    'POST',
    '/v1/stores/$storeId/stock/adjustments',
    StockWriteResult.fromJson,
    body: <String, Object?>{
      'reason': reason,
      'lines': <Map<String, Object?>>[
        <String, Object?>{
          'batch_id': batch.id,
          'counted_qty': formatQty(countedQty),
        },
      ],
    },
    idempotent: true,
  );

  @override
  Future<StoreResult<List<CreditApproval>>> creditApprovals({
    String status = 'pending',
  }) async {
    final pages = await _pages(
      '/v1/credit-approvals',
      query: <String, Object?>{'status': status},
    );
    return pages.map(
      (rows) => <CreditApproval>[
        for (final r in rows) CreditApproval.fromJson(r),
      ],
    );
  }

  @override
  Future<StoreResult<CreditApproval>> decideCredit(
    String approvalId, {
    required bool approve,
    String? note,
  }) => _json(
    'POST',
    '/v1/credit-approvals/$approvalId/${approve ? 'approve' : 'reject'}',
    CreditApproval.fromJson,
    body: <String, Object?>{'note': ?note},
  );

  @override
  Future<StoreResult<int>> setCreditLimit(
    String farmerId, {
    required String storeId,
    required int limitPaise,
  }) => _json(
    'PUT',
    '/v1/farmers/$farmerId/credit-limit',
    (j) => (j['limit_paise'] as num?)?.toInt() ?? limitPaise,
    body: <String, Object?>{'store_id': storeId, 'limit_paise': limitPaise},
  );

  @override
  Future<StoreResult<DaySummary>> daySummary(String storeId, {String? date}) =>
      _json(
        'GET',
        '/v1/stores/$storeId/day-summary',
        DaySummary.fromJson,
        query: <String, Object?>{'date': ?date},
      );

  @override
  Future<StoreResult<DayClose>> closeDay(
    String storeId,
    DayCloseRequest request,
  ) => _json(
    'POST',
    '/v1/stores/$storeId/day-close',
    DayClose.fromJson,
    body: request.toJson(),
    idempotent: true,
  );

  @override
  Future<StoreResult<String>> uploadPhoto(Uint8List jpeg) async {
    final plan = ChunkedUploadPlanner.plan(jpeg);
    final init = await _json<Map<String, Object?>>(
      'POST',
      '/v1/uploads',
      (j) => j,
      body: <String, Object?>{
        'sha256': plan.fileSha256,
        'size_bytes': jpeg.length,
        'content_type': 'image/jpeg',
        'purpose': 'receipt',
        'chunk_size': defaultUploadChunkSize,
      },
    );
    if (!init.ok) return StoreResult.fail(init.failure!);
    final uploadId = init.value!['upload_id']! as String;
    for (final chunk in plan.chunks) {
      final (status, body) = await _call(
        'PUT',
        '/v1/uploads/$uploadId/chunks/${chunk.index}',
        bytes: plan.slice(jpeg, chunk),
        headers: <String, String>{'x-chunk-sha256': chunk.sha256},
      );
      if (status < 200 || status >= 300) {
        return StoreResult.fail(_failure(status, body));
      }
    }
    return _json(
      'POST',
      '/v1/uploads/$uploadId/complete',
      (j) => (j['blob_uri'] as String?) ?? '',
    );
  }
}
