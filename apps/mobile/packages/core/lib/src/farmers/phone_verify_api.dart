import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' as http;

import '../auth/api_config.dart';
import '../auth/auth_api.dart';
import '../auth/token_store.dart';

/// Outcome of `POST /v1/farmers/phone/verify/send`.
enum PhoneOtpSendResult {
  /// Code on its way to the farmer's phone.
  sent,

  /// Not a valid mobile number (or a staff phone).
  invalidNumber,

  /// Too many codes requested for this number.
  rateLimited,

  /// Number locked after wrong codes.
  locked,

  /// Could not reach the server (offline, timeout, 5xx, auth).
  network,
}

/// Result of sending a farmer OTP.
@immutable
class PhoneOtpSendOutcome {
  /// Creates the outcome.
  const PhoneOtpSendOutcome(
    this.result, {
    this.resendAfter,
    this.expiresIn,
    this.resendsLeft,
  });

  /// What happened.
  final PhoneOtpSendResult result;

  /// When a resend is allowed.
  final Duration? resendAfter;

  /// Code lifetime.
  final Duration? expiresIn;

  /// Resends left for this number.
  final int? resendsLeft;
}

/// Outcome of `POST /v1/farmers/phone/verify/confirm`.
enum PhoneOtpConfirmResult {
  /// Verified; [PhoneOtpConfirmOutcome.token] is set.
  ok,

  /// Wrong code.
  invalid,

  /// Code timed out.
  expired,

  /// No code was sent to this number (or it was consumed).
  notFound,

  /// Locked after too many wrong codes.
  locked,

  /// Could not reach the server.
  network,
}

/// Result of confirming a farmer OTP.
@immutable
class PhoneOtpConfirmOutcome {
  /// Creates the outcome.
  const PhoneOtpConfirmOutcome(
    this.result, {
    this.token,
    this.expiresIn,
    this.attemptsLeft,
    this.retryAfter,
  });

  /// What happened.
  final PhoneOtpConfirmResult result;

  /// `phone_verification_token` (30 minutes) on [PhoneOtpConfirmResult.ok].
  final String? token;

  /// Token lifetime.
  final Duration? expiresIn;

  /// Wrong attempts left before lockout.
  final int? attemptsLeft;

  /// How long the number stays locked.
  final Duration? retryAfter;
}

/// Verifies a farmer's phone before registration (FA-012, VA-F01):
/// `/v1/farmers/phone/verify/send` + `/confirm`. Phones are E.164.
abstract interface class FarmerPhoneVerifyApi {
  /// Sends a 6-digit code to [phone].
  Future<PhoneOtpSendOutcome> send(String phone);

  /// Confirms [code] for [phone]; returns the verification token.
  Future<PhoneOtpConfirmOutcome> confirm(String phone, String code);
}

/// In-memory verifier for tests and previews: any valid number, code
/// [code] verifies, five wrong codes lock the number, [offline] makes every
/// call a network failure.
class FakeFarmerPhoneVerifyApi implements FarmerPhoneVerifyApi {
  /// Creates the fake.
  FakeFarmerPhoneVerifyApi({
    this.code = '123456',
    this.tokenLifetime = const Duration(minutes: 30),
    this.maxAttempts = 5,
  });

  /// The code that verifies.
  final String code;

  /// Token lifetime reported to the client.
  final Duration tokenLifetime;

  /// Wrong codes before lockout.
  final int maxAttempts;

  /// Every call fails with [PhoneOtpSendResult.network] while true.
  bool offline = false;

  /// Phones a code was sent to (E.164), in order.
  final List<String> sent = <String>[];

  /// Codes confirmed successfully, by phone.
  final Map<String, String> tokens = <String, String>{};

  final Map<String, int> _wrong = <String, int>{};
  int _tokenCounter = 0;

  @override
  Future<PhoneOtpSendOutcome> send(String phone) async {
    if (offline) return const PhoneOtpSendOutcome(PhoneOtpSendResult.network);
    if (!RegExp(r'^\+91[6-9]\d{9}$').hasMatch(phone)) {
      return const PhoneOtpSendOutcome(PhoneOtpSendResult.invalidNumber);
    }
    if ((_wrong[phone] ?? 0) >= maxAttempts) {
      return const PhoneOtpSendOutcome(
        PhoneOtpSendResult.locked,
        resendAfter: Duration(minutes: 15),
      );
    }
    sent.add(phone);
    return const PhoneOtpSendOutcome(
      PhoneOtpSendResult.sent,
      resendAfter: Duration(seconds: 30),
      expiresIn: Duration(minutes: 5),
      resendsLeft: 2,
    );
  }

  @override
  Future<PhoneOtpConfirmOutcome> confirm(String phone, String code) async {
    if (offline) {
      return const PhoneOtpConfirmOutcome(PhoneOtpConfirmResult.network);
    }
    if (!sent.contains(phone)) {
      return const PhoneOtpConfirmOutcome(PhoneOtpConfirmResult.notFound);
    }
    if ((_wrong[phone] ?? 0) >= maxAttempts) {
      return const PhoneOtpConfirmOutcome(
        PhoneOtpConfirmResult.locked,
        retryAfter: Duration(minutes: 15),
      );
    }
    if (code != this.code) {
      final wrong = (_wrong[phone] ?? 0) + 1;
      _wrong[phone] = wrong;
      if (wrong >= maxAttempts) {
        return const PhoneOtpConfirmOutcome(
          PhoneOtpConfirmResult.locked,
          retryAfter: Duration(minutes: 15),
        );
      }
      return PhoneOtpConfirmOutcome(
        PhoneOtpConfirmResult.invalid,
        attemptsLeft: maxAttempts - wrong,
      );
    }
    _tokenCounter += 1;
    final token = 'pv-token-$_tokenCounter';
    tokens[phone] = token;
    return PhoneOtpConfirmOutcome(
      PhoneOtpConfirmResult.ok,
      token: token,
      expiresIn: tokenLifetime,
    );
  }
}

/// [FarmerPhoneVerifyApi] over HTTP with the officer's bearer token.
class HttpFarmerPhoneVerifyApi implements FarmerPhoneVerifyApi {
  /// Creates the client.
  HttpFarmerPhoneVerifyApi({
    required TokenStore store,
    this.config = const ApiConfig(),
    http.Client? client,
    this.refreshSession,
    this.timeout = const Duration(seconds: 20),
  }) : _store = store, // ignore: prefer_initializing_formals
       _client = client ?? http.Client();

  final TokenStore _store;
  final http.Client _client;

  /// API location.
  final ApiConfig config;

  /// Rotates the session on 401 (normally `HttpAuthApi.refresh`).
  final Future<AuthSession?> Function()? refreshSession;

  /// Per-request timeout.
  final Duration timeout;

  static const Map<String, String> _headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json, application/problem+json',
  };

  /// `(status, body)`; status 0 when the request did not complete.
  Future<(int, Map<String, Object?>)> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    var session = await _store.read();
    if (session == null) return (0, const <String, Object?>{});
    if (session.isExpired() && refreshSession != null) {
      session = await refreshSession!() ?? session;
    }
    try {
      var response = await _send(path, body, session.accessToken);
      if (response.statusCode == 401 && refreshSession != null) {
        final fresh = await refreshSession!();
        if (fresh != null) {
          response = await _send(path, body, fresh.accessToken);
        }
      }
      Map<String, Object?> decoded = const <String, Object?>{};
      if (response.body.isNotEmpty) {
        try {
          final json = jsonDecode(response.body);
          if (json is Map) decoded = Map<String, Object?>.from(json);
        } on FormatException {
          // Keep the status only.
        }
      }
      return (response.statusCode, decoded);
    } on http.ClientException {
      return (0, const <String, Object?>{});
    } on SocketException {
      return (0, const <String, Object?>{});
    } on TimeoutException {
      return (0, const <String, Object?>{});
    }
  }

  Future<http.Response> _send(
    String path,
    Map<String, Object?> body,
    String token,
  ) => _client
      .post(
        config.resolve(path),
        headers: <String, String>{
          ..._headers,
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      )
      .timeout(timeout);

  static Duration? _seconds(Object? v) =>
      v is num ? Duration(seconds: v.toInt()) : null;

  @override
  Future<PhoneOtpSendOutcome> send(String phone) async {
    final (status, body) = await _post('/v1/farmers/phone/verify/send', {
      'phone': phone,
    });
    return switch (status) {
      200 || 202 => PhoneOtpSendOutcome(
        PhoneOtpSendResult.sent,
        resendAfter: _seconds(body['resend_after']),
        expiresIn: _seconds(body['expires_in']),
        resendsLeft: (body['resends_left'] as num?)?.toInt(),
      ),
      422 || 400 => const PhoneOtpSendOutcome(PhoneOtpSendResult.invalidNumber),
      423 => PhoneOtpSendOutcome(
        PhoneOtpSendResult.locked,
        resendAfter: _seconds(body['retry_after']),
      ),
      429 => PhoneOtpSendOutcome(
        PhoneOtpSendResult.rateLimited,
        resendAfter: _seconds(body['retry_after']),
      ),
      _ => const PhoneOtpSendOutcome(PhoneOtpSendResult.network),
    };
  }

  @override
  Future<PhoneOtpConfirmOutcome> confirm(String phone, String code) async {
    final (status, body) = await _post('/v1/farmers/phone/verify/confirm', {
      'phone': phone,
      'code': code,
    });
    if (status == 200) {
      return PhoneOtpConfirmOutcome(
        PhoneOtpConfirmResult.ok,
        token: body['phone_verification_token'] as String?,
        expiresIn: _seconds(body['expires_in']),
      );
    }
    final problemCode = body['code'] as String?;
    return switch ((status, problemCode)) {
      (401, 'otp_expired') => const PhoneOtpConfirmOutcome(
        PhoneOtpConfirmResult.expired,
      ),
      (401, 'otp_invalid') => PhoneOtpConfirmOutcome(
        PhoneOtpConfirmResult.invalid,
        attemptsLeft: (body['attempts_left'] as num?)?.toInt(),
      ),
      (404, _) => const PhoneOtpConfirmOutcome(PhoneOtpConfirmResult.notFound),
      (423, _) => PhoneOtpConfirmOutcome(
        PhoneOtpConfirmResult.locked,
        retryAfter: _seconds(body['retry_after']),
      ),
      _ => const PhoneOtpConfirmOutcome(PhoneOtpConfirmResult.network),
    };
  }
}
