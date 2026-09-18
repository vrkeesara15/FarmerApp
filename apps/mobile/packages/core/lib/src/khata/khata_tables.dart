import 'package:drift/drift.dart';

/// FA-022 khata of a farmer as last fetched from `GET /v1/farmers/{id}/khata`
/// (every page), cached for offline viewing with its "as of" time.
@DataClassName('KhataSnapshotRow')
class KhataSnapshots extends Table {
  /// Farmer.
  TextColumn get farmerId => text()();

  /// The merged `KhataOut` JSON (all entries).
  TextColumn get data => text()();

  /// When it was fetched (UTC).
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{farmerId};
}
