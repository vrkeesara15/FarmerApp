import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

/// Opens the on-device database lazily in the app documents directory.
///
/// Encryption at rest (SEC-024) swaps the executor here; callers keep
/// using [AppDatabase].
AppDatabase openAppDatabase({String fileName = 'farmerapp.db'}) {
  return AppDatabase(
    LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(File('${dir.path}/$fileName'));
    }),
  );
}

/// An in-memory database for widget tests and previews.
AppDatabase openInMemoryDatabase() => AppDatabase(NativeDatabase.memory());

/// The app database; `main()` overrides it with [openAppDatabase] and tests
/// with [openInMemoryDatabase].
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError(
    'appDatabaseProvider must be overridden in ProviderScope',
  ),
);
