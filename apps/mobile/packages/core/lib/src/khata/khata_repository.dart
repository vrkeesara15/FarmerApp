import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../catalog/rest_json_client.dart';
import '../db/app_database.dart';
import '../kisan/kisan_cache.dart' show watchTables;
import 'khata_models.dart';

/// `GET /v1/farmers/{id}/khata` (FA-022).
abstract interface class KhataApi {
  /// Every page merged into one `KhataOut` (entries and payment history
  /// concatenated), so the entries shown add up to the balance.
  Future<Map<String, Object?>> fetch(String farmerId);
}

/// Merges `KhataOut` pages: the first page's header, all entries.
Map<String, Object?> mergeKhataPages(List<Map<String, Object?>> pages) {
  if (pages.isEmpty) return const <String, Object?>{};
  return <String, Object?>{
    ...pages.first,
    'entries': <Object?>[
      for (final p in pages) ...((p['entries'] as List?) ?? const <Object?>[]),
    ],
    'next_cursor': null,
  };
}

/// [KhataApi] over HTTP.
class HttpKhataApi implements KhataApi {
  /// Creates the client.
  HttpKhataApi(this._rest);

  final RestJsonClient _rest;

  @override
  Future<Map<String, Object?>> fetch(String farmerId) async {
    final pages = <Map<String, Object?>>[];
    String? cursor;
    do {
      final r = await _rest.get(
        '/v1/farmers/$farmerId/khata',
        query: <String, Object?>{'cursor': cursor, 'limit': 200},
      );
      if (!r.ok) throw KhataUnavailableException(r.status);
      pages.add(r.body);
      cursor = r.body['next_cursor'] as String?;
    } while (cursor != null);
    return mergeKhataPages(pages);
  }
}

/// In-memory khata server for tests and previews.
class FakeKhataApi implements KhataApi {
  /// Every call throws while true.
  bool offline = false;

  /// `KhataOut` per farmer.
  final Map<String, Map<String, Object?>> khatas =
      <String, Map<String, Object?>>{};

  /// Fetches made.
  int fetches = 0;

  @override
  Future<Map<String, Object?>> fetch(String farmerId) async {
    fetches += 1;
    if (offline) throw const KhataUnavailableException();
    final k = khatas[farmerId];
    if (k == null) throw const KhataUnavailableException(404);
    return k;
  }
}

/// Cached khata per farmer (A58 works offline with "as of").
class KhataRepository {
  /// Creates the repository.
  KhataRepository(this.db, this.api, {DateTime Function()? clock})
    : _now = clock ?? (() => DateTime.now().toUtc());

  /// The database.
  final AppDatabase db;

  /// The endpoint.
  final KhataApi api;

  final DateTime Function() _now;

  /// Fetches and caches the khata; false when offline (the cache stays).
  Future<bool> refresh(String farmerId) async {
    final Map<String, Object?> data;
    try {
      data = await api.fetch(farmerId);
    } on KhataUnavailableException {
      return false;
    }
    await db
        .into(db.khataSnapshots)
        .insertOnConflictUpdate(
          KhataSnapshotRow(
            farmerId: farmerId,
            data: jsonEncode(data),
            fetchedAt: _now(),
          ),
        );
    return true;
  }

  /// The cached khata, or null.
  Future<KhataView?> read(String farmerId) async {
    final row = await (db.select(
      db.khataSnapshots,
    )..where((t) => t.farmerId.equals(farmerId))).getSingleOrNull();
    if (row == null) return null;
    return KhataView.fromJson(
      Map<String, Object?>.from(jsonDecode(row.data) as Map),
      asOf: row.fetchedAt.toUtc(),
    );
  }

  /// [read] now and after every refresh (the update subscription opens
  /// before the first read, so a refresh started as the screen opens is
  /// never missed).
  Stream<KhataView?> watch(String farmerId) => watchTables(
    db,
    <TableInfo<Table, Object?>>[db.khataSnapshots],
    () => read(farmerId),
  );
}
