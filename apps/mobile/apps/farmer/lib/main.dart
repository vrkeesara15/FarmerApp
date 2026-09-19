import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'main_version.dart';
import 'platform.dart';
import 'router.dart';
import 'security.dart';

/// App version sent on login and refresh (pubspec).
const String farmerAppVersion = kisanAppVersion;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await startKisan();
}

/// Builds the provider container and runs the app; a remote wipe (SEC-025)
/// tears this run down, wipes and calls [startKisan] again, which opens on
/// the "signed out by your administrator" screen.
Future<void> startKisan() async {
  // Real API (FA-001): base URL from --dart-define=API_BASE_URL, default
  // http://10.0.2.2:8000 (host machine from the Android emulator). One
  // client for every call: pinning, Play Integrity on login, wipe detection.
  final store = SecureTokenStore();
  final wipe = WipeSignal();
  final client = buildApiHttpClient(
    wipeSignal: wipe,
    attestation: const PlayIntegrityAttestation(),
  );
  final auth = HttpAuthApi(
    store: store,
    client: client,
    deviceName: 'Kisan Android',
    appVersion: farmerAppVersion,
  );
  // SEC-024 encrypted database. Settings (language, theme) are read from the
  // Drift kv table before the first frame (FA-004).
  final opener = EncryptedDatabaseOpener(keyStore: SecureDatabaseKeyStore());
  final db = openAppDatabase(opener: opener);
  final settings = await settingsOverrides(KvSettingsStore(db));
  final wipedBefore = await hasWipeNotice(db);
  final signedIn = !wipedBefore && await store.read() != null;
  final rest = RestJsonClient(
    store: store,
    client: client,
    refreshSession: auth.refresh,
  );
  final connectivity = PlusConnectivityMonitor();
  final qualityModel = TfliteQualityModel(
    loader: TfliteFlutterInterpreter.load,
  );
  final container = ProviderContainer(
    overrides: [
      ...settings,
      appDatabaseProvider.overrideWithValue(db),
      tokenStoreProvider.overrideWithValue(store),
      authApiProvider.overrideWithValue(auth),
      wipeSignalProvider.overrideWithValue(wipe),
      wipeNoticeProvider.overrideWithValue(wipedBefore),
      signedInProvider.overrideWithValue(signedIn),
      deviceStatusApiProvider.overrideWithValue(
        HttpDeviceStatusApi(rest, store),
      ),
      tenantSettingsApiProvider.overrideWithValue(HttpTenantSettingsApi(rest)),
      // M6 farmer app: profile, consent, orders, deletion request and visit
      // confirmation (REST), queued writes over /v1/sync, money through the
      // shared payments / khata / catalogue clients.
      kisanApiProvider.overrideWithValue(HttpKisanApi(rest)),
      syncApiProvider.overrideWithValue(
        HttpSyncApi(store: store, client: client, refreshSession: auth.refresh),
      ),
      connectivityMonitorProvider.overrideWithValue(connectivity),
      catalogApiProvider.overrideWithValue(HttpCatalogApi(rest)),
      paymentsApiProvider.overrideWithValue(HttpPaymentsApi(rest)),
      khataApiProvider.overrideWithValue(HttpKhataApi(rest)),
      // NF-009 audio prompts (device TTS until recorded clips exist), UPI /
      // call / WhatsApp intents, the visit QR scanner.
      audioPromptProvider.overrideWithValue(TtsAudioPrompt()),
      urlOpenerProvider.overrideWithValue(const LauncherUrlOpener()),
      barcodeScannerProvider.overrideWithValue(const MobileScannerQrScanner()),
      // M6 crop doctor (FM-004 .. FM-006): live camera with the guide
      // overlay, the DX-001 on-device gate (TFLite, heuristic fallback),
      // photos kept on disk until uploaded, results polled and synced.
      guidedCameraFactoryProvider.overrideWithValue(PluginGuidedCamera.new),
      onDeviceQualityModelProvider.overrideWithValue(qualityModel),
      photoStoreProvider.overrideWithValue(const DocumentsPhotoStore()),
      diagnosisApiProvider.overrideWithValue(HttpDiagnosisApi(rest)),
    ],
  );
  StreamSubscription<bool>? onlineSub;
  RemoteWipeCoordinator(
    signal: wipe,
    steps: (reason) => kisanWipeSteps(
      db: db,
      opener: opener,
      tokens: store,
      reason: reason,
      directories: appCacheDirectories,
    ),
    teardown: () async {
      runApp(const WipeInProgressView());
      await onlineSub?.cancel();
      container.dispose();
      client.close();
    },
    restart: startKisan,
  ).arm();
  if (!wipedBefore) {
    unawaited(
      checkDeviceStatusOnStart(
        tokens: store,
        api: container.read(deviceStatusApiProvider),
        signal: wipe,
        isOnline: connectivity.isOnline,
      ),
    );
    unawaited(container.read(tenantSettingsSyncProvider).pullIfStale());
    // DX-001: load the on-device model early (off the first frame's path).
    unawaited(qualityModel.load());
    // Queued consent / visit confirmations go out on start and whenever the
    // network returns (NF-002; the farmer app has no background sync).
    Future<void> flush() =>
        container.read(kisanFlushProvider)().catchError((Object _) {});
    if (signedIn) unawaited(flush());
    onlineSub = connectivity.onlineChanges.listen((online) {
      if (!online) return;
      unawaited(container.read(tenantSettingsSyncProvider).pullIfStale());
      unawaited(flush());
    });
  }
  runApp(
    UncontrolledProviderScope(container: container, child: const KisanApp()),
  );
}
