import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';

/// Store of the test village.
const String storeId = 'store-1';

/// A `ProductWithSkusOut` row priced for [storeId].
Map<String, Object?> product(
  String id,
  String name, {
  required List<Map<String, Object?>> skus,
  String brand = 'Sri Rama Agro',
  bool ownBrand = false,
  String category = 'pesticide',
  String? ingredient,
  int gstBp = 1800,
}) => <String, Object?>{
  'id': id,
  'name': name,
  'brand': brand,
  'own_brand': ownBrand,
  'category': category,
  'gst_rate_bp': gstBp,
  'active_ingredient': ingredient,
  'names': const <String, Object?>{},
  'active': true,
  'version': 1,
  'skus': skus,
};

/// A `SkuOut` row.
Map<String, Object?> sku(
  String id,
  String pack, {
  required int mrp,
  int? price,
  String? stock,
}) => <String, Object?>{
  'id': id,
  'pack_label': pack,
  'mrp_paise': mrp,
  'price_paise': price ?? mrp,
  'stock_qty': stock,
  'active': true,
  'version': 1,
};

/// Realistic pilot catalogue for Kondapur Agri Store.
List<Map<String, Object?>> pilotCatalog() => <Map<String, Object?>>[
  product(
    'p-cora',
    'Coragen',
    brand: 'FMC',
    ingredient: 'Chlorantraniliprole 18.5% SC',
    skus: <Map<String, Object?>>[
      sku('sku-cora-150', '150 ml', mrp: 125000, price: 118000, stock: '12'),
    ],
  ),
  product(
    'p-neem',
    'Mitra Neem Shakti',
    ownBrand: true,
    ingredient: 'Azadirachtin 1500 ppm',
    gstBp: 1200,
    skus: <Map<String, Object?>>[
      sku('sku-neem-500', '500 ml', mrp: 45000, price: 42000, stock: '30'),
    ],
  ),
  product(
    'p-dap',
    'DAP 18-46-0',
    brand: 'Coromandel',
    category: 'fertiliser',
    gstBp: 500,
    skus: <Map<String, Object?>>[
      sku('sku-dap-50', '50 kg', mrp: 135000, stock: '40'),
    ],
  ),
  product(
    'p-seed',
    'Bt Cotton RCH 659',
    brand: 'Rasi Seeds',
    category: 'seed',
    gstBp: 0,
    skus: <Map<String, Object?>>[
      sku('sku-seed-450', '450 g', mrp: 86400, stock: '0'),
    ],
  ),
];

/// A farmer khata: balance ₹12,500.00 over four entries.
Map<String, Object?> pilotKhata() {
  Map<String, Object?> entry(
    String id,
    String type,
    int amount,
    String at, {
    String? due,
    String? harvest,
    String ref = 'order',
  }) => <String, Object?>{
    'id': id,
    'farmer_id': 'f-1',
    'store_id': storeId,
    'type': type,
    'amount_paise': amount,
    'signed_paise': type == 'debit' ? amount : -amount,
    'due_date': due,
    'ref_type': ref,
    'harvest_month': harvest,
    'created_at': at,
  };
  return <String, Object?>{
    'farmer_id': 'f-1',
    'balance_paise': 1250000,
    'overdue_paise': 650000,
    'next_due_date': '2026-11-30',
    'balances': <Object?>[
      <String, Object?>{'store_id': storeId, 'balance_paise': 1250000},
    ],
    'credit_limits': <Object?>[
      <String, Object?>{'store_id': storeId, 'limit_paise': 2000000},
    ],
    'overdue_buckets': <String, Object?>{
      '0_30': 250000,
      '31_60': 0,
      '61_90': 400000,
      '90_plus': 0,
    },
    'payment_history': <Object?>[
      <String, Object?>{
        'id': 'pay-old-1',
        'mode': 'cash',
        'amount_paise': 300000,
        'status': 'reconciled',
        'paid_at': '2026-08-10T06:00:00Z',
      },
    ],
    'entries': <Object?>[
      entry(
        'ke-4',
        'debit',
        600000,
        '2026-09-01T05:00:00Z',
        due: '2026-11-30',
        harvest: '2026-11-01',
      ),
      entry('ke-3', 'credit', 300000, '2026-08-10T06:00:00Z', ref: 'payment'),
      entry('ke-2', 'debit', 450000, '2026-06-20T05:00:00Z', due: '2026-08-31'),
      entry('ke-1', 'debit', 500000, '2026-05-02T05:00:00Z', due: '2026-07-01'),
    ],
  };
}

/// Village with a store, farmer `f-1`, the catalogue / nearest store /
/// khata fakes and the money rules on the sync fake.
Future<FakeCommerceServer> seedCommerceWorld(AgentDeps deps) async {
  await LocalEntities(deps.db).writeRef(
    SyncEntities.village,
    'village-1',
    <String, Object?>{
      'name': 'Kondapur',
      'district': 'Medak',
      'mandal': 'Sangareddy',
      'store_id': storeId,
      'lat': farmOrigin.latitude,
      'lon': farmOrigin.longitude,
    },
    version: 1,
    now: t0,
  );
  await seedSyncedFarmer(deps.db, id: 'f-1', phone: '+919876543210');
  deps.catalogApi.productsByStore[storeId] = pilotCatalog();
  deps.catalogApi.nearestByFarmer['f-1'] = const StoreInfo(
    id: storeId,
    code: 'KDP',
    name: 'Kondapur Agri Store',
    district: 'Medak',
  );
  deps.catalogApi.available.addAll(<String, double>{
    '$storeId/sku-cora-150': 12,
    '$storeId/sku-neem-500': 30,
    '$storeId/sku-dap-50': 40,
    '$storeId/sku-seed-450': 0,
  });
  deps.khataApi.khatas['f-1'] = pilotKhata();
  return FakeCommerceServer(
    api: deps.api,
    prices: <String, int>{
      'sku-cora-150': 118000,
      'sku-neem-500': 42000,
      'sku-dap-50': 135000,
    },
    gstBp: <String, int>{
      'sku-cora-150': 1800,
      'sku-neem-500': 1200,
      'sku-dap-50': 500,
    },
    clock: () => deps.now,
  );
}

/// Downloads the catalogue into the cache (as a previous online session did).
Future<void> preloadCatalog(AgentDeps deps) async {
  final offline = deps.catalogApi.offline;
  deps.catalogApi.offline = false;
  final cache = CatalogCache(deps.db, deps.catalogApi, clock: () => deps.now);
  await cache.refresh(storeId: storeId);
  await cache.nearestStore(
    'f-1',
    skuIds: <String>[
      'sku-cora-150',
      'sku-neem-500',
      'sku-dap-50',
      'sku-seed-450',
    ],
  );
  deps.catalogApi
    ..offline = offline
    ..calls.clear();
}

/// Caches the khata (as a previous online session did).
Future<void> preloadKhata(AgentDeps deps) async {
  final offline = deps.khataApi.offline;
  deps.khataApi.offline = false;
  await KhataRepository(
    deps.db,
    deps.khataApi,
    clock: () => deps.now,
  ).refresh('f-1');
  deps.khataApi
    ..offline = offline
    ..fetches = 0;
}

/// The container behind the running app.
ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

/// Scrolls until [finder] is visible and taps it.
Future<void> tapIt(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
