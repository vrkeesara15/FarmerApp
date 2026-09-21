import 'dart:async';
import 'dart:convert';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/app.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Saturday 2026-09-19 10:00 IST as UTC.
final DateTime t0 = DateTime.utc(2026, 9, 19, 4, 30);

/// The farmer behind the login.
const String farmerId = 'f-1';

/// Their store.
const String storeId = 'store-1';

/// Deterministic ids.
class SeqIds {
  int _n = 0;

  /// Next id.
  String call() => 'id-${(++_n).toString().padLeft(4, '0')}';
}

/// `FarmerDetailOut` for [farmerId]: an officer-registered farmer (Ramesh
/// Kumar) with one mapped farm and two crop plots, or a self-registered
/// farmer with no farm.
Map<String, Object?> farmerRecord({
  bool officerRegistered = true,
  bool dataConsent = false,
  bool marketingConsent = false,
  bool withOfficerContact = true,
}) {
  final ring = <GeoPoint>[
    const GeoPoint(17.4, 78.4),
    const GeoPoint(17.4, 78.401),
    const GeoPoint(17.401, 78.401),
    const GeoPoint(17.401, 78.4),
  ];
  return <String, Object?>{
    'id': farmerId,
    'tenant_id': 't-1',
    'phone': '+919000000004',
    'phone_last4': '0004',
    'phone_verified': true,
    'name': 'Lakshmi Devi',
    'village_id': 'village-1',
    'landmark': null,
    'language': 'te',
    'consent_marketing': marketingConsent,
    'consent_version': '2026-09-v1',
    'registered_by': officerRegistered ? 'officer-1' : null,
    'user_id': 'u-fake',
    'source': officerRegistered ? 'field_officer' : 'store',
    'land_ownership': 'own',
    'created_at': '2026-09-01T05:00:00Z',
    'updated_at': '2026-09-01T05:00:00Z',
    'version': 3,
    if (officerRegistered && withOfficerContact)
      'officer': <String, Object?>{
        'id': 'officer-1',
        'name': 'Ramesh Kumar',
        'phone': '+919100000001',
      },
    'farms': <Object?>[
      if (officerRegistered)
        <String, Object?>{
          'id': 'farm-1',
          'farmer_id': farmerId,
          'name': 'Home farm',
          'boundary': polygonToGeoJson(ring),
          'area_acres': '2.50',
          'soil': 'black',
          'irrigation': 'borewell',
          'version': 2,
          'crop_plots': <Object?>[
            <String, Object?>{
              'id': 'plot-1',
              'farm_id': 'farm-1',
              'crop_id': 'pilot:cotton',
              'season': 'kharif',
              'sowing_date': '2026-06-15',
              'stage': 'flowering',
              'version': 1,
            },
            <String, Object?>{
              'id': 'plot-2',
              'farm_id': 'farm-1',
              'crop_id': 'pilot:chilli',
              'season': 'kharif',
              'sowing_date': '2026-07-01',
              'stage': 'vegetative',
              'version': 1,
            },
          ],
        },
    ],
    'consents': <Object?>[
      if (dataConsent)
        <String, Object?>{
          'id': 'consent-a',
          'subject_id': farmerId,
          'purpose': 'data',
          'version': '2026-09-v1',
          'language': 'te',
          'granted_at': '2026-09-01T05:00:00Z',
          'withdrawn_at': null,
          'channel': 'officer',
          'recorded_by': 'officer-1',
          'created_at': '2026-09-01T05:00:00Z',
        },
      if (marketingConsent)
        <String, Object?>{
          'id': 'consent-b',
          'subject_id': farmerId,
          'purpose': 'marketing',
          'version': '2026-09-v1',
          'language': 'te',
          'granted_at': '2026-09-01T05:00:00Z',
          'withdrawn_at': null,
          'channel': 'officer',
          'recorded_by': 'officer-1',
          'created_at': '2026-09-01T05:00:00Z',
        },
    ],
  };
}

/// A `ProductWithSkusOut` row.
Map<String, Object?> product(
  String id,
  String name, {
  required String skuId,
  required String pack,
  required int price,
  String category = 'pesticide',
  bool ownBrand = false,
  String stock = '20',
}) => <String, Object?>{
  'id': id,
  'name': name,
  'brand': ownBrand ? 'Mitra' : 'FMC',
  'own_brand': ownBrand,
  'category': category,
  'gst_rate_bp': 0,
  'active_ingredient': null,
  'names': const <String, Object?>{},
  'active': true,
  'version': 1,
  'skus': <Object?>[
    <String, Object?>{
      'id': skuId,
      'pack_label': pack,
      'mrp_paise': price,
      'price_paise': price,
      'stock_qty': stock,
      'active': true,
      'version': 1,
    },
  ],
};

/// A khata of [balance] paise at [storeId].
Map<String, Object?> khataOf(int balance, {List<Object?>? entries}) =>
    <String, Object?>{
      'farmer_id': farmerId,
      'store_id': null,
      'balance_paise': balance,
      'overdue_paise': 0,
      'next_due_date': balance > 0 ? '2026-11-30' : null,
      'balances': <Object?>[
        <String, Object?>{'store_id': storeId, 'balance_paise': balance},
      ],
      'credit_limits': <Object?>[],
      'overdue_buckets': <String, Object?>{},
      'payment_history': <Object?>[],
      'entries':
          entries ??
          <Object?>[
            if (balance > 0)
              <String, Object?>{
                'id': 'k-1',
                'farmer_id': farmerId,
                'store_id': storeId,
                'type': 'debit',
                'amount_paise': balance,
                'signed_paise': balance,
                'due_date': '2026-11-30',
                'ref_type': 'order',
                'created_at': '2026-09-02T05:00:00Z',
              },
          ],
    };

/// A signed-looking visit confirmation token (claims only; the server
/// verifies the signature).
String visitToken(String visitId, {String channel = 'qr'}) {
  String part(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part(<String, Object?>{'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part(<String, Object?>{'typ': 'visit_confirm', 'vid': visitId, 'cid': 'c-1', 'ch': channel, 'exp': t0.add(const Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000})}'
      '.sig';
}

/// `CalendarOut` for [farmerId]: cotton on plot-1 (sown 2026-06-15, four
/// tasks, the first already done) and chilli on plot-2 (sown 2026-07-01,
/// one task). Dates are around `t0` (2026-09-19 IST).
Map<String, Object?> calendarBody({String today = '2026-09-19'}) =>
    <String, Object?>{
      'farmer_id': farmerId,
      'today': today,
      'plots': <Object?>[
        <String, Object?>{
          'crop_plot_id': 'plot-1',
          'farm_id': 'farm-1',
          'crop_id': 'pilot:cotton',
          'crop_code': 'cotton',
          'crop_names': <String, Object?>{'en': 'Cotton', 'te': 'పత్తి'},
          'season': 'kharif',
          'sowing_date': '2026-06-15',
          'tasks': <Object?>[
            calendarTask(
              id: 'task-1',
              key: 'cotton.sow',
              type: 'sow',
              due: '2026-06-15',
              title: 'Sow the seed',
              titleTe: 'విత్తనం వేయండి',
              instruction: 'Sow in rows 90 cm apart.',
              status: 'done',
            ),
            calendarTask(
              id: 'task-2',
              key: 'cotton.top_dress_1',
              type: 'fertilise',
              due: '2026-07-20',
              title: 'First top dressing',
              titleTe: 'మొదటి పైపాటు ఎరువు',
              instruction: 'Apply the first split of nitrogen.',
            ),
            calendarTask(
              id: 'task-3',
              key: 'cotton.spray_1',
              type: 'spray',
              due: '2026-09-21',
              end: '2026-09-23',
              title: 'Check for sucking pests',
              titleTe: 'రసం పీల్చే పురుగులు చూడండి',
              instruction: 'Spray only if you see the pest.',
            ),
            calendarTask(
              id: 'task-4',
              key: 'cotton.harvest',
              type: 'harvest',
              due: '2026-11-10',
              title: 'First picking',
              titleTe: 'మొదటి కోత',
              instruction: 'Pick when the bolls open fully.',
              reminder: false,
            ),
          ],
        },
        <String, Object?>{
          'crop_plot_id': 'plot-2',
          'farm_id': 'farm-1',
          'crop_id': 'pilot:chilli',
          'crop_code': 'chilli',
          'crop_names': <String, Object?>{'en': 'Chilli', 'te': 'మిరప'},
          'season': 'kharif',
          'sowing_date': '2026-07-01',
          'tasks': <Object?>[
            calendarTask(
              id: 'task-5',
              key: 'chilli.irrigate_1',
              type: 'irrigate',
              due: '2026-09-25',
              title: 'Water the field',
              titleTe: 'పొలానికి నీరు పెట్టండి',
              instruction: 'Give light irrigation in the morning.',
            ),
          ],
        },
      ],
    };

/// One `CropPlotTaskOut` row.
Map<String, Object?> calendarTask({
  required String id,
  required String key,
  required String type,
  required String due,
  required String title,
  required String instruction,
  String? titleTe,
  String? end,
  String status = 'pending',
  bool reminder = true,
  int version = 1,
}) => <String, Object?>{
  'id': id,
  'task_key': key,
  'task_type': type,
  'stage': 'vegetative',
  'due_date': due,
  'end_date': end ?? due,
  'titles': <String, Object?>{'en': title, 'te': ?titleTe},
  'instructions': <String, Object?>{'en': instruction},
  'product_category': null,
  'sort_order': 10,
  'status': status,
  'done_at': status == 'done' ? '2026-06-15T05:00:00Z' : null,
  'reminder_enabled': reminder,
  'reminded_at': null,
  'basis_sowing_date': null,
  'version': version,
};

/// `WeatherOut` for farm-1: seven days from 2026-09-19 and four 3-hour
/// FM-012 `MandiPricesOut`: one crop with two markets, both published on
/// 2026-09-20, from the public source.
Map<String, Object?> mandiPricesBody({
  String source = 'Agmarknet (data.gov.in)',
  String priceDate = '2026-09-20',
}) => <String, Object?>{
  'farmer_id': farmerId,
  'district': 'Medak',
  'as_of': priceDate,
  'indicative_note_key': 'mandi.indicative',
  'crops': <Object?>[
    <String, Object?>{
      'crop_id': 'crop-paddy',
      'crop_code': 'paddy',
      'crop_name': 'Paddy',
      'crop_names': <String, Object?>{'en': 'Paddy', 'te': 'వరి'},
      'price_date': priceDate,
      'source_name': source,
      'quotes': <Object?>[
        <String, Object?>{
          'id': 'mp-1',
          'market': 'Medak Main Yard',
          'district': 'Medak',
          'state': 'Telangana',
          'variety': 'Common',
          'grade': 'FAQ',
          'price_date': priceDate,
          'min_price_paise': 205000,
          'modal_price_paise': 215050,
          'max_price_paise': 225000,
          'source': 'agmarknet',
          'source_name': source,
        },
        <String, Object?>{
          'id': 'mp-2',
          'market': 'Sangareddy Yard',
          'district': 'Sangareddy',
          'state': 'Telangana',
          'variety': '',
          'grade': '',
          'price_date': priceDate,
          'min_price_paise': 200000,
          'modal_price_paise': 210000,
          'max_price_paise': 220000,
          'source': 'agmarknet',
          'source_name': source,
        },
      ],
    },
  ],
};

/// FM-013 `MyReferralOut`: a code, a share link and the counts.
Map<String, Object?> referralBody({
  String code = 'KISAN123',
  bool enabled = true,
  int invited = 2,
  int attributed = 1,
  int rewarded = 0,
}) => <String, Object?>{
  'farmer_id': farmerId,
  'code': code,
  'share_link': 'https://kisan.farmerapp.in/r/$code',
  'enabled': enabled,
  'referrer_reward_paise': 0,
  'store_reward_paise': 0,
  'reward_note': null,
  'invited': invited,
  'attributed': attributed,
  'rewarded': rewarded,
  'referrals': <Object?>[],
};

/// spray windows — one good, one hidden for rain, one hidden for wind,
/// and one the server calls good although its wind breaches the
/// threshold (the app re-checks and must not show it as good).
Map<String, Object?> weatherBody() => <String, Object?>{
  'farm_id': 'farm-1',
  'latitude': 17.4,
  'longitude': 78.4,
  'location_source': 'farm',
  'provider': 'open_meteo',
  'fetched_at': t0.toIso8601String(),
  'cached': false,
  'timezone': 'Asia/Kolkata',
  'daily': <Object?>[
    for (var i = 0; i < 7; i++)
      <String, Object?>{
        'date': isoDay(DateTime.utc(2026, 9, 19).add(Duration(days: i))),
        'temperature_max_c': 31.0 + i,
        'temperature_min_c': 22.0 + i,
        'precipitation_mm': i == 1 ? 12.0 : 0.0,
        'precipitation_probability_pct': i == 1 ? 80 : 10,
        'wind_max_kmh': 8.0 + i,
        'weather_code': i == 1 ? 61 : 1,
      },
  ],
  'hourly': const <Object?>[],
  'spray': <String, Object?>{
    'windows': <Object?>[
      sprayWindow(hourIst: 6, advice: 'good'),
      // The server called this one good; its wind is over the threshold.
      sprayWindow(hourIst: 18, advice: 'good', wind: 21),
    ],
    'avoided': <Object?>[
      sprayWindow(
        hourIst: 9,
        advice: 'avoid',
        reasons: <String>['rain_likely'],
        rainProbability: 70,
      ),
      sprayWindow(
        hourIst: 12,
        advice: 'avoid',
        reasons: <String>['wind_high'],
        wind: 24,
      ),
    ],
    'thresholds': <String, Object?>{
      'max_rain_probability_pct': 30,
      'max_rain_mm': 0.5,
      'max_wind_kmh': 15,
      'caution_max_temperature_c': 35,
      'caution_max_humidity_pct': 90,
      'caution_min_humidity_pct': 30,
    },
  },
};

/// A 3-hour spray window starting at [hourIst] IST on 2026-09-19.
Map<String, Object?> sprayWindow({
  required int hourIst,
  required String advice,
  List<String> reasons = const <String>[],
  List<String> cautions = const <String>[],
  int rainProbability = 10,
  double rain = 0,
  double wind = 8,
  double temperature = 30,
}) {
  final start = DateTime.utc(2026, 9, 19, hourIst - 5, 30);
  return <String, Object?>{
    'start': start.toIso8601String(),
    'end': start.add(const Duration(hours: 3)).toIso8601String(),
    'advice': advice,
    'reasons': reasons,
    'cautions': cautions,
    'max_precipitation_probability_pct': rainProbability,
    'precipitation_mm': rain,
    'max_wind_kmh': wind,
    'max_temperature_c': temperature,
    'min_relative_humidity_pct': 45,
    'max_relative_humidity_pct': 70,
  };
}

/// One `OutbreakAlertOut` row.
Map<String, Object?> alertRow({
  String id = 'alert-1',
  String district = 'Medak',
  String cropCode = 'cotton',
  String cropId = 'pilot:cotton',
  String problemCode = 'pink_bollworm',
  String problemType = 'pest',
  String problemName = 'Pink bollworm',
  String problemNameTe = 'గులాబీ కాయ తొలుచు పురుగు',
  int cases = 12,
  int farmers = 9,
  double baseline = 2,
  bool growsCrop = true,
}) => <String, Object?>{
  'id': id,
  'district': district,
  'crop_id': cropId,
  'crop_code': cropCode,
  'crop_names': <String, Object?>{'en': 'Cotton', 'te': 'పత్తి'},
  'problem_id': 'problem-$problemCode',
  'problem_code': problemCode,
  'problem_type': problemType,
  'problem_names': <String, Object?>{'en': problemName, 'te': problemNameTe},
  'week_start': '2026-09-14',
  'iso_year': 2026,
  'iso_week': 38,
  'case_count': cases,
  'farmers_affected': farmers,
  'baseline_mean': baseline,
  'status': 'active',
  'grows_crop': growsCrop,
  'created_at': '2026-09-18T02:00:00Z',
};

/// Everything the farmer screens talk to, scriptable.
class KisanDeps {
  /// Creates the dependencies over an in-memory database.
  KisanDeps({bool online = true})
    : db = openInMemoryDatabase(),
      connectivity = FakeConnectivityMonitor(online: online) {
    kisan = FakeKisanApi(clock: () => now);
    advisory = FakeAdvisoryApi(clock: () => now);
    payApi = FakePaymentsApi(clock: () => now);
    diagnosisServer = FakeDiagnosisServer(
      sync: syncApi,
      api: diagnosisApi,
      clock: () => now,
    );
  }

  /// Crop doctor: the live camera (queue shots on it).
  final FakeGuidedCamera camera = FakeGuidedCamera();

  /// Crop doctor: the DX-001 gate (queue verdicts on it).
  final ScriptedQualityModel quality = ScriptedQualityModel();

  /// Crop doctor: `GET /v1/diagnoses/{id}`.
  final FakeDiagnosisApi diagnosisApi = FakeDiagnosisApi();

  /// Crop doctor: answers the `diagnosis` create op and plays the
  /// agronomist.
  late final FakeDiagnosisServer diagnosisServer;

  /// Photos kept until uploaded.
  final MemoryPhotoStore photos = MemoryPhotoStore();

  /// Tenant flag `on_device_crop_guess`.
  bool cropGuessFlag = false;

  /// Result poll waits: each completes when the test calls
  /// [releaseDiagnosisPoll].
  final List<Completer<void>> diagnosisPolls = <Completer<void>>[];

  /// Lets the waiting result poll run once.
  void releaseDiagnosisPoll() {
    for (final c in diagnosisPolls) {
      if (!c.isCompleted) c.complete();
    }
  }

  /// Farmer REST calls.
  late final FakeKisanApi kisan;

  /// M7 advisory REST calls (calendar, weather, alerts, inbox, push token).
  late final FakeAdvisoryApi advisory;

  /// M8 market REST calls (FM-012 mandi prices, FM-013 referrals).
  final FakeMarketApi market = FakeMarketApi();

  /// Records what the FM-013 invite shared.
  final FakeTextSharer sharer = FakeTextSharer();

  /// FA-007 push transport.
  final FakePushService push = FakePushService();

  /// Payments.
  late final FakePaymentsApi payApi;

  /// Khata.
  final FakeKhataApi khataApi = FakeKhataApi();

  /// Catalogue.
  final FakeCatalogApi catalogApi = FakeCatalogApi(pageSize: 50);

  /// Sync (queued consent / visit confirmations).
  final FakeSyncApi syncApi = FakeSyncApi();

  /// Login.
  FakeAuthApi auth = FakeAuthApi(role: 'farmer');

  /// Audio prompts.
  final FakeAudioPrompt audio = FakeAudioPrompt();

  /// UPI / tel / WhatsApp.
  final RecordingUrlOpener urls = RecordingUrlOpener();

  /// QR scanner.
  final FakeBarcodeScanner scanner = FakeBarcodeScanner();

  /// Database.
  final AppDatabase db;

  /// Network.
  final FakeConnectivityMonitor connectivity;

  /// Ids.
  final SeqIds ids = SeqIds();

  /// Clock.
  DateTime now = t0;

  /// UPI poll waits: each completes when the test calls [releasePoll].
  final List<Completer<void>> polls = <Completer<void>>[];

  /// Lets the waiting UPI poll run once.
  void releasePoll() {
    for (final c in polls) {
      if (!c.isCompleted) c.complete();
    }
  }

  /// Seeds the officer-registered farmer, catalogue and nearest store.
  void seedWorld({
    bool officerRegistered = true,
    bool dataConsent = true,
    bool marketingConsent = false,
    int khataBalance = 0,
  }) {
    kisan.farmerRecord = farmerRecord(
      officerRegistered: officerRegistered,
      dataConsent: dataConsent,
      marketingConsent: marketingConsent,
    );
    catalogApi.nearestByFarmer[farmerId] = const StoreInfo(
      id: storeId,
      name: 'Kondapur Agri Store',
    );
    catalogApi.productsByStore[storeId] = <Map<String, Object?>>[
      product(
        'p-neem',
        'Neem Shakti',
        skuId: 'sku-neem',
        pack: '500 ml',
        price: 42000,
        ownBrand: true,
      ),
      product(
        'p-dap',
        'DAP 18-46-0',
        skuId: 'sku-dap',
        pack: '50 kg',
        price: 135000,
        category: 'fertiliser',
      ),
    ];
    kisan.prices
      ..['sku-neem'] = 42000
      ..['sku-dap'] = 135000;
    khataApi.khatas[farmerId] = khataOf(khataBalance);
  }

  /// Seeds the M7 advisory data: the crop calendar, the farm forecast and
  /// one district alert.
  void seedAdvisory({
    bool calendar = true,
    bool weather = true,
    bool alerts = true,
  }) {
    if (calendar) advisory.calendarBody = calendarBody();
    if (weather) advisory.weatherByFarm['farm-1'] = weatherBody();
    if (alerts) {
      advisory.districts.add('Medak');
      advisory.alertRows.add(alertRow());
    }
  }

  /// Fills the advisory caches the way a refresh would, so a screen opens
  /// with data even when the test runs it offline.
  Future<void> primeAdvisory() async {
    final c = container();
    await c.read(kisanRepositoryProvider).refreshProfile();
    final repo = c.read(advisoryRepositoryProvider);
    await repo.refreshCalendar();
    await repo.refreshWeather('farm-1');
    await repo.refreshAlerts();
    await repo.refreshInbox();
    c.dispose();
  }

  /// Seeds the M8 fake API (FM-012 prices, FM-013 referral).
  void seedMarket({bool prices = true, bool referral = true}) {
    if (prices) market.mandiPricesBody = mandiPricesBody();
    if (referral) market.referralBody = referralBody();
  }

  /// Fills the M8 caches so the screens open with data.
  Future<void> primeMarket() async {
    final c = container();
    final repo = c.read(marketRepositoryProvider);
    await repo.refreshPrices();
    await repo.refreshReferral();
    c.dispose();
  }

  /// Signs the farmer in (farmer id known, welcome done) for screens
  /// behind the login.
  Future<void> signIn({bool welcomeDone = true}) async {
    await db.setValue(KisanRepository.farmerIdKey, farmerId);
    if (welcomeDone) await db.setValue(KisanRepository.welcomeDoneKey, 'true');
  }

  /// Provider overrides.
  List<Override> overrides({
    String initialLocation = AppRoutes.home,
    Locale locale = const Locale('en'),
    AppThemeMode theme = AppThemeMode.light,
  }) => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now),
    idGeneratorProvider.overrideWithValue(ids.call),
    kisanApiProvider.overrideWithValue(kisan),
    advisoryApiProvider.overrideWithValue(advisory),
    marketApiProvider.overrideWithValue(market),
    textSharerProvider.overrideWithValue(sharer),
    pushServiceProvider.overrideWithValue(push),
    ...advisoryPushOverrides,
    pushAppVersionProvider.overrideWithValue('0.1.0+1'),
    pushDeviceIdProvider.overrideWithValue('dev-1'),
    authApiProvider.overrideWithValue(auth),
    paymentsApiProvider.overrideWithValue(payApi),
    khataApiProvider.overrideWithValue(khataApi),
    catalogApiProvider.overrideWithValue(catalogApi),
    syncApiProvider.overrideWithValue(syncApi),
    connectivityMonitorProvider.overrideWithValue(connectivity),
    audioPromptProvider.overrideWithValue(audio),
    urlOpenerProvider.overrideWithValue(urls),
    barcodeScannerProvider.overrideWithValue(scanner),
    tokenStoreProvider.overrideWithValue(InMemoryTokenStore(deviceId: 'dev-1')),
    mapTileProviderProvider.overrideWithValue(BlankTileProvider()),
    paymentTickerProvider.overrideWithValue(const Stream<void>.empty()),
    guidedCameraFactoryProvider.overrideWithValue(() => camera),
    onDeviceQualityModelProvider.overrideWithValue(quality),
    diagnosisPhotoPipelineProvider.overrideWithValue(
      DiagnosisPhotoPipeline(
        model: quality,
        process: (bytes, time) async => processPhotoSync(
          PhotoProcessRequest(bytes: bytes, captureTime: time),
        ),
      ),
    ),
    diagnosisApiProvider.overrideWithValue(diagnosisApi),
    photoStoreProvider.overrideWithValue(photos),
    fileReaderProvider.overrideWithValue((path) async => photos.files[path]!),
    onDeviceCropGuessFlagProvider.overrideWithValue(cropGuessFlag),
    captureClockProvider.overrideWithValue(() => now),
    diagnosisPollSleepProvider.overrideWithValue((d) {
      final c = Completer<void>();
      diagnosisPolls.add(c);
      return c.future;
    }),
    upiSleepProvider.overrideWithValue((d) {
      final c = Completer<void>();
      polls.add(c);
      return c.future;
    }),
    settingsStoreProvider.overrideWithValue(
      InMemorySettingsStore(AppSettings(locale: locale, themeMode: theme)),
    ),
    initialSettingsProvider.overrideWithValue(
      AppSettings(locale: locale, themeMode: theme),
    ),
    routerProvider.overrideWithValue(
      buildRouter(initialLocation: initialLocation),
    ),
  ];

  /// The app at [initialLocation].
  Widget app({
    String initialLocation = AppRoutes.home,
    Locale locale = const Locale('en'),
    AppThemeMode theme = AppThemeMode.light,
  }) => ProviderScope(
    overrides: overrides(
      initialLocation: initialLocation,
      locale: locale,
      theme: theme,
    ),
    child: const KisanApp(),
  );

  /// A bare container.
  ProviderContainer container() => ProviderContainer(overrides: overrides());

  /// Closes everything.
  Future<void> dispose() async {
    await push.dispose();
    await connectivity.dispose();
    await db.close();
  }
}

/// Sets the test surface to the reference phone (360x800 at 1x).
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps [app] and lets the database streams settle (real async for Drift).
Future<void> pumpApp(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await settle(tester);
}

/// Lets the database streams and fakes answer, then settles frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view and taps it.
Future<void> tapIt(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await settle(tester);
}

/// Runs real async work (database, fakes) from a widget test body.
Future<T> real<T>(WidgetTester tester, Future<T> Function() work) async =>
    (await tester.runAsync(work)) as T;

/// Scrolls the main list until [finder] is built and visible.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// Pumps (letting real async work run) until [finder] shows up, for screens
/// with an endless spinner while they wait (pumpAndSettle cannot settle).
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxTries = 200,
}) async {
  for (var i = 0; i < maxTries && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
  await settle(tester);
}
