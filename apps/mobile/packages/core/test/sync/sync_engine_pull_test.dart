import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// FA-025 pull: changes upsert and delete local rows, the cursor is stored,
/// `has_more` pages are followed, unknown entities land in `synced_refs`.
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late FakeSyncApi api;
  late SyncEngine engine;

  setUp(() {
    db = newDb();
    clock = FakeClock(t0);
    api = FakeSyncApi();
    engine = engineFor(db, api, clock: clock);
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  test('upserts and deletes known entities, stores the cursor', () async {
    api.addChange(
      entity: 'farmer',
      action: SyncAction.create,
      entityId: 'f-1',
      version: 2,
      data: <String, Object?>{...farmerPayload(1), 'id': 'f-1'},
    );
    api.addChange(
      entity: 'farm',
      action: SyncAction.create,
      entityId: 'farm-1',
      data: <String, Object?>{...farmPayload('f-1'), 'id': 'farm-1'},
    );
    final report = await engine.syncNow();
    expect(report.pulled, 2);
    final farmer = await db.select(db.farmers).getSingle();
    expect(farmer.name, 'Farmer 1');
    expect(farmer.version, 2);
    expect(farmer.dirty, isFalse);
    expect((await db.select(db.farms).getSingle()).areaAcres, 2.5);
    expect((await engine.store.state()).cursor, '2');

    api.addChange(
      entity: 'farmer',
      action: SyncAction.update,
      entityId: 'f-1',
      version: 3,
      data: <String, Object?>{
        ...farmerPayload(1),
        'id': 'f-1',
        'name': 'Renamed',
      },
    );
    api.addChange(
      entity: 'farm',
      action: SyncAction.delete,
      entityId: 'farm-1',
    );
    await engine.syncNow();
    expect(api.requests.last.cursor, '2', reason: 'sends the stored cursor');
    expect((await db.select(db.farmers).getSingle()).name, 'Renamed');
    expect((await db.select(db.farmers).getSingle()).version, 3);
    expect(await db.select(db.farms).get(), isEmpty);
    expect((await engine.store.state()).cursor, '4');
  });

  test('follows has_more until the feed is drained', () async {
    api.pageSize = 100;
    for (var n = 1; n <= 250; n++) {
      api.addChange(
        entity: 'farmer',
        action: SyncAction.create,
        entityId: 'f-$n',
        data: <String, Object?>{...farmerPayload(n), 'id': 'f-$n'},
      );
    }
    final report = await engine.syncNow();
    expect(report.pulled, 250);
    expect(report.calls, 3);
    expect(api.requests.map((r) => r.cursor), [null, '100', '200']);
    expect(await db.select(db.farmers).get(), hasLength(250));
    expect((await engine.store.state()).cursor, '250');
  });

  test('a dirty local row is not clobbered by a pulled change', () async {
    final outbox = outboxFor(db, clock: clock, ids: SeqIds());
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', farmerPayload(1));
    await engine.syncNow();
    await outbox.enqueueUpdate(SyncEntities.farmer, 'f-1', {'name': 'Mine'});
    api.addChange(
      entity: 'farmer',
      action: SyncAction.update,
      entityId: 'f-1',
      version: 5,
      data: <String, Object?>{
        ...farmerPayload(1),
        'id': 'f-1',
        'name': 'Theirs',
      },
    );
    // Make the push fail so the row stays dirty while the pull is applied.
    api.script = (op) => SyncOpResult(
      opId: op.opId,
      status: SyncResultStatus.rejected,
      entityId: op.entityId,
      error: const SyncError('validation_error', 'hold'),
    );
    await engine.syncNow();
    final farmer = await db.select(db.farmers).getSingle();
    expect(farmer.name, 'Mine');
    expect(farmer.dirty, isTrue);
  });

  test('unknown entities are kept as JSON in synced_refs', () async {
    api.addChange(
      entity: 'village',
      action: SyncAction.create,
      entityId: 'v-1',
      data: <String, Object?>{
        'id': 'v-1',
        'name': 'Kondapur',
        'district': 'Medak',
        'mandal': 'Sangareddy',
        'lat': 17.6,
        'lon': 78.1,
        'store_id': 's-1',
      },
    );
    api.addChange(
      entity: 'crop',
      action: SyncAction.create,
      entityId: 'crop-cotton',
      data: <String, Object?>{
        'id': 'crop-cotton',
        'code': 'cotton',
        'names': <String, Object?>{'en': 'Cotton', 'te': 'పత్తి'},
      },
    );
    api.addChange(
      entity: 'weather_alert',
      action: SyncAction.create,
      entityId: 'w-1',
      data: <String, Object?>{'id': 'w-1', 'kind': 'heat'},
    );
    await engine.syncNow();
    final refs = await db.select(db.syncedRefs).get();
    expect(refs.map((r) => '${r.entity}/${r.refId}'), [
      'village/v-1',
      'crop/crop-cotton',
      'weather_alert/w-1',
    ]);
    final village = await engine.store.entities.readRef('village', 'v-1');
    expect(village!['name'], 'Kondapur');
    final crop = await engine.store.entities.readRef('crop', 'crop-cotton');
    expect((crop!['names']! as Map)['te'], 'పత్తి');

    api.addChange(
      entity: 'weather_alert',
      action: SyncAction.delete,
      entityId: 'w-1',
    );
    api.addChange(
      entity: 'village',
      action: SyncAction.update,
      entityId: 'v-1',
      version: 2,
      data: <String, Object?>{'id': 'v-1', 'name': 'Kondapur (new)'},
    );
    await engine.syncNow();
    expect(await engine.store.entities.readRef('weather_alert', 'w-1'), isNull);
    final updated = (await db.select(db.syncedRefs).get()).firstWhere(
      (r) => r.refId == 'v-1',
    );
    expect(updated.version, 2);
  });

  test('a pull with nothing new leaves the cursor alone', () async {
    api.addChange(entity: 'crop', action: SyncAction.create, entityId: 'c');
    await engine.syncNow();
    await engine.syncNow();
    expect((await engine.store.state()).cursor, '1');
    expect(api.requests.last.cursor, '1');
  });
}
