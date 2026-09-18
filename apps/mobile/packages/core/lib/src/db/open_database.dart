import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

/// How the on-device database file is opened.
///
/// SEC-024 (M5) adds an encrypted opener (SQLCipher via Drift's
/// `sqlcipher_flutter_libs`, key held in the Android Keystore) behind this
/// same interface; callers keep using [AppDatabase] and [openAppDatabase].
abstract interface class DatabaseOpener {
  /// Creates the executor the database runs on.
  QueryExecutor open();
}

/// Plain SQLite file in the app documents directory (no encryption yet).
class NativeDatabaseOpener implements DatabaseOpener {
  /// Creates the opener for [fileName].
  const NativeDatabaseOpener({this.fileName = 'farmerapp.db'});

  /// File name inside the documents directory.
  final String fileName;

  @override
  QueryExecutor open() => LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    return NativeDatabase.createInBackground(File('${dir.path}/$fileName'));
  });
}

/// In-memory database for tests and previews.
class InMemoryDatabaseOpener implements DatabaseOpener {
  /// Creates the opener.
  const InMemoryDatabaseOpener();

  @override
  QueryExecutor open() => NativeDatabase.memory();
}

/// Opens the on-device database lazily through [opener]
/// (default: [NativeDatabaseOpener] on [fileName]).
AppDatabase openAppDatabase({
  DatabaseOpener? opener,
  String fileName = 'farmerapp.db',
}) {
  return AppDatabase(
    (opener ?? NativeDatabaseOpener(fileName: fileName)).open(),
  );
}

/// An in-memory database for widget tests and previews.
AppDatabase openInMemoryDatabase() =>
    AppDatabase(const InMemoryDatabaseOpener().open());

/// The app database; `main()` overrides it with [openAppDatabase] and tests
/// with [openInMemoryDatabase].
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError(
    'appDatabaseProvider must be overridden in ProviderScope',
  ),
);
