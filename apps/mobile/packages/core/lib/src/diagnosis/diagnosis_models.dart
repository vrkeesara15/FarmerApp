import 'package:flutter/foundation.dart' show immutable;

import '../widgets/confidence_band.dart';
import '../widgets/treatment_card.dart';

/// Lifecycle of a diagnosis (`DiagnosisOut.status`), plus the device-only
/// [pending] state before the `diagnosis` create op has reached the server.
enum DiagnosisStatus {
  /// On the phone only: photos and the create op wait for the network (F24
  /// / A42 "we'll check when you're online").
  pending,

  /// The server has it and is working on it.
  queued,

  /// Corpus answer with high confidence (buy allowed).
  answered,

  /// Low / medium confidence or an LLM answer: the agronomist will confirm
  /// (no buy button, SPEC 3.4).
  provisional,

  /// The agronomist confirmed the label.
  confirmed,

  /// The agronomist changed the label.
  corrected,

  /// Not a plant, unsupported crop, unreadable photo or no match (DX-010).
  outOfScope;

  /// Parses the wire value (`out_of_scope`); unknown values are [queued].
  static DiagnosisStatus parse(Object? value) => switch (value) {
    'queued' => queued,
    'answered' => answered,
    'provisional' => provisional,
    'confirmed' => confirmed,
    'corrected' => corrected,
    'out_of_scope' => outOfScope,
    null => pending,
    _ => queued,
  };

  /// Wire value.
  String get wire => switch (this) {
    outOfScope => 'out_of_scope',
    _ => name,
  };

  /// Still waiting for an answer.
  bool get isWaiting => this == pending || this == queued;

  /// Reviewed by the agronomist (F27).
  bool get isReviewed => this == confirmed || this == corrected;
}

/// The diagnosed problem (`result.problem`).
@immutable
class DiagnosisProblem {
  /// Creates the problem.
  const DiagnosisProblem({
    required this.id,
    required this.code,
    required this.type,
    this.names = const <String, String>{},
    this.symptoms = const <String, List<String>>{},
  });

  /// Parses the wire shape.
  factory DiagnosisProblem.fromJson(Map<String, Object?> j) => DiagnosisProblem(
    id: '${j['id'] ?? ''}',
    code: (j['code'] as String?) ?? '',
    type: (j['type'] as String?) ?? 'disease',
    names: _stringMap(j['names']),
    symptoms: _listMap(j['symptoms']),
  );

  /// Corpus problem id.
  final String id;

  /// Stable code (`paddy_blast`).
  final String code;

  /// `disease`, `pest`, `nutrient` or `abiotic`.
  final String type;

  /// Name per language.
  final Map<String, String> names;

  /// Symptom checklist per language.
  final Map<String, List<String>> symptoms;

  /// Name in [lang], falling back to English, then the code.
  String nameIn(String lang) => names[lang] ?? names['en'] ?? code;

  /// Symptoms in [lang], falling back to English.
  List<String> symptomsIn(String lang) =>
      symptoms[lang] ?? symptoms['en'] ?? const <String>[];
}

/// One ranked, label-claim-backed product (`ProductOption`, DX-007/8/9).
@immutable
class ProductOption {
  /// Creates the option.
  const ProductOption({
    required this.rank,
    required this.kind,
    required this.skuId,
    required this.productId,
    required this.productName,
    required this.labelClaimId,
    required this.pricePaise,
    this.brand = '',
    this.ownBrand = false,
    this.packLabel = '',
    this.activeIngredient,
    this.efficacyTier,
    this.dosePerAcre,
    this.dosePerTank15l,
    this.phiDays,
    this.ppeText,
    this.safetyText,
    this.mrpPaise,
    this.stockQty,
    this.inStock = false,
  });

  /// Parses the wire shape.
  factory ProductOption.fromJson(Map<String, Object?> j) => ProductOption(
    rank: (j['rank'] as num?)?.toInt() ?? 0,
    kind: j['kind'] == 'organic'
        ? TreatmentKind.organic
        : TreatmentKind.chemical,
    skuId: '${j['sku_id']}',
    productId: '${j['product_id'] ?? ''}',
    productName: (j['product_name'] as String?) ?? '',
    labelClaimId: '${j['label_claim_id']}',
    pricePaise: (j['price_paise'] as num?)?.toInt() ?? 0,
    brand: (j['brand'] as String?) ?? '',
    ownBrand: j['own_brand'] == true,
    packLabel: (j['pack_label'] as String?) ?? '',
    activeIngredient: j['active_ingredient'] as String?,
    efficacyTier: (j['efficacy_tier'] as num?)?.toInt(),
    dosePerAcre: j['dose_per_acre'] as String?,
    dosePerTank15l: j['dose_per_tank_15l'] as String?,
    phiDays: (j['phi_days'] as num?)?.toInt(),
    ppeText: j['ppe_text'] as String?,
    safetyText: j['safety_text'] as String?,
    mrpPaise: (j['mrp_paise'] as num?)?.toInt(),
    stockQty: j['stock_qty'] == null
        ? null
        : double.tryParse('${j['stock_qty']}')?.floor(),
    inStock: j['in_stock'] == true,
  );

  /// 1 = best (DX-008).
  final int rank;

  /// Organic or chemical.
  final TreatmentKind kind;

  /// The SKU to order.
  final String skuId;

  /// Its product.
  final String productId;

  /// Product name.
  final String productName;

  /// The label claim that allows the recommendation (DX-007); carried into
  /// the order line (FA-020 checks it again).
  final String labelClaimId;

  /// Price at the store (paise).
  final int pricePaise;

  /// Brand.
  final String brand;

  /// Tenant's own brand (OwnBrandBadge).
  final bool ownBrand;

  /// Pack, e.g. `250 ml`.
  final String packLabel;

  /// Active ingredient.
  final String? activeIngredient;

  /// Agronomist efficacy tier.
  final int? efficacyTier;

  /// Dose per acre as on the label.
  final String? dosePerAcre;

  /// Dose per 15 L tank.
  final String? dosePerTank15l;

  /// Pre-harvest interval (days); null for nutrients.
  final int? phiDays;

  /// PPE as on the label.
  final String? ppeText;

  /// Safety text as on the label.
  final String? safetyText;

  /// MRP (paise).
  final int? mrpPaise;

  /// Units available at the store.
  final int? stockQty;

  /// Available at the store now.
  final bool inStock;

  /// PPE pictograms named in [ppeText] (gloves, mask, goggles, full
  /// clothing); chemicals with no PPE text get gloves and mask.
  Set<Ppe> get ppe {
    final t = (ppeText ?? '').toLowerCase();
    final out = <Ppe>{
      if (t.contains('glove')) Ppe.gloves,
      if (t.contains('mask') || t.contains('respirator')) Ppe.mask,
      if (t.contains('goggle') ||
          t.contains('eye') ||
          t.contains('face shield'))
        Ppe.goggles,
      if (t.contains('sleeve') ||
          t.contains('cloth') ||
          t.contains('apron') ||
          t.contains('coverall') ||
          t.contains('boot'))
        Ppe.clothing,
    };
    if (out.isEmpty && kind == TreatmentKind.chemical) {
      return <Ppe>{Ppe.gloves, Ppe.mask};
    }
    return out;
  }
}

/// The store the products are priced at (`treatments.store`).
@immutable
class DiagnosisStore {
  /// Creates the store.
  const DiagnosisStore({
    required this.id,
    this.code = '',
    this.name = '',
    this.source,
  });

  /// Parses the wire shape.
  factory DiagnosisStore.fromJson(Map<String, Object?> j) => DiagnosisStore(
    id: '${j['id']}',
    code: (j['code'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    source: j['source'] as String?,
  );

  /// Store id.
  final String id;

  /// Code.
  final String code;

  /// "FCC Kondapur".
  final String name;

  /// `village` or `nearest`.
  final String? source;
}

/// A previous answer kept when the agronomist confirms or corrects (F27
/// "keep history").
@immutable
class DiagnosisHistoryEntry {
  /// Creates the entry.
  const DiagnosisHistoryEntry({
    required this.status,
    this.confidence,
    this.problemNames = const <String, String>{},
    this.at,
  });

  /// Parses [toJson] output.
  factory DiagnosisHistoryEntry.fromJson(Map<String, Object?> j) =>
      DiagnosisHistoryEntry(
        status: DiagnosisStatus.parse(j['status']),
        confidence: j['confidence'] as String?,
        problemNames: _stringMap(j['problem_names']),
        at: _time(j['at']),
      );

  /// Status then.
  final DiagnosisStatus status;

  /// Confidence then.
  final String? confidence;

  /// Problem name per language then (empty when there was none).
  final Map<String, String> problemNames;

  /// When that answer was given.
  final DateTime? at;

  /// Name in [lang].
  String? nameIn(String lang) => problemNames[lang] ?? problemNames['en'];

  /// Stored shape (`_local.history[]`).
  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.wire,
    'confidence': confidence,
    'problem_names': problemNames,
    'at': at?.toIso8601String(),
  };
}

/// One crop-doctor case as the apps show it: the server's `DiagnosisOut`
/// (sync feed / poll / applied echo) or, before it arrives, the queued
/// create payload, plus device-only fields under `_local`.
@immutable
class Diagnosis {
  /// Creates the diagnosis.
  const Diagnosis({
    required this.id,
    required this.status,
    this.subject = 'farmer',
    this.farmerId,
    this.cropPlotId,
    this.cropId,
    this.confidence,
    this.provisional = false,
    this.canBuy = false,
    this.cta,
    this.messageKey,
    this.problem,
    this.organic = const <ProductOption>[],
    this.chemical = const <ProductOption>[],
    this.cultural = const <String, List<String>>{},
    this.store,
    this.outOfScopeReason,
    this.visibleSymptoms = const <String>[],
    this.modelVersions = const <String, Object?>{},
    this.corpusVersion,
    this.imageCount = 0,
    this.localPhotos = const <String>[],
    this.cropCode,
    this.capturedAt,
    this.answeredAt,
    this.reviewedAt,
    this.updatedAt,
    this.version = 0,
    this.waitingForNetwork = false,
    this.askExpert = false,
    this.failureCode,
    this.history = const <DiagnosisHistoryEntry>[],
    this.updateUnseen = false,
  });

  /// Reads a stored row (`sync_docs` data) or a `DiagnosisOut`.
  factory Diagnosis.fromData(
    String id,
    Map<String, Object?> d, {
    bool dirty = false,
  }) {
    final local = _map(d[localKey]);
    final result = _map(d['result']);
    final treatments = _map(result['treatments']);
    List<ProductOption> options(Object? raw) => <ProductOption>[
      for (final o in raw is List ? raw : const <Object?>[])
        if (o is Map) ProductOption.fromJson(Map<String, Object?>.from(o)),
    ]..sort((a, b) => a.rank.compareTo(b.rank));
    final status = DiagnosisStatus.parse(d['status']);
    final images = d['images'];
    final storeJson = treatments['store'];
    return Diagnosis(
      id: id,
      status: status,
      subject:
          (d['subject'] as String?) ??
          (local['subject'] as String?) ??
          'farmer',
      farmerId: d['farmer_id'] as String?,
      cropPlotId: d['crop_plot_id'] as String?,
      cropId: d['crop_id'] is String && d['crop_id'] != 'unknown'
          ? d['crop_id']! as String
          : null,
      confidence: _confidence(d['confidence'] ?? result['confidence']),
      provisional:
          d['provisional'] == true ||
          result['provisional'] == true ||
          status == DiagnosisStatus.provisional,
      canBuy: d['can_buy'] == true || result['can_buy'] == true,
      cta: (d['cta'] ?? result['cta']) as String?,
      messageKey: (d['message_key'] ?? result['message_key']) as String?,
      problem: result['problem'] is Map
          ? DiagnosisProblem.fromJson(
              Map<String, Object?>.from(result['problem']! as Map),
            )
          : null,
      organic: options(treatments['organic']),
      chemical: options(treatments['chemical']),
      cultural: _listMap(treatments['cultural']),
      store: storeJson is Map
          ? DiagnosisStore.fromJson(Map<String, Object?>.from(storeJson))
          : null,
      outOfScopeReason:
          (d['out_of_scope_reason'] ?? result['out_of_scope_reason'])
              as String?,
      visibleSymptoms: <String>[
        for (final s in (result['visible_symptoms'] as List?) ?? const []) '$s',
      ],
      modelVersions: _map(d['model_versions']),
      corpusVersion: (d['corpus_version'] as num?)?.toInt(),
      imageCount: images is List ? images.length : 0,
      localPhotos: <String>[
        for (final p in (local['photos'] as List?) ?? const <Object?>[]) '$p',
      ],
      cropCode: local['crop_code'] as String?,
      capturedAt: _time(d['captured_at']),
      answeredAt: _time(d['answered_at']),
      reviewedAt: _time(d['reviewed_at']),
      updatedAt: _time(d['updated_at']),
      version: (d['version'] as num?)?.toInt() ?? 0,
      waitingForNetwork: dirty || status == DiagnosisStatus.pending,
      askExpert:
          d['ask_expert'] == true ||
          d['flagged'] == true ||
          local['ask_expert'] == true,
      failureCode: _map(local['failure'])['code'] as String?,
      history: <DiagnosisHistoryEntry>[
        for (final h in (local['history'] as List?) ?? const <Object?>[])
          if (h is Map)
            DiagnosisHistoryEntry.fromJson(Map<String, Object?>.from(h)),
      ],
      updateUnseen: local['update_unseen'] == true,
    );
  }

  /// Key of the device-only fields in the stored row.
  static const String localKey = '_local';

  /// Client-generated id.
  final String id;

  /// Lifecycle.
  final DiagnosisStatus status;

  /// `farmer` (crop doctor) or `officer` (scouting, FA-019).
  final String subject;

  /// Farmer.
  final String? farmerId;

  /// Crop plot the result is attached to (scouting).
  final String? cropPlotId;

  /// Crop.
  final String? cropId;

  /// Confidence band.
  final ConfidenceLevel? confidence;

  /// "Provisional — expert will confirm".
  final bool provisional;

  /// Server says a buy action may be shown (SPEC 3.4).
  final bool canBuy;

  /// `buy` | `talk_to_field_officer` | `ask_expert`.
  final String? cta;

  /// Headline i18n key (`diagnosis.result.answered`, ...).
  final String? messageKey;

  /// The problem, when there is one.
  final DiagnosisProblem? problem;

  /// Ranked organic options.
  final List<ProductOption> organic;

  /// Ranked chemical options.
  final List<ProductOption> chemical;

  /// Cultural practices per language.
  final Map<String, List<String>> cultural;

  /// Where the products are priced.
  final DiagnosisStore? store;

  /// `not_a_plant`, `unsupported_crop`, `unreadable_image`, `no_match`,
  /// `expert_not_diagnosable`.
  final String? outOfScopeReason;

  /// What the LLM saw (provisional answers).
  final List<String> visibleSymptoms;

  /// DX-005 model versions.
  final Map<String, Object?> modelVersions;

  /// DX-005 corpus version.
  final int? corpusVersion;

  /// Number of photos the server has.
  final int imageCount;

  /// Local photo paths (thumbnails, offline).
  final List<String> localPhotos;

  /// Crop code chosen on the phone (display before the server answers).
  final String? cropCode;

  /// Photo time.
  final DateTime? capturedAt;

  /// First answer.
  final DateTime? answeredAt;

  /// Agronomist review.
  final DateTime? reviewedAt;

  /// Last server change.
  final DateTime? updatedAt;

  /// Server version.
  final int version;

  /// The create op has not reached the server yet.
  final bool waitingForNetwork;

  /// Sent to the agronomist on request (FM-006).
  final bool askExpert;

  /// Why the queued create was refused (`diagnosis_image_missing`, ...).
  final String? failureCode;

  /// Earlier answers, oldest first (F27).
  final List<DiagnosisHistoryEntry> history;

  /// Changed by the agronomist since the user last looked (F27 banner).
  final bool updateUnseen;

  /// Out of scope (F28).
  bool get isOutOfScope => status == DiagnosisStatus.outOfScope;

  /// Has a problem to show (F25 / F26 / A43).
  bool get hasResult => problem != null && !isOutOfScope;

  /// SPEC 3.4 / FM-005: a buy (order) action may be shown only when the
  /// server allows it **and** the answer is not provisional and backed by
  /// the corpus or the agronomist.
  bool get showBuy =>
      canBuy &&
      !provisional &&
      (status == DiagnosisStatus.answered || status.isReviewed);

  /// Every option, organic first (ranked within each kind).
  List<ProductOption> get options => <ProductOption>[...organic, ...chemical];

  /// The recommended option: the best in-stock chemical, else organic.
  ProductOption? get recommended {
    for (final list in <List<ProductOption>>[chemical, organic]) {
      final inStock = list.where((o) => o.inStock).firstOrNull;
      if (inStock != null) return inStock;
    }
    return chemical.firstOrNull ?? organic.firstOrNull;
  }

  /// Cultural practices in [lang] (English fallback).
  List<String> culturalIn(String lang) =>
      cultural[lang] ?? cultural['en'] ?? const <String>[];
}

ConfidenceLevel? _confidence(Object? v) => switch (v) {
  'high' => ConfidenceLevel.high,
  'medium' => ConfidenceLevel.medium,
  'low' => ConfidenceLevel.low,
  _ => null,
};

Map<String, Object?> _map(Object? v) =>
    v is Map ? Map<String, Object?>.from(v) : const <String, Object?>{};

Map<String, String> _stringMap(Object? v) => v is Map
    ? <String, String>{
        for (final e in v.entries)
          if (e.value is String) '${e.key}': e.value! as String,
      }
    : const <String, String>{};

Map<String, List<String>> _listMap(Object? v) => v is Map
    ? <String, List<String>>{
        for (final e in v.entries)
          if (e.value is List)
            '${e.key}': <String>[for (final s in e.value! as List) '$s'],
      }
    : const <String, List<String>>{};

DateTime? _time(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;
