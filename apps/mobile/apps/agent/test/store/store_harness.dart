import 'package:farmerapp_agent/app.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';

/// A signed-in session for [role].
AuthSession storeSession(String role, {String? storeId = 'store-knd'}) =>
    AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.utc(2030),
      user: AuthUser(
        id: 'u-1',
        tenantId: 't-1',
        phone: '+919000000001',
        name: 'Suresh Kumar',
        role: role,
        language: 'en',
        status: 'active',
        storeId: storeId,
      ),
    );

/// The agent app's dependencies plus the store-mode fakes.
class StoreDeps {
  /// Creates the dependencies.
  StoreDeps({bool online = true})
    : agent = AgentDeps(online: online),
      api = FakeStoreApi(),
      scanner = FakeBarcodeScanner();

  /// Agent fakes (db, connectivity, camera, clock 2026-09-20 06:00 IST).
  final AgentDeps agent;

  /// Store server.
  final FakeStoreApi api;

  /// Barcode camera.
  final FakeBarcodeScanner scanner;

  /// PDF viewer (the agent harness's URL opener).
  RecordingUrlOpener get opener => agent.urls;

  /// Share sheet (the officer app's invoice sharer, shared with A57).
  FakeInvoiceSharer get sharer => agent.sharer;

  /// Signs [role] in (token store).
  Future<void> signIn(String role, {String? storeId = 'store-knd'}) =>
      agent.tokens.write(storeSession(role, storeId: storeId));

  /// Overrides.
  List<Override> overrides({
    String initialLocation = '/store',
    AppThemeMode theme = AppThemeMode.light,
    Locale locale = const Locale('en'),
  }) => <Override>[
    ...agent.overrides(
      initialLocation: initialLocation,
      theme: theme,
      locale: locale,
    ),
    storeApiProvider.overrideWithValue(api),
    barcodeScannerProvider.overrideWithValue(scanner),
    storePhotoProcessorProvider.overrideWithValue((raw) async => raw),
  ];

  /// The app.
  Widget app({
    String initialLocation = '/store',
    AppThemeMode theme = AppThemeMode.light,
    Locale locale = const Locale('en'),
    List<Override> extra = const <Override>[],
  }) => ProviderScope(
    overrides: <Override>[
      ...overrides(
        initialLocation: initialLocation,
        theme: theme,
        locale: locale,
      ),
      ...extra,
    ],
    child: const MitraApp(),
  );

  /// Closes everything.
  Future<void> dispose() => agent.dispose();
}

/// 800 x 1280 dp tablet portrait (SPEC 13.2 store mode).
void useTabletSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps [deps] at [location] signed in as [role].
Future<void> pumpStore(
  WidgetTester tester,
  StoreDeps deps, {
  String role = 'store_manager',
  String location = '/store',
  AppThemeMode theme = AppThemeMode.light,
}) async {
  await deps.signIn(role);
  await tester.pumpWidget(deps.app(initialLocation: location, theme: theme));
  await tester.pumpAndSettle();
}
