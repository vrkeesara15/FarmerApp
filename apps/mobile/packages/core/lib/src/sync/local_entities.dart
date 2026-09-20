import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

import '../db/app_database.dart';
import '../diagnosis/diagnosis_codec.dart';
import '../orders/order_codec.dart';
import '../payments/payment_codec.dart';
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
/// | duty_session   | merge_fields      |
/// | location_batch | server_wins       |
/// | policy_acceptance | server_wins    |
/// | visit          | server_wins (score fields; notes last writer) |
/// | visit_photo    | server_wins       |
/// | visit_confirmation | server_wins   |
/// | order          | server_wins (FA-020; lines replaced by the server's) |
/// | payment        | server_wins (FA-021) |
/// | khata_entry    | server_wins (pull only, `synced_refs`) |
/// | diagnosis      | server_wins (create only; `sync_docs`, answers kept as history) |
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
    SyncEntities.dutySession: 'merge_fields',
    SyncEntities.locationBatch: 'server_wins',
    SyncEntities.policyAcceptance: 'server_wins',
    SyncEntities.visit: 'server_wins',
    SyncEntities.visitPhoto: 'server_wins',
    SyncEntities.visitConfirmation: 'server_wins',
    SyncEntities.order: 'server_wins',
    SyncEntities.payment: 'server_wins',
    SyncEntities.khataEntry: 'server_wins',
    SyncEntities.diagnosis: 'server_wins',
    // M7 field P1 (`sync_docs`; docs/prs/M7-field-p1-api.md "Sync").
    'notification': 'last_writer_wins',
    'track_gap': 'last_writer_wins',
    'beat_plan': 'last_writer_wins',
    'travel_claim': 'server_wins',
    'demo_plot': 'last_writer_wins',
    'demo_observation': 'server_wins',
    'farmer_meeting': 'last_writer_wins',
    'meeting_attendance': 'server_wins',
  };

  LocalRow? _row(String entity, String id, Map<String, Object?>? data) {
    if (data == null) return null;
    return LocalRow(
      entity: entity,
      id: id,
      version: (data['version'] as num?)?.toInt() ?? 0,
      dirty: data[_dirtyKey] == true,
      deleted: data[_deletedKey] == true,
      data: <String, Object?>{...data}
        ..remove(_dirtyKey)
        ..remove(_deletedKey),
    );
  }

  static const String _dirtyKey = '__dirty';
  static const String _deletedKey = '__deleted';

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
      case SyncEntities.dutySession:
        final row = await (db.select(
          db.dutySessions,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : LocalRow(
                entity: entity,
                id: id,
                version: row.version,
                dirty: row.dirty,
                deleted: row.deleted,
                data: dutySessionToData(row),
              );
      case SyncEntities.visit:
        final row = await (db.select(
          db.visits,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : LocalRow(
                entity: entity,
                id: id,
                version: row.version,
                dirty: row.dirty,
                deleted: row.deleted,
                data: visitToData(row),
              );
      case SyncEntities.visitPhoto:
        final row = await (db.select(
          db.visitPhotos,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : LocalRow(
                entity: entity,
                id: id,
                version: row.version,
                dirty: row.dirty,
                deleted: row.deleted,
                data: visitPhotoToData(row),
              );
      case SyncEntities.visitConfirmation:
        final row = await (db.select(
          db.visitConfirmations,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return row == null
            ? null
            : LocalRow(
                entity: entity,
                id: id,
                version: row.version,
                dirty: row.dirty,
                deleted: row.deleted,
                data: visitConfirmationToData(row),
              );
      case SyncEntities.order:
        final row = await (db.select(
          db.orders,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row == null) return null;
        return _row(entity, id, <String, Object?>{
          ...?await OrderCodec.read(db, id),
          _dirtyKey: row.dirty,
          _deletedKey: row.deleted,
        });
      case SyncEntities.payment:
        final row = await (db.select(
          db.payments,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row == null) return null;
        return _row(entity, id, <String, Object?>{
          ...PaymentCodec.toData(row),
          _dirtyKey: row.dirty,
          _deletedKey: row.deleted,
        });
      default:
        if (!isKnown(entity)) {
          throw ArgumentError.value(entity, 'entity', 'no local table');
        }
        final row =
            await (db.select(db.syncDocs)
                  ..where((t) => t.entity.equals(entity) & t.docId.equals(id)))
                .getSingleOrNull();
        return row == null
            ? null
            : LocalRow(
                entity: entity,
                id: id,
                version: row.version,
                dirty: row.dirty,
                deleted: row.deleted,
                data: Map<String, Object?>.from(jsonDecode(row.data) as Map),
              );
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
      case SyncEntities.dutySession:
        await db
            .into(db.dutySessions)
            .insertOnConflictUpdate(
              dutySessionFromData(
                id,
                data,
                version: version,
                dirty: dirty,
                deleted: deleted,
                now: now,
              ),
            );
      case SyncEntities.visit:
        await db
            .into(db.visits)
            .insertOnConflictUpdate(
              visitFromData(
                id,
                await _keepLocal(entity, id, data),
                version: version,
                dirty: dirty,
                deleted: deleted,
                now: now,
              ),
            );
      case SyncEntities.visitPhoto:
        await db
            .into(db.visitPhotos)
            .insertOnConflictUpdate(
              visitPhotoFromData(
                id,
                await _keepLocal(entity, id, data),
                version: version,
                dirty: dirty,
                deleted: deleted,
                now: now,
              ),
            );
      case SyncEntities.visitConfirmation:
        await db
            .into(db.visitConfirmations)
            .insertOnConflictUpdate(
              visitConfirmationFromData(
                id,
                await _keepLocal(entity, id, data),
                version: version,
                dirty: dirty,
                deleted: deleted,
                now: now,
              ),
            );
      case SyncEntities.order:
        await OrderCodec.write(
          db,
          id,
          data,
          version: version,
          dirty: dirty,
          deleted: deleted,
          now: now,
        );
      case SyncEntities.payment:
        await PaymentCodec.write(
          db,
          id,
          data,
          version: version,
          dirty: dirty,
          deleted: deleted,
          now: now,
        );
      default:
        if (!isKnown(entity)) {
          throw ArgumentError.value(entity, 'entity', 'no local table');
        }
        final stored = entity == SyncEntities.diagnosis
            ? DiagnosisCodec.onWrite(
                (await read(entity, id))?.data,
                data,
                now: now,
              )
            : data;
        await db
            .into(db.syncDocs)
            .insertOnConflictUpdate(
              SyncDocsCompanion.insert(
                entity: entity,
                docId: id,
                version: Value<int>(version),
                dirty: Value<bool>(dirty),
                deleted: Value<bool>(deleted),
                data: jsonEncode(docData(entity, id, stored)),
                updatedAt: now,
              ),
            );
    }
  }

  /// What a `sync_docs` row keeps: a `location_batch` stores its point
  /// count instead of the points (they live in `location_buffer` and in the
  /// outbox payload until the op is applied).
  static Map<String, Object?> docData(
    String entity,
    String id,
    Map<String, Object?> data,
  ) {
    final out = <String, Object?>{...data, 'id': id};
    if (entity == SyncEntities.locationBatch && out['points'] is List) {
      out['point_count'] = (out['points']! as List).length;
      out.remove('points');
    }
    return out;
  }

  /// Key under which the visit tables keep their device-only fields
  /// (pre-check, rejection, local photo path, QR token) in the wire-shaped
  /// data, so a server row written over the local one keeps them.
  static const String localKey = '_local';

  /// Server rows (applied / conflict echo, pull) carry no [localKey]; keep
  /// the existing row's device-only fields in that case.
  Future<Map<String, Object?>> _keepLocal(
    String entity,
    String id,
    Map<String, Object?> data,
  ) async {
    if (data.containsKey(localKey)) return data;
    final existing = await read(entity, id);
    final local = existing?.data[localKey];
    if (local == null) return data;
    return <String, Object?>{...data, localKey: local};
  }

  /// Records a server rejection on the row (visits keep the code and the
  /// problem fields so A31 / A34 can explain, e.g. `outside_geofence` with
  /// the distance); other entities are untouched (the outbox row has it).
  Future<void> markRejected(
    String entity,
    String id,
    SyncError error, {
    required DateTime now,
  }) async {
    if (entity != SyncEntities.visit && entity != SyncEntities.diagnosis) {
      return;
    }
    final existing = await read(entity, id);
    if (existing == null) return;
    final local = Map<String, Object?>.from(
      (existing.data[localKey] as Map?) ?? const <String, Object?>{},
    );
    local['failure'] = <String, Object?>{
      'code': error.code,
      'detail': error.detail,
      'distance_m': error.distanceM,
      'target': error.target,
      'radius_m': error.radiusM,
    };
    await write(
      entity,
      id,
      <String, Object?>{...existing.data, localKey: local},
      version: existing.version,
      dirty: existing.dirty,
      deleted: existing.deleted,
      now: now,
    );
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
      case SyncEntities.dutySession:
        await (db.delete(db.dutySessions)..where((t) => t.id.equals(id))).go();
      case SyncEntities.visit:
        await (db.delete(db.visits)..where((t) => t.id.equals(id))).go();
      case SyncEntities.visitPhoto:
        await (db.delete(db.visitPhotos)..where((t) => t.id.equals(id))).go();
      case SyncEntities.visitConfirmation:
        await (db.delete(
          db.visitConfirmations,
        )..where((t) => t.id.equals(id))).go();
      case SyncEntities.order:
        await OrderCodec.delete(db, id);
      case SyncEntities.payment:
        await PaymentCodec.delete(db, id);
      default:
        if (!isKnown(entity)) {
          throw ArgumentError.value(entity, 'entity', 'no local table');
        }
        await (db.delete(
          db.syncDocs,
        )..where((t) => t.entity.equals(entity) & t.docId.equals(id))).go();
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
    if (entity == SyncEntities.orderLine) {
      await OrderCodec.writeLine(db, id, data);
      return;
    }
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
    if (entity == SyncEntities.orderLine) {
      return (db.delete(db.orderLines)..where((t) => t.id.equals(id))).go();
    }
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
    final meeting = _pointOf(d['meeting_point']);
    return Village(
      id: id,
      name: (d['name'] as String?) ?? '',
      district: (d['district'] as String?) ?? '',
      mandal: (d['mandal'] as String?) ?? '',
      state: (d['state'] as String?) ?? '',
      storeId: d['store_id'] as String?,
      latitude: _num(d['lat'] ?? d['latitude'] ?? loc?['lat']),
      longitude: _num(d['lon'] ?? d['longitude'] ?? loc?['lon']),
      meetingPointLat: _num(d['meeting_point_lat'] ?? meeting?['lat']),
      meetingPointLon: _num(d['meeting_point_lon'] ?? meeting?['lon']),
      meetingPointRadiusM: _num(d['meeting_point_radius_m']),
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
    'meeting_point': r.meetingPointLat == null
        ? null
        : <String, Object?>{'lat': r.meetingPointLat, 'lon': r.meetingPointLon},
    'meeting_point_radius_m': r.meetingPointRadiusM,
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

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toUtc() : null;

  static Map<String, Object?>? _pointOf(Object? v) =>
      v is Map ? Map<String, Object?>.from(v) : null;

  /// Keys of the wire shape that have typed columns; everything else goes
  /// to `extra` so server fields (km, stops, points) survive a round trip.
  static const Set<String> _dutySessionKeys = <String>{
    'id',
    'start_at',
    'end_at',
    'end_reason',
    'start_point',
    'end_point',
    'policy_version',
    'device_id',
    'app_version',
    'integrity',
    'distance_m',
    'auto_ended',
    'version',
  };

  /// Duty session row from wire data.
  static DutySession dutySessionFromData(
    String id,
    Map<String, Object?> d, {
    required int version,
    required bool dirty,
    required bool deleted,
    required DateTime now,
  }) {
    final start = _pointOf(d['start_point']);
    final end = _pointOf(d['end_point']);
    final extra = <String, Object?>{
      for (final e in d.entries)
        if (!_dutySessionKeys.contains(e.key)) e.key: e.value,
    };
    return DutySession(
      id: id,
      startAt: _time(d['start_at']) ?? now,
      endAt: _time(d['end_at']),
      endReason: d['end_reason'] as String?,
      startLat: _num(start?['lat']),
      startLon: _num(start?['lon']),
      startAccuracyM: _num(start?['accuracy_m']),
      endLat: _num(end?['lat']),
      endLon: _num(end?['lon']),
      endAccuracyM: _num(end?['accuracy_m']),
      policyVersion: d['policy_version'] as String?,
      deviceId: d['device_id'] as String?,
      appVersion: d['app_version'] as String?,
      integrity: jsonEncode(d['integrity'] ?? const <String, Object?>{}),
      distanceM: _num(d['distance_m']) ?? 0,
      autoEnded: d['auto_ended'] == true,
      extra: jsonEncode(extra),
      version: version,
      updatedAt: now,
      dirty: dirty,
      deleted: deleted,
    );
  }

  /// Wire data from a duty session row.
  static Map<String, Object?> dutySessionToData(DutySession r) =>
      <String, Object?>{
        ...Map<String, Object?>.from(jsonDecode(r.extra) as Map),
        'id': r.id,
        'start_at': r.startAt.toUtc().toIso8601String(),
        'end_at': r.endAt?.toUtc().toIso8601String(),
        'end_reason': r.endReason,
        'start_point': r.startLat == null
            ? null
            : <String, Object?>{
                'lat': r.startLat,
                'lon': r.startLon,
                'accuracy_m': r.startAccuracyM,
              },
        'end_point': r.endLat == null
            ? null
            : <String, Object?>{
                'lat': r.endLat,
                'lon': r.endLon,
                'accuracy_m': r.endAccuracyM,
              },
        'policy_version': r.policyVersion,
        'device_id': r.deviceId,
        'app_version': r.appVersion,
        'integrity': jsonDecode(r.integrity),
        'distance_m': r.distanceM,
        'auto_ended': r.autoEnded,
        'version': r.version,
      };

  static List<Object?> _list(Object? v) =>
      v is List ? List<Object?>.from(v) : const <Object?>[];

  static Map<String, Object?> _map(Object? v) =>
      v is Map ? Map<String, Object?>.from(v) : const <String, Object?>{};

  /// Keys of the visit wire shape with typed columns; the rest goes to
  /// `extra` (photos / confirmations embedded in a detail echo are dropped:
  /// they have their own tables and feed rows).
  static const Set<String> _visitKeys = <String>{
    'id',
    'farmer_id',
    'farm_id',
    'village_id',
    'purpose',
    'checkin_at',
    'checkin_point',
    'checkin_accuracy_m',
    'checkout_at',
    'checkout_point',
    'geofence_result',
    'override_note',
    'override_approved_by',
    'notes',
    'crop_stage',
    'duration_s',
    'score',
    'status',
    'confirmation_channel',
    'confirmed_at',
    'device_integrity',
    'integrity_issues',
    'flags',
    'score_components',
    'client_visit_id',
    'officer_id',
    'version',
    'photos',
    'confirmations',
    'override_request',
    localKey,
  };

  /// Visit row from wire data (create payload, detail echo or feed row).
  static Visit visitFromData(
    String id,
    Map<String, Object?> d, {
    required int version,
    required bool dirty,
    required bool deleted,
    required DateTime now,
  }) {
    final checkin = _pointOf(d['checkin_point']);
    final checkout = _pointOf(d['checkout_point']);
    final local = _map(d[localKey]);
    final precheck = _map(local['precheck']);
    final failure = local['failure'];
    final extra = <String, Object?>{
      for (final e in d.entries)
        if (!_visitKeys.contains(e.key)) e.key: e.value,
    };
    final components = d['score_components'];
    return Visit(
      id: id,
      farmerId: (d['farmer_id'] as String?) ?? '',
      farmId: d['farm_id'] as String?,
      villageId: d['village_id'] as String?,
      purpose: (d['purpose'] as String?) ?? 'advisory',
      checkinAt: _time(d['checkin_at']) ?? now,
      checkinLat: _num(checkin?['lat']) ?? 0,
      checkinLon: _num(checkin?['lon']) ?? 0,
      checkinAccuracyM: _num(d['checkin_accuracy_m'] ?? checkin?['accuracy_m']),
      checkoutAt: _time(d['checkout_at']),
      checkoutLat: _num(checkout?['lat']),
      checkoutLon: _num(checkout?['lon']),
      geofenceResult: d['geofence_result'] as String?,
      precheckResult: precheck['result'] as String?,
      precheckDistanceM: _num(precheck['distance_m']),
      precheckTarget: precheck['target'] as String?,
      precheckRadiusM: _num(precheck['radius_m']),
      overrideNote: d['override_note'] as String?,
      overrideApprovedBy: d['override_approved_by'] as String?,
      notes: d['notes'] as String?,
      cropStage: d['crop_stage'] as String?,
      durationS: (d['duration_s'] as num?)?.toInt(),
      score: (d['score'] as num?)?.toInt(),
      status: (d['status'] as String?) ?? 'open',
      confirmationChannel: (d['confirmation_channel'] as String?) ?? 'none',
      confirmedAt: _time(d['confirmed_at']),
      deviceIntegrity: jsonEncode(_map(d['device_integrity'])),
      integrityIssues: jsonEncode(_list(d['integrity_issues'])),
      flags: jsonEncode(_list(d['flags'])),
      scoreComponents: components is Map ? jsonEncode(components) : null,
      clientVisitId: d['client_visit_id'] as String?,
      officerId: d['officer_id'] as String?,
      failureCode: failure is Map ? failure['code'] as String? : null,
      failureDetail: failure is Map ? jsonEncode(failure) : null,
      extra: jsonEncode(extra),
      version: version,
      updatedAt: now,
      dirty: dirty,
      deleted: deleted,
    );
  }

  /// Wire data from a visit row (device-only fields under [localKey]).
  static Map<String, Object?> visitToData(Visit r) => <String, Object?>{
    ...Map<String, Object?>.from(jsonDecode(r.extra) as Map),
    'id': r.id,
    'farmer_id': r.farmerId,
    'farm_id': r.farmId,
    'village_id': r.villageId,
    'purpose': r.purpose,
    'checkin_at': r.checkinAt.toUtc().toIso8601String(),
    'checkin_point': <String, Object?>{
      'lat': r.checkinLat,
      'lon': r.checkinLon,
      'accuracy_m': r.checkinAccuracyM,
    },
    'checkin_accuracy_m': r.checkinAccuracyM,
    'checkout_at': r.checkoutAt?.toUtc().toIso8601String(),
    'checkout_point': r.checkoutLat == null
        ? null
        : <String, Object?>{'lat': r.checkoutLat, 'lon': r.checkoutLon},
    'geofence_result': r.geofenceResult,
    'override_note': r.overrideNote,
    'override_approved_by': r.overrideApprovedBy,
    'notes': r.notes,
    'crop_stage': r.cropStage,
    'duration_s': r.durationS,
    'score': r.score,
    'status': r.status,
    'confirmation_channel': r.confirmationChannel,
    'confirmed_at': r.confirmedAt?.toUtc().toIso8601String(),
    'device_integrity': jsonDecode(r.deviceIntegrity),
    'integrity_issues': jsonDecode(r.integrityIssues),
    'flags': jsonDecode(r.flags),
    'score_components': r.scoreComponents == null
        ? null
        : jsonDecode(r.scoreComponents!),
    'client_visit_id': r.clientVisitId,
    'officer_id': r.officerId,
    'version': r.version,
    localKey: <String, Object?>{
      'precheck': r.precheckResult == null
          ? null
          : <String, Object?>{
              'result': r.precheckResult,
              'distance_m': r.precheckDistanceM,
              'target': r.precheckTarget,
              'radius_m': r.precheckRadiusM,
            },
      'failure': r.failureDetail == null ? null : jsonDecode(r.failureDetail!),
    },
  };

  static const Set<String> _visitPhotoKeys = <String>{
    'id',
    'visit_id',
    'blob_uri',
    'sha256',
    'phash',
    'exif_time',
    'exif_point',
    'taken_in_app',
    'device_time',
    'server_time',
    'photo_flags',
    'version',
    'signed_url',
    'signed_url_expires_at',
    localKey,
  };

  /// Visit photo row from wire data.
  static VisitPhoto visitPhotoFromData(
    String id,
    Map<String, Object?> d, {
    required int version,
    required bool dirty,
    required bool deleted,
    required DateTime now,
  }) {
    final exif = _pointOf(d['exif_point']);
    final local = _map(d[localKey]);
    final extra = <String, Object?>{
      for (final e in d.entries)
        if (!_visitPhotoKeys.contains(e.key)) e.key: e.value,
    };
    return VisitPhoto(
      id: id,
      visitId: (d['visit_id'] as String?) ?? '',
      blobUri: (d['blob_uri'] as String?) ?? '',
      sha256: d['sha256'] as String?,
      phash: d['phash'] as String?,
      exifTime: _time(d['exif_time']),
      exifLat: _num(exif?['lat']),
      exifLon: _num(exif?['lon']),
      takenInApp: d['taken_in_app'] != false,
      deviceTime: _time(d['device_time']),
      serverTime: _time(d['server_time']),
      photoFlags: jsonEncode(_list(d['photo_flags'])),
      localPath: local['path'] as String?,
      extra: jsonEncode(extra),
      version: version,
      updatedAt: now,
      dirty: dirty,
      deleted: deleted,
    );
  }

  /// Wire data from a visit photo row.
  static Map<String, Object?> visitPhotoToData(VisitPhoto r) =>
      <String, Object?>{
        ...Map<String, Object?>.from(jsonDecode(r.extra) as Map),
        'id': r.id,
        'visit_id': r.visitId,
        'blob_uri': r.blobUri,
        'sha256': r.sha256,
        'phash': r.phash,
        'exif_time': r.exifTime?.toUtc().toIso8601String(),
        'exif_point': r.exifLat == null
            ? null
            : <String, Object?>{'lat': r.exifLat, 'lon': r.exifLon},
        'taken_in_app': r.takenInApp,
        'device_time': r.deviceTime?.toUtc().toIso8601String(),
        'server_time': r.serverTime?.toUtc().toIso8601String(),
        'photo_flags': jsonDecode(r.photoFlags),
        'version': r.version,
        localKey: <String, Object?>{'path': r.localPath},
      };

  static const Set<String> _visitConfirmationKeys = <String>{
    'id',
    'visit_id',
    'channel',
    'status',
    'requested_at',
    'expires_at',
    'confirmed_at',
    'farmer_phone_last4',
    'rating',
    'version',
    'code',
    'token',
    localKey,
  };

  /// Visit confirmation row from wire data.
  static VisitConfirmation visitConfirmationFromData(
    String id,
    Map<String, Object?> d, {
    required int version,
    required bool dirty,
    required bool deleted,
    required DateTime now,
  }) {
    final local = _map(d[localKey]);
    final extra = <String, Object?>{
      for (final e in d.entries)
        if (!_visitConfirmationKeys.contains(e.key)) e.key: e.value,
    };
    return VisitConfirmation(
      id: id,
      visitId: (d['visit_id'] as String?) ?? '',
      channel: (d['channel'] as String?) ?? 'sms_otp',
      status: (d['status'] as String?) ?? 'pending',
      requestedAt: _time(d['requested_at']),
      expiresAt: _time(d['expires_at']),
      confirmedAt: _time(d['confirmed_at']),
      farmerPhoneLast4: d['farmer_phone_last4'] as String?,
      rating: (d['rating'] as num?)?.toInt(),
      token: local['token'] as String?,
      extra: jsonEncode(extra),
      version: version,
      updatedAt: now,
      dirty: dirty,
      deleted: deleted,
    );
  }

  /// Wire data from a visit confirmation row (the QR token stays local).
  static Map<String, Object?> visitConfirmationToData(VisitConfirmation r) =>
      <String, Object?>{
        ...Map<String, Object?>.from(jsonDecode(r.extra) as Map),
        'id': r.id,
        'visit_id': r.visitId,
        'channel': r.channel,
        'status': r.status,
        'requested_at': r.requestedAt?.toUtc().toIso8601String(),
        'expires_at': r.expiresAt?.toUtc().toIso8601String(),
        'confirmed_at': r.confirmedAt?.toUtc().toIso8601String(),
        'farmer_phone_last4': r.farmerPhoneLast4,
        'rating': r.rating,
        'version': r.version,
        localKey: <String, Object?>{'token': r.token},
      };
}
