import 'dart:convert';

import 'package:async/async.dart' show StreamGroup;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../db/app_database.dart';
import '../geo/geo.dart';
import '../sync/sync_models.dart';
import '../sync/sync_store.dart';
import 'farm_options.dart';

/// Server problem code when another farmer already has the phone.
const String farmerPhoneExistsCode = 'farmer_phone_exists';

/// A20 list filter: free text (name, last digits of the phone, village)
/// plus village and crop filters.
@immutable
class FarmerListFilter {
  /// Creates the filter.
  const FarmerListFilter({this.query = '', this.villageId, this.cropId});

  /// Free text.
  final String query;

  /// Village filter.
  final String? villageId;

  /// Crop filter (any farm of the farmer grows it).
  final String? cropId;

  /// Nothing set.
  bool get isEmpty =>
      query.trim().isEmpty && villageId == null && cropId == null;

  /// Copy with overrides (`clearVillage` / `clearCrop` remove the filter).
  FarmerListFilter copyWith({
    String? query,
    String? villageId,
    bool clearVillage = false,
    String? cropId,
    bool clearCrop = false,
  }) => FarmerListFilter(
    query: query ?? this.query,
    villageId: clearVillage ? null : (villageId ?? this.villageId),
    cropId: clearCrop ? null : (cropId ?? this.cropId),
  );

  @override
  bool operator ==(Object other) =>
      other is FarmerListFilter &&
      other.query == query &&
      other.villageId == villageId &&
      other.cropId == cropId;

  @override
  int get hashCode => Object.hash(query, villageId, cropId);
}

/// One A20 row.
@immutable
class FarmerSummary {
  /// Creates the summary.
  const FarmerSummary({
    required this.id,
    required this.name,
    required this.phone,
    required this.villageId,
    required this.villageName,
    required this.crops,
    required this.pendingSync,
    required this.phoneVerified,
    this.rejected = false,
  });

  /// Farmer id.
  final String id;

  /// Name.
  final String name;

  /// E.164 phone (may be empty).
  final String phone;

  /// Village id.
  final String? villageId;

  /// Village name (typed fallback or synced name).
  final String villageName;

  /// Distinct crops across the farmer's farms.
  final List<CropRef> crops;

  /// A queued op still references the farmer.
  final bool pendingSync;

  /// OTP-verified.
  final bool phoneVerified;

  /// The server rejected the farmer (see A64 / A22 banner).
  final bool rejected;

  /// Last four digits of the phone.
  String get phoneLast4 =>
      phone.length >= 4 ? phone.substring(phone.length - 4) : phone;

  @override
  bool operator ==(Object other) =>
      other is FarmerSummary &&
      other.id == id &&
      other.name == name &&
      other.phone == phone &&
      other.villageName == villageName &&
      listEquals(
        other.crops.map((c) => c.id).toList(),
        crops.map((c) => c.id).toList(),
      ) &&
      other.pendingSync == pendingSync &&
      other.phoneVerified == phoneVerified &&
      other.rejected == rejected;

  @override
  int get hashCode => Object.hash(id, name, phone, pendingSync, rejected);
}

/// A farm with its plots, for A22 / A23.
@immutable
class FarmDetail {
  /// Creates the detail.
  const FarmDetail({required this.farm, required this.plots});

  /// The farm row.
  final Farm farm;

  /// Its crop plots.
  final List<CropPlot> plots;

  /// Boundary ring decoded from the stored GeoJSON.
  List<GeoPoint> get boundary => polygonFromGeoJson(farm.boundary);
}

/// Everything A22 shows.
@immutable
class FarmerDetail {
  /// Creates the detail.
  const FarmerDetail({
    required this.farmer,
    required this.village,
    required this.farms,
    required this.consents,
    required this.rejection,
    required this.duplicateOfId,
  });

  /// The farmer row.
  final Farmer farmer;

  /// Synced village, if known.
  final Village? village;

  /// Farms with plots.
  final List<FarmDetail> farms;

  /// Consent records.
  final List<ConsentRecord> consents;

  /// Error of a rejected op on this farmer, if any.
  final SyncError? rejection;

  /// The synced farmer that already has this phone (rejected duplicate).
  final String? duplicateOfId;

  /// The server rejected the registration as a duplicate phone.
  bool get isDuplicate => rejection?.code == farmerPhoneExistsCode;

  /// A queued op still references the farmer.
  bool get pendingSync => farmer.dirty;

  /// Every plot across every farm.
  List<CropPlot> get plots => <CropPlot>[for (final f in farms) ...f.plots];
}

/// Reads farmers, farms, plots, consents and reference data from the local
/// Drift tables (works offline; FA-012 A20 / A22, FA-013).
class FarmerRepository {
  /// Creates the repository over [db].
  FarmerRepository(this.db);

  /// The database.
  final AppDatabase db;

  Stream<T> _watch<T>(Future<T> Function() load) async* {
    yield await load();
    final changes = StreamGroup.merge<Object?>(<Stream<Object?>>[
      db.tableUpdates(),
    ]);
    await for (final _ in changes) {
      yield await load();
    }
  }

  // --- reference data -----------------------------------------------------

  /// Synced villages, by name.
  Future<List<Village>> villages() =>
      (db.select(db.villages)..orderBy(<OrderingTerm Function($VillagesTable)>[
            (t) => OrderingTerm.asc(t.name),
          ]))
          .get();

  /// [villages], live.
  Stream<List<Village>> watchVillages() => _watch(villages);

  /// Crops from the `crop` feed, or the pilot fallback when none synced.
  Future<List<CropRef>> crops() async {
    final rows = await (db.select(
      db.syncedRefs,
    )..where((t) => t.entity.equals(SyncEntities.crop))).get();
    if (rows.isEmpty) return CropRef.pilotFallback;
    final crops = <CropRef>[
      for (final r in rows)
        CropRef.fromJson(
          r.refId,
          Map<String, Object?>.from(jsonDecode(r.data) as Map),
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return crops;
  }

  /// [crops] keyed by id.
  Future<Map<String, CropRef>> cropIndex() async => <String, CropRef>{
    for (final c in await crops()) c.id: c,
  };

  // --- farmers ------------------------------------------------------------

  /// A farmer (not tombstoned) with this E.164 phone, other than
  /// [excludingId]; the FA-012 local duplicate check.
  Future<Farmer?> findByPhone(String phone, {String? excludingId}) async {
    final rows = await (db.select(
      db.farmers,
    )..where((t) => t.phone.equals(phone) & t.deleted.equals(false))).get();
    for (final r in rows) {
      if (r.id != excludingId) return r;
    }
    return null;
  }

  /// A20 rows matching [filter], newest first.
  Future<List<FarmerSummary>> farmers([
    FarmerListFilter filter = const FarmerListFilter(),
  ]) async {
    final farmers =
        await (db.select(db.farmers)
              ..where((t) => t.deleted.equals(false))
              ..orderBy(<OrderingTerm Function($FarmersTable)>[
                (t) => OrderingTerm.desc(t.updatedAt),
              ]))
            .get();
    final farms = await (db.select(
      db.farms,
    )..where((t) => t.deleted.equals(false))).get();
    final plots = await (db.select(
      db.cropPlots,
    )..where((t) => t.deleted.equals(false))).get();
    final villages = <String, Village>{
      for (final v in await this.villages()) v.id: v,
    };
    final crops = await cropIndex();
    final rejectedIds = await _rejectedFarmerIds();

    final farmsByFarmer = <String, List<String>>{};
    for (final f in farms) {
      farmsByFarmer.putIfAbsent(f.farmerId, () => <String>[]).add(f.id);
    }
    final cropIdsByFarm = <String, List<String>>{};
    for (final p in plots) {
      if (p.cropId != null) {
        cropIdsByFarm.putIfAbsent(p.farmId, () => <String>[]).add(p.cropId!);
      }
    }

    final q = filter.query.trim().toLowerCase();
    final out = <FarmerSummary>[];
    for (final f in farmers) {
      final cropIds = <String>{
        for (final farmId in farmsByFarmer[f.id] ?? const <String>[])
          ...cropIdsByFarm[farmId] ?? const <String>[],
      };
      if (filter.villageId != null && f.villageId != filter.villageId) continue;
      if (filter.cropId != null && !cropIds.contains(filter.cropId)) continue;
      final villageName = villages[f.villageId]?.name ?? '';
      if (q.isNotEmpty) {
        final phone = f.phone ?? '';
        final hit =
            f.name.toLowerCase().contains(q) ||
            villageName.toLowerCase().contains(q) ||
            (RegExp(r'^\d+$').hasMatch(q) && phone.endsWith(q));
        if (!hit) continue;
      }
      out.add(
        FarmerSummary(
          id: f.id,
          name: f.name,
          phone: f.phone ?? '',
          villageId: f.villageId,
          villageName: villageName,
          crops: <CropRef>[
            for (final id in cropIds)
              crops[id] ?? CropRef(id: id, code: id, name: id),
          ],
          pendingSync: f.dirty,
          phoneVerified: f.phoneVerified,
          rejected: rejectedIds.contains(f.id),
        ),
      );
    }
    return out;
  }

  /// [farmers], live.
  Stream<List<FarmerSummary>> watchFarmers([
    FarmerListFilter filter = const FarmerListFilter(),
  ]) => _watch(() => farmers(filter));

  Future<Set<String>> _rejectedFarmerIds() async {
    final rows =
        await (db.select(db.outboxTable)..where(
              (t) =>
                  t.entity.equals(SyncEntities.farmer) &
                  t.state.equals(OutboxState.rejected.name),
            ))
            .get();
    return rows.map((r) => r.entityId).toSet();
  }

  /// A22 detail, or `null` when unknown.
  Future<FarmerDetail?> farmer(String id) async {
    final farmer = await (db.select(
      db.farmers,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (farmer == null) return null;
    final village = farmer.villageId == null
        ? null
        : await (db.select(
            db.villages,
          )..where((t) => t.id.equals(farmer.villageId!))).getSingleOrNull();
    final farms =
        await (db.select(db.farms)
              ..where((t) => t.farmerId.equals(id) & t.deleted.equals(false))
              ..orderBy(<OrderingTerm Function($FarmsTable)>[
                (t) => OrderingTerm.asc(t.updatedAt),
              ]))
            .get();
    final details = <FarmDetail>[];
    for (final farm in farms) {
      details.add(FarmDetail(farm: farm, plots: await plots(farm.id)));
    }
    final consents = await (db.select(
      db.consentRecords,
    )..where((t) => t.farmerId.equals(id))).get();
    final rejectedOp =
        await (db.select(db.outboxTable)
              ..where(
                (t) =>
                    t.entityId.equals(id) &
                    t.state.equals(OutboxState.rejected.name),
              )
              ..orderBy(<OrderingTerm Function($OutboxTableTable)>[
                (t) => OrderingTerm.asc(t.seq),
              ])
              ..limit(1))
            .getSingleOrNull();
    final rejection = rejectedOp == null ? null : SyncStore.errorOf(rejectedOp);
    String? duplicateOf;
    if (rejection?.code == farmerPhoneExistsCode && farmer.phone != null) {
      final other = await findByPhone(farmer.phone!, excludingId: id);
      duplicateOf = other?.id;
    }
    return FarmerDetail(
      farmer: farmer,
      village: village,
      farms: details,
      consents: consents,
      rejection: rejection,
      duplicateOfId: duplicateOf,
    );
  }

  /// [farmer], live.
  Stream<FarmerDetail?> watchFarmer(String id) => _watch(() => farmer(id));

  /// One farm with its plots, or `null`.
  Future<FarmDetail?> farm(String id) async {
    final farm = await (db.select(
      db.farms,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (farm == null) return null;
    return FarmDetail(farm: farm, plots: await plots(id));
  }

  /// Plots of a farm (not tombstoned), oldest first.
  Future<List<CropPlot>> plots(String farmId) =>
      (db.select(db.cropPlots)
            ..where((t) => t.farmId.equals(farmId) & t.deleted.equals(false))
            ..orderBy(<OrderingTerm Function($CropPlotsTable)>[
              (t) => OrderingTerm.asc(t.updatedAt),
            ]))
          .get();
}
