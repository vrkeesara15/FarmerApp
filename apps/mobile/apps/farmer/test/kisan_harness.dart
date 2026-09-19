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

/// Everything the farmer screens talk to, scriptable.
class KisanDeps {
  /// Creates the dependencies over an in-memory database.
  KisanDeps({bool online = true})
    : db = openInMemoryDatabase(),
      connectivity = FakeConnectivityMonitor(online: online) {
    kisan = FakeKisanApi(clock: () => now);
    payApi = FakePaymentsApi(clock: () => now);
  }

  /// Farmer REST calls.
  late final FakeKisanApi kisan;

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
