import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' as http;

import '../auth/api_config.dart';
import '../auth/auth_api.dart';
import '../auth/token_store.dart';
import '../sync/http_sync_api.dart' show ServerDateObserver, reportServerDate;

/// `(status, body)` of one REST call. [status] is 0 when the request never
/// completed (offline, timeout, no session); [body] is the decoded JSON
/// object (problem+json on errors) or empty.
@immutable
class RestResponse {
  /// Creates the response.
  const RestResponse(this.status, [this.body = const <String, Object?>{}]);

  /// HTTP status, 0 = no answer.
  final int status;

  /// Decoded JSON object.
  final Map<String, Object?> body;

  /// 2xx.
  bool get ok => status >= 200 && status < 300;

  /// The request did not reach the server (or the server failed with 5xx).
  bool get isNetworkFailure => status == 0 || status >= 500;

  /// Problem `code`, if any.
  String? get code => body['code'] as String?;
}

/// Minimal authenticated JSON client for the M3 read / collect endpoints
/// (catalogue, nearest store, payments, khata, invoices). One 401 triggers
/// [refreshSession] and a retry, exactly like the other HTTP clients.
class RestJsonClient {
  /// Creates the client.
  RestJsonClient({
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

  /// Rotates the session on 401.
  final Future<AuthSession?> Function()? refreshSession;

  /// Per-request timeout.
  final Duration timeout;

  /// Clock-drift observer (FA-028).
  final ServerDateObserver? onServerDate;

  static const Map<String, String> _headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json, application/problem+json',
  };

  /// `GET path?query` (with extra [headers], e.g. `X-Device-Id`).
  Future<RestResponse> get(
    String path, {
    Map<String, Object?> query = const <String, Object?>{},
    Map<String, String> headers = const <String, String>{},
  }) => _call((token) {
    final uri = config.resolve(path);
    final params = <String, dynamic>{
      for (final e in query.entries)
        if (e.value != null)
          e.key: e.value is List
              ? <String>[for (final v in e.value! as List) '$v']
              : '${e.value}',
    };
    return _client
        .get(
          params.isEmpty ? uri : uri.replace(queryParameters: params),
          headers: <String, String>{
            ..._headers,
            ...headers,
            'Authorization': token,
          },
        )
        .timeout(timeout);
  });

  /// `POST path` with a JSON body.
  Future<RestResponse> post(String path, Map<String, Object?> body) => _call(
    (token) => _client
        .post(
          config.resolve(path),
          headers: <String, String>{..._headers, 'Authorization': token},
          body: jsonEncode(body),
        )
        .timeout(timeout),
  );

  /// `PUT path?query` with a JSON body (M7 `PUT /v1/me/beat?date=`).
  Future<RestResponse> put(
    String path,
    Map<String, Object?> body, {
    Map<String, Object?> query = const <String, Object?>{},
  }) => _call((token) {
    final uri = config.resolve(path);
    final params = <String, dynamic>{
      for (final e in query.entries)
        if (e.value != null) e.key: '${e.value}',
    };
    return _client
        .put(
          params.isEmpty ? uri : uri.replace(queryParameters: params),
          headers: <String, String>{..._headers, 'Authorization': token},
          body: jsonEncode(body),
        )
        .timeout(timeout);
  });

  /// `PATCH path` with a JSON body.
  Future<RestResponse> patch(String path, Map<String, Object?> body) => _call(
    (token) => _client
        .patch(
          config.resolve(path),
          headers: <String, String>{..._headers, 'Authorization': token},
          body: jsonEncode(body),
        )
        .timeout(timeout),
  );

  Future<RestResponse> _call(
    Future<http.Response> Function(String bearer) send,
  ) async {
    var session = await _store.read();
    if (session == null) return const RestResponse(0);
    if (session.isExpired() && refreshSession != null) {
      session = await refreshSession!() ?? session;
    }
    try {
      var response = await send('Bearer ${session.accessToken}');
      if (response.statusCode == 401 && refreshSession != null) {
        final fresh = await refreshSession!();
        if (fresh != null) {
          response = await send('Bearer ${fresh.accessToken}');
        }
      }
      reportServerDate(response.headers['date'], onServerDate);
      var decoded = const <String, Object?>{};
      if (response.body.isNotEmpty) {
        try {
          final json = jsonDecode(response.body);
          if (json is Map) decoded = Map<String, Object?>.from(json);
        } on FormatException {
          // Keep the status only.
        }
      }
      return RestResponse(response.statusCode, decoded);
    } on http.ClientException {
      return const RestResponse(0);
    } on SocketException {
      return const RestResponse(0);
    } on TimeoutException {
      return const RestResponse(0);
    }
  }
}
