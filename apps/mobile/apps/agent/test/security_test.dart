import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase, QueryExecutor;
import 'package:drift/native.dart';
import 'package:farmerapp_agent/app.dart';
import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_agent/security.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// SEC-025 / SEC-020 in the officer app: A08 after a remote wipe, the wipe
/// driven end to end from a 401 on sync, and the device-binding message.
class _FileOpener implements DestroyableDatabaseOpener {
  _FileOpener(this.dir, this.keys);

  final Directory dir;
  final InMemoryDatabaseKeyStore keys;

  File get file => File('${dir.path}/app.db');

  @override
  QueryExecutor open() => LazyDatabase(() async {
    await keys.readOrCreate();
    return NativeDatabase(file);
  });

  @override
  Future<void> destroy() async {
    await deleteSqliteFiles(file.path);
    await keys.delete();
  }
}

AuthSession _session() => AuthSession(
  accessToken: 'access',
  refreshToken: 'refresh',
  expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
  user: const AuthUser(
    id: 'u1',
    tenantId: 't1',
    phone: '+919000000004',
    name: 'Ramesh',
    role: 'field_officer',
    language: 'en',
    status: 'active',
  ),
);

void main() {
  testWidgets('A08 opens after a wipe; "Sign in again" clears the notice and '
      'goes to the language step', (tester) async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    await tester.runAsync(
      () => db.setValue(wipeNoticeKey, '{"reason":"device_status:lost"}'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          wipeNoticeProvider.overrideWithValue(true),
        ],
        child: const MitraApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Signed out by your administrator'), findsOneWidget);
    expect(
      find.textContaining('app data on this phone has been deleted'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('wipe-sign-in')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePicker), findsOneWidget);
    expect(await tester.runAsync(() => hasWipeNotice(db)), isFalse);
  });

  testWidgets('A04: device_not_bound explains who can fix it', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authApiProvider.overrideWithValue(FakeAuthApi(deviceBound: false)),
          routerProvider.overrideWithValue(
            buildRouter(initialLocation: AppRoutes.phone),
          ),
        ],
        child: const MitraApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '9000000004');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This phone is not registered to you. Ask your administrator to '
        'approve it, then sign in again.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('otp-continue')), findsNothing);
  });

  test('a 401 device_wipe_required on sync wipes the officer app and '
      'restarts it on A08', () async {
    final root = Directory.systemTemp.createTempSync('mitra_wipe_');
    addTearDown(() => root.deleteSync(recursive: true));
    final keys = InMemoryDatabaseKeyStore();
    final opener = _FileOpener(root, keys);
    final db = AppDatabase(opener.open());
    await db.setValue(KvSettingsStore.localeKey, 'hi');
    await Outbox(db)
        .enqueueCreate('farmer', 'f-1', <String, Object?>{'name': 'Ramesh'});
    final photos = Directory('${root.path}/photos')..createSync();
    File('${photos.path}/v.jpg').writeAsBytesSync(<int>[1]);
    final tokens = InMemoryTokenStore(deviceId: 'dev-1', session: _session());
    final service = FakeForegroundDutyService();
    await service.start(title: 't', text: 't');
    final sampler = FakeLocationSampler();
    await sampler.start(const DutyPolicy());
    var backgroundCancelled = false;
    var tornDown = false;
    var restarted = false;

    final signal = WipeSignal();
    final client = SecureApiClient(
      inner: MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{'code': 'device_wipe_required'}),
          401,
        ),
      ),
      wipeSignal: signal,
    );
    final engine = SyncEngine(
      db: db,
      api: HttpSyncApi(
        store: tokens,
        client: client,
        config: const ApiConfig(baseUrl: 'https://api.test'),
      ),
      deviceId: tokens.deviceId,
    );
    final coordinator = RemoteWipeCoordinator(
      signal: signal,
      steps: (reason) => mitraWipeSteps(
        db: db,
        opener: opener,
        tokens: tokens,
        reason: reason,
        dutyService: service,
        sampler: sampler,
        directories: () async => <Directory>[photos],
        cancelBackgroundSync: () async => backgroundCancelled = true,
      ),
      // As in main.dart: the run that saw the order finishes first.
      teardown: () async {
        await engine.whenIdle();
        tornDown = true;
      },
      restart: () async => restarted = true,
      log: (_) {},
    )..arm();

    await engine.syncNow();
    await engine.dispose();
    final report = await coordinator.done;

    expect(report.ok, isTrue);
    expect(report.completed, <String>[
      'duty',
      'tokens',
      'database',
      'files',
      'background_sync',
    ]);
    expect(tornDown && restarted && backgroundCancelled, isTrue);
    expect(service.running, isFalse);
    expect(sampler.isRunning, isFalse);
    expect(await tokens.read(), isNull);
    expect(photos.existsSync(), isFalse);
    final fresh = AppDatabase(opener.open());
    addTearDown(fresh.close);
    expect(await hasWipeNotice(fresh), isTrue);
    expect(await fresh.getValue(KvSettingsStore.localeKey), 'hi');
    expect(await fresh.select(fresh.outboxTable).get(), isEmpty);
  });
}
