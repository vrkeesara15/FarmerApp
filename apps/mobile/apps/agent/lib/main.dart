import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'observability.dart';
import 'push.dart';
import 'router.dart';
import 'screens/store/store_platform.dart';
import 'security.dart';
import 'speech.dart';
import 'widgets/share_plus_invoice_sharer.dart';

/// App version sent with duty sessions and policy acceptances (pubspec).
const String agentAppVersion = '0.1.0+1';

/// Builds the sync engine outside the widget tree (WorkManager runs it in a
/// background isolate with no ProviderScope).
SyncEngine buildSyncEngine({
  required AppDatabase db,
  required SecureTokenStore store,
  required HttpAuthApi auth,
  required http.Client client,
}) => SyncEngine(
  db: db,
  api: HttpSyncApi(store: store, client: client, refreshSession: auth.refresh),
  deviceId: store.deviceId,
);

/// SEC-024: the encrypted database (SQLCipher, key in the Android Keystore).
EncryptedDatabaseOpener mitraDatabaseOpener() =>
    EncryptedDatabaseOpener(keyStore: SecureDatabaseKeyStore());

/// WorkManager entry point (FA-025): periodic every 15 min on network and
/// one-off on reconnect; both run [SyncEngine.syncNow] over the same
/// encrypted database as the app, through the pinned, attested client. A
/// wipe order seen here is acted on by the next foreground start
/// (`GET /v1/devices/me/status`).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) {
    return SyncScheduler.runBackgroundTask(taskName, () async {
      WidgetsFlutterBinding.ensureInitialized();
      final store = SecureTokenStore();
      final client = buildApiHttpClient(
        attestation: const PlayIntegrityAttestation(),
      );
      return buildSyncEngine(
        db: openAppDatabase(opener: mitraDatabaseOpener()),
        store: store,
        client: client,
        auth: HttpAuthApi(
          store: store,
          client: client,
          deviceName: 'Mitra Android',
          appVersion: agentAppVersion,
        ),
      );
    });
  });
}

Future<void> main() async {
  // NF-005 / NF-001: the clock starts on the first line of main(), before the
  // bindings, so the measured cold start includes everything the officer
  // waits for (docs/device-matrix.md).
  final startTrace = AppStartTrace();
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  // FA-007: without google-services.json this returns a NoPushService and
  // the app runs with push off (see push.dart).
  final push = await FirebasePushService.create();
  if (push is FirebasePushService) {
    FirebaseMessaging.onBackgroundMessage(mitraBackgroundMessageHandler);
  }
  // NF-014: Crashlytics, Performance and Remote Config, or the core's no-op
  // seams when this build has no Firebase (observability.dart).
  final obs = await MitraObservability.create(appVersion: agentAppVersion);
  // Everything after this point runs inside the guarded zone, so an error on
  // the start-up path is a reported crash rather than a blank screen.
  await runWithCrashReporting(
    obs.crashes,
    () => startMitra(push: push, obs: obs, startTrace: startTrace),
  );
}

/// Builds the provider container and runs the app. A remote wipe (SEC-025)
/// tears this run down, wipes, and calls [startMitra] again: the fresh
/// database carries the A08 notice, so the router opens "Signed out by
/// your administrator".
Future<void> startMitra({
  PushService push = const NoPushService(),
  MitraObservability obs = MitraObservability.disabled,
  AppStartTrace? startTrace,
}) async {
  // Real API (FA-001): base URL from --dart-define=API_BASE_URL, default
  // http://10.0.2.2:8000 (host machine from the Android emulator). Every
  // call goes through one client: certificate pinning (API_CERT_PINS), Play
  // Integrity on login and sensitive actions, wipe detection (SEC-024/025).
  final store = SecureTokenStore();
  final wipe = WipeSignal();
  // SPEC 8.4: remote flags first -- a kill switch that only takes effect on
  // the *second* start is not a kill switch. A failed fetch keeps the local
  // defaults (remote_flags.dart), which matters here: an officer can be
  // offline for a whole working day (NF-002).
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
    deviceName: 'Mitra Android',
    appVersion: agentAppVersion,
  );
  // Settings (language, theme) are read from the Drift kv table before the
  // first frame so the saved language is used immediately (FA-004).
  final opener = mitraDatabaseOpener();
  final db = openAppDatabase(opener: opener);
  final settings = await settingsOverrides(KvSettingsStore(db));
  final wipedBefore = await hasWipeNotice(db);
  // FA-028: device clock vs server clock from every response's Date header,
  // persisted so the next duty start / point carries the last known drift.
  final drift = ClockDriftTracker(
    onChanged: (d) => db.setValue(clockDriftKey, '$d'),
  );
  final qualityModel = TfliteQualityModel(
    loader: TfliteFlutterInterpreter.load,
  );
  final rest = RestJsonClient(
    store: store,
    client: client,
    refreshSession: auth.refresh,
    onServerDate: drift.record,
  );
  final copy = DutyCopy.forLocale(
    (await KvSettingsStore(db).load()).locale ?? const Locale('en'),
  );
  final dutyService = FlutterForegroundDutyService(
    channelName: copy.channelName,
  );
  final sampler = GeolocatorLocationSampler();
  final connectivity = PlusConnectivityMonitor();
  final container = ProviderContainer(
    overrides: [
      ...settings,
      ...flagOverrides,
      // NF-014: the seams the app reports through. Inert when this build has
      // no Firebase.
      crashReporterProvider.overrideWithValue(obs.crashes),
      performanceMonitorProvider.overrideWithValue(obs.performance),
      appDatabaseProvider.overrideWithValue(db),
      tokenStoreProvider.overrideWithValue(store),
      authApiProvider.overrideWithValue(auth),
      syncApiProvider.overrideWithValue(
        HttpSyncApi(
          store: store,
          client: client,
          refreshSession: auth.refresh,
          onServerDate: drift.record,
        ),
      ),
      // SEC-025 remote wipe, SEC-020 / M2 follow-up tenant settings.
      wipeSignalProvider.overrideWithValue(wipe),
      wipeNoticeProvider.overrideWithValue(wipedBefore),
      deviceStatusApiProvider.overrideWithValue(
        HttpDeviceStatusApi(rest, store),
      ),
      tenantSettingsApiProvider.overrideWithValue(HttpTenantSettingsApi(rest)),
      // FA-010 / FA-011 / VV-001 / VV-007 / FA-028: duty toggle stack.
      clockDriftTrackerProvider.overrideWithValue(drift),
      locationSamplerProvider.overrideWithValue(sampler),
      foregroundDutyServiceProvider.overrideWithValue(dutyService),
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
          client: client,
          refreshSession: auth.refresh,
          onServerDate: drift.record,
        ),
      ),
      appVersionProvider.overrideWithValue(agentAppVersion),
      connectivityMonitorProvider.overrideWithValue(connectivity),
      backgroundWorkSchedulerProvider.overrideWithValue(
        WorkmanagerSyncScheduler(),
      ),
      // FA-012 A21: farmer OTP, GPS walk-around, in-app camera, photo files.
      farmerPhoneVerifyApiProvider.overrideWithValue(
        HttpFarmerPhoneVerifyApi(
          store: store,
          client: client,
          refreshSession: auth.refresh,
        ),
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
          client: client,
          refreshSession: auth.refresh,
          onServerDate: drift.record,
          catalogApi: HttpCatalogApi(rest),
        ),
      ),
      barcodeScannerProvider.overrideWithValue(
        const MobileScannerBarcodeScanner(),
      ),
      urlOpenerProvider.overrideWithValue(const LauncherUrlOpener()),
      // FA-019 scouting: live camera with the guide overlay, the DX-001
      // on-device gate (TFLite, heuristic fallback), result polling.
      guidedCameraFactoryProvider.overrideWithValue(PluginGuidedCamera.new),
      onDeviceQualityModelProvider.overrideWithValue(qualityModel),
      diagnosisApiProvider.overrideWithValue(HttpDiagnosisApi(rest)),
      // FA-007 / FA-018 / FA-023 / FA-024 / FA-026 / FA-027 / VV-008 /
      // VA-005: the M7 officer endpoints (A11, A12, A13, A35, A36, A60,
      // A61, A62). Reads are cached; writes go through the outbox.
      fieldApiProvider.overrideWithValue(HttpFieldApi(rest)),
      // FA-007 push: the shared seam (packages/core/src/push/) with this
      // app's FCM adapter, its token registry and its router's deep links.
      pushServiceProvider.overrideWithValue(push),
      ...fieldPushOverrides,
      pushRouteHandlerProvider.overrideWith(
        (ref) =>
            (route) => ref.read(routerProvider).go(deepLinkFor(route)),
      ),
      // FA-005 voice input on every free-text field.
      speechServiceProvider.overrideWithValue(PluginSpeechService()),
      // FA-016: confirmation request / officer-side OTP (online only).
      visitConfirmApiProvider.overrideWithValue(
        HttpVisitConfirmApi(
          store: store,
          client: client,
          refreshSession: auth.refresh,
          onServerDate: drift.record,
        ),
      ),
    ],
  );

  StreamSubscription<bool>? onlineSub;
  RemoteWipeCoordinator(
    signal: wipe,
    steps: (reason) => mitraWipeSteps(
      db: db,
      opener: opener,
      tokens: store,
      reason: reason,
      dutyService: dutyService,
      sampler: sampler,
      directories: appCacheDirectories,
      cancelBackgroundSync: Workmanager().cancelAll,
    ),
    teardown: () async {
      runApp(const WipeInProgressView());
      await onlineSub?.cancel();
      // The sync run that saw the order finishes before the database closes.
      await container
          .read(syncEngineProvider)
          .whenIdle()
          .timeout(const Duration(seconds: 30), onTimeout: () {});
      container.dispose();
      client.close();
    },
    restart: () => startMitra(push: push, obs: obs),
  ).arm();

  // Periodic background sync + immediate sync on reconnect (NF-002/NF-003).
  await container.read(syncSchedulerProvider).start();
  // An open duty session survives a restart: service + sampler resume
  // (FA-010); the policy version is refreshed when online (FA-011).
  await container.read(dutyControllerProvider.notifier).restore();
  unawaited(container.read(locationPolicyProvider.notifier).refresh());
  if (!wipedBefore) {
    // SEC-025: ask the server whether this phone must be wiped (in the
    // background: the cold start does not wait for the network, NF-005).
    unawaited(
      checkDeviceStatusOnStart(
        tokens: store,
        api: container.read(deviceStatusApiProvider),
        signal: wipe,
        isOnline: connectivity.isOnline,
      ),
    );
    // M2 follow-up: tenant settings daily and whenever the network returns.
    final settingsSync = container.read(tenantSettingsSyncProvider);
    unawaited(settingsSync.pullIfStale());
    // DX-001: load the on-device model early (off the first frame's path).
    unawaited(qualityModel.load());
    onlineSub = connectivity.onlineChanges.listen((online) {
      if (online) unawaited(settingsSync.pullIfStale());
    });
  }
  // NF-005: the database, settings, session, duty state and schedulers are
  // all up; the officer can act from the first frame on.
  startTrace?.markInteractive();
  runApp(
    UncontrolledProviderScope(container: container, child: const MitraApp()),
  );
  // Reports app_start once the engine has actually rasterised that frame.
  startTrace?.reportFirstFrame(obs.performance);
  // FA-007: register the FCM token for this session, listen for data
  // messages and follow a tapped push to its screen (the router exists by
  // now). All of it is inert when push is a NoPushService.
  unawaited(container.read(pushControllerProvider).signedIn());
}
