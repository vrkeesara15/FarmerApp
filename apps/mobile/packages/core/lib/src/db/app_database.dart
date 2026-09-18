import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Simple key/value table used for settings and sync bookkeeping.
///
/// Real domain tables (farmers, visits, outbox, ...) are added per requirement
/// ID; this table exists to prove the Drift toolchain end to end.
class Kv extends Table {
  /// Setting key, e.g. `theme_mode` or `locale`.
  TextColumn get key => text()();

  /// Stored value as text (callers encode JSON when needed).
  TextColumn get value => text()();

  /// Last write time in UTC.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// The on-device SQLite database shared by both apps.
@DriftDatabase(tables: <Type>[Kv])
class AppDatabase extends _$AppDatabase {
  /// Opens the database over [executor] (in-memory in tests, a file on device).
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  /// Reads the value stored under [key], or `null`.
  Future<String?> getValue(String key) async {
    final row = await (select(
      kv,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// Upserts [value] under [key].
  Future<void> setValue(String key, String value) {
    return into(kv).insertOnConflictUpdate(
      KvCompanion.insert(
        key: key,
        value: value,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Deletes [key] if present.
  Future<int> removeValue(String key) {
    return (delete(kv)..where((t) => t.key.equals(key))).go();
  }
}
