import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../sync/sync_harness.dart';

export '../sync/sync_harness.dart';

/// Everything the wizard talks to, scriptable.
class WizardDeps {
  /// Creates the dependencies over a fresh in-memory database.
  WizardDeps({AppDatabase? db})
    : db = db ?? newDb(),
      clock = FakeClock(t0),
      ids = SeqIds(),
      api = FakeSyncApi(),
      verify = FakeFarmerPhoneVerifyApi(),
      connectivity = FakeConnectivityMonitor(),
      location = FakeLocationSource(),
      camera = FakeCameraSource(),
      photos = MemoryPhotoStore();

  /// The database.
  final AppDatabase db;

  /// Test clock.
  final FakeClock clock;

  /// Sequential ids (`op-0001`, ...): op ids and entity ids share the seq.
  final SeqIds ids;

  /// Sync server.
  final FakeSyncApi api;

  /// OTP server.
  final FakeFarmerPhoneVerifyApi verify;

  /// Network.
  final FakeConnectivityMonitor connectivity;

  /// GPS.
  final FakeLocationSource location;

  /// Camera.
  final FakeCameraSource camera;

  /// Photo files.
  final MemoryPhotoStore photos;

  /// Provider overrides for a container or a `ProviderScope`.
  List<Override> get overrides => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(clock.call),
    idGeneratorProvider.overrideWithValue(ids.call),
    syncApiProvider.overrideWithValue(api),
    farmerPhoneVerifyApiProvider.overrideWithValue(verify),
    connectivityMonitorProvider.overrideWithValue(connectivity),
    locationSourceProvider.overrideWithValue(location),
    cameraSourceProvider.overrideWithValue(camera),
    photoStoreProvider.overrideWithValue(photos),
  ];

  /// A container over [overrides].
  ProviderContainer container() {
    final c = ProviderContainer(overrides: overrides);
    return c;
  }

  /// Closes everything.
  Future<void> dispose() async {
    await location.dispose();
    await connectivity.dispose();
    await db.close();
  }
}

/// Origin of the test farms (Telangana).
const GeoPoint farmOrigin = GeoPoint(17.4, 78.4);

/// A point [east] / [north] metres from [farmOrigin].
GeoPoint offsetPoint(double east, double north) {
  final dLat = north / metresPerDegreeLatitude;
  final dLon =
      east /
      (metresPerDegreeLatitude * math.cos(farmOrigin.latitude * math.pi / 180));
  return GeoPoint(farmOrigin.latitude + dLat, farmOrigin.longitude + dLon);
}

/// A 100 m square (one hectare, 2.47 acres).
final List<GeoPoint> squareHectare = <GeoPoint>[
  farmOrigin,
  offsetPoint(100, 0),
  offsetPoint(100, 100),
  offsetPoint(0, 100),
];

/// A GPS fix at [point].
GeoFix fixAt(GeoPoint point, {double accuracy = 6, DateTime? time}) =>
    GeoFix(point: point, accuracyMetres: accuracy, time: time ?? t0);

/// Inserts a synced village.
Future<void> seedVillage(
  AppDatabase db, {
  String id = 'village-1',
  String name = 'Kondapur',
}) => db
    .into(db.villages)
    .insertOnConflictUpdate(
      VillagesCompanion.insert(
        id: id,
        name: name,
        district: const Value<String>('Medak'),
        mandal: const Value<String>('Sangareddy'),
        version: const Value<int>(1),
        updatedAt: t0,
      ),
    );

/// Inserts a synced (clean, version 1) farmer with [phone].
Future<void> seedSyncedFarmer(
  AppDatabase db, {
  required String id,
  required String phone,
  String name = 'Existing Farmer',
  String villageId = 'village-1',
}) => LocalEntities(db).write(
  SyncEntities.farmer,
  id,
  <String, Object?>{
    ...farmerPayload(1, phone: phone),
    'name': name,
    'village_id': villageId,
  },
  version: 1,
  dirty: false,
  now: t0,
);
