import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'farmers_harness.dart';

/// A20 / A22 data: search by name, phone last digits and village; village
/// and crop filters; detail with farms, plots, consents; rejected duplicate
/// linked to the synced farmer.
void main() {
  late AppDatabase db;
  late FarmerRepository repo;
  late LocalEntities entities;

  setUp(() async {
    db = newDb();
    repo = FarmerRepository(db);
    entities = LocalEntities(db);
    await seedVillage(db);
    await seedVillage(db, id: 'village-2', name: 'Nallagutta');
    await seedSyncedFarmer(
      db,
      id: 'f-1',
      phone: '+919876543210',
      name: 'Ramesh Reddy',
    );
    await seedSyncedFarmer(
      db,
      id: 'f-2',
      phone: '+919000011122',
      name: 'Lakshmi Devi',
      villageId: 'village-2',
    );
    await entities.write(
      SyncEntities.farm,
      'farm-1',
      farmPayload('f-1'),
      version: 1,
      dirty: false,
      now: t0,
    );
    await entities.write(
      SyncEntities.cropPlot,
      'plot-1',
      <String, Object?>{
        ...cropPlotPayload('farm-1'),
        'crop_id': 'pilot:cotton',
      },
      version: 1,
      dirty: false,
      now: t0,
    );
    await entities.write(
      SyncEntities.cropPlot,
      'plot-2',
      <String, Object?>{...cropPlotPayload('farm-1'), 'crop_id': 'pilot:paddy'},
      version: 1,
      dirty: false,
      now: t0,
    );
  });

  tearDown(() => db.close());

  test('lists every farmer with village and crops, newest first', () async {
    final rows = await repo.farmers();
    expect(rows.map((r) => r.name), <String>['Ramesh Reddy', 'Lakshmi Devi']);
    final ramesh = rows.first;
    expect(ramesh.villageName, 'Kondapur');
    expect(ramesh.crops.map((c) => c.code), <String>['cotton', 'paddy']);
    expect(ramesh.pendingSync, isFalse);
    expect(ramesh.phoneVerified, isTrue);
    expect(ramesh.phoneLast4, '3210');
    expect(rows.last.crops, isEmpty);
  });

  test('search by name, phone last digits and village', () async {
    expect(
      (await repo.farmers(const FarmerListFilter(query: 'lak'))).single.id,
      'f-2',
    );
    expect(
      (await repo.farmers(const FarmerListFilter(query: '3210'))).single.id,
      'f-1',
    );
    expect(
      (await repo.farmers(const FarmerListFilter(query: 'nalla'))).single.id,
      'f-2',
    );
    expect(await repo.farmers(const FarmerListFilter(query: 'zzz')), isEmpty);
  });

  test('village and crop filters', () async {
    expect(
      (await repo.farmers(const FarmerListFilter(villageId: 'village-2')))
          .single
          .id,
      'f-2',
    );
    expect(
      (await repo.farmers(const FarmerListFilter(cropId: 'pilot:paddy')))
          .single
          .id,
      'f-1',
    );
    expect(
      await repo.farmers(const FarmerListFilter(cropId: 'pilot:tomato')),
      isEmpty,
    );
  });

  test('offline-created farmers show as pending sync', () async {
    final later = t0.add(const Duration(minutes: 5));
    await Outbox(
      db,
      clock: () => later,
    ).enqueueCreate(SyncEntities.farmer, 'f-3', farmerPayload(3));
    final rows = await repo.farmers();
    expect(rows.first.id, 'f-3');
    expect(rows.first.pendingSync, isTrue);
  });

  test('watchFarmers emits again when a farmer is added', () async {
    final lengths = <int>[];
    final gotThree = Completer<void>();
    final sub = repo.watchFarmers().listen((rows) {
      lengths.add(rows.length);
      if (rows.length == 3 && !gotThree.isCompleted) gotThree.complete();
    });
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(lengths, <int>[2]);
    await Outbox(db)
        .enqueueCreate(SyncEntities.farmer, 'f-3', farmerPayload(3));
    await gotThree.future.timeout(const Duration(seconds: 5));
    expect(lengths.last, 3);
  });

  test('detail carries farms, plots, village and consents', () async {
    await entities.write(
      SyncEntities.consentRecord,
      'c-1',
      <String, Object?>{
        'farmer_id': 'f-1',
        'purpose': 'data',
        'granted': true,
        'version': '2026-09-v1',
      },
      version: 1,
      dirty: false,
      now: t0,
    );
    final d = (await repo.farmer('f-1'))!;
    expect(d.farmer.name, 'Ramesh Reddy');
    expect(d.village!.name, 'Kondapur');
    expect(d.farms.single.farm.areaAcres, 2.5);
    expect(d.farms.single.boundary, hasLength(4));
    expect(d.farms.single.plots, hasLength(2));
    expect(d.plots, hasLength(2));
    expect(d.consents.single.consentVersion, '2026-09-v1');
    expect(d.rejection, isNull);
    expect(d.isDuplicate, isFalse);
    expect(await repo.farmer('nope'), isNull);
  });

  test(
    'a rejected duplicate links to the synced farmer with the phone',
    () async {
      final outbox = Outbox(db);
      final op = await outbox.enqueueCreate(
        SyncEntities.farmer,
        'f-dup',
        farmerPayload(9, phone: '+919876543210'),
      );
      await SyncStore(db).setResult(
        op.opId,
        OutboxState.rejected,
        error: const SyncError(
          farmerPhoneExistsCode,
          'phone already registered',
        ),
      );
      final d = (await repo.farmer('f-dup'))!;
      expect(d.isDuplicate, isTrue);
      expect(d.rejection!.code, farmerPhoneExistsCode);
      expect(d.duplicateOfId, 'f-1');
      expect(d.pendingSync, isTrue);
      final row = (await repo.farmers()).firstWhere((r) => r.id == 'f-dup');
      expect(row.rejected, isTrue);
    },
  );

  test('crops fall back to the pilot list until the feed arrives', () async {
    expect((await repo.crops()).map((c) => c.code), contains('cotton'));
    expect((await repo.crops()).first.id, startsWith(CropRef.pilotIdPrefix));
    await entities.writeRef(
      SyncEntities.crop,
      'crop-uuid-1',
      <String, Object?>{
        'code': 'cotton',
        'name': 'Cotton',
        'names': {'te': 'పత్తి'},
      },
      version: 1,
      now: t0,
    );
    final crops = await repo.crops();
    expect(crops.single.id, 'crop-uuid-1');
    expect(crops.single.nameIn('te'), 'పత్తి');
    expect(crops.single.nameIn('kn'), 'Cotton');
  });

  test('villages come back sorted by name', () async {
    expect((await repo.villages()).map((v) => v.name), <String>[
      'Kondapur',
      'Nallagutta',
    ]);
  });
}
