import 'dart:math' as math;

import 'package:farmerapp_agent/app.dart';
import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Sunday 2026-09-20 06:00 IST as UTC.
final DateTime t0 = DateTime.utc(2026, 9, 20, 0, 30);

/// Deterministic ids (`id-0001`, ...).
class SeqIds {
  int _n = 0;

  /// Next id.
  String call() => 'id-${(++_n).toString().padLeft(4, '0')}';
}

/// Everything the agent screens talk to, scriptable.
class AgentDeps {
  /// Creates the dependencies over an in-memory database.
  AgentDeps({bool online = true})
    : db = openInMemoryDatabase(),
      ids = SeqIds(),
      api = FakeSyncApi(),
      verify = FakeFarmerPhoneVerifyApi(),
      connectivity = FakeConnectivityMonitor(online: online),
      location = FakeLocationSource(),
      camera = FakeCameraSource(),
      photos = MemoryPhotoStore();

  /// The database.
  final AppDatabase db;

  /// Sequential ids.
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

  /// Now (UTC), fixed.
  DateTime now = t0;

  /// Overrides for the app.
  List<Override> overrides({
    String initialLocation = AppRoutes.farmers,
    Locale locale = const Locale('en'),
    AppThemeMode theme = AppThemeMode.light,
  }) => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now),
    idGeneratorProvider.overrideWithValue(ids.call),
    syncApiProvider.overrideWithValue(api),
    farmerPhoneVerifyApiProvider.overrideWithValue(verify),
    connectivityMonitorProvider.overrideWithValue(connectivity),
    locationSourceProvider.overrideWithValue(location),
    cameraSourceProvider.overrideWithValue(camera),
    photoStoreProvider.overrideWithValue(photos),
    mapTileProviderProvider.overrideWithValue(BlankTileProvider()),
    settingsStoreProvider.overrideWithValue(
      InMemorySettingsStore(AppSettings(locale: locale, themeMode: theme)),
    ),
    initialSettingsProvider.overrideWithValue(
      AppSettings(locale: locale, themeMode: theme),
    ),
    routerProvider.overrideWithValue(
      buildRouter(initialLocation: initialLocation),
    ),
  ];

  /// The app at [initialLocation].
  Widget app({
    String initialLocation = AppRoutes.farmers,
    Locale locale = const Locale('en'),
    AppThemeMode theme = AppThemeMode.light,
  }) => ProviderScope(
    overrides: overrides(
      initialLocation: initialLocation,
      locale: locale,
      theme: theme,
    ),
    child: const MitraApp(),
  );

  /// A bare container (drive the notifier without a screen).
  ProviderContainer container() => ProviderContainer(overrides: overrides());

  /// Closes everything.
  Future<void> dispose() async {
    await location.dispose();
    await connectivity.dispose();
    await db.close();
  }
}

/// Inserts a synced village.
Future<void> seedVillage(
  AppDatabase db, {
  String id = 'village-1',
  String name = 'Kondapur',
  String mandal = 'Sangareddy',
}) => LocalEntities(db).writeRef(
  SyncEntities.village,
  id,
  <String, Object?>{
    'name': name,
    'district': 'Medak',
    'mandal': mandal,
    'lat': farmOrigin.latitude,
    'lon': farmOrigin.longitude,
  },
  version: 1,
  now: t0,
);

/// Origin of the test farms.
const GeoPoint farmOrigin = GeoPoint(17.4, 78.4);

/// A point [east] / [north] metres from [farmOrigin].
GeoPoint offsetPoint(double east, double north) {
  final dLat = north / metresPerDegreeLatitude;
  final dLon =
      east /
      (metresPerDegreeLatitude * math.cos(farmOrigin.latitude * math.pi / 180));
  return GeoPoint(farmOrigin.latitude + dLat, farmOrigin.longitude + dLon);
}

/// A 100 m square (2.47 acres).
final List<GeoPoint> squareHectare = <GeoPoint>[
  farmOrigin,
  offsetPoint(100, 0),
  offsetPoint(100, 100),
  offsetPoint(0, 100),
];

/// Inserts a synced farmer with one farm and two plots.
Future<void> seedSyncedFarmer(
  AppDatabase db, {
  required String id,
  required String phone,
  String name = 'Ramesh Reddy',
  String villageId = 'village-1',
  bool withFarm = true,
}) async {
  final entities = LocalEntities(db);
  await entities.write(
    SyncEntities.farmer,
    id,
    <String, Object?>{
      'phone': phone,
      'name': name,
      'village_id': villageId,
      'landmark': 'Near the temple',
      'language': 'te',
      'preferred_language': 'te',
      'land_ownership': 'own',
      'source': 'field_officer',
      'phone_verified': true,
      'consent_marketing': true,
    },
    version: 1,
    dirty: false,
    now: t0,
  );
  if (!withFarm) return;
  await entities.write(
    SyncEntities.farm,
    'farm-$id',
    <String, Object?>{
      'farmer_id': id,
      'name': 'Home farm',
      'boundary': polygonToGeoJson(squareHectare),
      'area_acres': 2.5,
      'soil': 'black',
      'irrigation': 'borewell',
      'ownership': 'own',
      'photos': const <Object?>[],
    },
    version: 1,
    dirty: false,
    now: t0,
  );
  for (final (n, crop) in <String>['pilot:cotton', 'pilot:chilli'].indexed) {
    await entities.write(
      SyncEntities.cropPlot,
      'plot-$id-$n',
      <String, Object?>{
        'farm_id': 'farm-$id',
        'crop_id': crop,
        'variety': 'Bt',
        'season': 'kharif',
        'sowing_date': '2026-06-15',
        'area_acres': 1.0,
      },
      version: 1,
      dirty: false,
      now: t0.add(Duration(minutes: n)),
    );
  }
  await entities.write(
    SyncEntities.consentRecord,
    'consent-$id',
    <String, Object?>{
      'farmer_id': id,
      'purpose': 'data',
      'granted': true,
      'version': '2026-09-v1',
    },
    version: 1,
    dirty: false,
    now: t0,
  );
}

/// Sets the test surface to the reference phone size at 1x.
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
