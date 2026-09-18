import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';

/// Builds the sync engine outside the widget tree (WorkManager runs it in a
/// background isolate with no ProviderScope).
SyncEngine buildSyncEngine({
  required AppDatabase db,
  required SecureTokenStore store,
  required HttpAuthApi auth,
}) => SyncEngine(
  db: db,
  api: HttpSyncApi(store: store, refreshSession: auth.refresh),
  deviceId: store.deviceId,
);

/// WorkManager entry point (FA-025): periodic every 15 min on network and
/// one-off on reconnect; both run [SyncEngine.syncNow] over the same file
/// database as the app.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) {
    return SyncScheduler.runBackgroundTask(taskName, () async {
      WidgetsFlutterBinding.ensureInitialized();
      final store = SecureTokenStore();
      return buildSyncEngine(
        db: openAppDatabase(),
        store: store,
        auth: HttpAuthApi(store: store, deviceName: 'Mitra Android'),
      );
    });
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real API (FA-001): base URL from --dart-define=API_BASE_URL, default
  // http://10.0.2.2:8000 (host machine from the Android emulator).
  final store = SecureTokenStore();
  final auth = HttpAuthApi(store: store, deviceName: 'Mitra Android');
  // Settings (language, theme) are read from the Drift kv table before the
  // first frame so the saved language is used immediately (FA-004).
  final db = openAppDatabase();
  final settings = await settingsOverrides(KvSettingsStore(db));
  await Workmanager().initialize(callbackDispatcher);
  final container = ProviderContainer(
    overrides: [
      ...settings,
      appDatabaseProvider.overrideWithValue(db),
      tokenStoreProvider.overrideWithValue(store),
      authApiProvider.overrideWithValue(auth),
      syncApiProvider.overrideWithValue(
        HttpSyncApi(store: store, refreshSession: auth.refresh),
      ),
      connectivityMonitorProvider.overrideWithValue(PlusConnectivityMonitor()),
      backgroundWorkSchedulerProvider.overrideWithValue(
        WorkmanagerSyncScheduler(),
      ),
      // FA-012 A21: farmer OTP, GPS walk-around, in-app camera, photo files.
      farmerPhoneVerifyApiProvider.overrideWithValue(
        HttpFarmerPhoneVerifyApi(store: store, refreshSession: auth.refresh),
      ),
      locationSourceProvider.overrideWithValue(
        const GeolocatorLocationSource(),
      ),
      cameraSourceProvider.overrideWithValue(ImagePickerCameraSource()),
      photoStoreProvider.overrideWithValue(const DocumentsPhotoStore()),
    ],
  );
  // Periodic background sync + immediate sync on reconnect (NF-002/NF-003).
  await container.read(syncSchedulerProvider).start();
  runApp(
    UncontrolledProviderScope(container: container, child: const MitraApp()),
  );
}
