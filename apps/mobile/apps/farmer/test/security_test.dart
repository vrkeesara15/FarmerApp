import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase, QueryExecutor;
import 'package:drift/native.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/app.dart';
import 'package:farmerapp_farmer/security.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// SEC-025 in the farmer app: the same wipe handling for its data (session,
/// encrypted database, cached files) and the signed-out screen.
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
    id: 'f1',
    tenantId: 't1',
    phone: '+919000000009',
    name: 'Lakshmi',
    role: 'farmer',
    language: 'te',
    status: 'active',
  ),
);

void main() {
  testWidgets('opens on the signed-out screen after a wipe, in the kept '
      'language', (tester) async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    await tester.runAsync(() => db.setValue(wipeNoticeKey, '{}'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          wipeNoticeProvider.overrideWithValue(true),
          initialSettingsProvider.overrideWithValue(
            const AppSettings(locale: Locale('te')),
          ),
        ],
        child: const KisanApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('మీ అడ్మినిస్ట్రేటర్ సైన్ అవుట్ చేశారు'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wipe-sign-in')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePicker), findsOneWidget);
  });

  group('wipe', () {
    late Directory root;
    late InMemoryDatabaseKeyStore keys;
    late _FileOpener opener;
    late AppDatabase db;
    late InMemoryTokenStore tokens;
    late Directory cache;
    late WipeSignal signal;
    late RemoteWipeCoordinator coordinator;
    late int restarts;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('kisan_wipe_');
      keys = InMemoryDatabaseKeyStore();
      opener = _FileOpener(root, keys);
      db = AppDatabase(opener.open());
      await db.setValue(KvSettingsStore.localeKey, 'te');
      await db.setValue(TenantSettingsSync.kvKey, '{}');
      tokens = InMemoryTokenStore(deviceId: 'dev-9', session: _session());
      cache = Directory('${root.path}/cache')..createSync();
      File('${cache.path}/crop.jpg').writeAsBytesSync(<int>[1]);
      signal = WipeSignal();
      restarts = 0;
      coordinator = RemoteWipeCoordinator(
        signal: signal,
        steps: (reason) => kisanWipeSteps(
          db: db,
          opener: opener,
          tokens: tokens,
          reason: reason,
          directories: () async => <Directory>[cache],
        ),
        teardown: () async {},
        restart: () async => restarts += 1,
        log: (_) {},
      )..arm();
    });

    tearDown(() => root.deleteSync(recursive: true));

    Future<void> expectWiped() async {
      final report = await coordinator.done;
      expect(report.ok, isTrue);
      expect(report.completed, <String>['tokens', 'database', 'files']);
      expect(restarts, 1);
      expect(await tokens.read(), isNull);
      expect(cache.existsSync(), isFalse);
      final fresh = AppDatabase(opener.open());
      addTearDown(fresh.close);
      expect(await fresh.getValue(TenantSettingsSync.kvKey), isNull);
      expect(await fresh.getValue(KvSettingsStore.localeKey), 'te');
      expect(await hasWipeNotice(fresh), isTrue);
    }

    test('from an API call (refresh answered device_wipe_required)', () async {
      final auth = HttpAuthApi(
        store: tokens,
        config: const ApiConfig(baseUrl: 'https://api.test'),
        client: SecureApiClient(
          inner: MockClient(
            (_) async => http.Response(
              jsonEncode(<String, Object?>{'code': 'device_wipe_required'}),
              401,
            ),
          ),
          wipeSignal: signal,
        ),
      );
      await auth.refresh();
      await expectWiped();
    });

    test('from the start-up status check', () async {
      await checkDeviceStatusOnStart(
        tokens: tokens,
        api: FakeDeviceStatusApi(
          status: const DeviceStatus(status: 'lost', wipeRequired: true),
        ),
        signal: signal,
      );
      await expectWiped();
    });
  });
}
