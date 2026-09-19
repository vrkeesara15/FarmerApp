import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// A cached JSON value and when it was fetched.
typedef Snapshot = ({Object? data, DateTime fetchedAt});

/// NF-002 farmer-app cache: the last server answers (profile, orders,
/// deletion request, visit prompts) as JSON in the encrypted database's
/// `kv` table under `kisan.cache.<key>`, each with its fetch time so the
/// screens can say "as of". The khata keeps its own `khata_snapshots`
/// table (FA-022); queued writes live in the outbox.
class KisanCache {
  /// Creates the cache over [db].
  KisanCache(this.db, {DateTime Function()? clock})
    : _now = clock ?? (() => DateTime.now().toUtc());

  /// The database.
  final AppDatabase db;

  final DateTime Function() _now;

  /// `kv` key prefix.
  static const String prefix = 'kisan.cache.';

  /// Stores [data] (JSON-encodable) under [key], fetched now.
  Future<void> put(String key, Object? data, {DateTime? fetchedAt}) =>
      db.setValue(
        '$prefix$key',
        jsonEncode(<String, Object?>{
          'fetched_at': (fetchedAt ?? _now()).toUtc().toIso8601String(),
          'data': data,
        }),
      );

  /// The cached value, or null.
  Future<Snapshot?> get(String key) async {
    final raw = await db.getValue('$prefix$key');
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return (
      data: decoded['data'],
      fetchedAt:
          DateTime.tryParse('${decoded['fetched_at']}')?.toUtc() ??
          DateTime.utc(1970),
    );
  }

  /// Forgets [key].
  Future<void> remove(String key) => db.removeValue('$prefix$key');

  /// [get] now and after every `kv` write.
  Stream<Snapshot?> watch(String key) =>
      watchTables(db, <TableInfo<Table, Object?>>[db.kv], () => get(key));
}

/// [load] now and after every write to [tables].
///
/// The update subscription is opened before the first load, so a write
/// that lands while the first value is being read (a refresh started as
/// the screen opens) is never missed; loads run one at a time and a burst
/// of writes coalesces into one more load.
Stream<T> watchTables<T>(
  AppDatabase db,
  List<TableInfo<Table, Object?>> tables,
  Future<T> Function() load,
) => Stream<T>.multi((controller) {
  var running = false;
  var again = false;
  var closed = false;
  Future<void> run() async {
    if (running) {
      again = true;
      return;
    }
    running = true;
    do {
      again = false;
      try {
        final value = await load();
        if (!closed) controller.add(value);
      } on Object catch (e, s) {
        if (!closed) controller.addError(e, s);
      }
    } while (again && !closed);
    running = false;
  }

  final sub = db
      .tableUpdates(TableUpdateQuery.onAllTables(tables))
      .listen((_) => run());
  run();
  controller.onCancel = () {
    closed = true;
    return sub.cancel();
  };
});
