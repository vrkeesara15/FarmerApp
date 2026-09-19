import 'dart:async';
import 'dart:convert';
import 'dart:io' show TlsException;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'certificate_pinning.dart';
import 'device_attestation.dart';

/// Problem code of the 401 that orders a remote wipe (SEC-025).
const String deviceWipeRequiredCode = 'device_wipe_required';

/// Fires once when the server orders a remote wipe (SEC-025): a 401
/// `device_wipe_required` on any call, or `wipe_required: true` from
/// `GET /v1/devices/me/status`. The app's wipe controller listens.
class WipeSignal {
  final Completer<String> _completer = Completer<String>();

  /// Whether a wipe was ordered.
  bool get triggered => _completer.isCompleted;

  /// Completes with the reason of the first [trigger].
  Future<String> get onWipe => _completer.future;

  /// Orders the wipe (idempotent; the first reason wins).
  void trigger(String reason) {
    if (!_completer.isCompleted) _completer.complete(reason);
  }
}

/// Which [SensitiveAction]s a request performs (SEC-024 Play Integrity):
/// OTP verification, POS sales (credit → credit sale, other modes →
/// payment collection), payment creation, store day close, and `/v1/sync`
/// batches carrying a credit `order` or a `payment` op.
List<SensitiveAction> sensitiveActionsOf(
  String method,
  Uri url,
  List<int> body,
) {
  if (method.toUpperCase() != 'POST') return const <SensitiveAction>[];
  final path = url.path;
  if (path == '/v1/auth/otp/verify') {
    return const <SensitiveAction>[SensitiveAction.login];
  }
  if (RegExp(r'^/v1/stores/[^/]+/day-close$').hasMatch(path)) {
    return const <SensitiveAction>[SensitiveAction.dayClose];
  }
  if (path == '/v1/payments' || path.startsWith('/v1/payments/')) {
    return const <SensitiveAction>[SensitiveAction.paymentCollection];
  }
  final isPosSale = RegExp(r'^/v1/stores/[^/]+/pos/sales$').hasMatch(path);
  if (!isPosSale && path != '/v1/sync') return const <SensitiveAction>[];
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(body));
  } on FormatException {
    return const <SensitiveAction>[];
  }
  if (json is! Map) return const <SensitiveAction>[];
  if (isPosSale) {
    return json['mode'] == 'credit'
        ? const <SensitiveAction>[SensitiveAction.creditSale]
        : const <SensitiveAction>[SensitiveAction.paymentCollection];
  }
  final found = <SensitiveAction>{};
  final ops = json['ops'];
  if (ops is List) {
    for (final op in ops) {
      if (op is! Map) continue;
      final payload = op['payload'];
      if (op['entity'] == 'order' &&
          payload is Map &&
          payload['payment_mode'] == 'credit') {
        found.add(SensitiveAction.creditSale);
      } else if (op['entity'] == 'payment' && op['action'] == 'create') {
        found.add(SensitiveAction.paymentCollection);
      }
    }
  }
  return SensitiveAction.values.where(found.contains).toList();
}

/// The one HTTP client every API call of the apps goes through:
/// * adds the Play Integrity headers to sensitive requests
///   ([sensitiveActionsOf], [attestationHeaders]; never blocks);
/// * reports a 401 `device_wipe_required` to [wipeSignal] (SEC-025) — the
///   response still reaches the caller unchanged;
/// * turns TLS failures (pin mismatch, handshake) into
///   [http.ClientException], which every API client handles as a network
///   failure;
/// * runs over [inner] (the pinned `dart:io` client in the apps).
class SecureApiClient extends http.BaseClient {
  /// Creates the client.
  SecureApiClient({
    required this._inner,
    this.wipeSignal,
    this.attestation,
    this.attestationTimeout = const Duration(seconds: 3),
  });

  final http.Client _inner;

  /// Receives the wipe order; null = not reported.
  final WipeSignal? wipeSignal;

  /// Integrity token source; null = no integrity headers.
  final DeviceAttestation? attestation;

  /// Longest wait for a token before sending `unavailable`.
  final Duration attestationTimeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final attest = attestation;
    if (attest != null && request is http.Request) {
      final actions = sensitiveActionsOf(
        request.method,
        request.url,
        request.bodyBytes,
      );
      if (actions.isNotEmpty) {
        final headers = await attestationHeaders(
          attest,
          method: request.method,
          path: request.url.path,
          body: request.bodyBytes,
          actions: actions,
          timeout: attestationTimeout,
        );
        request.headers.addAll(headers.values);
      }
    }
    final http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } on TlsException catch (e) {
      // A pin mismatch or a failed handshake: surface it like any other
      // transport failure (callers treat ClientException as "offline").
      throw http.ClientException('TLS: ${e.message}', request.url);
    }
    final signal = wipeSignal;
    if (response.statusCode != 401 || signal == null) return response;
    final bytes = await response.stream.toBytes();
    if (problemCode(bytes) == deviceWipeRequiredCode) {
      signal.trigger('http_401:${request.url.path}');
    }
    return http.StreamedResponse(
      http.ByteStream.fromBytes(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

/// The problem+json `code` of a response body, if any.
String? problemCode(List<int> body) {
  if (body.isEmpty) return null;
  try {
    final json = jsonDecode(utf8.decode(body, allowMalformed: true));
    return json is Map ? json['code'] as String? : null;
  } on FormatException {
    return null;
  }
}

/// The apps' API client: [SecureApiClient] over a pinned `dart:io` client
/// ([createPinnedHttpClient], pins from `--dart-define=API_CERT_PINS`).
http.Client buildApiHttpClient({
  WipeSignal? wipeSignal,
  DeviceAttestation? attestation,
  CertificatePinning? pinning,
}) => SecureApiClient(
  inner: IOClient(
    createPinnedHttpClient(pinning ?? CertificatePinning.fromEnvironment()),
  ),
  wipeSignal: wipeSignal,
  attestation: attestation,
);
