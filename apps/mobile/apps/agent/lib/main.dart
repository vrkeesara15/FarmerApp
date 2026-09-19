import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'screens/store/store_platform.dart';
import 'widgets/share_plus_invoice_sharer.dart';

/// App version sent with duty sessions and policy acceptances (pubspec).
const String agentAppVersion = '0.1.0+1';

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
  // FA-028: device clock vs server clock from every response's Date header,
  // persisted so the next duty start / point carries the last known drift.
  final drift = ClockDriftTracker(
    onChanged: (d) => db.setValue(clockDriftKey, '$d'),
  );
  final rest = RestJsonClient(
    store: store,
    refreshSession: auth.refresh,
    onServerDate: drift.record,
  );
  final copy = DutyCopy.forLocale(
    (await KvSettingsStore(db).load()).locale ?? const Locale('en'),
  );
  final container = ProviderContainer(
    overrides: [
      ...settings,
      appDatabaseProvider.overrideWithValue(db),
      tokenStoreProvider.overrideWithValue(store),
      authApiProvider.overrideWithValue(auth),
      syncApiProvider.overrideWithValue(
        HttpSyncApi(
          store: store,
          refreshSession: auth.refresh,
          onServerDate: drift.record,
        ),
      ),
      // FA-010 / FA-011 / VV-001 / VV-007 / FA-028: duty toggle stack.
      clockDriftTrackerProvider.overrideWithValue(drift),
      locationSamplerProvider.overrideWithValue(GeolocatorLocationSampler()),
      foregroundDutyServiceProvider.overrideWithValue(
        FlutterForegroundDutyService(channelName: copy.channelName),
      ),
      dutyAlertsProvider.overrideWithValue(
        LocalDutyAlerts(channelName: copy.alertsChannelName),
      ),
      deviceConditionsProvider.overrideWithValue(PlusDeviceConditionsMonitor()),
      permissionGateProvider.overrideWithValue(const PermissionHandlerGate()),
      deviceIntegrityProbeProvider.overrideWithValue(
        const SafeDeviceIntegrityProbe(),
      ),
      policyApiProvider.overrideWithValue(
        HttpPolicyApi(
          store: store,
          refreshSession: auth.refresh,
          onServerDate: drift.record,
        ),
      ),
      appVersionProvider.overrideWithValue(agentAppVersion),
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
      // FA-020 .. FA-022: catalogue, nearest store, UPI QR / payment link,
      // A53 polling, invoice links and the khata (online reads; writes go
      // through the outbox).
      catalogApiProvider.overrideWithValue(HttpCatalogApi(rest)),
      paymentsApiProvider.overrideWithValue(HttpPaymentsApi(rest)),
      khataApiProvider.overrideWithValue(HttpKhataApi(rest)),
      invoiceSharerProvider.overrideWithValue(const SharePlusInvoiceSharer()),
      // ST-001 .. ST-007 store mode: online API (catalogue through the
      // officer client), barcode camera, PDF viewer; invoices are shared
      // through the same `invoiceSharerProvider` as A57.
      storeApiProvider.overrideWithValue(
        HttpStoreApi(
          store: store,
          refreshSession: auth.refresh,
          onServerDate: drift.record,
          catalogApi: HttpCatalogApi(rest),
        ),
      ),
      barcodeScannerProvider.overrideWithValue(
        const MobileScannerBarcodeScanner(),
      ),
      urlOpenerProvider.overrideWithValue(const LauncherUrlOpener()),
      // FA-016: confirmation request / officer-side OTP (online only).
      visitConfirmApiProvider.overrideWithValue(
        HttpVisitConfirmApi(
          store: store,
          refreshSession: auth.refresh,
          onServerDate: drift.record,
        ),
      ),
    ],
  );
  // Periodic background sync + immediate sync on reconnect (NF-002/NF-003).
  await container.read(syncSchedulerProvider).start();
  // An open duty session survives a restart: service + sampler resume
  // (FA-010); the policy version is refreshed when online (FA-011).
  await container.read(dutyControllerProvider.notifier).restore();
  unawaited(container.read(locationPolicyProvider.notifier).refresh());
  runApp(
    UncontrolledProviderScope(container: container, child: const MitraApp()),
  );
}
