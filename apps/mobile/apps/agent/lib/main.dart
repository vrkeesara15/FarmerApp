import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  // Real API (FA-001): base URL from --dart-define=API_BASE_URL, default
  // http://10.0.2.2:8000 (host machine from the Android emulator).
  final store = SecureTokenStore();
  runApp(
    ProviderScope(
      overrides: [
        tokenStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(
          HttpAuthApi(store: store, deviceName: 'Mitra Android'),
        ),
      ],
      child: const MitraApp(),
    ),
  );
}
