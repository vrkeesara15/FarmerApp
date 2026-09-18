import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' as http;

import '../auth/api_config.dart';
import '../auth/auth_api.dart';
import '../auth/token_store.dart';
import '../sync/http_sync_api.dart' show ServerDateObserver, reportServerDate;
import 'visit_models.dart';

/// Outcome of `POST /v1/visits/{id}/confirm/request`.
enum ConfirmationRequestResult {
  /// The code / prompt / token is on its way; see the outcome fields.
  ok,

  /// Could not reach the server (offline, timeout, 5xx, auth).
  network,

  /// The visit is already confirmed through another channel.
  alreadyConfirmed,

  /// Farmer phone locked after wrong codes.
  locked,

  /// Too many codes for this farmer.
  rateLimited,

  /// The channel cannot be used (farmer without the app, no phone).
  channelInvalid,

  /// The visit does not exist on the server yet (check-in still queued).
  notFound,
}

/// Result of a confirmation request.
@immutable
class ConfirmationRequestOutcome {
  /// Creates the outcome.
  const ConfirmationRequestOutcome(
    this.result, {
    this.confirmation,
    this.phoneMasked,
    this.expiresIn,
    this.resendAfter,
    this.resendsLeft,
    this.token,
  });

  /// What happened.
  final ConfirmationRequestResult result;

  /// The server's `visit_confirmation` row (`VisitConfirmationOut`).
  final Map<String, Object?>? confirmation;

  /// `sms_otp`: where the code went.
  final String? phoneMasked;

  /// Code / token lifetime.
  final Duration? expiresIn;

  /// When a resend is allowed.
  final Duration? resendAfter;

  /// Resends left.
  final int? resendsLeft;

  /// `qr`: the signed token to render.
  final String? token;
}

/// Outcome of `POST /v1/visits/{id}/confirm` (officer-side SMS OTP).
enum OtpConfirmResult {
  /// Confirmed; [OtpConfirmOutcome.visit] is the updated visit.
  ok,

  /// Wrong code; the visit stays unconfirmed.
  invalid,

  /// Code timed out.
  expired,

  /// No code was requested (or it was consumed).
  notFound,

  /// Locked after too many wrong codes.
  locked,

  /// Already confirmed.
  alreadyConfirmed,

  /// Could not reach the server.
  network,
}

/// Result of an OTP confirmation.
@immutable
class OtpConfirmOutcome {
  /// Creates the outcome.
  const OtpConfirmOutcome(
    this.result, {
    this.visit,
    this.attemptsLeft,
    this.retryAfter,
  });

  /// What happened.
  final OtpConfirmResult result;

  /// `VisitDetailOut` on [OtpConfirmResult.ok].
  final Map<String, Object?>? visit;

  /// Wrong attempts left before lockout.
  final int? attemptsLeft;

  /// How long the farmer's phone stays locked.
  final Duration? retryAfter;
}

/// FA-016 online calls: request a confirmation through one channel and
/// complete the SMS OTP on the officer's phone. Push and QR are completed
/// by the farmer app; the officer app learns about them through the sync
/// pull (`visit.confirmed_at`).
abstract interface class VisitConfirmApi {
  /// `POST /v1/visits/{id}/confirm/request {channel}`.
  Future<ConfirmationRequestOutcome> request(
    String visitId,
    ConfirmationChannel channel,
  );

  /// `POST /v1/visits/{id}/confirm {channel: sms_otp, code}`.
  Future<OtpConfirmOutcome> confirm(String visitId, String code);
}

/// In-memory server for tests and previews: any request succeeds, the
/// code [code] confirms, five wrong codes lock, [offline] fails everything.
class FakeVisitConfirmApi implements VisitConfirmApi {
  /// Creates the fake.
  FakeVisitConfirmApi({
    this.code = '123456',
    this.maxAttempts = 5,
    DateTime Function()? clock,
  }) : _now = clock ?? (() => DateTime.now().toUtc());

  /// The code that confirms.
  final String code;

  /// Wrong codes before lockout.
  final int maxAttempts;

  final DateTime Function() _now;

  /// Every call answers `network` while true.
  bool offline = false;

  /// Visit ids the server does not know (check-in never arrived).
  final Set<String> unknownVisits = <String>{};

  /// `(visitId, channel)` requested, in order.
  final List<(String, ConfirmationChannel)> requests =
      <(String, ConfirmationChannel)>[];

  /// Confirmation row ids by visit id (last request).
  final Map<String, String> confirmationIds = <String, String>{};

  /// Visits confirmed through the OTP path.
  final Set<String> confirmed = <String>{};

  /// Row version the fake reports after an OTP confirmation.
  int confirmedVersion = 2;

  final Map<String, int> _wrong = <String, int>{};
  int _counter = 0;

  /// The QR / push token the fake issues for [visitId].
  static String tokenFor(String visitId) => 'visit-confirm-token-$visitId';

  @override
  Future<ConfirmationRequestOutcome> request(
    String visitId,
    ConfirmationChannel channel,
  ) async {
    if (offline) {
      return const ConfirmationRequestOutcome(
        ConfirmationRequestResult.network,
      );
    }
    if (unknownVisits.contains(visitId)) {
      return const ConfirmationRequestOutcome(
        ConfirmationRequestResult.notFound,
      );
    }
    if (confirmed.contains(visitId)) {
      return const ConfirmationRequestOutcome(
        ConfirmationRequestResult.alreadyConfirmed,
      );
    }
    if ((_wrong[visitId] ?? 0) >= maxAttempts) {
      return const ConfirmationRequestOutcome(
        ConfirmationRequestResult.locked,
        resendAfter: Duration(minutes: 15),
      );
    }
    requests.add((visitId, channel));
    _counter += 1;
    final id = 'conf-$_counter';
    confirmationIds[visitId] = id;
    final now = _now();
    final ttl = channel == ConfirmationChannel.smsOtp
        ? const Duration(minutes: 5)
        : const Duration(hours: 24);
    return ConfirmationRequestOutcome(
      ConfirmationRequestResult.ok,
      confirmation: <String, Object?>{
        'id': id,
        'visit_id': visitId,
        'channel': channel.wire,
        'status': ConfirmationStatuses.pending,
        'requested_at': now.toIso8601String(),
        'expires_at': now.add(ttl).toIso8601String(),
        'farmer_phone_last4': channel == ConfirmationChannel.smsOtp
            ? '3210'
            : null,
        'version': 1,
      },
      phoneMasked: channel == ConfirmationChannel.smsOtp
          ? '+91••••••3210'
          : null,
      expiresIn: ttl,
      resendAfter: channel == ConfirmationChannel.smsOtp
          ? const Duration(seconds: 30)
          : null,
      resendsLeft: channel == ConfirmationChannel.smsOtp ? 2 : null,
      token: channel == ConfirmationChannel.qr ? tokenFor(visitId) : null,
    );
  }

  @override
  Future<OtpConfirmOutcome> confirm(String visitId, String code) async {
    if (offline) return const OtpConfirmOutcome(OtpConfirmResult.network);
    if (confirmed.contains(visitId)) {
      return const OtpConfirmOutcome(OtpConfirmResult.alreadyConfirmed);
    }
    final confirmationId = confirmationIds[visitId];
    if (confirmationId == null) {
      return const OtpConfirmOutcome(OtpConfirmResult.notFound);
    }
    if ((_wrong[visitId] ?? 0) >= maxAttempts) {
      return const OtpConfirmOutcome(
        OtpConfirmResult.locked,
        retryAfter: Duration(minutes: 15),
      );
    }
    if (code != this.code) {
      final wrong = (_wrong[visitId] ?? 0) + 1;
      _wrong[visitId] = wrong;
      if (wrong >= maxAttempts) {
        return const OtpConfirmOutcome(
          OtpConfirmResult.locked,
          retryAfter: Duration(minutes: 15),
        );
      }
      return OtpConfirmOutcome(
        OtpConfirmResult.invalid,
        attemptsLeft: maxAttempts - wrong,
      );
    }
    confirmed.add(visitId);
    final now = _now().toIso8601String();
    return OtpConfirmOutcome(
      OtpConfirmResult.ok,
      visit: <String, Object?>{
        'id': visitId,
        'confirmation_channel': ConfirmationChannel.smsOtp.wire,
        'confirmed_at': now,
        'version': confirmedVersion,
        'confirmations': <Object?>[
          <String, Object?>{
            'id': confirmationId,
            'visit_id': visitId,
            'channel': ConfirmationChannel.smsOtp.wire,
            'status': ConfirmationStatuses.confirmed,
            'confirmed_at': now,
            'farmer_phone_last4': '3210',
            'version': 2,
          },
        ],
      },
    );
  }
}

/// [VisitConfirmApi] over HTTP with the officer's bearer token.
class HttpVisitConfirmApi implements VisitConfirmApi {
  /// Creates the client.
  HttpVisitConfirmApi({
    required TokenStore store,
    this.config = const ApiConfig(),
    http.Client? client,
    this.refreshSession,
    this.timeout = const Duration(seconds: 20),
    this.onServerDate,
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

  /// Clock-drift observer (FA-028).
  final ServerDateObserver? onServerDate;

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
      reportServerDate(response.headers['date'], onServerDate);
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
  Future<ConfirmationRequestOutcome> request(
    String visitId,
    ConfirmationChannel channel,
  ) async {
    final (status, body) = await _post('/v1/visits/$visitId/confirm/request', {
      'channel': channel.wire,
    });
    if (status == 200 || status == 202) {
      final confirmation = body['confirmation'];
      return ConfirmationRequestOutcome(
        ConfirmationRequestResult.ok,
        confirmation: confirmation is Map
            ? Map<String, Object?>.from(confirmation)
            : null,
        phoneMasked: body['phone_masked'] as String?,
        expiresIn: _seconds(body['expires_in']),
        resendAfter: _seconds(body['resend_after']),
        resendsLeft: (body['resends_left'] as num?)?.toInt(),
        token: body['token'] as String?,
      );
    }
    return switch (status) {
      404 => const ConfirmationRequestOutcome(
        ConfirmationRequestResult.notFound,
      ),
      409 => const ConfirmationRequestOutcome(
        ConfirmationRequestResult.alreadyConfirmed,
      ),
      422 || 400 => const ConfirmationRequestOutcome(
        ConfirmationRequestResult.channelInvalid,
      ),
      423 => ConfirmationRequestOutcome(
        ConfirmationRequestResult.locked,
        resendAfter: _seconds(body['retry_after']),
      ),
      429 => ConfirmationRequestOutcome(
        ConfirmationRequestResult.rateLimited,
        resendAfter: _seconds(body['retry_after']),
      ),
      _ => const ConfirmationRequestOutcome(ConfirmationRequestResult.network),
    };
  }

  @override
  Future<OtpConfirmOutcome> confirm(String visitId, String code) async {
    final (status, body) = await _post('/v1/visits/$visitId/confirm', {
      'channel': ConfirmationChannel.smsOtp.wire,
      'code': code,
    });
    if (status == 200) {
      return OtpConfirmOutcome(OtpConfirmResult.ok, visit: body);
    }
    final problemCode = body['code'] as String?;
    return switch ((status, problemCode)) {
      (401, 'otp_expired') => const OtpConfirmOutcome(OtpConfirmResult.expired),
      (401, 'otp_invalid') => OtpConfirmOutcome(
        OtpConfirmResult.invalid,
        attemptsLeft: (body['attempts_left'] as num?)?.toInt(),
      ),
      (404, _) => const OtpConfirmOutcome(OtpConfirmResult.notFound),
      (409, _) => const OtpConfirmOutcome(OtpConfirmResult.alreadyConfirmed),
      (423, _) => OtpConfirmOutcome(
        OtpConfirmResult.locked,
        retryAfter: _seconds(body['retry_after']),
      ),
      _ => const OtpConfirmOutcome(OtpConfirmResult.network),
    };
  }
}
