import 'package:drift/drift.dart';

import '../catalog/catalog_tables.dart';
import '../khata/khata_tables.dart';
import '../orders/order_tables.dart';
import '../payments/payment_tables.dart';

part 'app_database.g.dart';

/// Simple key/value table used for settings and sync bookkeeping.
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

/// Columns every synced domain row carries (FA-025).
///
/// `version` is the server row version (0 until the create is applied),
/// `dirty` means an outbox op for the row is still queued, `deleted` is the
/// local tombstone until the delete op is applied.
mixin SyncedRow on Table {
  /// Client-generated uuid, also the server id.
  TextColumn get id => text()();

  /// Server row version; 0 while the create is still queued.
  IntColumn get version => integer().withDefault(const Constant(0))();

  /// Last local write (UTC).
  DateTimeColumn get updatedAt => dateTime()();

  /// A queued op still references this row.
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// Deleted locally; removed once the server confirms.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// FA-012 farmer as captured offline.
class Farmers extends Table with SyncedRow {
  /// E.164 phone.
  TextColumn get phone => text().nullable()();

  /// Display name.
  TextColumn get name => text().withDefault(const Constant(''))();

  /// Village id (reference data in `synced_refs`).
  TextColumn get villageId => text().nullable()();

  /// Landmark near the home.
  TextColumn get landmark => text().nullable()();

  /// Spoken language code.
  TextColumn get language => text().nullable()();

  /// Preferred language for messages.
  TextColumn get preferredLanguage => text().nullable()();

  /// `own` | `leased`.
  TextColumn get landOwnership => text().nullable()();

  /// How the farmer was acquired (e.g. `field_officer`).
  TextColumn get source => text().nullable()();

  /// Phone verified by OTP at registration.
  BoolColumn get phoneVerified =>
      boolean().withDefault(const Constant(false))();

  /// Marketing consent cache (FM-002).
  BoolColumn get consentMarketing =>
      boolean().withDefault(const Constant(false))();
}

/// FA-013 farm (one farmer has many).
class Farms extends Table with SyncedRow {
  /// Owning farmer.
  TextColumn get farmerId => text()();

  /// Farm label.
  TextColumn get name => text().nullable()();

  /// GeoJSON Polygon as text.
  TextColumn get boundary => text().nullable()();

  /// Area in acres as entered.
  RealColumn get areaAcres => real().nullable()();

  /// Soil type.
  TextColumn get soil => text().nullable()();

  /// Irrigation type.
  TextColumn get irrigation => text().nullable()();

  /// `own` | `leased`.
  TextColumn get ownership => text().nullable()();

  /// JSON list of blob URIs (or `upload:<id>` placeholders while queued).
  TextColumn get photos => text().withDefault(const Constant('[]'))();
}

/// FA-013 crop plot (one farm has many per season).
class CropPlots extends Table with SyncedRow {
  /// Owning farm.
  TextColumn get farmId => text()();

  /// Crop id (reference data in `synced_refs`).
  TextColumn get cropId => text().nullable()();

  /// Variety as entered.
  TextColumn get variety => text().nullable()();

  /// `kharif` | `rabi` | `summer`.
  TextColumn get season => text().nullable()();

  /// ISO-8601 date.
  TextColumn get sowingDate => text().nullable()();

  /// Growth stage.
  TextColumn get stage => text().nullable()();

  /// Area in acres.
  RealColumn get areaAcres => real().nullable()();
}

/// FM-002 consent record (append-only on the server).
class ConsentRecords extends Table with SyncedRow {
  /// Subject farmer.
  TextColumn get farmerId => text()();

  /// `data` | `marketing`.
  TextColumn get purpose => text()();

  /// Granted or withdrawn.
  BoolColumn get granted => boolean().withDefault(const Constant(false))();

  /// Consent text version (e.g. `2026-09-v1`), distinct from the row version.
  TextColumn get consentVersion => text().nullable()();

  /// Channel the consent was taken on.
  TextColumn get channel => text().nullable()();
}

/// Queued write operations (NF-003 outbox with idempotency keys).
@TableIndex(name: 'outbox_state_seq', columns: <Symbol>{#state, #seq})
@TableIndex(name: 'outbox_entity', columns: <Symbol>{#entityId})
@DataClassName('OutboxRow')
class OutboxTable extends Table {
  @override
  String get tableName => 'outbox';

  /// Idempotency key (uuid), generated when the op is queued.
  TextColumn get opId => text()();

  /// Local insertion order; the push order.
  IntColumn get seq => integer()();

  /// `farmer` | `farm` | `crop_plot` | `consent_record`.
  TextColumn get entity => text()();

  /// `create` | `update` | `delete`.
  TextColumn get action => text()();

  /// The row this op targets.
  TextColumn get entityId => text()();

  /// Server version the op was based on (0 for create).
  IntColumn get baseVersion => integer().withDefault(const Constant(0))();

  /// JSON payload.
  TextColumn get payload => text()();

  /// ISO-8601 UTC time the op was queued.
  TextColumn get clientTs => text()();

  /// queued | sending | applied | duplicate | conflict | rejected.
  TextColumn get state => text().withDefault(const Constant('queued'))();

  /// Push attempts so far.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// JSON `{code, detail}` of the last error.
  TextColumn get lastError => text().nullable()();

  /// Earliest next push (UTC); null = as soon as possible.
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  /// Local upload row this op waits for (photo `blob_uri`).
  TextColumn get dependsOnUploadId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{opId};
}

/// Resumable chunked uploads (NF-003, 256 KB chunks).
class Uploads extends Table {
  /// Local id, referenced by outbox payloads as `upload:<id>`.
  TextColumn get id => text()();

  /// Server upload id; null until `POST /v1/uploads` succeeds.
  TextColumn get uploadId => text().nullable()();

  /// Local file path of the processed photo.
  TextColumn get filePath => text()();

  /// Hex SHA-256 of the whole file.
  TextColumn get sha256 => text()();

  /// File size.
  IntColumn get sizeBytes => integer()();

  /// Chunk size negotiated with the server.
  IntColumn get chunkSize => integer()();

  /// JSON list of acknowledged chunk indexes.
  TextColumn get receivedChunks => text().withDefault(const Constant('[]'))();

  /// pending | uploading | complete | failed.
  TextColumn get state => text().withDefault(const Constant('pending'))();

  /// Server blob URI once complete.
  TextColumn get blobUri => text().nullable()();

  /// e.g. `farm_photo`, `visit_photo`.
  TextColumn get purpose => text()();

  /// MIME type.
  TextColumn get contentType =>
      text().withDefault(const Constant('image/jpeg'))();

  /// Attempts so far.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// JSON `{code, detail}` of the last error.
  TextColumn get lastError => text().nullable()();

  /// Server-side expiry of the upload session.
  DateTimeColumn get expiresAt => dateTime().nullable()();

  /// When the upload was queued (UTC).
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Single-row sync bookkeeping (`id` is always 1).
@DataClassName('SyncStateRow')
class SyncStates extends Table {
  /// Always 1.
  IntColumn get id => integer()();

  /// Pull cursor from the last `/v1/sync` response.
  TextColumn get cursor => text().nullable()();

  /// Last fully successful sync (UTC).
  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  /// JSON `{code, detail}` of the last transport failure.
  TextColumn get lastError => text().nullable()();

  /// Consecutive transport failures (drives the backoff).
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Earliest next automatic attempt (UTC) after a failure.
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Generic store for pulled reference data and entities this app version
/// does not know (villages, crops, ...), so new server entities never break
/// old clients.
class SyncedRefs extends Table {
  /// Entity name as sent by the server.
  TextColumn get entity => text()();

  /// Entity id.
  TextColumn get refId => text()();

  /// Server version.
  IntColumn get version => integer().withDefault(const Constant(0))();

  /// JSON data.
  TextColumn get data => text()();

  /// Last pull that touched the row (UTC).
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{entity, refId};
}

/// Village reference data pulled from the sync change feed (FA-012 A21a
/// village picker works offline).
class Villages extends Table {
  /// Server id.
  TextColumn get id => text()();

  /// Village name.
  TextColumn get name => text()();

  /// District.
  TextColumn get district => text().withDefault(const Constant(''))();

  /// Mandal / taluk.
  TextColumn get mandal => text().withDefault(const Constant(''))();

  /// State.
  TextColumn get state => text().withDefault(const Constant(''))();

  /// Nearest store, if assigned.
  TextColumn get storeId => text().nullable()();

  /// Village centre latitude.
  RealColumn get latitude => real().nullable()();

  /// Village centre longitude.
  RealColumn get longitude => real().nullable()();

  /// Meeting point latitude (VV-003), if registered.
  RealColumn get meetingPointLat => real().nullable()();

  /// Meeting point longitude.
  RealColumn get meetingPointLon => real().nullable()();

  /// Meeting point radius (m); null = tenant default.
  RealColumn get meetingPointRadiusM => real().nullable()();

  /// Server row version.
  IntColumn get version => integer().withDefault(const Constant(0))();

  /// Last pull that touched the row (UTC).
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// FA-010 duty session as started on this device (one per shift).
///
/// `end_at` / `end_reason` are server-owned once the server auto-ended the
/// session (VV-007): the engine writes the server row on `conflict` and
/// the `DutyController` ends the local service when it sees `end_at`.
class DutySessions extends Table with SyncedRow {
  /// When duty started (UTC).
  DateTimeColumn get startAt => dateTime()();

  /// When duty ended (UTC); null while active.
  DateTimeColumn get endAt => dateTime().nullable()();

  /// `manual` | `auto_time` | `auto_idle` | `forced` | `rejected`.
  TextColumn get endReason => text().nullable()();

  /// Start fix latitude.
  RealColumn get startLat => real().nullable()();

  /// Start fix longitude.
  RealColumn get startLon => real().nullable()();

  /// Start fix accuracy (m).
  RealColumn get startAccuracyM => real().nullable()();

  /// End fix latitude.
  RealColumn get endLat => real().nullable()();

  /// End fix longitude.
  RealColumn get endLon => real().nullable()();

  /// End fix accuracy (m).
  RealColumn get endAccuracyM => real().nullable()();

  /// Location policy version accepted when the session started (VV-010).
  TextColumn get policyVersion => text().nullable()();

  /// Device that started the session.
  TextColumn get deviceId => text().nullable()();

  /// App version that started the session.
  TextColumn get appVersion => text().nullable()();

  /// JSON `{is_mock, is_rooted, clock_drift_s}` at start (FA-028).
  TextColumn get integrity => text().withDefault(const Constant('{}'))();

  /// Client-side distance estimate in metres (sum of accepted point hops).
  RealColumn get distanceM => real().withDefault(const Constant(0))();

  /// The server ended the session (VV-007); end fields are then read-only.
  BoolColumn get autoEnded => boolean().withDefault(const Constant(false))();

  /// JSON of server fields this app does not model (km, stops, points).
  TextColumn get extra => text().withDefault(const Constant('{}'))();
}

/// VV-001 on-duty location points waiting for (or already in) a
/// `location_batch` op. Points are only ever written while a session is
/// active; the day's points stay until the next day for A12 (track, km).
@TableIndex(name: 'location_buffer_session', columns: <Symbol>{#sessionId, #ts})
@DataClassName('LocationBufferRow')
class LocationBuffer extends Table {
  /// Local sequence.
  IntColumn get id => integer().autoIncrement()();

  /// Owning duty session.
  TextColumn get sessionId => text()();

  /// Fix time (UTC).
  DateTimeColumn get ts => dateTime()();

  /// Latitude.
  RealColumn get lat => real()();

  /// Longitude.
  RealColumn get lon => real()();

  /// Horizontal accuracy (m).
  RealColumn get accuracyM => real()();

  /// Speed (m/s), if the provider gave one.
  RealColumn get speedMps => real().nullable()();

  /// Bearing (degrees), if the provider gave one.
  RealColumn get bearing => real().nullable()();

  /// Battery level 0-100.
  IntColumn get batteryPct => integer().nullable()();

  /// The fix came from a mock provider (FA-028).
  BoolColumn get isMock => boolean().withDefault(const Constant(false))();

  /// The device looked rooted when the fix was taken (FA-028).
  BoolColumn get isRooted => boolean().withDefault(const Constant(false))();

  /// Device clock minus server clock (s) at the fix, if known (VV-002).
  IntColumn get clockDriftS => integer().nullable()();

  /// `fused` | `gps` | `network` | ...
  TextColumn get provider => text().nullable()();

  /// The `location_batch` op the point went out in; null while pending.
  TextColumn get batchId => text().nullable()();
}

/// Writable sync entities without a typed table (`location_batch`,
/// `policy_acceptance`): the row in JSON plus the sync flags.
class SyncDocs extends Table {
  /// Entity wire name.
  TextColumn get entity => text()();

  /// Row id.
  TextColumn get docId => text()();

  /// Server row version; 0 while the create is still queued.
  IntColumn get version => integer().withDefault(const Constant(0))();

  /// A queued op still references this row.
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// Local tombstone.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// JSON data.
  TextColumn get data => text()();

  /// Last local write (UTC).
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{entity, docId};
}

/// FA-014 .. FA-017 visit as captured on this device (sync entity `visit`).
///
/// `geofence_result`, `score`, `score_components`, `status`, `duration_s`,
/// `confirmed_at`, `flags` and `integrity_issues` are server-owned: the
/// applied / conflict echo and the pull overwrite them. The `precheck*`
/// columns hold the client-side VV-003 decision taken before the op was
/// queued, `failure*` the server's rejection (e.g. `outside_geofence`).
@TableIndex(name: 'visits_checkin', columns: <Symbol>{#checkinAt})
class Visits extends Table with SyncedRow {
  /// Farmer visited.
  TextColumn get farmerId => text()();

  /// Farm (geofence target), if any.
  TextColumn get farmId => text().nullable()();

  /// Meeting-point village, if any.
  TextColumn get villageId => text().nullable()();

  /// `advisory` | `scouting` | `demo` | `collection` | `sale` | `meeting`.
  TextColumn get purpose => text().withDefault(const Constant('advisory'))();

  /// Check-in time (UTC, device clock).
  DateTimeColumn get checkinAt => dateTime()();

  /// Check-in fix latitude.
  RealColumn get checkinLat => real()();

  /// Check-in fix longitude.
  RealColumn get checkinLon => real()();

  /// Check-in fix accuracy (m).
  RealColumn get checkinAccuracyM => real().nullable()();

  /// Check-out time (UTC); null while open.
  DateTimeColumn get checkoutAt => dateTime().nullable()();

  /// Check-out fix latitude.
  RealColumn get checkoutLat => real().nullable()();

  /// Check-out fix longitude.
  RealColumn get checkoutLon => real().nullable()();

  /// Server `geofence_result` (inside | outside | meeting_point | override).
  TextColumn get geofenceResult => text().nullable()();

  /// Client pre-check result (inside | meeting_point | outside).
  TextColumn get precheckResult => text().nullable()();

  /// Client pre-check distance to the target (m).
  RealColumn get precheckDistanceM => real().nullable()();

  /// Client pre-check target (`farm` | `meeting_point`).
  TextColumn get precheckTarget => text().nullable()();

  /// Client pre-check radius (m).
  RealColumn get precheckRadiusM => real().nullable()();

  /// FA-014 override note (outside the geofence).
  TextColumn get overrideNote => text().nullable()();

  /// Cluster head who approved the override, once decided.
  TextColumn get overrideApprovedBy => text().nullable()();

  /// FA-015 notes.
  TextColumn get notes => text().nullable()();

  /// FA-015 crop stage.
  TextColumn get cropStage => text().nullable()();

  /// Server-computed duration (s).
  IntColumn get durationS => integer().nullable()();

  /// Server VV-004 score; null while open.
  IntColumn get score => integer().nullable()();

  /// Server VV-005 status (`open` until check-out).
  TextColumn get status => text().withDefault(const Constant('open'))();

  /// `sms_otp` | `app_push` | `qr` | `none`.
  TextColumn get confirmationChannel =>
      text().withDefault(const Constant('none'))();

  /// Server-owned confirmation time.
  DateTimeColumn get confirmedAt => dateTime().nullable()();

  /// JSON `{is_mock, is_rooted, clock_drift_s}` at check-in (FA-028).
  TextColumn get deviceIntegrity => text().withDefault(const Constant('{}'))();

  /// JSON list of server integrity issues.
  TextColumn get integrityIssues => text().withDefault(const Constant('[]'))();

  /// JSON list of server flags (`under_minimum`).
  TextColumn get flags => text().withDefault(const Constant('[]'))();

  /// JSON `{geofence, confirmation, photo, duration, integrity}` from the
  /// server; null until the server has seen the visit.
  TextColumn get scoreComponents => text().nullable()();

  /// The device's own id for replays (defaults to `id`).
  TextColumn get clientVisitId => text().nullable()();

  /// Officer (server-assigned).
  TextColumn get officerId => text().nullable()();

  /// Problem code of a rejected check-in (`outside_geofence`).
  TextColumn get failureCode => text().nullable()();

  /// JSON `{detail, distance_m, target, radius_m}` of the rejection.
  TextColumn get failureDetail => text().nullable()();

  /// JSON of server fields this app does not model.
  TextColumn get extra => text().withDefault(const Constant('{}'))();
}

/// FA-015 in-app photo of a visit (sync entity `visit_photo`).
@TableIndex(name: 'visit_photos_visit', columns: <Symbol>{#visitId})
class VisitPhotos extends Table with SyncedRow {
  /// Owning visit.
  TextColumn get visitId => text()();

  /// Server blob URI, or the `upload:<id>` placeholder while queued.
  TextColumn get blobUri => text().withDefault(const Constant(''))();

  /// Hex SHA-256 of the processed JPEG.
  TextColumn get sha256 => text().nullable()();

  /// Server perceptual hash.
  TextColumn get phash => text().nullable()();

  /// EXIF capture time (UTC).
  DateTimeColumn get exifTime => dateTime().nullable()();

  /// EXIF GPS latitude.
  RealColumn get exifLat => real().nullable()();

  /// EXIF GPS longitude.
  RealColumn get exifLon => real().nullable()();

  /// Always true on this device (no gallery path exists).
  BoolColumn get takenInApp => boolean().withDefault(const Constant(true))();

  /// Device time at capture (UTC).
  DateTimeColumn get deviceTime => dateTime().nullable()();

  /// Server receive time.
  DateTimeColumn get serverTime => dateTime().nullable()();

  /// JSON list of VA-E08 flags from the server.
  TextColumn get photoFlags => text().withDefault(const Constant('[]'))();

  /// Local file of the processed photo (thumbnail).
  TextColumn get localPath => text().nullable()();

  /// JSON of server fields this app does not model.
  TextColumn get extra => text().withDefault(const Constant('{}'))();
}

/// FA-016 confirmation request / result (sync entity `visit_confirmation`).
@TableIndex(name: 'visit_confirmations_visit', columns: <Symbol>{#visitId})
class VisitConfirmations extends Table with SyncedRow {
  /// Owning visit.
  TextColumn get visitId => text()();

  /// `sms_otp` | `app_push` | `qr`.
  TextColumn get channel => text()();

  /// `pending` | `confirmed` | `expired` (server) | `queued` (local:
  /// requested offline, sent when online).
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// When the request was made.
  DateTimeColumn get requestedAt => dateTime().nullable()();

  /// When the code / token lapses.
  DateTimeColumn get expiresAt => dateTime().nullable()();

  /// Server-owned confirmation time.
  DateTimeColumn get confirmedAt => dateTime().nullable()();

  /// Last four digits of the farmer phone the OTP went to.
  TextColumn get farmerPhoneLast4 => text().nullable()();

  /// FM-011 rating, once the farmer gave one.
  IntColumn get rating => integer().nullable()();

  /// Signed QR token to render (local only; never sent back).
  TextColumn get token => text().nullable()();

  /// JSON of server fields this app does not model.
  TextColumn get extra => text().withDefault(const Constant('{}'))();
}

/// The on-device SQLite database shared by both apps.
///
/// Schema history:
/// * v1 (M0): `kv`.
/// * v2 (FA-025): farmers, farms, crop_plots, consent_records, outbox,
///   uploads, sync_states, synced_refs.
/// * v3 (FA-012): villages.
/// * v4 (FA-010 / VV-001): duty_sessions, location_buffer, sync_docs.
/// * v5 (FA-014 .. FA-017): visits, visit_photos, visit_confirmations;
///   villages gain the meeting point columns (VV-003).
/// * v6 (FA-020 .. FA-022): catalog_products, catalog_skus, catalog_prices,
///   stock_snapshots, catalog_stores, orders, order_lines, payments,
///   khata_snapshots.
@DriftDatabase(
  tables: <Type>[
    Kv,
    Farmers,
    Farms,
    CropPlots,
    ConsentRecords,
    OutboxTable,
    Uploads,
    SyncStates,
    SyncedRefs,
    Villages,
    DutySessions,
    LocationBuffer,
    SyncDocs,
    Visits,
    VisitPhotos,
    VisitConfirmations,
    CatalogProducts,
    CatalogSkus,
    CatalogPrices,
    StockSnapshots,
    CatalogStores,
    Orders,
    OrderLines,
    Payments,
    KhataSnapshots,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the database over [executor] (in-memory in tests, a file on device).
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 6;

  /// Tables added in schema v2, in creation order.
  List<TableInfo<Table, Object?>> get _v2Tables => <TableInfo<Table, Object?>>[
    farmers,
    farms,
    cropPlots,
    consentRecords,
    outboxTable,
    uploads,
    syncStates,
    syncedRefs,
  ];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        for (final table in _v2Tables) {
          await m.createTable(table);
        }
        await m.createIndex(outboxStateSeq);
        await m.createIndex(outboxEntity);
      }
      if (from < 3) {
        await m.createTable(villages);
      }
      if (from < 4) {
        await m.createTable(dutySessions);
        await m.createTable(locationBuffer);
        await m.createIndex(locationBufferSession);
        await m.createTable(syncDocs);
      }
      if (from < 5) {
        await m.createTable(visits);
        await m.createIndex(visitsCheckin);
        await m.createTable(visitPhotos);
        await m.createIndex(visitPhotosVisit);
        await m.createTable(visitConfirmations);
        await m.createIndex(visitConfirmationsVisit);
        if (from >= 3) {
          // Older `villages` tables (v3 / v4) gain the meeting point; a
          // table created above by the v3 step already has the columns.
          await m.addColumn(villages, villages.meetingPointLat);
          await m.addColumn(villages, villages.meetingPointLon);
          await m.addColumn(villages, villages.meetingPointRadiusM);
        }
      }
      if (from < 6) {
        await m.createTable(catalogProducts);
        await m.createTable(catalogSkus);
        await m.createIndex(catalogSkusProduct);
        await m.createTable(catalogPrices);
        await m.createTable(stockSnapshots);
        await m.createTable(catalogStores);
        await m.createTable(orders);
        await m.createIndex(ordersFarmer);
        await m.createTable(orderLines);
        await m.createIndex(orderLinesOrder);
        await m.createTable(payments);
        await m.createIndex(paymentsCollected);
        await m.createTable(khataSnapshots);
      }
    },
  );

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
