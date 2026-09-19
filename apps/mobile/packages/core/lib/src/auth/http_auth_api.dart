import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'auth_api.dart';
import 'token_store.dart';

/// [AuthApi] over HTTP against `/v1/auth/*` (FA-001).
///
/// Errors are RFC 9457 problem+json; the stable `code` is mapped to the
/// result enums. The session is persisted in the [TokenStore] on success and
/// the refresh token is bound to the store's device id.
class HttpAuthApi implements AuthApi {
  /// Creates the client.
  HttpAuthApi({
    required this._store,
    this._config = const ApiConfig(),
    http.Client? client,
    this.deviceName,
    this.appVersion,
    this.platform = 'android',
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final TokenStore _store;
  final ApiConfig _config;
  final http.Client _client;

  /// Human-readable device label sent on login (optional).
  final String? deviceName;

  /// App version sent on login and refresh (shown in C101; optional).
  final String? appVersion;

  /// Platform sent on login (C101 device list).
  final String platform;

  /// Per-request timeout (the SLO says the OTP arrives within 20 s).
  final Duration timeout;

  static const Map<String, String> _headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json, application/problem+json',
  };

  /// Formats a 10-digit national number as E.164.
  static String e164(String phone) =>
      phone.startsWith('+') ? phone : '+91$phone';

  Future<_Reply> _post(String path, Map<String, Object?> body) async {
    final response = await _client
        .post(_config.resolve(path), headers: _headers, body: jsonEncode(body))
        .timeout(timeout);
    return _Reply(response.statusCode, response.body);
  }

  @override
  Future<OtpRequestOutcome> requestOtp(String phone) async {
    final _Reply reply;
    try {
      reply = await _post('/v1/auth/otp/send', <String, Object?>{
        'phone': e164(phone),
        'purpose': 'login',
        'device_id': await _store.deviceId(),
      });
    } on http.ClientException {
      return const OtpRequestOutcome(OtpRequestResult.network);
    } on TimeoutException {
      return const OtpRequestOutcome(OtpRequestResult.network);
    }
    final json = reply.json;
    if (reply.status == 202 || reply.status == 200) {
      return OtpRequestOutcome(
        OtpRequestResult.sent,
        resendsLeft: (json['resends_left'] as num?)?.toInt(),
        expiresIn: _seconds(json['expires_in']),
      );
    }
    final retryAfter = _seconds(json['retry_after']);
    return switch (reply.code) {
      'otp_locked' => OtpRequestOutcome(
        OtpRequestResult.locked,
        retryAfter: retryAfter,
      ),
      'otp_rate_limited' => OtpRequestOutcome(
        OtpRequestResult.rateLimited,
        retryAfter: retryAfter,
      ),
      'user_not_found' ||
      'user_disabled' => const OtpRequestOutcome(OtpRequestResult.notFound),
      'validation_error' => const OtpRequestOutcome(
        OtpRequestResult.invalidNumber,
      ),
      _ => const OtpRequestOutcome(OtpRequestResult.network),
    };
  }

  @override
  Future<OtpVerifyOutcome> verifyOtp(String phone, String otp) async {
    final _Reply reply;
    try {
      reply = await _post('/v1/auth/otp/verify', <String, Object?>{
        'phone': e164(phone),
        'code': otp,
        'device_id': await _store.deviceId(),
        if (deviceName != null) 'device_name': deviceName,
        'platform': platform,
        if (appVersion != null) 'app_version': appVersion,
      });
    } on http.ClientException {
      return const OtpVerifyOutcome(OtpVerifyResult.network);
    } on TimeoutException {
      return const OtpVerifyOutcome(OtpVerifyResult.network);
    }
    final json = reply.json;
    if (reply.status == 200) {
      final session = AuthSession.fromTokenResponse(json);
      await _store.write(session);
      return OtpVerifyOutcome(OtpVerifyResult.ok, session: session);
    }
    return switch (reply.code) {
      'otp_invalid' => OtpVerifyOutcome(
        OtpVerifyResult.invalid,
        attemptsLeft: (json['attempts_left'] as num?)?.toInt(),
      ),
      'otp_expired' => const OtpVerifyOutcome(OtpVerifyResult.expired),
      'otp_not_found' ||
      'user_not_found' ||
      'user_disabled' => const OtpVerifyOutcome(OtpVerifyResult.notFound),
      'otp_locked' => OtpVerifyOutcome(
        OtpVerifyResult.locked,
        retryAfter: _seconds(json['retry_after']),
      ),
      // SEC-020: an officer on a phone other than their bound device. The
      // refresh token stays bound to the device id sent above.
      'device_not_bound' => const OtpVerifyOutcome(
        OtpVerifyResult.deviceNotBound,
      ),
      _ => const OtpVerifyOutcome(OtpVerifyResult.network),
    };
  }

  /// Rotates the refresh token (SEC-020). Returns the new session, or `null`
  /// when the server rejected it (the stored session is cleared then).
  Future<AuthSession?> refresh() async {
    final current = await _store.read();
    if (current == null) return null;
    final _Reply reply;
    try {
      reply = await _post('/v1/auth/refresh', <String, Object?>{
        'refresh_token': current.refreshToken,
        'device_id': await _store.deviceId(),
        if (appVersion != null) 'app_version': appVersion,
      });
    } on http.ClientException {
      return current;
    } on TimeoutException {
      return current;
    }
    if (reply.status == 200) {
      final session = AuthSession.fromTokenResponse(reply.json);
      await _store.write(session);
      return session;
    }
    if (reply.status == 401 || reply.status == 403) {
      await _store.clear();
      return null;
    }
    return current;
  }

  /// Revokes the session server-side (best effort) and forgets it locally.
  Future<void> logout() async {
    final current = await _store.read();
    await _store.clear();
    if (current == null) return;
    try {
      await _post('/v1/auth/logout', <String, Object?>{
        'refresh_token': current.refreshToken,
      });
    } on http.ClientException {
      // Local sign-out still happened; the family expires on its own.
    } on TimeoutException {
      // Same.
    }
  }

  /// Fetches `/v1/me` with the stored access token; `null` when signed out.
  Future<AuthUser?> me() async {
    final current = await _store.read();
    if (current == null) return null;
    final response = await _client
        .get(
          _config.resolve('/v1/me'),
          headers: <String, String>{
            ..._headers,
            'Authorization': 'Bearer ${current.accessToken}',
          },
        )
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    return AuthUser.fromJson(jsonDecode(response.body) as Map<String, Object?>);
  }

  static Duration? _seconds(Object? value) =>
      value is num ? Duration(seconds: value.toInt()) : null;
}

class _Reply {
  _Reply(this.status, this.body);

  final int status;
  final String body;

  late final Map<String, Object?> json = _decode();

  String get code => (json['code'] as String?) ?? '';

  Map<String, Object?> _decode() {
    if (body.isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?>
          ? decoded
          : const <String, Object?>{};
    } on FormatException {
      return const <String, Object?>{};
    }
  }
}
