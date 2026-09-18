import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

import '../db/app_database.dart';
import 'sync_models.dart';

/// A synced row read back as JSON plus its sync flags.
@immutable
class LocalRow {
  /// Creates the view.
  const LocalRow({
    required this.entity,
    required this.id,
    required this.version,
    required this.dirty,
    required this.deleted,
    required this.data,
  });

  /// Entity wire name.
  final String entity;

  /// Row id.
  final String id;

  /// Server version (0 until created).
  final int version;

  /// A queued op still references the row.
  final bool dirty;

  /// Local tombstone.
  final bool deleted;

  /// Fields in wire shape.
  final Map<String, Object?> data;
}

/// Reads and writes the typed local tables (farmers, farms, crop plots,
/// consent records) from and to the JSON payloads of the sync contract.
///
/// Conflict rule table (mirrors the server; the server is the arbiter and
/// the client simply applies the response):
///
/// | entity         | rule              |
/// |----------------|-------------------|
/// | farmer         | last_writer_wins  |
/// | farm           | last_writer_wins  |
/// | crop_plot      | last_writer_wins  |
/// | consent_record | append_only       |
/// | khata, payment | server_wins (M3)  |
class LocalEntities {
  /// Creates the accessor over [db].
  LocalEntities(this.db);

  /// The database.
  final AppDatabase db;

  /// Conflict rule per entity (see class doc).
  static const Map<String, String> conflictRules = <String, String>{
    SyncEntities.farmer: 'last_writer_wins',
    SyncEntities.farm: 'last_writer_wins',
    SyncEntities.cropPlot: 'last_writer_wins',
    SyncEntities.consentRecord: 'append_only',
    'khata_entry': 'server_wins',
    'payment': 'server_wins',
  };

  /// Whether [entity] has a typed table here.
  static bool isKnown(String entity) => SyncEntities.writable.contains(entity);

  /// Reads a row, or null.
  Future<LocalRow?> read(String entity, String id) async {
    switch (entity) {
      case SyncEntities.farmer:
        final row = await (db.select(
          db.farmers,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : LocalRow(
                entity: entity,
                id: id,
                version: row.version,
                dirty: row.dirty,
                deleted: row.deleted,
                data: farmerToData(row),
              );
      case SyncEntities.farm:
        final row = await (db.select(
          db.farms,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : LocalRow(
                entity: entity,
                id: id,
                version: row.version,
                dirty: row.dirty,
                deleted: row.deleted,
                data: farmToData(row),
              );
      case SyncEntities.cropPlot:
        final row = await (db.select(
          db.cropPlots,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : LocalRow(
                entity: entity,
                id: id,
                version: row.version,
                dirty: row.dirty,
                deleted: row.deleted,
                data: cropPlotToData(row),
              );
      case SyncEntities.consentRecord:
        final row = await (db.select(
          db.consentRecords,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : LocalRow(
                entity: entity,
                id: id,
                version: row.version,
                dirty: row.dirty,
                deleted: row.deleted,
                data: consentToData(row),
              );
      default:
        throw ArgumentError.value(entity, 'entity', 'no local table');
    }
  }

  /// Replaces (or inserts) the row with [data].
  Future<void> write(
    String entity,
    String id,
    Map<String, Object?> data, {
    required int version,
    required bool dirty,
    required DateTime now,
    bool deleted = false,
  }) async {
    switch (entity) {
      case SyncEntities.farmer:
        await db
            .into(db.farmers)
            .insertOnConflictUpdate(
              farmerFromData(
                id,
                data,
                version: version,
                dirty: dirty,
                deleted: deleted,
                now: now,
              ),
            );
      case SyncEntities.farm:
        await db
            .into(db.farms)
            .insertOnConflictUpdate(
              farmFromData(
                id,
                data,
                version: version,
                dirty: dirty,
                deleted: deleted,
                now: now,
              ),
            );
      case SyncEntities.cropPlot:
        await db
            .into(db.cropPlots)
            .insertOnConflictUpdate(
              cropPlotFromData(
                id,
                data,
                version: version,
                dirty: dirty,
                deleted: deleted,
                now: now,
              ),
            );
      case SyncEntities.consentRecord:
        await db
            .into(db.consentRecords)
            .insertOnConflictUpdate(
              consentFromData(
                id,
                data,
                version: version,
                dirty: dirty,
                deleted: deleted,
                now: now,
              ),
            );
      default:
        throw ArgumentError.value(entity, 'entity', 'no local table');
    }
  }

  /// Merges [patch] into the existing row (or inserts it).
  Future<LocalRow> merge(
    String entity,
    String id,
    Map<String, Object?> patch, {
    required DateTime now,
    int? version,
    bool? dirty,
    bool? deleted,
  }) async {
    final existing = await read(entity, id);
    final data = <String, Object?>{...?existing?.data, ...patch};
    final nextVersion = version ?? existing?.version ?? 0;
    final nextDirty = dirty ?? existing?.dirty ?? false;
    final nextDeleted = deleted ?? existing?.deleted ?? false;
    await write(
      entity,
      id,
      data,
      version: nextVersion,
      dirty: nextDirty,
      deleted: nextDeleted,
      now: now,
    );
    return LocalRow(
      entity: entity,
      id: id,
      version: nextVersion,
      dirty: nextDirty,
      deleted: nextDeleted,
      data: data,
    );
  }

  /// Updates only the sync flags of an existing row (no-op when missing).
  Future<void> setFlags(
    String entity,
    String id, {
    required DateTime now,
    int? version,
    bool? dirty,
    bool? deleted,
  }) async {
    final existing = await read(entity, id);
    if (existing == null) return;
    await write(
      entity,
      id,
      existing.data,
      version: version ?? existing.version,
      dirty: dirty ?? existing.dirty,
      deleted: deleted ?? existing.deleted,
      now: now,
    );
  }

  /// Hard-deletes the row.
  Future<void> delete(String entity, String id) async {
    switch (entity) {
      case SyncEntities.farmer:
        await (db.delete(db.farmers)..where((t) => t.id.equals(id))).go();
      case SyncEntities.farm:
        await (db.delete(db.farms)..where((t) => t.id.equals(id))).go();
      case SyncEntities.cropPlot:
        await (db.delete(db.cropPlots)..where((t) => t.id.equals(id))).go();
      case SyncEntities.consentRecord:
        await (db.delete(
          db.consentRecords,
        )..where((t) => t.id.equals(id))).go();
      default:
        throw ArgumentError.value(entity, 'entity', 'no local table');
    }
  }

  /// Upserts a pulled row of an entity without a writable table: villages
  /// go to the typed `villages` table (merged over the existing row),
  /// everything else to `synced_refs` as JSON.
  Future<void> writeRef(
    String entity,
    String id,
    Map<String, Object?> data, {
    required int version,
    required DateTime now,
  }) async {
    if (entity == SyncEntities.village) {
      final existing = await (db.select(
        db.villages,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      final merged = <String, Object?>{
        ...?existing == null ? null : villageToData(existing),
        ...data,
      };
      await db
          .into(db.villages)
          .insertOnConflictUpdate(
            villageFromData(id, merged, version: version, now: now),
          );
      return;
    }
    await db
        .into(db.syncedRefs)
        .insertOnConflictUpdate(
          SyncedRefsCompanion.insert(
            entity: entity,
            refId: id,
            version: Value<int>(version),
            data: jsonEncode(data),
            updatedAt: now,
          ),
        );
  }

  /// Reads a generic row's data (villages from their typed table), or null.
  Future<Map<String, Object?>?> readRef(String entity, String id) async {
    if (entity == SyncEntities.village) {
      final row = await (db.select(
        db.villages,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return row == null ? null : villageToData(row);
    }
    final row =
        await (db.select(db.syncedRefs)
              ..where((t) => t.entity.equals(entity) & t.refId.equals(id)))
            .getSingleOrNull();
    if (row == null) return null;
    return Map<String, Object?>.from(jsonDecode(row.data) as Map);
  }

  /// Deletes a generic row.
  Future<void> deleteRef(String entity, String id) {
    if (entity == SyncEntities.village) {
      return (db.delete(db.villages)..where((t) => t.id.equals(id))).go();
    }
    return (db.delete(
      db.syncedRefs,
    )..where((t) => t.entity.equals(entity) & t.refId.equals(id))).go();
  }

  // --- codecs -------------------------------------------------------------

  static double? _num(Object? v) => (v as num?)?.toDouble();

  /// Village row from wire data (`lat`/`lon`, `latitude`/`longitude` or a
  /// `location: {lat, lon}` object are all accepted).
  static Village villageFromData(
    String id,
    Map<String, Object?> d, {
    required int version,
    required DateTime now,
  }) {
    final location = d['location'];
    final loc = location is Map ? Map<String, Object?>.from(location) : null;
    return Village(
      id: id,
      name: (d['name'] as String?) ?? '',
      district: (d['district'] as String?) ?? '',
      mandal: (d['mandal'] as String?) ?? '',
      state: (d['state'] as String?) ?? '',
      storeId: d['store_id'] as String?,
      latitude: _num(d['lat'] ?? d['latitude'] ?? loc?['lat']),
      longitude: _num(d['lon'] ?? d['longitude'] ?? loc?['lon']),
      version: version,
      updatedAt: now,
    );
  }

  /// Wire data from a village row.
  static Map<String, Object?> villageToData(Village r) => <String, Object?>{
    'id': r.id,
    'name': r.name,
    'district': r.district,
    'mandal': r.mandal,
    'state': r.state,
    'store_id': r.storeId,
    'lat': r.latitude,
    'lon': r.longitude,
    'version': r.version,
  };

  /// Farmer row from wire data.
  static Farmer farmerFromData(
    String id,
    Map<String, Object?> d, {
    required int version,
    required bool dirty,
    required bool deleted,
    required DateTime now,
  }) => Farmer(
    id: id,
    phone: d['phone'] as String?,
    name: (d['name'] as String?) ?? '',
    villageId: d['village_id'] as String?,
    landmark: d['landmark'] as String?,
    language: d['language'] as String?,
    preferredLanguage: d['preferred_language'] as String?,
    landOwnership: d['land_ownership'] as String?,
    source: d['source'] as String?,
    phoneVerified: d['phone_verified'] == true,
    consentMarketing: d['consent_marketing'] == true,
    version: version,
    updatedAt: now,
    dirty: dirty,
    deleted: deleted,
  );

  /// Wire data from a farmer row.
  static Map<String, Object?> farmerToData(Farmer r) => <String, Object?>{
    'id': r.id,
    'phone': r.phone,
    'name': r.name,
    'village_id': r.villageId,
    'landmark': r.landmark,
    'language': r.language,
    'preferred_language': r.preferredLanguage,
    'land_ownership': r.landOwnership,
    'source': r.source,
    'phone_verified': r.phoneVerified,
    'consent_marketing': r.consentMarketing,
    'version': r.version,
  };

  /// Farm row from wire data.
  static Farm farmFromData(
    String id,
    Map<String, Object?> d, {
    required int version,
    required bool dirty,
    required bool deleted,
    required DateTime now,
  }) => Farm(
    id: id,
    farmerId: (d['farmer_id'] as String?) ?? '',
    name: d['name'] as String?,
    boundary: d['boundary'] == null ? null : jsonEncode(d['boundary']),
    areaAcres: (d['area_acres'] as num?)?.toDouble(),
    soil: d['soil'] as String?,
    irrigation: d['irrigation'] as String?,
    ownership: d['ownership'] as String?,
    photos: jsonEncode(d['photos'] ?? const <Object?>[]),
    version: version,
    updatedAt: now,
    dirty: dirty,
    deleted: deleted,
  );

  /// Wire data from a farm row.
  static Map<String, Object?> farmToData(Farm r) => <String, Object?>{
    'id': r.id,
    'farmer_id': r.farmerId,
    'name': r.name,
    'boundary': r.boundary == null ? null : jsonDecode(r.boundary!),
    'area_acres': r.areaAcres,
    'soil': r.soil,
    'irrigation': r.irrigation,
    'ownership': r.ownership,
    'photos': jsonDecode(r.photos),
    'version': r.version,
  };

  /// Crop plot row from wire data.
  static CropPlot cropPlotFromData(
    String id,
    Map<String, Object?> d, {
    required int version,
    required bool dirty,
    required bool deleted,
    required DateTime now,
  }) => CropPlot(
    id: id,
    farmId: (d['farm_id'] as String?) ?? '',
    cropId: d['crop_id'] as String?,
    variety: d['variety'] as String?,
    season: d['season'] as String?,
    sowingDate: d['sowing_date'] as String?,
    stage: d['stage'] as String?,
    areaAcres: (d['area_acres'] as num?)?.toDouble(),
    version: version,
    updatedAt: now,
    dirty: dirty,
    deleted: deleted,
  );

  /// Wire data from a crop plot row.
  static Map<String, Object?> cropPlotToData(CropPlot r) => <String, Object?>{
    'id': r.id,
    'farm_id': r.farmId,
    'crop_id': r.cropId,
    'variety': r.variety,
    'season': r.season,
    'sowing_date': r.sowingDate,
    'stage': r.stage,
    'area_acres': r.areaAcres,
    'version': r.version,
  };

  /// Consent row from wire data. The payload's `version` is the consent
  /// text version (a string); the row version comes from the envelope.
  static ConsentRecord consentFromData(
    String id,
    Map<String, Object?> d, {
    required int version,
    required bool dirty,
    required bool deleted,
    required DateTime now,
  }) => ConsentRecord(
    id: id,
    farmerId: (d['farmer_id'] as String?) ?? '',
    purpose: (d['purpose'] as String?) ?? 'data',
    granted: d['granted'] == true,
    consentVersion: switch (d['version']) {
      final String s => s,
      _ => d['consent_version'] as String?,
    },
    channel: d['channel'] as String?,
    version: version,
    updatedAt: now,
    dirty: dirty,
    deleted: deleted,
  );

  /// Wire data from a consent row.
  static Map<String, Object?> consentToData(ConsentRecord r) =>
      <String, Object?>{
        'id': r.id,
        'farmer_id': r.farmerId,
        'purpose': r.purpose,
        'granted': r.granted,
        'version': r.consentVersion,
        'channel': r.channel,
      };
}
