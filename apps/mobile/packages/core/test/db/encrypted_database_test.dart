import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// SEC-024 encrypted local database.
///
/// The unit tests of the rest of the app use plain in-memory SQLite through
/// the `DatabaseOpener` seam. The `SQLCipher` group below runs against the
/// SQLite the build hook linked on the test host (`source: sqlcipher` in
/// the workspace pubspec); where that library is plain SQLite the group is
/// skipped with the reason printed.
void main() {
  final cipher = sqlCipherVersion();
  final skipReason = cipher == null
      ? 'SQLCipher is not linked on this host (plain SQLite); the encrypted '
            'database is verified on the reference device instead'
      : null;
  if (skipReason != null) {
    // ignore: avoid_print
    print('SKIPPED SEC-024 SQLCipher integration tests: $skipReason');
  }

  group('database key', () {
    test('32 random bytes as 64 hex characters, different each time', () {
      final a = generateDatabaseKey();
      final b = generateDatabaseKey();
      expect(isValidDatabaseKey(a), isTrue);
      expect(a, hasLength(64));
      expect(a, isNot(b));
      expect(isValidDatabaseKey('zz'), isFalse);
      expect(isValidDatabaseKey(null), isFalse);
    });

    test('key store generates once, then returns the same key', () async {
      final store = InMemoryDatabaseKeyStore();
      expect(await store.read(), isNull);
      final key = await store.readOrCreate();
      expect(await store.readOrCreate(), key);
      expect(store.generated, 1);
      await store.delete();
      expect(await store.read(), isNull);
    });

    test('a malformed key is refused before touching SQLite', () {
      expect(
        () => migratePlainDatabaseToEncrypted(
          plainPath: 'x',
          encryptedPath: 'y',
          keyHex: "'; DROP TABLE kv; --",
        ),
        throwsArgumentError,
      );
    });
  });

  group('SQLCipher (host library: ${cipher ?? 'not available'})', () {
    late Directory dir;
    late InMemoryDatabaseKeyStore keys;
    late List<String> log;

    EncryptedDatabaseOpener opener() => EncryptedDatabaseOpener(
      keyStore: keys,
      directory: () async => dir.path,
      log: log.add,
    );

    String path(String name) => '${dir.path}/$name';

    bool isPlainSqliteFile(String p) {
      final head = File(p).readAsBytesSync().take(15).toList();
      return String.fromCharCodes(head) == 'SQLite format 3';
    }

    /// Writes a plain (pre-SEC-024) app database with a few rows.
    Future<void> seedPlain() async {
      final db = AppDatabase(NativeDatabase(File(path('farmerapp.db'))));
      await db.setValue(KvSettingsStore.localeKey, 'te');
      await db.setValue('visits.settings', '{"geofence_radius_m":90}');
      await Outbox(db)
          .enqueueCreate('farmer', 'f-1', <String, Object?>{'name': 'Ramesh'});
      await db.close();
    }

    setUp(() {
      dir = Directory.systemTemp.createTempSync('sec024_');
      keys = InMemoryDatabaseKeyStore();
      log = <String>[];
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('new install: the file is encrypted and needs the key', () async {
      final db = AppDatabase(opener().open());
      await db.setValue('probe', 'secret-value');
      await db.close();

      final file = path('farmerapp_secure.db');
      expect(File(file).existsSync(), isTrue);
      expect(isPlainSqliteFile(file), isFalse, reason: 'header is encrypted');
      expect(
        File(file).readAsStringSync(encoding: latin1),
        isNot(contains('secret-value')),
      );
      final key = (await keys.read())!;

      final wrong = sqlite3.open(file);
      expect(
        () => applyDatabaseKey(wrong, generateDatabaseKey()),
        throwsA(isA<SqliteException>()),
      );
      wrong.close();

      final noKey = sqlite3.open(file);
      expect(
        () => noKey.select('SELECT * FROM kv'),
        throwsA(isA<SqliteException>()),
      );
      noKey.close();

      final right = sqlite3.open(file);
      applyDatabaseKey(right, key);
      expect(
        right.select("SELECT value FROM kv WHERE key = 'probe'").first['value'],
        'secret-value',
      );
      right.close();

      final again = AppDatabase(opener().open());
      expect(await again.getValue('probe'), 'secret-value');
      await again.close();
      expect(keys.generated, 1);
    }, skip: skipReason);

    test('upgrade: a plain database is exported into the encrypted one, '
        'row counts verified, plain file deleted', () async {
      await seedPlain();
      final plainCounts = () {
        final p = sqlite3.open(path('farmerapp.db'));
        try {
          return <String, int>{
            'kv': p.select('SELECT count(*) AS n FROM kv').first['n'] as int,
            'outbox':
                p.select('SELECT count(*) AS n FROM outbox').first['n'] as int,
            'version': p.userVersion,
          };
        } finally {
          p.close();
        }
      }();

      final o = opener();
      final db = AppDatabase(o.open());
      expect(await db.getValue(KvSettingsStore.localeKey), 'te');
      expect(await db.getValue('visits.settings'), contains('90'));
      expect(await db.select(db.outboxTable).get(), hasLength(1));
      await db.close();

      final report = o.lastMigration!;
      expect(report.rowCounts['kv'], plainCounts['kv']);
      expect(report.rowCounts['outbox'], plainCounts['outbox']);
      expect(report.userVersion, plainCounts['version']);
      expect(File(path('farmerapp.db')).existsSync(), isFalse);
      expect(File(path('farmerapp_secure.db.migrating')).existsSync(), isFalse);
      expect(isPlainSqliteFile(path('farmerapp_secure.db')), isFalse);
      expect(log.single, contains('migrated'));
    }, skip: skipReason);

    test('migration function: sqlcipher_export copy with equal counts', () {
      final plain = sqlite3.open(path('plain.db'))
        ..execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)')
        ..execute("INSERT INTO t (v) VALUES ('a'), ('b'), ('c')")
        ..userVersion = 6;
      plain.close();
      final key = generateDatabaseKey();
      final report = migratePlainDatabaseToEncrypted(
        plainPath: path('plain.db'),
        encryptedPath: path('enc.db'),
        keyHex: key,
      );
      expect(report.rowCounts, <String, int>{'t': 3});
      expect(report.userVersion, 6);
      final enc = sqlite3.open(path('enc.db'));
      applyDatabaseKey(enc, key);
      expect(enc.select('SELECT count(*) AS n FROM t').first['n'], 3);
      expect(enc.userVersion, 6);
      enc.close();
      expect(
        File(path('plain.db')).existsSync(),
        isTrue,
        reason:
            'caller '
            'deletes the plain file',
      );
    }, skip: skipReason);

    test(
      'a failed migration keeps the plain file and opens it for this run',
      () async {
        File(path('farmerapp.db')).writeAsStringSync('not a database at all');
        final target = await opener().prepare();
        expect(target.file.path, path('farmerapp.db'));
        expect(target.key, isNull);
        expect(File(path('farmerapp.db')).existsSync(), isTrue);
        expect(File(path('farmerapp_secure.db')).existsSync(), isFalse);
        expect(
          File(path('farmerapp_secure.db.migrating')).existsSync(),
          isFalse,
        );
        expect(log.single, contains('migration failed'));
      },
      skip: skipReason,
    );

    test('an encrypted file without its key is recreated', () async {
      final db = AppDatabase(opener().open());
      await db.setValue('probe', 'x');
      await db.close();
      await keys.delete(); // Keystore reset / restored backup.

      final fresh = AppDatabase(opener().open());
      expect(await fresh.getValue('probe'), isNull);
      await fresh.close();
      expect(keys.generated, 2);
      expect(log.single, contains('without a key'));
    }, skip: skipReason);

    test('destroy deletes every file and the key', () async {
      final o = opener();
      final db = AppDatabase(o.open());
      await db.setValue('probe', 'x');
      await db.close();
      File(path('farmerapp.db')).writeAsStringSync('leftover');
      await o.destroy();
      expect(await keys.read(), isNull);
      expect(dir.listSync().map((e) => e.path.split('/').last), isEmpty);
    }, skip: skipReason);
  });
}
