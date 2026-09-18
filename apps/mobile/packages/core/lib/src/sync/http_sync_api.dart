import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/api_config.dart';
import '../auth/auth_api.dart';
import '../auth/token_store.dart';
import '../photo/chunked_upload_planner.dart';
import 'sync_api.dart';
import 'sync_models.dart';

/// Receives `(serverUtc, deviceUtc)` for every response that carried a
/// `Date` header.
typedef ServerDateObserver = void Function(
  DateTime serverUtc,
  DateTime deviceUtc,
);

/// Parses an HTTP `Date` header and hands it to [observer] (no-op when the
/// header is missing or malformed).
void reportServerDate(String? header, ServerDateObserver? observer) {
  if (header == null || observer == null) return;
  try {
    observer(HttpDate.parse(header).toUtc(), DateTime.now().toUtc());
  } on Exception {
    // A malformed Date header is not worth failing a request over.
  }
}

/// [SyncApi] over HTTP against `/v1/sync` and `/v1/uploads` (FA-025,
/// NF-003) with the bearer token from the [TokenStore].
///
/// A 401 triggers one [refreshSession] (normally `HttpAuthApi.refresh`) and
/// a retry; every failure to complete a request is a
/// [SyncTransportException] so the engine backs off. Per-op rejections come
/// back inside the 200 response and are never retried here.
class HttpSyncApi implements SyncApi {
  /// Creates the client.
  HttpSyncApi({
    required this._store,
    this._config = const ApiConfig(),
    http.Client? client,
    this.refreshSession,
    this.timeout = const Duration(seconds: 60),
    this.onServerDate,
  }) : _client = client ?? http.Client();

  final TokenStore _store;
  final ApiConfig _config;
  final http.Client _client;

  /// Rotates the session on 401; returns null when the user must log in.
  final Future<AuthSession?> Function()? refreshSession;

  /// Per-request timeout (chunk PUTs on 2G need headroom).
  final Duration timeout;

  /// Called with the server's `Date` header (UTC) and the device time at
  /// the moment the response arrived, on every completed request (FA-028
  /// clock drift, VV-002 `clock_drift_s`).
  final ServerDateObserver? onServerDate;

  static const Map<String, String> _jsonHeaders = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json, application/problem+json',
  };

  Future<http.Response> _authed(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var session = await _store.read();
    if (session == null) throw const SyncAuthException();
    if (session.isExpired() && refreshSession != null) {
      session = await refreshSession!() ?? session;
    }
    http.Response response;
    try {
      response = await send(_bearer(session.accessToken)).timeout(timeout);
      if (response.statusCode == 401 && refreshSession != null) {
        final fresh = await refreshSession!();
        if (fresh == null) throw const SyncAuthException('session revoked');
        response = await send(_bearer(fresh.accessToken)).timeout(timeout);
      }
    } on http.ClientException catch (e) {
      throw SyncTransportException(e.message);
    } on SocketException catch (e) {
      throw SyncTransportException(e.message);
    } on TimeoutException {
      throw const SyncTransportException('timeout');
    }
    if (response.statusCode == 401) {
      throw const SyncAuthException('session revoked');
    }
    reportServerDate(response.headers['date'], onServerDate);
    return response;
  }

  static Map<String, String> _bearer(String token) => <String, String>{
    ..._jsonHeaders,
    'Authorization': 'Bearer $token',
  };

  Map<String, Object?> _body(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return const <String, Object?>{};
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, Object?>
          ? decoded
          : Map<String, Object?>.from(decoded as Map);
    }
    Map<String, Object?> problem = const <String, Object?>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) problem = Map<String, Object?>.from(decoded);
    } on FormatException {
      // Not problem+json; keep the status only.
    }
    throw SyncTransportException(
      (problem['detail'] as String?) ??
          (problem['title'] as String?) ??
          'HTTP ${response.statusCode}',
      statusCode: response.statusCode,
      code: problem['code'] as String?,
    );
  }

  @override
  Future<SyncResponse> sync(SyncRequest request) async {
    final response = await _authed(
      (headers) => _client.post(
        _config.resolve('/v1/sync'),
        headers: headers,
        body: jsonEncode(request.toJson()),
      ),
    );
    return SyncResponse.fromJson(_body(response));
  }

  @override
  Future<UploadSession> initUpload({
    required String sha256,
    required int sizeBytes,
    required String contentType,
    required String purpose,
    int chunkSize = defaultUploadChunkSize,
  }) async {
    final response = await _authed(
      (headers) => _client.post(
        _config.resolve('/v1/uploads'),
        headers: headers,
        body: jsonEncode(<String, Object?>{
          'sha256': sha256,
          'size_bytes': sizeBytes,
          'content_type': contentType,
          'purpose': purpose,
          'chunk_size': chunkSize,
        }),
      ),
    );
    return UploadSession.fromJson(_body(response), chunkSize: chunkSize);
  }

  @override
  Future<UploadSession> uploadChunk({
    required String uploadId,
    required int index,
    required Uint8List bytes,
    required String chunkSha256,
  }) async {
    final response = await _authed(
      (headers) => _client.put(
        _config.resolve('/v1/uploads/$uploadId/chunks/$index'),
        headers: <String, String>{
          ...headers,
          'Content-Type': 'application/octet-stream',
          'X-Chunk-Sha256': chunkSha256,
        },
        body: bytes,
      ),
    );
    return UploadSession.fromJson(_body(response), uploadId: uploadId);
  }

  @override
  Future<UploadSession?> getUpload(String uploadId) async {
    final response = await _authed(
      (headers) => _client.get(
        _config.resolve('/v1/uploads/$uploadId'),
        headers: headers,
      ),
    );
    if (response.statusCode == 404 || response.statusCode == 410) return null;
    return UploadSession.fromJson(_body(response), uploadId: uploadId);
  }

  @override
  Future<UploadResult> completeUpload(String uploadId) async {
    final response = await _authed(
      (headers) => _client.post(
        _config.resolve('/v1/uploads/$uploadId/complete'),
        headers: headers,
      ),
    );
    return UploadResult.fromJson(_body(response));
  }
}
