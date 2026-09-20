import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../catalog/rest_json_client.dart';
import '../db/app_database.dart';
import '../farmers/farm_options.dart' show Seasons;
import '../orders/order_models.dart' show CartLine, Fulfilment;
import '../sync/outbox.dart';
import '../sync/sync_models.dart';
import 'kisan_api.dart';
import 'kisan_cache.dart';
import 'kisan_models.dart';

/// Result of [KisanRepository.placeOrder].
typedef PlaceOrderResult = ({
  KisanWrite write,
  KisanOrder? order,
  String? code,
});

/// The farmer app's data (FM-001 .. FM-015): online first, cached for
/// offline viewing (NF-002), consent and visit confirmations queued in the
/// outbox when offline.
class KisanRepository {
  /// Creates the repository.
  KisanRepository({
    required this.db,
    required this.api,
    required this.outbox,
    required DateTime Function() clock,
    required String Function() ids,
    this.onQueued,
  }) : cache = KisanCache(db, clock: clock),
       _now = clock,
       _newId = ids;

  /// The database.
  final AppDatabase db;

  /// REST calls.
  final KisanApi api;

  /// Offline writes.
  final Outbox outbox;

  /// JSON snapshots with "as of".
  final KisanCache cache;

  /// Called after an op was queued (the app flushes the outbox when
  /// online).
  final void Function()? onQueued;

  final DateTime Function() _now;
  final String Function() _newId;

  /// `kv` key of the farmer id behind the login.
  static const String farmerIdKey = 'kisan.farmer_id';

  /// `kv` key set once F05 was confirmed or skipped.
  static const String welcomeDoneKey = 'kisan.welcome_done';

  /// `kv` key of the notifications preference (F70).
  static const String notificationsKey = 'kisan.notifications';

  /// Cache keys.
  static const String profileKey = 'profile';

  /// Orders list cache key.
  static const String ordersKey = 'orders';

  /// Deletion request cache key.
  static const String deletionKey = 'deletion';

  /// Visit prompts cache key.
  static const String promptsKey = 'visit_prompts';

  /// Answered / dismissed prompts cache key.
  static const String promptsDoneKey = 'visit_prompts_done';

  static String _orderKey(String id) => 'order.$id';

  // --- identity -------------------------------------------------------------

  /// The farmer record behind the login (remembered; asked once online).
  Future<String?> farmerId() async {
    final stored = await db.getValue(farmerIdKey);
    if (stored != null) return stored;
    final r = await api.ownFarmer();
    if (!r.ok) return null;
    final items = r.body['items'];
    if (items is! List || items.isEmpty || items.first is! Map) return null;
    final id = '${(items.first as Map)['id']}';
    await db.setValue(farmerIdKey, id);
    return id;
  }

  /// After login: the farmer id, profile, orders and deletion request.
  /// Returns the profile (cached when offline).
  Future<FarmerProfile?> bootstrap() async {
    final id = await farmerId();
    if (id == null) return (await _profile())?.value;
    await refreshProfile();
    unawaited(refreshOrders());
    unawaited(refreshDeletion());
    return (await _profile())?.value;
  }

  // --- profile (FM-003) -----------------------------------------------------

  /// Fetches the profile; false when offline (the cache stays).
  Future<bool> refreshProfile() async {
    final id = await farmerId();
    if (id == null) return false;
    final r = await api.farmer(id);
    if (!r.ok) return false;
    await cache.put(profileKey, r.body);
    return true;
  }

  Future<Cached<FarmerProfile>?> _profile() async =>
      _profileOf(await cache.get(profileKey));

  Cached<FarmerProfile>? _profileOf(Snapshot? s) {
    final data = s?.data;
    if (s == null || data is! Map) return null;
    return Cached<FarmerProfile>(
      FarmerProfile.fromJson(Map<String, Object?>.from(data)),
      s.fetchedAt,
    );
  }

  /// The cached profile, live.
  Stream<Cached<FarmerProfile>?> watchProfile() =>
      cache.watch(profileKey).map(_profileOf).distinct();

  /// F05 was confirmed (or skipped).
  Future<bool> welcomeDone() async =>
      (await db.getValue(welcomeDoneKey)) == 'true';

  /// Marks F05 done.
  Future<void> markWelcomeDone() => db.setValue(welcomeDoneKey, 'true');

  Future<KisanWrite> _patched(RestResponse r) async {
    if (r.ok) {
      await refreshProfile();
      return KisanWrite.done;
    }
    if (r.isNetworkFailure) return KisanWrite.offline;
    if (r.code == 'version_conflict') await refreshProfile();
    return KisanWrite.refused;
  }

  /// F05 / F40: the crop stage of [plot] (tap-only tiles).
  Future<KisanWrite> setPlotStage(KisanCropPlot plot, String stage) async =>
      _patched(
        await api.updateCropPlot(plot.id, <String, Object?>{
          'version': plot.version,
          'stage': stage,
        }),
      );

  /// F05: irrigation and / or soil of [farm] (icon tiles).
  Future<KisanWrite> setFarmDetails(
    KisanFarm farm, {
    String? irrigation,
    String? soil,
  }) async => _patched(
    await api.updateFarm(farm.id, <String, Object?>{
      'version': farm.version,
      'irrigation': ?irrigation,
      'soil': ?soil,
    }),
  );

  /// F05 quick setup for a farmer nobody registered: village from the
  /// list, one farm with one crop (size and sowing time from tiles).
  Future<KisanWrite> quickSetup({
    required String cropId,
    required double areaAcres,
    required DateTime sowingDate,
    String? villageId,
  }) async {
    final profile = (await _profile())?.value;
    final id = profile?.id ?? await farmerId();
    if (id == null) return KisanWrite.offline;
    if (villageId != null && villageId != profile?.villageId) {
      final r = await api.updateFarmer(id, <String, Object?>{
        'version': ?profile?.version,
        'village_id': villageId,
      });
      if (r.isNetworkFailure) return KisanWrite.offline;
      if (!r.ok) return KisanWrite.refused;
    }
    final day = sowingDate.toUtc();
    final iso =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final r = await api.createFarm(id, <String, Object?>{
      'id': _newId(),
      'area_acres': areaAcres,
      'crop_plots': <Object?>[
        <String, Object?>{
          'id': _newId(),
          'crop_id': cropId,
          'season': Seasons.forDate(day),
          'sowing_date': iso,
          'area_acres': areaAcres,
        },
      ],
    });
    if (r.isNetworkFailure) return KisanWrite.offline;
    if (!r.ok) return KisanWrite.refused;
    await refreshProfile();
    return KisanWrite.done;
  }

  /// F41: adds a crop plot to [farmId] from the tile answers (crop,
  /// sowing date, and the farm's water and soil when the farmer changed
  /// them). The server regenerates the crop calendar for the new plot.
  Future<KisanWrite> addCrop({
    required String farmId,
    required String cropId,
    required DateTime sowingDate,
    String? irrigation,
    String? soil,
    double? areaAcres,
  }) async {
    final profile = (await _profile())?.value;
    final farm = profile?.farms.where((f) => f.id == farmId).firstOrNull;
    if (farm != null && (irrigation != null || soil != null)) {
      final changed = <String, Object?>{
        if (irrigation != null && irrigation != farm.irrigation)
          'irrigation': irrigation,
        if (soil != null && soil != farm.soil) 'soil': soil,
      };
      if (changed.isNotEmpty) {
        final r = await api.updateFarm(farm.id, <String, Object?>{
          'version': farm.version,
          ...changed,
        });
        if (r.isNetworkFailure) return KisanWrite.offline;
      }
    }
    final day = sowingDate.toUtc();
    final iso =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final r = await api.createCropPlot(farmId, <String, Object?>{
      'id': _newId(),
      'crop_id': cropId,
      'season': Seasons.forDate(day),
      'sowing_date': iso,
      'area_acres': ?areaAcres,
    });
    if (r.isNetworkFailure) return KisanWrite.offline;
    if (!r.ok) return KisanWrite.refused;
    await refreshProfile();
    return KisanWrite.done;
  }

  // --- consent (FM-002) -----------------------------------------------------

  /// Records a grant or withdrawal: online `POST /consents`
  /// (`channel: app`, the tenant's version), else a queued
  /// `consent_record` create. A withdrawal is a new row with
  /// `granted: false`.
  Future<KisanWrite> recordConsent(
    String purpose, {
    required bool granted,
    String? language,
  }) async {
    final id = await farmerId();
    if (id == null) return KisanWrite.offline;
    final r = await api.recordConsent(
      id,
      purpose: purpose,
      granted: granted,
      language: language,
    );
    if (r.ok) {
      final snap = await cache.get(profileKey);
      final data = snap?.data;
      if (data is Map) {
        final profile = Map<String, Object?>.from(data);
        profile['consents'] = <Object?>[
          ...(profile['consents'] as List?) ?? const <Object?>[],
          r.body,
        ];
        await cache.put(profileKey, profile, fetchedAt: snap!.fetchedAt);
      }
      return KisanWrite.done;
    }
    if (!r.isNetworkFailure) return KisanWrite.refused;
    await outbox.enqueueCreate(
      SyncEntities.consentRecord,
      _newId(),
      <String, Object?>{
        'farmer_id': id,
        'purpose': purpose,
        'granted': granted,
        'language': ?language,
      },
    );
    onQueued?.call();
    return KisanWrite.queued;
  }

  Future<ConsentState> _consents(Snapshot? snap) async {
    final profile = _profileOf(snap)?.value;
    final entries = <String, ConsentEntry>{
      for (final c in profile?.consents ?? const <ConsentEntry>[]) c.id: c,
    };
    final local = await db.select(db.consentRecords).get();
    for (final r in local) {
      if (profile != null && r.farmerId != profile.id) continue;
      if (!r.dirty && entries.containsKey(r.id)) continue;
      entries[r.id] = ConsentEntry(
        id: r.id,
        purpose: r.purpose,
        granted: r.granted,
        at: r.updatedAt.toUtc(),
        version: r.consentVersion,
        channel: r.channel,
        pending: r.dirty,
      );
    }
    return ConsentState.of(entries.values);
  }

  /// Latest consent per purpose (cached rows + queued ones), live.
  Stream<ConsentState> watchConsents() => watchTables(
    db,
    <TableInfo<Table, Object?>>[db.kv, db.consentRecords],
    () async => _consents(await cache.get(profileKey)),
  );

  // --- orders (FM-010) ------------------------------------------------------

  List<KisanOrder> _ordersOf(Object? data) => <KisanOrder>[
    for (final o in (data is List ? data : const <Object?>[]))
      if (o is Map) KisanOrder.fromJson(Map<String, Object?>.from(o)),
  ];

  /// Fetches the order list; false when offline.
  Future<bool> refreshOrders() async {
    final r = await api.orders();
    if (!r.ok) return false;
    await cache.put(ordersKey, r.body['items'] ?? const <Object?>[]);
    return true;
  }

  /// F34 orders (cached), live.
  Stream<Cached<List<KisanOrder>>?> watchOrders() => cache
      .watch(ordersKey)
      .map(
        (s) => s == null
            ? null
            : Cached<List<KisanOrder>>(_ordersOf(s.data), s.fetchedAt),
      );

  /// Fetches one order (keeps line names placed from this phone).
  Future<bool> refreshOrder(String id) async {
    final r = await api.order(id);
    if (!r.ok) return false;
    await _putOrder(r.body);
    return true;
  }

  Future<void> _putOrder(
    Map<String, Object?> body, {
    List<CartLine>? cart,
  }) async {
    final id = '${body['id']}';
    final previous = (await cache.get(_orderKey(id)))?.data;
    final names = <String, (String, String)>{
      for (final l in cart ?? const <CartLine>[])
        l.item.skuId: (l.item.name, l.item.packLabel),
      if (previous is Map)
        for (final l in (previous['lines'] as List?) ?? const <Object?>[])
          if (l is Map && l['product_name'] is String)
            '${l['sku_id']}': (
              l['product_name']! as String,
              (l['pack_label'] as String?) ?? '',
            ),
    };
    final merged = <String, Object?>{
      ...body,
      'lines': <Object?>[
        for (final l in (body['lines'] as List?) ?? const <Object?>[])
          if (l is Map)
            <String, Object?>{
              ...Map<String, Object?>.from(l),
              if (names['${l['sku_id']}'] case (final n, final p)) ...{
                'product_name': n,
                'pack_label': p,
              },
            },
      ],
    };
    await cache.put(_orderKey(id), merged);
  }

  /// F33 order (cached), live.
  Stream<Cached<KisanOrder>?> watchOrder(String id) =>
      cache.watch(_orderKey(id)).map((s) {
        final data = s?.data;
        if (s == null || data is! Map) return null;
        return Cached<KisanOrder>(
          KisanOrder.fromJson(Map<String, Object?>.from(data)),
          s.fetchedAt,
        );
      });

  /// F32: places the order online. [paymentMode] `credit` asks the store
  /// for credit (402 `credit_limit_exceeded` = the store will confirm);
  /// null = pay at the store; `upi_qr` = UPI right after.
  Future<PlaceOrderResult> placeOrder({
    required String? storeId,
    required Fulfilment fulfilment,
    required List<CartLine> lines,
    String? paymentMode,
  }) async {
    final r = await api.placeOrder(<String, Object?>{
      'id': _newId(),
      'store_id': ?storeId,
      'fulfilment': fulfilment.name,
      'payment_mode': paymentMode == 'upi_qr' ? null : paymentMode,
      'lines': <Object?>[
        for (final l in lines)
          <String, Object?>{
            'sku_id': l.item.skuId,
            'qty': l.qty,
            'label_claim_id': ?l.labelClaimId,
          },
      ],
    });
    if (r.isNetworkFailure) {
      return (write: KisanWrite.offline, order: null, code: null);
    }
    if (!r.ok) return (write: KisanWrite.refused, order: null, code: r.code);
    await _putOrder(r.body, cart: lines);
    unawaited(refreshOrders());
    return (
      write: KisanWrite.done,
      order: KisanOrder.fromJson(r.body),
      code: null,
    );
  }

  // --- deletion request (FM-015) --------------------------------------------

  DeletionRequest? _deletionOf(Snapshot? s) {
    final data = s?.data;
    return data is Map
        ? DeletionRequest.fromJson(Map<String, Object?>.from(data))
        : null;
  }

  /// `POST /v1/me/deletion-request`.
  Future<KisanWrite> requestDeletion({String? reason}) async {
    final r = await api.requestDeletion(reason: reason);
    if (r.isNetworkFailure) return KisanWrite.offline;
    if (!r.ok) return KisanWrite.refused;
    await cache.put(deletionKey, r.body);
    return KisanWrite.done;
  }

  /// `GET /v1/me/deletion-request`; false when offline.
  Future<bool> refreshDeletion() async {
    final r = await api.deletionRequest();
    if (r.status == 404) {
      await cache.remove(deletionKey);
      return true;
    }
    if (!r.ok) return false;
    await cache.put(deletionKey, r.body);
    return true;
  }

  /// The deletion ticket, live.
  Stream<DeletionRequest?> watchDeletion() =>
      cache.watch(deletionKey).map(_deletionOf).distinct();

  // --- visit confirmation (FM-011) ------------------------------------------

  /// FA-007 push handler entry point: `{type: visit_confirm, visit_id,
  /// token, officer_name, expires_at}` becomes an F60 prompt.
  Future<void> receivePush(Map<String, Object?> data) async {
    if (data['type'] != 'visit_confirm' || data['visit_id'] == null) return;
    final prompt = VisitPrompt.fromJson(data);
    final stored = await _storedPrompts();
    await cache.put(promptsKey, <Object?>[
      for (final p in stored)
        if (p.visitId != prompt.visitId) p.toJson(),
      prompt.toJson(),
    ]);
  }

  Future<List<VisitPrompt>> _storedPrompts() async {
    final data = (await cache.get(promptsKey))?.data;
    return <VisitPrompt>[
      for (final p in (data is List ? data : const <Object?>[]))
        if (p is Map) VisitPrompt.fromJson(Map<String, Object?>.from(p)),
    ];
  }

  Future<Set<String>> _answered() async {
    final data = (await cache.get(promptsDoneKey))?.data;
    return <String>{
      for (final v in (data is List ? data : const <Object?>[])) '$v',
    };
  }

  /// Pending prompts: push payloads plus `app_push` confirmations from the
  /// sync feed (pending, not expired, not answered here), newest first.
  Future<List<VisitPrompt>> prompts() async {
    final now = _now();
    final answered = await _answered();
    final out = <String, VisitPrompt>{};
    final synced =
        await (db.select(db.visitConfirmations)..where(
              (t) =>
                  t.channel.equals('app_push') &
                  t.status.equals('pending') &
                  t.confirmedAt.isNull(),
            ))
            .get();
    for (final c in synced) {
      out[c.visitId] = VisitPrompt(
        visitId: c.visitId,
        token: c.token,
        expiresAt: c.expiresAt?.toUtc(),
      );
    }
    for (final p in await _storedPrompts()) {
      final synced = out[p.visitId];
      out[p.visitId] = VisitPrompt(
        visitId: p.visitId,
        token: p.token ?? synced?.token,
        officerName: p.officerName,
        expiresAt: p.expiresAt ?? synced?.expiresAt,
        channel: p.channel,
      );
    }
    return <VisitPrompt>[
      for (final p in out.values)
        if (!answered.contains(p.visitId) &&
            (p.expiresAt == null || p.expiresAt!.isAfter(now)))
          p,
    ];
  }

  /// [prompts], live.
  Stream<List<VisitPrompt>> watchPrompts() => watchTables(
    db,
    <TableInfo<Table, Object?>>[db.kv, db.visitConfirmations],
    prompts,
  );

  /// Hides the prompt for [visitId] ("No" or answered).
  Future<void> dismissPrompt(String visitId) async {
    final done = await _answered()
      ..add(visitId);
    await cache.put(promptsDoneKey, done.toList());
  }

  /// F61: confirms the visit with the token (push or QR) and the optional
  /// rating 1–5 + reason, online; offline the `visit_confirmation` create
  /// is queued (the server validates the token on arrival).
  Future<KisanWrite> confirmVisit({
    required String visitId,
    required String token,
    String channel = 'app_push',
    int? rating,
    String? reason,
  }) async {
    final r = await api.farmerConfirm(
      visitId,
      token: token,
      rating: rating,
      reason: reason,
    );
    if (r.ok || r.code == 'visit_already_confirmed') {
      await dismissPrompt(visitId);
      return KisanWrite.done;
    }
    if (!r.isNetworkFailure) return KisanWrite.refused;
    await outbox.enqueueCreate(
      SyncEntities.visitConfirmation,
      _newId(),
      <String, Object?>{
        'visit_id': visitId,
        'channel': channel,
        'token': token,
        'rating': ?rating,
        'reason': ?reason,
      },
    );
    await dismissPrompt(visitId);
    onQueued?.call();
    return KisanWrite.queued;
  }

  // --- settings -------------------------------------------------------------

  /// F70 notifications preference (default on).
  Future<bool> notificationsOn() async =>
      (await db.getValue(notificationsKey)) != 'false';

  /// Sets the notifications preference.
  Future<void> setNotifications(bool on) =>
      db.setValue(notificationsKey, jsonEncode(on));
}
