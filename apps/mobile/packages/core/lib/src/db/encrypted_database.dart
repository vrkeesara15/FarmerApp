import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' hide DatabaseOpener;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database_key_store.dart';
import 'open_database.dart';

/// SEC-024: the on-device database is a SQLCipher file.
///
/// `package:sqlite3` 3.x bundles SQLCipher through its build hook (see the
/// `hooks: user_defines: sqlite3: source: sqlcipher` block of the workspace
/// `pubspec.yaml`), on Android and on the test host alike. The key is a raw
/// 256-bit key (`PRAGMA key = "x'…'"`), so no PBKDF2 runs at open time
/// (NF-005 cold start).

/// The SQLCipher version of the linked SQLite, or `null` when the library is
/// plain SQLite (no encryption available).
String? sqlCipherVersion([Database? db]) {
  final probe = db ?? sqlite3.openInMemory();
  try {
    final rows = probe.select('PRAGMA cipher_version');
    if (rows.isEmpty) return null;
    final value = rows.first.values.first;
    return value is String && value.isNotEmpty ? value : null;
  } finally {
    if (db == null) probe.close();
  }
}

/// Whether the linked SQLite is SQLCipher.
bool get sqlCipherAvailable => sqlCipherVersion() != null;

/// Applies [keyHex] (see [generateDatabaseKey]) to a freshly opened
/// connection and proves it: SQLCipher only checks the key on the first
/// read, so a wrong key fails here with `SQLITE_NOTADB` (26) instead of on
/// some later query. Refuses to run on a SQLite without SQLCipher (fail
/// closed: never write personal data to an unencrypted file by accident).
void applyDatabaseKey(Database db, String keyHex) {
  if (!isValidDatabaseKey(keyHex)) {
    throw ArgumentError('database key must be 64 hex characters');
  }
  if (sqlCipherVersion(db) == null) {
    throw StateError(
      'SQLCipher is not available; refusing to open unencrypted',
    );
  }
  db
    ..execute('PRAGMA key = "x\'$keyHex\'"')
    ..select('SELECT count(*) FROM sqlite_master');
}

/// Row counts per table of the migration (verified equal on both sides).
@immutable
class DatabaseMigrationReport {
  /// Creates the report.
  const DatabaseMigrationReport({
    required this.rowCounts,
    required this.userVersion,
  });

  /// `table -> rows` of the plain source (and, verified, of the copy).
  final Map<String, int> rowCounts;

  /// Drift schema version carried over (`PRAGMA user_version`).
  final int userVersion;

  /// Rows copied in total.
  int get totalRows => rowCounts.values.fold(0, (a, b) => a + b);
}

Map<String, int> _rowCounts(Database db, [String schema = 'main']) {
  final tables = db.select(
    "SELECT name FROM $schema.sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  return <String, int>{
    for (final row in tables)
      row['name'] as String:
          db
                  .select('SELECT count(*) AS n FROM $schema."${row['name']}"')
                  .first['n']
              as int,
  };
}

String _sqlString(String value) => "'${value.replaceAll("'", "''")}'";

/// Exports the plain SQLite file [plainPath] into a new SQLCipher file at
/// [encryptedPath] keyed with [keyHex] (`ATTACH … KEY` +
/// `sqlcipher_export`), carries `user_version` over and verifies that every
/// table has the same row count on both sides. The plain file is left alone
/// (the caller deletes it once this returns); on any failure the partial
/// encrypted file is deleted and the error rethrown.
DatabaseMigrationReport migratePlainDatabaseToEncrypted({
  required String plainPath,
  required String encryptedPath,
  required String keyHex,
}) {
  if (!isValidDatabaseKey(keyHex)) {
    throw ArgumentError('database key must be 64 hex characters');
  }
  final target = File(encryptedPath);
  if (target.existsSync()) target.deleteSync();
  final source = sqlite3.open(plainPath);
  try {
    if (sqlCipherVersion(source) == null) {
      throw StateError('SQLCipher is not available; cannot encrypt');
    }
    final counts = _rowCounts(source);
    final version = source.userVersion;
    source
      ..execute(
        'ATTACH DATABASE ${_sqlString(encryptedPath)} AS encrypted '
        'KEY "x\'$keyHex\'"',
      )
      ..select("SELECT sqlcipher_export('encrypted')")
      ..execute('PRAGMA encrypted.user_version = $version')
      ..execute('DETACH DATABASE encrypted');
    source.close();

    final copy = sqlite3.open(encryptedPath);
    try {
      applyDatabaseKey(copy, keyHex);
      final copied = _rowCounts(copy);
      if (copy.userVersion != version || !_sameCounts(counts, copied)) {
        throw StateError(
          'encrypted copy differs: $copied (v${copy.userVersion}) vs '
          '$counts (v$version)',
        );
      }
    } finally {
      copy.close();
    }
    return DatabaseMigrationReport(rowCounts: counts, userVersion: version);
  } on Object {
    try {
      source.close();
    } on Object {
      // Already closed.
    }
    if (target.existsSync()) target.deleteSync();
    rethrow;
  }
}

bool _sameCounts(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// Deletes a SQLite file and its side files (`-wal`, `-shm`, `-journal`).
Future<void> deleteSqliteFiles(String path) async {
  for (final suffix in const <String>['', '-wal', '-shm', '-journal']) {
    final file = File('$path$suffix');
    if (await file.exists()) await file.delete();
  }
}

/// A [DatabaseOpener] whose files and key can be destroyed (SEC-025 wipe).
abstract interface class DestroyableDatabaseOpener implements DatabaseOpener {
  /// Deletes the database files and its key. The database must be closed.
  Future<void> destroy();
}

/// Opens `farmerapp_secure.db` through SQLCipher with the key from
/// [keyStore], migrating a plain `farmerapp.db` from an earlier version on
/// the first run (export, verify row counts, then delete the plain file).
///
/// Recovery rules (all logged):
/// * An encrypted file without a stored key (Keystore reset, a restored
///   backup) can never be read again: it is deleted and a new one created.
/// * A failed migration keeps the plain file and opens it for this run so
///   unsynced work is not lost; the migration is retried on the next start.
class EncryptedDatabaseOpener implements DestroyableDatabaseOpener {
  /// Creates the opener.
  EncryptedDatabaseOpener({
    required this.keyStore,
    this.fileName = 'farmerapp_secure.db',
    this.legacyFileName = 'farmerapp.db',
    Future<String> Function()? directory,
    void Function(String message)? log,
  }) : _directory = directory ?? _documents,
       _log = log ?? debugPrint;

  /// Where the key lives.
  final DatabaseKeyStore keyStore;

  /// Encrypted file name.
  final String fileName;

  /// Plain file name used before SEC-024.
  final String legacyFileName;

  final Future<String> Function() _directory;
  final void Function(String message) _log;

  static Future<String> _documents() async =>
      (await getApplicationDocumentsDirectory()).path;

  /// Result of the last migration in this process (tests, diagnostics).
  DatabaseMigrationReport? lastMigration;

  /// Resolves the file to open, migrating or recovering first.
  Future<({File file, String? key})> prepare() async {
    final dir = await _directory();
    final encrypted = File('$dir/$fileName');
    final plain = File('$dir/$legacyFileName');
    final staging = '$dir/$fileName.migrating';
    await deleteSqliteFiles(staging);

    final hadKey = await keyStore.read() != null;
    if (!hadKey && await encrypted.exists()) {
      _log('SEC-024: encrypted database without a key; recreating it');
      await deleteSqliteFiles(encrypted.path);
    }
    final key = await keyStore.readOrCreate();

    if (await plain.exists()) {
      if (await encrypted.exists()) {
        // A previous migration finished but the plain file survived.
        await deleteSqliteFiles(plain.path);
      } else {
        try {
          final plainPath = plain.path;
          lastMigration = await Isolate.run(
            () => migratePlainDatabaseToEncrypted(
              plainPath: plainPath,
              encryptedPath: staging,
              keyHex: key,
            ),
          );
          await File(staging).rename(encrypted.path);
          await deleteSqliteFiles(plain.path);
          _log(
            'SEC-024: migrated ${lastMigration!.totalRows} rows into the '
            'encrypted database',
          );
        } on Object catch (e) {
          _log('SEC-024: migration failed ($e); plain database kept');
          await deleteSqliteFiles(staging);
          return (file: plain, key: null);
        }
      }
    }
    return (file: encrypted, key: key);
  }

  @override
  QueryExecutor open() => LazyDatabase(() async {
    final target = await prepare();
    final key = target.key;
    return NativeDatabase.createInBackground(
      target.file,
      setup: key == null ? null : (db) => applyDatabaseKey(db, key),
    );
  });

  @override
  Future<void> destroy() async {
    final dir = await _directory();
    await deleteSqliteFiles('$dir/$fileName');
    await deleteSqliteFiles('$dir/$fileName.migrating');
    await deleteSqliteFiles('$dir/$legacyFileName');
    await keyStore.delete();
  }
}
