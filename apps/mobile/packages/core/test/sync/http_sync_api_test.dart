import 'dart:convert';
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'sync_harness.dart';

/// [HttpSyncApi] against a `MockClient`: request shapes of the contract,
/// bearer + refresh on 401, transport errors, upload endpoints.
void main() {
  AuthSession session(String token, {DateTime? expiresAt}) => AuthSession(
    accessToken: token,
    refreshToken: 'r',
    expiresAt:
        expiresAt ?? DateTime.now().toUtc().add(const Duration(minutes: 10)),
    user: const AuthUser(
      id: 'u',
      tenantId: 't',
      phone: '+919876543210',
      name: 'Officer',
      role: 'field_officer',
      language: 'te',
      status: 'active',
    ),
  );

  late InMemoryTokenStore store;
  late List<http.Request> seen;

  setUp(() {
    store = InMemoryTokenStore(deviceId: 'device-1', session: session('tok'));
    seen = <http.Request>[];
  });

  HttpSyncApi api(
    Future<http.Response> Function(http.Request request) handler, {
    Future<AuthSession?> Function()? refresh,
  }) => HttpSyncApi(
    store: store,
    config: const ApiConfig(baseUrl: 'http://api.test'),
    client: MockClient((request) {
      seen.add(request);
      return handler(request);
    }),
    refreshSession: refresh,
  );

  final op = SyncOp(
    opId: 'op-1',
    entity: 'farmer',
    action: SyncAction.create,
    entityId: 'f-1',
    baseVersion: 0,
    payload: farmerPayload(1),
    clientTs: t0,
  );

  test('sync posts the contract body with the bearer token', () async {
    final response = await api((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://api.test/v1/sync');
      expect(request.headers['Authorization'], 'Bearer tok');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['device_id'], 'device-1');
      expect(body['cursor'], '41');
      final ops = body['ops']! as List<Object?>;
      expect(ops, hasLength(1));
      expect(ops.single, <String, Object?>{
        'op_id': 'op-1',
        'entity': 'farmer',
        'action': 'create',
        'entity_id': 'f-1',
        'base_version': 0,
        'payload': farmerPayload(1),
        'client_ts': '2026-09-20T00:30:00.000Z',
      });
      return http.Response(
        jsonEncode(<String, Object?>{
          'results': <Object?>[
            <String, Object?>{
              'op_id': 'op-1',
              'status': 'applied',
              'entity_id': 'f-1',
              'version': 1,
              'error': null,
              'server': null,
            },
          ],
          'changes': <Object?>[
            <String, Object?>{
              'entity': 'village',
              'action': 'create',
              'entity_id': 'v-1',
              'version': 1,
              'data': <String, Object?>{'name': 'Kondapur'},
              'seq': 42,
            },
          ],
          'cursor': '42',
          'has_more': true,
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }).sync(SyncRequest(deviceId: 'device-1', cursor: '41', ops: [op]));
    expect(response.results.single.status, SyncResultStatus.applied);
    expect(response.results.single.version, 1);
    expect(response.changes.single.entity, 'village');
    expect(response.changes.single.data['name'], 'Kondapur');
    expect(response.cursor, '42');
    expect(response.hasMore, isTrue);
  });

  test('rejected and conflict results are parsed', () async {
    final response = await api(
      (_) async => http.Response(
        jsonEncode(<String, Object?>{
          'results': <Object?>[
            <String, Object?>{
              'op_id': 'op-1',
              'status': 'rejected',
              'entity_id': 'f-1',
              'version': null,
              'error': <String, Object?>{
                'code': 'duplicate_phone',
                'detail': 'already registered',
              },
              'server': null,
            },
            <String, Object?>{
              'op_id': 'op-2',
              'status': 'conflict',
              'entity_id': 'f-2',
              'version': 7,
              'error': null,
              'server': <String, Object?>{'id': 'f-2', 'name': 'S'},
            },
          ],
          'changes': <Object?>[],
          'cursor': '0',
          'has_more': false,
        }),
        200,
      ),
    ).sync(const SyncRequest(deviceId: 'd', cursor: null, ops: []));
    expect(
      response.results[0].error,
      const SyncError('duplicate_phone', 'already registered'),
    );
    expect(response.results[1].server, <String, Object?>{
      'id': 'f-2',
      'name': 'S',
    });
    expect(response.results[1].version, 7);
  });

  test('a 401 refreshes the session once and retries', () async {
    var calls = 0;
    final response = await api(
      (request) async {
        calls += 1;
        if (request.headers['Authorization'] == 'Bearer tok') {
          return http.Response('{"code":"token_expired"}', 401);
        }
        return http.Response(
          '{"results":[],"changes":[],"cursor":"1","has_more":false}',
          200,
        );
      },
      refresh: () async {
        final fresh = session('tok2');
        await store.write(fresh);
        return fresh;
      },
    ).sync(const SyncRequest(deviceId: 'd', cursor: null, ops: []));
    expect(response.cursor, '1');
    expect(calls, 2);
    expect(seen.last.headers['Authorization'], 'Bearer tok2');
  });

  test('an expired access token is refreshed before the call', () async {
    store = InMemoryTokenStore(
      deviceId: 'device-1',
      session: session('old', expiresAt: DateTime.utc(2020)),
    );
    await api(
      (_) async => http.Response(
        '{"results":[],"changes":[],"cursor":"1","has_more":false}',
        200,
      ),
      refresh: () async => session('new'),
    ).sync(const SyncRequest(deviceId: 'd', cursor: null, ops: []));
    expect(seen.single.headers['Authorization'], 'Bearer new');
  });

  test('no session or a revoked session is an auth failure', () async {
    store = InMemoryTokenStore(deviceId: 'device-1');
    await expectLater(
      api((_) async => http.Response('', 200))
          .sync(const SyncRequest(deviceId: 'd', cursor: null, ops: [])),
      throwsA(isA<SyncAuthException>()),
    );
    store = InMemoryTokenStore(deviceId: 'device-1', session: session('tok'));
    await expectLater(
      api(
        (_) async => http.Response('{}', 401),
        refresh: () async => null,
      ).sync(const SyncRequest(deviceId: 'd', cursor: null, ops: [])),
      throwsA(isA<SyncAuthException>()),
    );
  });

  test('5xx and network errors are transport exceptions', () async {
    await expectLater(
      api(
        (_) async => http.Response(
          '{"code":"upstream_down","detail":"db unavailable"}',
          503,
        ),
      ).sync(const SyncRequest(deviceId: 'd', cursor: null, ops: [])),
      throwsA(
        isA<SyncTransportException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.code, 'code', 'upstream_down')
            .having((e) => e.message, 'message', 'db unavailable'),
      ),
    );
    await expectLater(
      api((_) async => throw http.ClientException('reset'))
          .sync(const SyncRequest(deviceId: 'd', cursor: null, ops: [])),
      throwsA(isA<SyncTransportException>()),
    );
  });

  test('upload endpoints follow the contract', () async {
    final client = api((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path == '/v1/uploads') {
        expect(jsonDecode(request.body), <String, Object?>{
          'sha256': 'abc',
          'size_bytes': 300000,
          'content_type': 'image/jpeg',
          'purpose': 'farm_photo',
          'chunk_size': 262144,
        });
        return http.Response(
          '{"upload_id":"up-1","chunk_size":262144,"received_chunks":[],'
          '"expires_at":"2026-09-21T00:00:00Z"}',
          201,
        );
      }
      if (request.method == 'PUT' && path == '/v1/uploads/up-1/chunks/1') {
        expect(request.headers['Content-Type'], 'application/octet-stream');
        expect(request.headers['X-Chunk-Sha256'], 'chunkhash');
        expect(request.bodyBytes, [1, 2, 3]);
        return http.Response('{"received_chunks":[0,1]}', 200);
      }
      if (request.method == 'GET' && path == '/v1/uploads/up-1') {
        return http.Response(
          '{"upload_id":"up-1","chunk_size":262144,"received_chunks":[0,1]}',
          200,
        );
      }
      if (request.method == 'GET' && path == '/v1/uploads/gone') {
        return http.Response('{"code":"upload_not_found"}', 404);
      }
      if (request.method == 'POST' && path == '/v1/uploads/up-1/complete') {
        return http.Response(
          '{"blob_uri":"gs://b/x","sha256":"abc","size_bytes":300000,'
          '"content_type":"image/jpeg"}',
          200,
        );
      }
      return http.Response('nope', 500);
    });

    final init = await client.initUpload(
      sha256: 'abc',
      sizeBytes: 300000,
      contentType: 'image/jpeg',
      purpose: 'farm_photo',
    );
    expect(init.uploadId, 'up-1');
    expect(init.chunkSize, 262144);
    expect(init.receivedChunks, isEmpty);
    expect(init.expiresAt, DateTime.utc(2026, 9, 21));

    final ack = await client.uploadChunk(
      uploadId: 'up-1',
      index: 1,
      bytes: Uint8List.fromList([1, 2, 3]),
      chunkSha256: 'chunkhash',
    );
    expect(ack.uploadId, 'up-1');
    expect(ack.receivedChunks, [0, 1]);

    expect((await client.getUpload('up-1'))!.receivedChunks, [0, 1]);
    expect(await client.getUpload('gone'), isNull);

    final done = await client.completeUpload('up-1');
    expect(done.blobUri, 'gs://b/x');
    expect(done.sizeBytes, 300000);
  });
}
