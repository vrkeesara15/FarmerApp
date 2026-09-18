import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// FA-025 push semantics against the scripted [FakeSyncApi]:
/// applied / duplicate / conflict / rejected, FIFO per entity, batch cap,
/// ops waiting on uploads, crash recovery.
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late FakeSyncApi api;
  late Outbox outbox;
  late SyncEngine engine;

  setUp(() {
    db = newDb();
    clock = FakeClock(t0);
    api = FakeSyncApi();
    outbox = outboxFor(db, clock: clock, ids: SeqIds());
    engine = engineFor(db, api, clock: clock);
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  Future<OutboxRow> opRow(String opId) async =>
      (await db.select(db.outboxTable).get()).firstWhere((r) => r.opId == opId);

  test('applied: local row takes the server version and is clean', () async {
    final op = await outbox.enqueueCreate(
      SyncEntities.farmer,
      'f-1',
      farmerPayload(1),
    );
    final report = await engine.syncNow();
    expect(report.ok, isTrue);
    expect(report.pushed, 1);
    expect(report.applied, 1);
    expect(report.calls, 1);
    expect((await opRow(op.opId)).state, 'applied');
    final farmer = await db.select(db.farmers).getSingle();
    expect(farmer.version, 1);
    expect(farmer.dirty, isFalse);
    expect(api.row('farmer', 'f-1')!.data['name'], 'Farmer 1');
    expect(api.requests.single.deviceId, 'device-1');
    expect(api.requests.single.cursor, isNull);
    expect(await engine.status(), SyncStatus.synced);
    expect((await engine.details()).lastSyncAt, t0);
  });

  test('duplicate: an op the server already has counts as success', () async {
    final op = await outbox.enqueueCreate(
      SyncEntities.farmer,
      'f-1',
      farmerPayload(1),
    );
    api.loseResponseNext = 1;
    final first = await engine.syncNow();
    expect(first.error, isNotNull);
    expect((await opRow(op.opId)).state, 'queued', reason: 'requeued');
    expect(api.appliedOps, hasLength(1), reason: 'server applied it');

    final second = await engine.syncNow();
    expect(second.ok, isTrue);
    expect(second.duplicate, 1);
    expect(second.applied, 0);
    expect((await opRow(op.opId)).state, 'duplicate');
    expect(api.appliedOps, hasLength(1), reason: 'exactly once');
    final farmer = await db.select(db.farmers).getSingle();
    expect(farmer.version, 1);
    expect(farmer.dirty, isFalse);
  });

  test('conflict: server wins and replaces the local row', () async {
    api.rows['farmer/f-1'] = FakeServerRow(
      version: 3,
      data: <String, Object?>{
        ...farmerPayload(1),
        'id': 'f-1',
        'name': 'Server name',
      },
    );
    await db
        .into(db.farmers)
        .insert(
          LocalEntities.farmerFromData(
            'f-1',
            farmerPayload(1),
            version: 1,
            dirty: false,
            deleted: false,
            now: t0,
          ),
        );
    final op = await outbox.enqueueUpdate(SyncEntities.farmer, 'f-1', {
      'name': 'Local name',
    });
    final report = await engine.syncNow();
    expect(report.conflict, 1);
    final row = await opRow(op.opId);
    expect(row.state, 'conflict');
    expect(
      jsonDecode(row.lastError!),
      containsPair('code', 'version_conflict'),
    );
    final farmer = await db.select(db.farmers).getSingle();
    expect(farmer.name, 'Server name');
    expect(farmer.version, 3);
    expect(farmer.dirty, isFalse);
    expect(await engine.status(), SyncStatus.synced);
  });

  test('conflict with no server row deletes the local row', () async {
    await db
        .into(db.farmers)
        .insert(
          LocalEntities.farmerFromData(
            'f-1',
            farmerPayload(1),
            version: 1,
            dirty: false,
            deleted: false,
            now: t0,
          ),
        );
    await outbox.enqueueUpdate(SyncEntities.farmer, 'f-1', {'name': 'x'});
    await engine.syncNow();
    expect(await db.select(db.farmers).get(), isEmpty);
  });

  test('rejected: kept with the error, not retried until asked', () async {
    api.validate = (op) => op.payload['phone'] == 'bad'
        ? const SyncError('validation_error', 'phone must be E.164')
        : null;
    final op = await outbox.enqueueCreate(
      SyncEntities.farmer,
      'f-1',
      farmerPayload(1, phone: 'bad'),
    );
    final report = await engine.syncNow();
    expect(report.rejected, 1);
    expect(report.ok, isTrue, reason: 'a rejection is not a transport error');
    final row = await opRow(op.opId);
    expect(row.state, 'rejected');
    expect(jsonDecode(row.lastError!), <String, Object?>{
      'code': 'validation_error',
      'detail': 'phone must be E.164',
    });
    expect((await db.select(db.farmers).getSingle()).dirty, isTrue);
    expect(
      await engine.status(),
      const SyncStatus(SyncStatusKind.failed, failed: 1),
    );

    await engine.syncNow();
    expect(api.requests.last.ops, isEmpty, reason: 'no automatic retry');

    // The user fixes the phone (A64 retry after edit) and retries.
    await outbox.enqueueUpdate(SyncEntities.farmer, 'f-1', {
      'phone': '+919876500001',
    });
    final retried = await engine.syncNow();
    expect(retried.applied, 1);
    expect((await opRow(op.opId)).state, 'applied');
    expect(api.row('farmer', 'f-1')!.data['phone'], '+919876500001');
    expect(await engine.status(), SyncStatus.synced);
  });

  test('retry() and discard() on a rejected op', () async {
    api.validate = (_) => const SyncError('validation_error', 'no');
    final a = await outbox.enqueueCreate(
      SyncEntities.farmer,
      'f-a',
      farmerPayload(1),
    );
    final b = await outbox.enqueueCreate(
      SyncEntities.farmer,
      'f-b',
      farmerPayload(2),
    );
    await engine.syncNow();
    expect((await engine.details()).failed.map((i) => i.opId), [
      a.opId,
      b.opId,
    ]);

    api.validate = null;
    await engine.retry(a.opId);
    expect((await opRow(a.opId)).state, 'queued');
    await engine.discard(b.opId);
    expect((await db.select(db.outboxTable).get()).map((r) => r.opId), [
      a.opId,
    ]);
    expect((await db.select(db.farmers).get()).map((f) => f.id), [
      'f-a',
    ], reason: 'a discarded create removes the optimistic row');
    await engine.syncNow();
    expect((await opRow(a.opId)).state, 'applied');
  });

  test('FIFO per entity, one op per entity per call, batch cap', () async {
    engine = engineFor(db, api, clock: clock, batchSize: 4);
    for (var n = 1; n <= 5; n++) {
      await outbox.enqueueCreate(SyncEntities.farmer, 'f-$n', farmerPayload(n));
      await outbox.enqueueUpdate(SyncEntities.farmer, 'f-$n', {
        'landmark': 'a',
      });
      await outbox.enqueueUpdate(SyncEntities.farmer, 'f-$n', {
        'landmark': 'b',
      });
    }
    final report = await engine.syncNow();
    expect(report.ok, isTrue);
    expect(report.pushed, 15);
    expect(report.applied, 15);
    for (final request in api.requests) {
      expect(request.ops.length, lessThanOrEqualTo(4));
      expect(
        request.ops.map((o) => o.entityId).toSet().length,
        request.ops.length,
        reason: 'one op per entity per call',
      );
    }
    for (var n = 1; n <= 5; n++) {
      final ops = api.appliedOps.where((o) => o.entityId == 'f-$n').toList();
      expect(ops.map((o) => o.action), [
        SyncAction.create,
        SyncAction.update,
        SyncAction.update,
      ]);
      expect(ops.map((o) => o.baseVersion), [0, 1, 2], reason: 'refreshed');
      expect(api.row('farmer', 'f-$n')!.data['landmark'], 'b');
      expect(api.row('farmer', 'f-$n')!.version, 3);
    }
    final farmers = await db.select(db.farmers).get();
    expect(farmers.every((f) => f.version == 3 && !f.dirty), isTrue);
  });

  test('never more than 200 ops in one call', () async {
    for (var n = 1; n <= 250; n++) {
      await outbox.enqueueCreate(SyncEntities.farmer, 'f-$n', farmerPayload(n));
    }
    final report = await engine.syncNow();
    expect(report.ok, isTrue);
    expect(report.pushed, 250);
    expect(api.requests.map((r) => r.ops.length), [200, 50]);
    expect(api.requests.first.ops.first.entityId, 'f-1');
    expect(api.requests.last.ops.last.entityId, 'f-250');
  });

  test(
    'an op waits for its photo upload and then carries the blob_uri',
    () async {
      final bytes = photoBytes(600 * 1024);
      engine = engineFor(
        db,
        api,
        clock: clock,
        readFile: (path) async => bytes,
      );
      final uploadId = await outbox.enqueueUpload(
        filePath: '/photos/1.jpg',
        bytes: bytes,
        purpose: 'farm_photo',
      );
      final op = await outbox.enqueueCreate(
        SyncEntities.farm,
        'farm-1',
        farmPayload('f-1', photos: <Object?>[Outbox.uploadRef(uploadId)]),
      );
      expect(
        await engine.status(),
        const SyncStatus(SyncStatusKind.pending, pending: 2),
      );
      final report = await engine.syncNow();
      expect(report.uploads, 1);
      expect(report.applied, 1);
      final blob = api.uploads.values.single.blobUri;
      expect(blob, startsWith('blob://fake/farm_photo/'));
      expect(api.row('farm', 'farm-1')!.data['photos'], [blob]);
      final row = await opRow(op.opId);
      expect(row.state, 'applied');
      expect(row.dependsOnUploadId, isNull);
      expect(jsonDecode((await db.select(db.farms).getSingle()).photos), [
        blob,
      ]);
      expect(await engine.status(), SyncStatus.synced);
    },
  );

  test('an op whose upload cannot be sent is held, not pushed', () async {
    engine = engineFor(
      db,
      api,
      clock: clock,
      readFile: (_) async => photoBytes(10),
    );
    final uploadId = await outbox.enqueueUpload(
      filePath: '/photos/1.jpg',
      bytes: photoBytes(10),
      purpose: 'farm_photo',
    );
    await outbox.enqueueCreate(
      SyncEntities.farm,
      'farm-1',
      farmPayload('f-1', photos: <Object?>[Outbox.uploadRef(uploadId)]),
    );
    api.failNext = 1; // the upload init fails
    final report = await engine.syncNow();
    expect(report.error, isNotNull);
    expect(api.requests, isEmpty, reason: 'no op sent without its photo');
    expect((await db.select(db.outboxTable).getSingle()).state, 'queued');
  });

  test('a locally failed upload rejects the op that needs it', () async {
    engine = engineFor(
      db,
      api,
      clock: clock,
      readFile: (_) async => photoBytes(10, seed: 99), // wrong bytes
    );
    final uploadId = await outbox.enqueueUpload(
      filePath: '/photos/1.jpg',
      bytes: photoBytes(10),
      purpose: 'farm_photo',
    );
    final op = await outbox.enqueueCreate(
      SyncEntities.farm,
      'farm-1',
      farmPayload('f-1', photos: <Object?>[Outbox.uploadRef(uploadId)]),
    );
    await engine.syncNow();
    expect((await db.select(db.uploads).getSingle()).state, 'failed');
    final row = await opRow(op.opId);
    expect(row.state, 'rejected');
    expect(jsonDecode(row.lastError!), containsPair('code', 'upload_failed'));
    expect((await engine.status()).failed, 2);
  });

  test('ops left in sending by a crash are pushed on the next run', () async {
    final op = await outbox.enqueueCreate(
      SyncEntities.farmer,
      'f-1',
      farmerPayload(1),
    );
    await (db.update(db.outboxTable)..where((t) => t.opId.equals(op.opId)))
        .write(const OutboxTableCompanion(state: Value<String>('sending')));
    final fresh = engineFor(db, api, clock: clock);
    addTearDown(fresh.dispose);
    final report = await fresh.syncNow();
    expect(report.applied, 1);
  });

  test('a batch the server does not answer is requeued, not looped', () async {
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', farmerPayload(1));
    // Drop every result by wrapping the fake.
    final dropping = _DroppingApi(api);
    engine = engineFor(db, dropping, clock: clock);
    final report = await engine.syncNow();
    expect(report.error?.code, 'empty_results');
    expect((await db.select(db.outboxTable).getSingle()).state, 'queued');
    expect(dropping.calls, 1);
  });

  test('a valid phone verification token is sent, its expiry is not', () async {
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', <String, Object?>{
      ...farmerPayload(1),
      phoneVerificationTokenKey: 'tok-1',
      phoneVerificationExpiresKey: t0
          .add(const Duration(minutes: 30))
          .toIso8601String(),
    });
    clock.advance(const Duration(minutes: 10));
    await engine.syncNow();
    final sent = api.appliedOps.single.payload;
    expect(sent[phoneVerificationTokenKey], 'tok-1');
    expect(sent.containsKey(phoneVerificationExpiresKey), isFalse);
    expect(sent['phone_verified'], isTrue);
  });

  test(
    'an expired phone verification token is dropped before sending',
    () async {
      await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', <String, Object?>{
        ...farmerPayload(1),
        phoneVerificationTokenKey: 'tok-1',
        phoneVerificationExpiresKey: t0
            .add(const Duration(minutes: 30))
            .toIso8601String(),
      });
      clock.advance(const Duration(hours: 2));
      await engine.syncNow();
      final sent = api.appliedOps.single.payload;
      expect(sent.containsKey(phoneVerificationTokenKey), isFalse);
      expect(sent.containsKey(phoneVerificationExpiresKey), isFalse);
      expect(sent['phone_verified'], isFalse);
      // The stored op and the local row agree with what was sent.
      final row = await opRow(api.appliedOps.single.opId);
      expect(
        SyncStore.payloadOf(row).containsKey(phoneVerificationTokenKey),
        isFalse,
      );
      final local = await engine.store.entities.read(
        SyncEntities.farmer,
        'f-1',
      );
      expect(local!.data['phone_verified'], isFalse);
      expect(local.dirty, isFalse);
    },
  );

  test('delete applied removes the local row', () async {
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', farmerPayload(1));
    await engine.syncNow();
    await outbox.enqueueDelete(SyncEntities.farmer, 'f-1');
    final report = await engine.syncNow();
    expect(report.applied, 1);
    expect(await db.select(db.farmers).get(), isEmpty);
    expect(api.row('farmer', 'f-1'), isNull);
  });

  test('applied ops are purged after keepTerminalFor', () async {
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', farmerPayload(1));
    await engine.syncNow();
    expect(await db.select(db.outboxTable).get(), hasLength(1));
    clock.advance(const Duration(days: 8));
    await engine.syncNow();
    expect(await db.select(db.outboxTable).get(), isEmpty);
  });
  test('an applied result that echoes server fields merges them into the '
      'local row (location_batch accepted / rejected, FA-010)', () async {
    final db = newDb();
    addTearDown(db.close);
    final api = FakeSyncApi()
      ..script = (op) => SyncOpResult(
        opId: op.opId,
        status: SyncResultStatus.applied,
        entityId: op.entityId,
        version: 1,
        server: const <String, Object?>{'accepted': 2, 'rejected': <Object?>[]},
      );
    final outbox = outboxFor(db);
    await outbox.enqueueCreate(SyncEntities.locationBatch, 'b-1', {
      'duty_session_id': 'ds-1',
      'device_id': 'device-1',
      'sent_at': '2026-09-21T03:30:00.000Z',
      'points': <Object?>[
        <String, Object?>{
          'ts': '2026-09-21T03:30:00.000Z',
          'lat': 17.4,
          'lon': 78.4,
        },
        <String, Object?>{
          'ts': '2026-09-21T03:32:00.000Z',
          'lat': 17.41,
          'lon': 78.4,
        },
      ],
    });
    final before = await LocalEntities(db)
        .read(SyncEntities.locationBatch, 'b-1');
    expect(before!.data['point_count'], 2, reason: 'points are not duplicated');
    expect(before.data.containsKey('points'), isFalse);
    final report = await engineFor(db, api).syncNow();
    expect(report.applied, 1);
    final after = await LocalEntities(db)
        .read(SyncEntities.locationBatch, 'b-1');
    expect(after!.version, 1);
    expect(after.dirty, isFalse);
    expect(after.data['accepted'], 2);
    expect(after.data['duty_session_id'], 'ds-1');
  });

  test('duty_session rows round-trip through the typed table, unknown server '
      'fields kept in extra', () async {
    final db = newDb();
    addTearDown(db.close);
    final entities = LocalEntities(db);
    final data = <String, Object?>{
      'start_at': '2026-09-21T03:30:00.000Z',
      'end_at': null,
      'start_point': <String, Object?>{
        'lat': 17.4,
        'lon': 78.4,
        'accuracy_m': 8.0,
      },
      'policy_version': '2026-09-v1',
      'device_id': 'device-1',
      'app_version': '0.1.0',
      'integrity': <String, Object?>{
        'is_mock': false,
        'is_rooted': true,
        'clock_drift_s': 3,
      },
      'km': 12.5,
      'stops': 4,
    };
    await entities.write(
      SyncEntities.dutySession,
      'ds-1',
      data,
      version: 3,
      dirty: false,
      now: DateTime.utc(2026, 9, 21, 4),
    );
    final row = await entities.read(SyncEntities.dutySession, 'ds-1');
    expect(row!.version, 3);
    expect(row.data['start_at'], '2026-09-21T03:30:00.000Z');
    expect(row.data['end_at'], isNull);
    expect(row.data['start_point'], data['start_point']);
    expect(row.data['integrity'], data['integrity']);
    expect(row.data['km'], 12.5);
    expect(row.data['stops'], 4);
    expect(row.data['policy_version'], '2026-09-v1');
    await entities.merge(SyncEntities.dutySession, 'ds-1', {
      'end_at': '2026-09-21T14:30:00.000Z',
      'end_reason': 'auto_time',
    }, now: DateTime.utc(2026, 9, 21, 15));
    final ended = await entities.read(SyncEntities.dutySession, 'ds-1');
    expect(ended!.data['end_reason'], 'auto_time');
    expect(ended.data['km'], 12.5);
    await entities.delete(SyncEntities.dutySession, 'ds-1');
    expect(await entities.read(SyncEntities.dutySession, 'ds-1'), isNull);
  });
}

class _DroppingApi implements SyncApi {
  _DroppingApi(this.inner);

  final FakeSyncApi inner;
  int calls = 0;

  @override
  Future<SyncResponse> sync(SyncRequest request) async {
    calls += 1;
    final response = await inner.sync(request);
    return SyncResponse(
      results: const <SyncOpResult>[],
      changes: response.changes,
      cursor: response.cursor,
      hasMore: response.hasMore,
    );
  }

  @override
  Future<UploadResult> completeUpload(String uploadId) =>
      inner.completeUpload(uploadId);

  @override
  Future<UploadSession?> getUpload(String uploadId) =>
      inner.getUpload(uploadId);

  @override
  Future<UploadSession> initUpload({
    required String sha256,
    required int sizeBytes,
    required String contentType,
    required String purpose,
    int chunkSize = defaultUploadChunkSize,
  }) => inner.initUpload(
    sha256: sha256,
    sizeBytes: sizeBytes,
    contentType: contentType,
    purpose: purpose,
    chunkSize: chunkSize,
  );

  @override
  Future<UploadSession> uploadChunk({
    required String uploadId,
    required int index,
    required Uint8List bytes,
    required String chunkSha256,
  }) => inner.uploadChunk(
    uploadId: uploadId,
    index: index,
    bytes: bytes,
    chunkSha256: chunkSha256,
  );
}
