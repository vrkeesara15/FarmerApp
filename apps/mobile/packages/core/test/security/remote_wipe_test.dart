import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase, QueryExecutor;
import 'package:drift/native.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../sync/sync_harness.dart';

/// SEC-025 remote wipe: the trigger (401 `device_wipe_required` from the
/// sync engine, from an ordinary API call, `wipe_required` from the start-up
/// status check) and the wipe itself (every store removed, the language
/// kept, A08 notice written).

/// A plain file database in a temp dir with a key in [keys], so the test
/// sees the file and the key go away (SQLCipher itself is covered by
/// `test/db/encrypted_database_test.dart`).
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

http.Response _problem(int status, String code) => http.Response(
  jsonEncode(<String, Object?>{'status': status, 'code': code}),
  status,
  headers: <String, String>{'content-type': 'application/problem+json'},
);

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
    language: 'te',
    status: 'active',
  ),
);

void main() {
  group('trigger', () {
    late WipeSignal signal;
    late List<http.Request> sent;

    SecureApiClient client(http.Response Function(http.Request) answer) {
      sent = <http.Request>[];
      return SecureApiClient(
        inner: MockClient((request) async {
          sent.add(request);
          return answer(request);
        }),
        wipeSignal: signal,
      );
    }

    setUp(() => signal = WipeSignal());

    test('the signal fires once; the first reason wins', () async {
      signal
        ..trigger('a')
        ..trigger('b');
      expect(signal.triggered, isTrue);
      expect(await signal.onWipe, 'a');
    });

    test('from an ordinary API call (catalogue read)', () async {
      final rest = RestJsonClient(
        store: InMemoryTokenStore(session: _session()),
        config: const ApiConfig(baseUrl: 'https://api.test'),
        client: client((_) => _problem(401, 'device_wipe_required')),
      );
      final response = await rest.get('/v1/catalog/products');
      expect(signal.triggered, isTrue);
      expect(await signal.onWipe, 'http_401:/v1/catalog/products');
      // The caller still sees the unchanged problem.
      expect(response.status, 401);
      expect(response.code, 'device_wipe_required');
    });

    test('a plain 401 (session revoked) does not wipe', () async {
      final rest = RestJsonClient(
        store: InMemoryTokenStore(session: _session()),
        config: const ApiConfig(baseUrl: 'https://api.test'),
        client: client((_) => _problem(401, 'session_revoked')),
      );
      await rest.get('/v1/me');
      expect(signal.triggered, isFalse);
    });

    test('from the sync engine (push answered 401, refresh too)', () async {
      final store = InMemoryTokenStore(deviceId: 'dev-1', session: _session());
      final c = client((_) => _problem(401, 'device_wipe_required'));
      final auth = HttpAuthApi(
        store: store,
        client: c,
        config: const ApiConfig(baseUrl: 'https://api.test'),
      );
      final db = newDb();
      addTearDown(db.close);
      await outboxFor(db)
          .enqueueCreate('farmer', 'f-1', <String, Object?>{'name': 'Ramesh'});
      final engine = engineFor(
        db,
        HttpSyncApi(
          store: store,
          client: c,
          config: const ApiConfig(baseUrl: 'https://api.test'),
          refreshSession: auth.refresh,
        ),
      );
      addTearDown(engine.dispose);
      await engine.syncNow();
      expect(signal.triggered, isTrue);
      expect(await signal.onWipe, 'http_401:/v1/sync');
      expect(sent.map((r) => r.url.path), contains('/v1/sync'));
    });

    group('start-up status check', () {
      late InMemoryTokenStore tokens;

      HttpDeviceStatusApi api(http.Response Function(http.Request) answer) =>
          HttpDeviceStatusApi(
            RestJsonClient(
              store: tokens,
              config: const ApiConfig(baseUrl: 'https://api.test'),
              client: client(answer),
            ),
            tokens,
          );

      setUp(() {
        tokens = InMemoryTokenStore(deviceId: 'dev-1', session: _session());
      });

      test('wipe_required: true triggers the wipe', () async {
        final answered = await checkDeviceStatusOnStart(
          tokens: tokens,
          api: api(
            (_) => http.Response(
              jsonEncode(<String, Object?>{
                'device_id': 'dev-1',
                'status': 'lost',
                'wipe_required': true,
                'user_status': 'active',
              }),
              200,
            ),
          ),
          signal: signal,
        );
        expect(answered, isTrue);
        expect(await signal.onWipe, 'device_status:lost');
        expect(sent.single.url.path, '/v1/devices/me/status');
        expect(sent.single.headers['X-Device-Id'], 'dev-1');
        expect(sent.single.headers['Authorization'], 'Bearer access');
      });

      test('401 device_wipe_required (disabled account) triggers it', () async {
        await checkDeviceStatusOnStart(
          tokens: tokens,
          api: api((_) => _problem(401, 'device_wipe_required')),
          signal: signal,
        );
        expect(signal.triggered, isTrue);
      });

      test('active device, offline, signed out: nothing happens', () async {
        final active = await checkDeviceStatusOnStart(
          tokens: tokens,
          api: api(
            (_) => http.Response(
              jsonEncode(<String, Object?>{
                'status': 'active',
                'wipe_required': false,
              }),
              200,
            ),
          ),
          signal: signal,
        );
        expect(active, isTrue);
        final offline = await checkDeviceStatusOnStart(
          tokens: tokens,
          api: api((request) => throw http.ClientException('offline')),
          signal: signal,
        );
        expect(offline, isFalse);
        final fake = FakeDeviceStatusApi();
        expect(
          await checkDeviceStatusOnStart(
            tokens: tokens,
            api: fake,
            signal: signal,
            isOnline: () async => false,
          ),
          isFalse,
        );
        await tokens.clear();
        expect(
          await checkDeviceStatusOnStart(
            tokens: tokens,
            api: fake,
            signal: signal,
          ),
          isFalse,
        );
        expect(fake.calls, 0);
        expect(signal.triggered, isFalse);
      });
    });
  });

  group('wipe', () {
    late Directory root;
    late InMemoryDatabaseKeyStore keys;
    late _FileOpener opener;
    late AppDatabase db;
    late InMemoryTokenStore tokens;
    late FakeForegroundDutyService service;
    late FakeLocationSampler sampler;
    late Directory photos;
    late Directory cache;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('sec025_');
      keys = InMemoryDatabaseKeyStore();
      opener = _FileOpener(root, keys);
      db = AppDatabase(opener.open());
      await db.setValue(KvSettingsStore.localeKey, 'te');
      await db.setValue(KvSettingsStore.themeKey, 'sunlight');
      await db.setValue(VisitSettings.kvKey, '{"geofence_radius_m":90}');
      await db.setValue('registration.draft', '{"name":"Ramesh"}');
      await Outbox(db)
          .enqueueCreate('farmer', 'f-1', <String, Object?>{'name': 'Ramesh'});
      tokens = InMemoryTokenStore(deviceId: 'dev-1', session: _session());
      service = FakeForegroundDutyService();
      await service.start(title: 'On duty', text: 'Location on');
      sampler = FakeLocationSampler();
      await sampler.start(const DutyPolicy());
      photos = Directory('${root.path}/photos')..createSync();
      File('${photos.path}/visit-1.jpg').writeAsBytesSync(<int>[1, 2, 3]);
      cache = Directory('${root.path}/cache')..createSync();
      File('${cache.path}/picker.jpg').writeAsBytesSync(<int>[4]);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    Future<WipeReport> run() => RemoteWipe(
      standardWipeSteps(
        db: db,
        opener: opener,
        tokens: tokens,
        reason: 'http_401:/v1/sync',
        dutyService: service,
        sampler: sampler,
        directories: () async => <Directory>[photos, cache],
        clock: () => DateTime.utc(2026, 9, 19, 10),
      ),
      log: (_) {},
    ).run();

    test('removes every store and keeps only the language', () async {
      final oldKey = await keys.read();
      final report = await run();
      expect(report.ok, isTrue);
      expect(report.completed, <String>['duty', 'tokens', 'database', 'files']);

      // Duty: foreground service and sampler stopped.
      expect(service.running, isFalse);
      expect(sampler.isRunning, isFalse);
      // Tokens gone, device id kept (the server still knows the phone).
      expect(await tokens.read(), isNull);
      expect(await tokens.deviceId(), 'dev-1');
      // Files gone.
      expect(photos.existsSync(), isFalse);
      expect(cache.existsSync(), isFalse);
      // The database was destroyed with its key; the new one (new key)
      // holds only the language and the A08 notice.
      expect(await keys.read(), isNot(oldKey));
      expect(keys.generated, 2);
      final fresh = AppDatabase(opener.open());
      addTearDown(fresh.close);
      final rows = await fresh.select(fresh.kv).get();
      expect(
        {for (final r in rows) r.key},
        <String>{KvSettingsStore.localeKey, wipeNoticeKey},
      );
      expect(await fresh.getValue(KvSettingsStore.localeKey), 'te');
      expect(await fresh.select(fresh.outboxTable).get(), isEmpty);
      expect(await hasWipeNotice(fresh), isTrue);
      final notice = jsonDecode((await fresh.getValue(wipeNoticeKey))!) as Map;
      expect(notice['reason'], 'http_401:/v1/sync');
      expect(notice['at'], '2026-09-19T10:00:00.000Z');

      await clearWipeNotice(fresh);
      expect(await hasWipeNotice(fresh), isFalse);
    });

    test('a failing step does not stop the others', () async {
      final report = await RemoteWipe(<WipeStep>[
        WipeStep('broken', () async => throw StateError('boom')),
        tokensWipeStep(tokens),
        filesWipeStep(() async => <Directory>[photos]),
      ], log: (_) {}).run();
      expect(report.ok, isFalse);
      expect(report.failures.keys, <String>['broken']);
      expect(await tokens.read(), isNull);
      expect(photos.existsSync(), isFalse);
      await db.close();
    });

    test(
      'farmer app wipe (no duty service): database, tokens, files',
      () async {
        final report = await RemoteWipe(
          standardWipeSteps(
            db: db,
            opener: opener,
            tokens: tokens,
            reason: 'device_status:lost',
            directories: () async => <Directory>[photos, cache],
          ),
          log: (_) {},
        ).run();
        expect(report.completed, <String>['tokens', 'database', 'files']);
        expect(await tokens.read(), isNull);
        final fresh = AppDatabase(opener.open());
        addTearDown(fresh.close);
        expect(await fresh.getValue(VisitSettings.kvKey), isNull);
        expect(await fresh.getValue(KvSettingsStore.localeKey), 'te');
      },
    );
  });
}
