import 'package:flutter/foundation.dart' show immutable;

import '../catalog/rest_json_client.dart';

/// Outcome kinds of the online payment calls.
enum PaymentCallResult {
  /// Done; see the body.
  ok,

  /// No network (or 5xx): try again or collect cash / credit.
  network,

  /// The server refused; see [PaymentCallOutcome.code].
  refused,
}

/// Result of `POST /v1/payments`, `GET /v1/payments/{id}` or
/// `GET /v1/invoices/{id}/pdf`.
@immutable
class PaymentCallOutcome {
  /// Creates the outcome.
  const PaymentCallOutcome(
    this.result, {
    this.body = const <String, Object?>{},
    this.status = 0,
  });

  /// From a REST response.
  factory PaymentCallOutcome.of(RestResponse r) => PaymentCallOutcome(
    r.ok
        ? PaymentCallResult.ok
        : r.isNetworkFailure
        ? PaymentCallResult.network
        : PaymentCallResult.refused,
    body: r.body,
    status: r.status,
  );

  /// What happened.
  final PaymentCallResult result;

  /// Response body (`PaymentCreated`, `PaymentStatusOut`, `SignedUrlOut` or
  /// a problem).
  final Map<String, Object?> body;

  /// HTTP status.
  final int status;

  /// Problem code on [PaymentCallResult.refused] (`already_paid`,
  /// `amount_mismatch`, `credit_limit_exceeded`, `phone_required`, ...).
  String? get code => body['code'] as String?;
}

/// FA-021 online calls: UPI QR / payment link creation, A53 polling and the
/// invoice PDF link (A57 share). Cash and credit go through the outbox.
abstract interface class PaymentsApi {
  /// `POST /v1/payments` with [body] (`PaymentCreate`).
  Future<PaymentCallOutcome> create(Map<String, Object?> body);

  /// `GET /v1/payments/{id}`.
  Future<PaymentCallOutcome> status(String paymentId);

  /// `GET /v1/invoices/{id}/pdf` (15-minute signed URL).
  Future<PaymentCallOutcome> invoicePdf(String invoiceId);
}

/// [PaymentsApi] over HTTP.
class HttpPaymentsApi implements PaymentsApi {
  /// Creates the client.
  HttpPaymentsApi(this._rest);

  final RestJsonClient _rest;

  @override
  Future<PaymentCallOutcome> create(Map<String, Object?> body) async =>
      PaymentCallOutcome.of(await _rest.post('/v1/payments', body));

  @override
  Future<PaymentCallOutcome> status(String paymentId) async =>
      PaymentCallOutcome.of(await _rest.get('/v1/payments/$paymentId'));

  @override
  Future<PaymentCallOutcome> invoicePdf(String invoiceId) async =>
      PaymentCallOutcome.of(await _rest.get('/v1/invoices/$invoiceId/pdf'));
}

/// In-memory payments server for tests and previews.
class FakePaymentsApi implements PaymentsApi {
  /// Creates the fake.
  FakePaymentsApi({
    DateTime Function()? clock,
    this.qrTtl = const Duration(minutes: 15),
  }) : _now = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _now;

  /// QR lifetime.
  final Duration qrTtl;

  /// Every call answers `network` while true.
  bool offline = false;

  /// Amount the fake charges when the body has none.
  int amountPaise = 45000;

  /// Next create is refused with this problem (then cleared).
  Map<String, Object?>? refuseNext;

  /// Bodies of `POST /v1/payments`, in order.
  final List<Map<String, Object?>> created = <Map<String, Object?>>[];

  /// `state` per payment id: `waiting` | `paid` | `failed`.
  final Map<String, String> states = <String, String>{};

  /// Status polls per payment id.
  final Map<String, int> polls = <String, int>{};

  /// Invoice ids with a PDF.
  final Set<String> invoices = <String>{};

  int _n = 0;

  @override
  Future<PaymentCallOutcome> create(Map<String, Object?> body) async {
    if (offline) return const PaymentCallOutcome(PaymentCallResult.network);
    final refuse = refuseNext;
    if (refuse != null) {
      refuseNext = null;
      return PaymentCallOutcome(
        PaymentCallResult.refused,
        body: refuse,
        status: (refuse['status'] as num?)?.toInt() ?? 409,
      );
    }
    created.add(body);
    final id = 'pay-${++_n}';
    final mode = body['mode']! as String;
    states[id] = 'waiting';
    return PaymentCallOutcome(
      PaymentCallResult.ok,
      status: 201,
      body: <String, Object?>{
        'payment_id': id,
        'mode': mode,
        'status': 'created',
        'amount_paise': body['amount_paise'] ?? amountPaise,
        'order_id': body['order_id'],
        'farmer_id': body['farmer_id'],
        'store_id': body['store_id'] ?? 'store-1',
        if (mode == 'upi_qr')
          'qr_payload': 'upi://pay?pa=farmerapp@razorpay&am=450.00&tr=$id',
        if (mode == 'payment_link') 'short_url': 'https://rzp.io/i/$id',
        'expires_at': _now().add(qrTtl).toIso8601String(),
        if (mode == 'payment_link') 'sent_via': body['channel'] ?? 'sms',
      },
    );
  }

  @override
  Future<PaymentCallOutcome> status(String paymentId) async {
    polls.update(paymentId, (n) => n + 1, ifAbsent: () => 1);
    if (offline) return const PaymentCallOutcome(PaymentCallResult.network);
    final state = states[paymentId];
    if (state == null) {
      return const PaymentCallOutcome(
        PaymentCallResult.refused,
        status: 404,
        body: <String, Object?>{'code': 'not_found'},
      );
    }
    return PaymentCallOutcome(
      PaymentCallResult.ok,
      status: 200,
      body: <String, Object?>{
        'id': paymentId,
        'state': state,
        'status': switch (state) {
          'paid' => 'paid',
          'failed' => 'failed',
          _ => 'created',
        },
        if (state == 'paid') 'paid_at': _now().toIso8601String(),
        if (state == 'failed') 'failure_reason': 'payment_failed',
      },
    );
  }

  @override
  Future<PaymentCallOutcome> invoicePdf(String invoiceId) async {
    if (offline) return const PaymentCallOutcome(PaymentCallResult.network);
    if (!invoices.contains(invoiceId)) {
      return const PaymentCallOutcome(
        PaymentCallResult.refused,
        status: 404,
        body: <String, Object?>{'code': 'not_found'},
      );
    }
    return PaymentCallOutcome(
      PaymentCallResult.ok,
      status: 200,
      body: <String, Object?>{
        'url': 'https://storage.example/invoices/$invoiceId.pdf?sig=test',
        'expires_at': _now().add(const Duration(minutes: 15)).toIso8601String(),
      },
    );
  }
}
