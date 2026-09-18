import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real API (FA-001): base URL from --dart-define=API_BASE_URL, default
  // http://10.0.2.2:8000 (host machine from the Android emulator).
  final store = SecureTokenStore();
  // Settings (language, theme) are read from the Drift kv table before the
  // first frame so the saved language is used immediately (FA-004).
  final db = openAppDatabase();
  final settings = await settingsOverrides(KvSettingsStore(db));
  runApp(
    ProviderScope(
      overrides: [
        ...settings,
        appDatabaseProvider.overrideWithValue(db),
        tokenStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(
          HttpAuthApi(store: store, deviceName: 'Kisan Android'),
        ),
      ],
      child: const KisanApp(),
    ),
  );
}
