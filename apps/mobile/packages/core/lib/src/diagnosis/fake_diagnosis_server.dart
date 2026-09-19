import '../sync/sync_api.dart';
import '../sync/sync_models.dart';
import 'diagnosis_api.dart';

/// What the fake diagnosis server answers next.
enum FakeDiagnosisOutcome {
  /// Corpus answer, high confidence, buy allowed.
  high,

  /// Provisional (medium confidence, LLM): no buy.
  provisional,

  /// DX-010 not a plant.
  notAPlant,

  /// DX-010 unsupported crop.
  unsupportedCrop,

  /// Accepted but not answered yet (pubsub delivery).
  queued,
}

/// A scriptable diagnosis backend for tests and previews: plugs into
/// [FakeSyncApi] (the `diagnosis` create op is answered with a
/// `DiagnosisOut` in the applied echo, like `DIAGNOSIS_DELIVERY=inline`)
/// and [FakeDiagnosisApi] (polling), and can play the agronomist
/// ([review]) through the change feed.
class FakeDiagnosisServer {
  /// Creates the server and installs it on [sync].
  FakeDiagnosisServer({
    required this.sync,
    required this.api,
    this.farmerId = 'f-1',
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.utc(2026, 9, 19, 4, 30)) {
    final previous = sync.script;
    sync.script = (op) {
      if (op.entity == SyncEntities.diagnosis &&
          op.action == SyncAction.create) {
        return _create(op);
      }
      return previous?.call(op);
    };
  }

  /// Sync transport.
  final FakeSyncApi sync;

  /// Poll endpoint.
  final FakeDiagnosisApi api;

  /// Farmer the fake login belongs to (a farmer omits `farmer_id`).
  final String farmerId;

  final DateTime Function() _clock;

  /// The next answer.
  FakeDiagnosisOutcome next = FakeDiagnosisOutcome.high;

  /// Create ops received (payload as sent).
  final List<SyncOp> creates = <SyncOp>[];

  SyncOpResult _create(SyncOp op) {
    creates.add(op);
    final p = op.payload;
    final out = diagnosisOut(
      id: op.entityId,
      outcome: next,
      farmerId: (p['farmer_id'] as String?) ?? farmerId,
      cropPlotId: p['crop_plot_id'] as String?,
      subject: p['farmer_id'] == null ? 'farmer' : 'officer',
      images: <Object?>[
        for (final i in (p['images'] as List?) ?? const <Object?>[])
          if (i is Map)
            <String, Object?>{
              'blob_uri': i['blob_uri'],
              'sha256': i['sha256'],
              'quality': i['quality'],
            },
      ],
      askExpert: p['ask_expert'] == true,
      now: _clock(),
    );
    api.rows[op.entityId] = out;
    return SyncOpResult(
      opId: op.opId,
      status: SyncResultStatus.applied,
      entityId: op.entityId,
      version: out['version']! as int,
      server: out,
    );
  }

  /// The server answers a queued diagnosis (poll + feed).
  void answer(String id, FakeDiagnosisOutcome outcome) {
    final row = api.rows[id]!;
    final out = diagnosisOut(
      id: id,
      outcome: outcome,
      farmerId: row['farmer_id']! as String,
      cropPlotId: row['crop_plot_id'] as String?,
      subject: row['subject']! as String,
      images: (row['images'] as List?) ?? const <Object?>[],
      version: (row['version']! as int) + 1,
      now: _clock(),
    );
    api.rows[id] = out;
    sync.addChange(
      entity: SyncEntities.diagnosis,
      action: SyncAction.update,
      entityId: id,
      version: out['version']! as int,
      data: out,
    );
  }

  /// The agronomist confirms (or corrects) a provisional answer: the row
  /// becomes `confirmed` / `corrected`, high confidence, buy allowed, and a
  /// change reaches the feed (F27).
  void review(String id, {bool corrected = false}) {
    final row = api.rows[id]!;
    final out = diagnosisOut(
      id: id,
      outcome: FakeDiagnosisOutcome.high,
      farmerId: row['farmer_id']! as String,
      cropPlotId: row['crop_plot_id'] as String?,
      subject: row['subject']! as String,
      images: (row['images'] as List?) ?? const <Object?>[],
      status: corrected ? 'corrected' : 'confirmed',
      version: (row['version']! as int) + 1,
      corrected: corrected,
      now: _clock(),
    );
    api.rows[id] = out;
    sync.addChange(
      entity: SyncEntities.diagnosis,
      action: SyncAction.update,
      entityId: id,
      version: out['version']! as int,
      data: out,
    );
  }

  /// A `DiagnosisOut` for [outcome] (docs/prs/M6-diagnosis-api.md).
  static Map<String, Object?> diagnosisOut({
    required String id,
    required FakeDiagnosisOutcome outcome,
    String farmerId = 'f-1',
    String? cropPlotId,
    String subject = 'farmer',
    List<Object?> images = const <Object?>[],
    String? status,
    int version = 1,
    bool corrected = false,
    bool askExpert = false,
    DateTime? now,
  }) {
    final at = (now ?? DateTime.utc(2026, 9, 19, 4, 30)).toIso8601String();
    final (
      String st,
      String? confidence,
      bool canBuy,
      String cta,
      String messageKey,
      String? oos,
    ) = switch (outcome) {
      FakeDiagnosisOutcome.high => (
        status ?? 'answered',
        'high',
        true,
        'buy',
        'diagnosis.result.${status ?? 'answered'}',
        null,
      ),
      FakeDiagnosisOutcome.provisional => (
        'provisional',
        'medium',
        false,
        'talk_to_field_officer',
        'diagnosis.result.provisional',
        null,
      ),
      FakeDiagnosisOutcome.notAPlant => (
        'out_of_scope',
        null,
        false,
        'ask_expert',
        'diagnosis.out_of_scope.not_a_plant',
        'not_a_plant',
      ),
      FakeDiagnosisOutcome.unsupportedCrop => (
        'out_of_scope',
        null,
        false,
        'ask_expert',
        'diagnosis.out_of_scope.unsupported_crop',
        'unsupported_crop',
      ),
      FakeDiagnosisOutcome.queued => (
        'queued',
        null,
        false,
        'talk_to_field_officer',
        'diagnosis.result.unknown',
        null,
      ),
    };
    final hasProblem =
        outcome == FakeDiagnosisOutcome.high ||
        outcome == FakeDiagnosisOutcome.provisional;
    final result = st == 'queued'
        ? null
        : <String, Object?>{
            'problem': hasProblem ? (corrected ? leafCurl : anthracnose) : null,
            'confidence': confidence,
            'provisional': st == 'provisional',
            'can_buy': canBuy,
            'cta': cta,
            'message_key': messageKey,
            'out_of_scope_reason': oos,
            'visible_symptoms': const <String>[],
            'treatments': hasProblem
                ? treatments
                : <String, Object?>{
                    'organic': const <Object?>[],
                    'chemical': const <Object?>[],
                    'cultural': const <String, Object?>{},
                    'store': store,
                  },
          };
    return <String, Object?>{
      'id': id,
      'subject': subject,
      'farmer_id': farmerId,
      'crop_plot_id': cropPlotId,
      'requested_by': 'u-1',
      'crop_id': null,
      'crop_detected_on_device': null,
      'district': 'Medak',
      'season': 'kharif',
      'crop_stage': null,
      'status': st,
      'source': st == 'queued'
          ? null
          : st == 'provisional'
          ? 'llm'
          : (st == 'confirmed' || st == 'corrected')
          ? 'agronomist'
          : 'corpus',
      'confidence': confidence,
      'provisional': st == 'provisional' || st == 'queued',
      'can_buy': canBuy,
      'cta': cta,
      'message_key': messageKey,
      'result': result,
      'final_problem_id': hasProblem
          ? (corrected ? 'problem-leaf-curl' : 'problem-anthracnose')
          : null,
      'out_of_scope_reason': oos,
      'flagged': askExpert,
      'model_versions': <String, Object?>{
        'encoder': 'siglip-base-patch16-224@2024-01',
        'on_device': 'ondevice-v1.0',
        'llm': st == 'provisional' ? 'claude-opus-5' : null,
      },
      'corpus_version': 7,
      'images': images,
      'captured_at': at,
      'answered_at': st == 'queued' ? null : at,
      'reviewed_at': (st == 'confirmed' || st == 'corrected') ? at : null,
      'created_at': at,
      'updated_at': at,
      'version': version,
    };
  }

  /// Chilli anthracnose (the default answer).
  static const Map<String, Object?> anthracnose = <String, Object?>{
    'id': 'problem-anthracnose',
    'pest_or_disease_id': 'pd-anthracnose',
    'code': 'chilli_anthracnose',
    'type': 'disease',
    'crop_id': 'crop-chilli',
    'names': <String, Object?>{
      'en': 'Anthracnose (fruit rot)',
      'te': 'కాయ కుళ్ళు తెగులు',
      'kn': 'ಆಂಥ್ರಾಕ್ನೋಸ್ (ಕಾಯಿ ಕೊಳೆ)',
      'hi': 'एन्थ्रेक्नोज़ (फल सड़न)',
      'mr': 'करपा (फळ सड)',
    },
    'symptoms': <String, Object?>{
      'en': <String>[
        'Sunken dark spots on the fruit',
        'Spots with rings of orange dots',
        'Fruits dry and fall early',
      ],
      'te': <String>[
        'కాయలపై లోతైన నల్లని మచ్చలు',
        'మచ్చల చుట్టూ నారింజ చుక్కల వలయాలు',
        'కాయలు ఎండి ముందే రాలిపోతాయి',
      ],
      'hi': <String>[
        'फल पर धँसे हुए काले धब्बे',
        'धब्बों में नारंगी बिंदुओं के घेरे',
        'फल सूखकर जल्दी गिर जाते हैं',
      ],
    },
  };

  /// Chilli leaf curl (the agronomist's correction).
  static const Map<String, Object?> leafCurl = <String, Object?>{
    'id': 'problem-leaf-curl',
    'pest_or_disease_id': 'pd-leaf-curl',
    'code': 'chilli_leaf_curl',
    'type': 'disease',
    'crop_id': 'crop-chilli',
    'names': <String, Object?>{
      'en': 'Leaf curl virus',
      'te': 'ఆకు ముడత',
      'kn': 'ಎಲೆ ಮುರುಟು',
      'hi': 'पत्ती मरोड़',
      'mr': 'पाने चुरडणे',
    },
    'symptoms': <String, Object?>{
      'en': <String>['Leaves curl upwards', 'Plants stay small'],
    },
  };

  /// The store the products are priced at.
  static const Map<String, Object?> store = <String, Object?>{
    'id': 'store-1',
    'code': 'KDP',
    'name': 'FCC Kondapur',
    'source': 'nearest',
  };

  /// Ranked options: one own-brand organic, two chemicals.
  static const Map<String, Object?> treatments = <String, Object?>{
    'organic': <Object?>[
      <String, Object?>{
        'rank': 1,
        'kind': 'organic',
        'sku_id': 'sku-neem',
        'product_id': 'p-neem',
        'product_name': 'Neem Shakti',
        'brand': 'Mitra',
        'own_brand': true,
        'pack_label': '500 ml',
        'active_ingredient': 'Azadirachtin 1500 ppm',
        'label_claim_id': 'lc-neem',
        'efficacy_tier': 2,
        'dose_per_acre': '1 L',
        'dose_value': '1',
        'dose_unit': 'L',
        'dose_per_tank_15l': '75 ml',
        'phi_days': 3,
        'ppe_text': 'Gloves',
        'safety_text': 'Spray in the evening.',
        'price_paise': 42000,
        'mrp_paise': 45000,
        'stock_qty': '20',
        'in_stock': true,
      },
    ],
    'chemical': <Object?>[
      <String, Object?>{
        'rank': 1,
        'kind': 'chemical',
        'sku_id': 'sku-azoxy',
        'product_id': 'p-azoxy',
        'product_name': 'Amistar 250 ml',
        'brand': 'Syngenta',
        'own_brand': false,
        'pack_label': '250 ml',
        'active_ingredient': 'Azoxystrobin 23% SC',
        'label_claim_id': 'lc-azoxy',
        'efficacy_tier': 1,
        'dose_per_acre': '200 ml',
        'dose_value': '200',
        'dose_unit': 'ml',
        'dose_per_tank_15l': '15 ml',
        'phi_days': 5,
        'ppe_text': 'Gloves, mask, goggles, full sleeves',
        'safety_text': 'Do not spray against the wind. Wash hands after use.',
        'price_paise': 68000,
        'mrp_paise': 72000,
        'stock_qty': '8',
        'in_stock': true,
      },
      <String, Object?>{
        'rank': 2,
        'kind': 'chemical',
        'sku_id': 'sku-mitra-myclo',
        'product_id': 'p-mitra-myclo',
        'product_name': 'Mitra Myclo 100 g',
        'brand': 'Mitra',
        'own_brand': true,
        'pack_label': '100 g',
        'active_ingredient': 'Myclobutanil 10% WP',
        'label_claim_id': 'lc-myclo',
        'efficacy_tier': 2,
        'dose_per_acre': '160 g',
        'dose_value': '160',
        'dose_unit': 'g',
        'dose_per_tank_15l': '12 g',
        'phi_days': 7,
        'ppe_text': 'Gloves and mask',
        'safety_text': 'Keep away from children.',
        'price_paise': 31000,
        'mrp_paise': 33000,
        'stock_qty': '0',
        'in_stock': false,
      },
    ],
    'cultural': <String, Object?>{
      'en': <String>[
        'Pick and destroy rotten fruits',
        'Do not water from above',
      ],
      'te': <String>[
        'కుళ్ళిన కాయలు తీసి నాశనం చేయండి',
        'పై నుంచి నీరు పోయకండి',
      ],
      'hi': <String>['सड़े फल तोड़कर नष्ट करें', 'ऊपर से पानी न दें'],
    },
    'store': store,
  };
}
