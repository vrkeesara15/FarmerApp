import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'main_version.dart';
import 'observability.dart';
import 'platform.dart';
import 'push.dart';
import 'router.dart';
import 'security.dart';
import 'widgets/share_plus_text_sharer.dart';

/// App version sent on login and refresh (pubspec).
const String farmerAppVersion = kisanAppVersion;

Future<void> main() async {
  // NF-005 / NF-001: the clock starts on the first line of main(), before the
  // bindings, so the measured cold start includes everything the farmer waits
  // for (docs/device-matrix.md).
  final startTrace = AppStartTrace();
  WidgetsFlutterBinding.ensureInitialized();
  // NF-014: Crashlytics, Performance and Remote Config, or the core's no-op
  // seams when this build has no Firebase (observability.dart).
  final obs = await FarmerObservability.create(appVersion: farmerAppVersion);
  // Everything after this point runs inside the guarded zone, so an error on
  // the start-up path is a reported crash rather than a blank screen.
  await runWithCrashReporting(
    obs.crashes,
    () => startKisan(obs: obs, startTrace: startTrace),
  );
}

/// Builds the provider container and runs the app; a remote wipe (SEC-025)
/// tears this run down, wipes and calls [startKisan] again, which opens on
/// the "signed out by your administrator" screen.
Future<void> startKisan({
  FarmerObservability obs = FarmerObservability.disabled,
  AppStartTrace? startTrace,
}) async {
  // Real API (FA-001): base URL from --dart-define=API_BASE_URL, default
  // http://10.0.2.2:8000 (host machine from the Android emulator). One
  // client for every call: pinning, Play Integrity on login, wipe detection.
  final store = SecureTokenStore();
  final wipe = WipeSignal();
  // SPEC 8.4: remote flags first -- a kill switch that only takes effect on
  // the *second* start is not a kill switch. A failed fetch keeps the local
  // defaults (remote_flags.dart), so this never blocks the start.
  final flagOverrides = await remoteFlagOverrides(obs.flags);
  final flags = obs.flags.flags;
  final client = buildApiHttpClient(
    wipeSignal: wipe,
    attestation: const PlayIntegrityAttestation(),
    // NF-014: every request carries a W3C traceparent, and the trace id goes
    // on the crash report, so a Crashlytics issue names the API trace that
    // was in flight when the app died.
    sampler: TraceSampler(ratio: flags.traceSampleRatio),
    onTrace: (trace) =>
        unawaited(obs.crashes.setCustomKey(CrashKeys.traceId, trace.traceId)),
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
  // FA-008: the cached tenant brand, also before the first frame.
  final branding = await brandingOverrides(db);
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
  // FA-007: FCM when the build has a Firebase configuration, otherwise a
  // transport that never produces a token (the inbox still works).
  final push = await FirebasePushService.create();
  final container = ProviderContainer(
    overrides: [
      ...settings,
      ...branding,
      ...flagOverrides,
      brandSurfaceProvider.overrideWithValue(BrandSurface.farmer),
      // NF-014: the seams the app reports through. Inert when this build has
      // no Firebase.
      crashReporterProvider.overrideWithValue(obs.crashes),
      performanceMonitorProvider.overrideWithValue(obs.performance),
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
      // M7 advisory (FM-007, FM-008, FM-009) and the FA-007 inbox / push.
      advisoryApiProvider.overrideWithValue(HttpAdvisoryApi(rest)),
      // M8 market and referrals (FM-012, FM-013): mandi prices, the invite
      // code, and the OS share sheet the WhatsApp / SMS invite goes through.
      marketApiProvider.overrideWithValue(HttpMarketApi(rest)),
      textSharerProvider.overrideWithValue(const SharePlusTextSharer()),
      // FA-007 push: the shared seam (packages/core/src/push/) with this
      // app's FCM adapter and its own token registry / inbox handler.
      pushServiceProvider.overrideWithValue(push),
      ...advisoryPushOverrides,
      pushAppVersionProvider.overrideWithValue(farmerAppVersion),
      pushDeviceIdProvider.overrideWithValue(await store.deviceId()),
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
      push: container.read(pushControllerProvider),
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
    if (signedIn) {
      unawaited(flush());
      // FA-007: register the FCM token after login (and on every start,
      // which also covers a token that rotated while the app was closed).
      unawaited(
        container
            .read(pushControllerProvider)
            .signedIn()
            .then<void>((_) {})
            .catchError((Object _) {}),
      );
      unawaited(
        container
            .read(pushControllerProvider)
            .openingMessage()
            .then<void>((_) {})
            .catchError((Object _) {}),
      );
    }
    onlineSub = connectivity.onlineChanges.listen((online) {
      if (!online) return;
      unawaited(container.read(tenantSettingsSyncProvider).pullIfStale());
      unawaited(flush());
    });
  }
  // NF-005: the app has its database, settings and session; the farmer can
  // act from the first frame on.
  startTrace?.markInteractive();
  runApp(
    UncontrolledProviderScope(container: container, child: const KisanApp()),
  );
  // Reports app_start once the engine has actually rasterised that frame.
  startTrace?.reportFirstFrame(obs.performance);
}
