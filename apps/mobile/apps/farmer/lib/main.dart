import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'security.dart';

/// App version sent on login and refresh (pubspec).
const String farmerAppVersion = '0.1.0+1';

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
  final rest = RestJsonClient(
    store: store,
    client: client,
    refreshSession: auth.refresh,
  );
  final container = ProviderContainer(
    overrides: [
      ...settings,
      appDatabaseProvider.overrideWithValue(db),
      tokenStoreProvider.overrideWithValue(store),
      authApiProvider.overrideWithValue(auth),
      wipeSignalProvider.overrideWithValue(wipe),
      wipeNoticeProvider.overrideWithValue(wipedBefore),
      deviceStatusApiProvider.overrideWithValue(
        HttpDeviceStatusApi(rest, store),
      ),
      tenantSettingsApiProvider.overrideWithValue(HttpTenantSettingsApi(rest)),
    ],
  );
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
      ),
    );
    unawaited(container.read(tenantSettingsSyncProvider).pullIfStale());
  }
  runApp(
    UncontrolledProviderScope(container: container, child: const KisanApp()),
  );
}
