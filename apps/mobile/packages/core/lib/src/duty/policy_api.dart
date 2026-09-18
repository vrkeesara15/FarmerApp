import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/api_config.dart';
import '../auth/auth_api.dart';
import '../auth/token_store.dart';
import '../sync/http_sync_api.dart' show ServerDateObserver, reportServerDate;
import '../sync/sync_models.dart';
import 'duty_models.dart';

/// `GET /v1/policies/location` and `GET /v1/duty/policy` (FA-011, VV-001).
/// Both throw [SyncTransportException] when the request does not complete;
/// callers keep the cached / bundled copy.
abstract interface class PolicyApi {
  /// The current location policy text and version.
  Future<LocationPolicyDoc> fetchLocationPolicy();

  /// Sampling / upload / auto-end settings.
  Future<DutyPolicy> fetchDutyPolicy();
}

/// Scriptable API for tests and previews.
class FakePolicyApi implements PolicyApi {
  /// Creates the fake with the bundled policy and default settings.
  FakePolicyApi({LocationPolicyDoc? location, DutyPolicy? duty})
    : location = location ?? LocationPolicyDoc.bundled(),
      duty = duty ?? const DutyPolicy();

  /// What [fetchLocationPolicy] answers.
  LocationPolicyDoc location;

  /// What [fetchDutyPolicy] answers.
  DutyPolicy duty;

  /// Every call throws while true.
  bool offline = false;

  /// Calls so far.
  int locationCalls = 0;

  /// Calls so far.
  int dutyCalls = 0;

  void _gate() {
    if (offline) throw const SyncTransportException('offline');
  }

  @override
  Future<LocationPolicyDoc> fetchLocationPolicy() async {
    locationCalls += 1;
    _gate();
    return location;
  }

  @override
  Future<DutyPolicy> fetchDutyPolicy() async {
    dutyCalls += 1;
    _gate();
    return duty;
  }
}

/// [PolicyApi] over HTTP with the bearer token from the [TokenStore].
class HttpPolicyApi implements PolicyApi {
  /// Creates the client.
  HttpPolicyApi({
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

  Future<Map<String, Object?>> _get(String path) async {
    var session = await _store.read();
    if (session == null) throw const SyncAuthException();
    if (session.isExpired() && refreshSession != null) {
      session = await refreshSession!() ?? session;
    }
    Future<http.Response> send(String token) => _client
        .get(
          config.resolve(path),
          headers: <String, String>{
            'Accept': 'application/json, application/problem+json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(timeout);
    http.Response response;
    try {
      response = await send(session.accessToken);
      if (response.statusCode == 401 && refreshSession != null) {
        final fresh = await refreshSession!();
        if (fresh == null) throw const SyncAuthException('session revoked');
        response = await send(fresh.accessToken);
      }
    } on http.ClientException catch (e) {
      throw SyncTransportException(e.message);
    } on SocketException catch (e) {
      throw SyncTransportException(e.message);
    } on TimeoutException {
      throw const SyncTransportException('timeout');
    }
    reportServerDate(response.headers['date'], onServerDate);
    if (response.statusCode == 401) {
      throw const SyncAuthException('session revoked');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncTransportException(
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, Object?>
        ? decoded
        : Map<String, Object?>.from(decoded as Map);
  }

  @override
  Future<LocationPolicyDoc> fetchLocationPolicy() async =>
      LocationPolicyDoc.fromJson(await _get('/v1/policies/location'));

  @override
  Future<DutyPolicy> fetchDutyPolicy() async =>
      DutyPolicy.fromJson(await _get('/v1/duty/policy'));
}
