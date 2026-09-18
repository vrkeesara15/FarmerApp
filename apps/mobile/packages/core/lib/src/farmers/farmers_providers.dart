import 'package:flutter_map/flutter_map.dart' show TileProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;

import '../db/app_database.dart';
import '../db/open_database.dart';
import 'camera_source.dart';
import 'farm_options.dart';
import 'farmer_repository.dart';
import 'location_source.dart';
import 'phone_verify_api.dart';
import 'photo_store.dart';
import 'registration_notifier.dart';

/// Local farmer data over [appDatabaseProvider].
final Provider<FarmerRepository> farmerRepositoryProvider =
    Provider<FarmerRepository>(
      (ref) => FarmerRepository(ref.watch(appDatabaseProvider)),
    );

/// Farmer OTP verification; apps override it with [HttpFarmerPhoneVerifyApi].
final Provider<FarmerPhoneVerifyApi> farmerPhoneVerifyApiProvider =
    Provider<FarmerPhoneVerifyApi>((ref) => FakeFarmerPhoneVerifyApi());

/// GPS; apps override it with [GeolocatorLocationSource].
final Provider<LocationSource> locationSourceProvider =
    Provider<LocationSource>((ref) => FakeLocationSource());

/// Camera; apps override it with [ImagePickerCameraSource].
final Provider<CameraSource> cameraSourceProvider = Provider<CameraSource>(
  (ref) => FakeCameraSource(),
);

/// Photo files; apps override it with [DocumentsPhotoStore].
final Provider<PhotoStore> photoStoreProvider = Provider<PhotoStore>(
  (ref) => MemoryPhotoStore(),
);

/// Map tiles for every `MapPanel` in the app: null = OSM over the network;
/// tests and goldens override it with `BlankTileProvider`.
final Provider<TileProvider?> mapTileProviderProvider = Provider<TileProvider?>(
  (ref) => null,
);

/// The A21 / A23 wizard state.
final NotifierProvider<RegistrationNotifier, RegistrationState>
registrationProvider =
    NotifierProvider<RegistrationNotifier, RegistrationState>(
      RegistrationNotifier.new,
    );

/// A20 rows for a filter, live.
final StreamProviderFamily<List<FarmerSummary>, FarmerListFilter>
farmerListProvider =
    StreamProvider.family<List<FarmerSummary>, FarmerListFilter>(
      (ref, filter) => ref.watch(farmerRepositoryProvider).watchFarmers(filter),
    );

/// A22 detail, live.
final StreamProviderFamily<FarmerDetail?, String> farmerDetailProvider =
    StreamProvider.family<FarmerDetail?, String>(
      (ref, id) => ref.watch(farmerRepositoryProvider).watchFarmer(id),
    );

/// Synced villages, live.
final StreamProvider<List<Village>> villagesProvider =
    StreamProvider<List<Village>>(
      (ref) => ref.watch(farmerRepositoryProvider).watchVillages(),
    );

/// Crop reference list (feed or pilot fallback).
final FutureProvider<List<CropRef>> cropsProvider =
    FutureProvider<List<CropRef>>(
      (ref) => ref.watch(farmerRepositoryProvider).crops(),
    );
