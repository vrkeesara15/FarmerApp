import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// NF-003: every enqueue writes the local row optimistically (dirty) and
/// one outbox op with a fresh idempotency key, in insertion order.
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late Outbox outbox;

  setUp(() {
    db = newDb();
    clock = FakeClock(t0);
    outbox = outboxFor(db, clock: clock, ids: SeqIds());
  });

  tearDown(() => db.close());

  test('enqueueCreate writes a dirty local row and a queued op', () async {
    final op = await outbox.enqueueCreate(
      SyncEntities.farmer,
      'f-1',
      farmerPayload(1),
    );
    expect(op.opId, 'op-0001');
    expect(op.action, SyncAction.create);
    expect(op.baseVersion, 0);
    expect(op.clientTs, t0);
    expect(op.payload['id'], 'f-1');

    final rows = await db.select(db.outboxTable).get();
    expect(rows, hasLength(1));
    expect(rows.single.state, 'queued');
    expect(rows.single.seq, 1);
    expect(rows.single.entity, 'farmer');
    expect(rows.single.entityId, 'f-1');
    expect(rows.single.clientTs, '2026-09-20T00:30:00.000Z');
    expect(jsonDecode(rows.single.payload), containsPair('name', 'Farmer 1'));

    final farmer = await db.select(db.farmers).getSingle();
    expect(farmer.name, 'Farmer 1');
    expect(farmer.phone, '+919876500001');
    expect(farmer.villageId, 'village-1');
    expect(farmer.landOwnership, 'own');
    expect(farmer.phoneVerified, isTrue);
    expect(farmer.dirty, isTrue);
    expect(farmer.deleted, isFalse);
    expect(farmer.version, 0);
  });

  test('enqueueUpdate merges into the row and queues in order', () async {
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', farmerPayload(1));
    clock.advance(const Duration(minutes: 5));
    final op = await outbox.enqueueUpdate(SyncEntities.farmer, 'f-1', {
      'landmark': 'opposite the school',
    });
    expect(op.action, SyncAction.update);
    expect(op.baseVersion, 0);
    expect(op.payload, <String, Object?>{'landmark': 'opposite the school'});
    expect(op.clientTs, t0.add(const Duration(minutes: 5)));

    final rows = await db.select(db.outboxTable).get();
    expect(rows.map((r) => r.seq), <int>[1, 2]);
    final farmer = await db.select(db.farmers).getSingle();
    expect(farmer.landmark, 'opposite the school');
    expect(farmer.name, 'Farmer 1', reason: 'merge keeps other fields');
    expect(farmer.dirty, isTrue);
  });

  test('enqueueUpdate uses the server version as base_version', () async {
    await db
        .into(db.farmers)
        .insert(
          LocalEntities.farmerFromData(
            'f-9',
            farmerPayload(9),
            version: 4,
            dirty: false,
            deleted: false,
            now: t0,
          ),
        );
    final op = await outbox.enqueueUpdate(SyncEntities.farmer, 'f-9', {
      'name': 'Renamed',
    });
    expect(op.baseVersion, 4);
    expect((await db.select(db.farmers).getSingle()).dirty, isTrue);
  });

  test('enqueueDelete tombstones the row', () async {
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', farmerPayload(1));
    final op = await outbox.enqueueDelete(SyncEntities.farmer, 'f-1');
    expect(op.action, SyncAction.delete);
    expect(op.payload, isEmpty);
    final farmer = await db.select(db.farmers).getSingle();
    expect(farmer.deleted, isTrue);
    expect(farmer.dirty, isTrue);
  });

  test('unknown entities are refused', () async {
    expect(
      () => outbox.enqueueCreate('khata_entry', 'k-1', {}),
      throwsArgumentError,
    );
  });

  test('farm boundary and photos round-trip through the typed row', () async {
    await outbox.enqueueCreate(
      SyncEntities.farm,
      'farm-1',
      farmPayload('f-1', photos: <Object?>['blob://a', 'blob://b']),
    );
    final row = await db.select(db.farms).getSingle();
    expect(row.farmerId, 'f-1');
    expect(row.areaAcres, 2.5);
    expect(jsonDecode(row.photos), <Object?>['blob://a', 'blob://b']);
    final back = await outbox.store.entities.read(SyncEntities.farm, 'farm-1');
    expect(back!.data['boundary'], farmPayload('f-1')['boundary']);
    expect(back.data['photos'], <Object?>['blob://a', 'blob://b']);
  });

  test('crop plot and consent rows keep their fields', () async {
    await outbox.enqueueCreate(
      SyncEntities.cropPlot,
      'plot-1',
      cropPlotPayload('farm-1'),
    );
    await outbox.enqueueCreate(SyncEntities.consentRecord, 'c-1', {
      'farmer_id': 'f-1',
      'purpose': 'marketing',
      'granted': true,
      'version': '2026-09-v1',
      'channel': 'agent_app',
    });
    final plot = await db.select(db.cropPlots).getSingle();
    expect(plot.season, 'kharif');
    expect(plot.sowingDate, '2026-06-15');
    expect(plot.areaAcres, 1.5);
    final consent = await db.select(db.consentRecords).getSingle();
    expect(consent.purpose, 'marketing');
    expect(consent.granted, isTrue);
    expect(consent.consentVersion, '2026-09-v1');
    expect(consent.version, 0, reason: 'row version is the envelope version');
    final back = await outbox.store.entities.read(
      SyncEntities.consentRecord,
      'c-1',
    );
    expect(back!.data['version'], '2026-09-v1');
  });

  test('an op referencing a queued photo waits for the upload', () async {
    final uploadId = await outbox.enqueueUpload(
      filePath: '/tmp/photo.jpg',
      bytes: photoBytes(1000),
      purpose: 'farm_photo',
    );
    final op = await outbox.enqueueCreate(
      SyncEntities.farm,
      'farm-1',
      farmPayload('f-1', photos: <Object?>[Outbox.uploadRef(uploadId)]),
    );
    final row = await db.select(db.outboxTable).getSingle();
    expect(row.dependsOnUploadId, uploadId);
    expect(op.payload['photos'], <Object?>['upload:$uploadId']);

    final upload = await db.select(db.uploads).getSingle();
    expect(upload.state, 'pending');
    expect(upload.sizeBytes, 1000);
    expect(upload.chunkSize, defaultUploadChunkSize);
    expect(upload.sha256, FakeSyncApi.hexSha256(photoBytes(1000)));

    // A completed upload no longer blocks new ops.
    await outbox.store.patchUpload(
      uploadId,
      const UploadsCompanion(
        state: Value<String>('complete'),
        blobUri: Value<String?>('blob://done'),
      ),
    );
    await outbox.enqueueUpdate(SyncEntities.farm, 'farm-1', {
      'photos': <Object?>[Outbox.uploadRef(uploadId)],
    });
    final ops = await db.select(db.outboxTable).get();
    expect(ops.last.dependsOnUploadId, isNull);
  });

  test('an edit after a rejection folds into the rejected op', () async {
    final create = await outbox.enqueueCreate(
      SyncEntities.farmer,
      'f-1',
      farmerPayload(1, phone: 'bad'),
    );
    await outbox.store.setResult(
      create.opId,
      OutboxState.rejected,
      error: const SyncError('validation_error', 'phone'),
    );
    final op = await outbox.enqueueUpdate(SyncEntities.farmer, 'f-1', {
      'phone': '+919876500001',
    });
    expect(op.opId, create.opId, reason: 'same idempotency key');
    expect(op.payload['phone'], '+919876500001');
    expect(op.payload['name'], 'Farmer 1');
    final rows = await db.select(db.outboxTable).get();
    expect(rows, hasLength(1));
    expect(rows.single.state, 'queued');
    expect(rows.single.lastError, isNull);
    expect(
      jsonDecode(rows.single.payload),
      containsPair('phone', '+919876500001'),
    );
  });

  test('uploadRefsIn and substituteUploadRefs walk nested JSON', () {
    final json = <String, Object?>{
      'photos': <Object?>['upload:a', 'blob://x'],
      'nested': <String, Object?>{'cover': 'upload:b'},
      'n': 1,
    };
    expect(uploadRefsIn(json), <String>{'a', 'b'});
    final out = substituteUploadRefs(json, <String, String>{'a': 'blob://a'});
    expect(out, <String, Object?>{
      'photos': <Object?>['blob://a', 'blob://x'],
      'nested': <String, Object?>{'cover': 'upload:b'},
      'n': 1,
    });
  });
}
