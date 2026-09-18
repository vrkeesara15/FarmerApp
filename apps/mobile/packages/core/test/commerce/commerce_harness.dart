import 'package:farmerapp_core/farmerapp_core.dart';

/// Sunday 2026-09-20 06:00 IST as UTC.
final DateTime t0 = DateTime.utc(2026, 9, 20, 0, 30);

/// Store of the test farmer's village.
const String storeId = 'store-1';

/// A `ProductWithSkusOut` row as the catalogue page sends it for a store.
Map<String, Object?> productJson({
  required String id,
  required String name,
  String brand = 'Sri Rama Agro',
  bool ownBrand = false,
  String category = 'pesticide',
  String? ingredient,
  Map<String, String> names = const <String, String>{},
  int gstBp = 1800,
  List<Map<String, Object?>> skus = const <Map<String, Object?>>[],
}) => <String, Object?>{
  'id': id,
  'tenant_id': 'tenant-1',
  'name': name,
  'brand': brand,
  'own_brand': ownBrand,
  'category': category,
  'hsn': '3808',
  'gst_rate_bp': gstBp,
  'description': null,
  'active_ingredient': ingredient,
  'formulation': null,
  'names': names,
  'image_uri': null,
  'active': true,
  'created_at': '2026-09-01T00:00:00Z',
  'updated_at': '2026-09-01T00:00:00Z',
  'version': 1,
  'skus': skus,
};

/// A `SkuOut` row.
Map<String, Object?> skuJson({
  required String id,
  required String productId,
  required String pack,
  required int mrp,
  int? price,
  String? stock,
}) => <String, Object?>{
  'id': id,
  'product_id': productId,
  'pack_size_value': '1',
  'pack_size_unit': 'l',
  'pack_label': pack,
  'barcode': null,
  'mrp_paise': mrp,
  'active': true,
  'price_paise': price ?? mrp,
  'stock_qty': stock,
  'created_at': '2026-09-01T00:00:00Z',
  'updated_at': '2026-09-01T00:00:00Z',
  'version': 1,
};

/// Four products / five SKUs used across the commerce tests.
List<Map<String, Object?>> sampleCatalog() => <Map<String, Object?>>[
  productJson(
    id: 'p-cora',
    name: 'Coragen',
    brand: 'FMC',
    ingredient: 'Chlorantraniliprole 18.5% SC',
    names: const <String, String>{'te': 'కొరాజెన్'},
    skus: <Map<String, Object?>>[
      skuJson(
        id: 'sku-cora-150',
        productId: 'p-cora',
        pack: '150 ml',
        mrp: 125000,
        price: 118000,
        stock: '12.000',
      ),
    ],
  ),
  productJson(
    id: 'p-mitra',
    name: 'Mitra Neem Shakti',
    ownBrand: true,
    ingredient: 'Azadirachtin 1500 ppm',
    gstBp: 1200,
    skus: <Map<String, Object?>>[
      skuJson(
        id: 'sku-neem-500',
        productId: 'p-mitra',
        pack: '500 ml',
        mrp: 45000,
        price: 42000,
        stock: '30.000',
      ),
      skuJson(
        id: 'sku-neem-1l',
        productId: 'p-mitra',
        pack: '1 l',
        mrp: 85000,
        price: 80000,
        stock: '0.000',
      ),
    ],
  ),
  productJson(
    id: 'p-dap',
    name: 'DAP 18-46-0',
    brand: 'Coromandel',
    category: 'fertiliser',
    gstBp: 500,
    skus: <Map<String, Object?>>[
      skuJson(
        id: 'sku-dap-50',
        productId: 'p-dap',
        pack: '50 kg',
        mrp: 135000,
        stock: '40.000',
      ),
    ],
  ),
  productJson(
    id: 'p-seed',
    name: 'Bt Cotton RCH 659',
    brand: 'Rasi Seeds',
    category: 'seed',
    gstBp: 0,
    skus: <Map<String, Object?>>[
      skuJson(
        id: 'sku-seed-450',
        productId: 'p-seed',
        pack: '450 g',
        mrp: 86400,
        stock: '25.000',
      ),
    ],
  ),
];

/// A catalogue fake with [sampleCatalog] for [storeId].
FakeCatalogApi sampleCatalogApi() => FakeCatalogApi()
  ..productsByStore[storeId] = sampleCatalog()
  ..nearestByFarmer['f-1'] = const StoreInfo(
    id: storeId,
    code: 'KDP',
    name: 'Kondapur Agri Store',
    district: 'Medak',
  );

/// A `KhataEntryOut` row.
Map<String, Object?> khataEntryJson({
  required String id,
  required String type,
  required int amount,
  required String createdAt,
  String? dueDate,
  String? harvestMonth,
  String refType = 'order',
  String store = storeId,
  String? note,
}) => <String, Object?>{
  'id': id,
  'tenant_id': 'tenant-1',
  'farmer_id': 'f-1',
  'store_id': store,
  'type': type,
  'amount_paise': amount,
  'signed_paise': type == 'debit' ? amount : -amount,
  'due_date': dueDate,
  'ref_type': refType,
  'ref_id': null,
  'note': note,
  'harvest_month': harvestMonth,
  'created_by': 'officer-1',
  'created_at': createdAt,
};

/// A farmer khata: 3 debits, 1 payment; balance ₹12,500.
Map<String, Object?> sampleKhata() => <String, Object?>{
  'farmer_id': 'f-1',
  'store_id': null,
  'balance_paise': 1250000,
  'overdue_paise': 650000,
  'next_due_date': '2026-11-30',
  'balances': <Object?>[
    <String, Object?>{'store_id': storeId, 'balance_paise': 1250000},
  ],
  'credit_limits': <Object?>[
    <String, Object?>{
      'id': 'cl-1',
      'farmer_id': 'f-1',
      'store_id': storeId,
      'limit_paise': 2000000,
      'set_by': 'manager-1',
      'approved_by': null,
      'created_at': '2026-06-01T00:00:00Z',
      'updated_at': '2026-06-01T00:00:00Z',
      'version': 1,
    },
  ],
  'open_debits': const <Object?>[],
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
      'created_at': '2026-08-10T06:00:00Z',
    },
  ],
  'entries': <Object?>[
    khataEntryJson(
      id: 'ke-4',
      type: 'debit',
      amount: 600000,
      createdAt: '2026-09-01T05:00:00Z',
      dueDate: '2026-11-30',
      harvestMonth: '2026-11-01',
    ),
    khataEntryJson(
      id: 'ke-3',
      type: 'credit',
      amount: 300000,
      createdAt: '2026-08-10T06:00:00Z',
      refType: 'payment',
      note: 'Payment received',
    ),
    khataEntryJson(
      id: 'ke-2',
      type: 'debit',
      amount: 450000,
      createdAt: '2026-06-20T05:00:00Z',
      dueDate: '2026-08-31',
    ),
    khataEntryJson(
      id: 'ke-1',
      type: 'debit',
      amount: 500000,
      createdAt: '2026-05-02T05:00:00Z',
      dueDate: '2026-07-01',
    ),
  ],
  'next_cursor': null,
};
