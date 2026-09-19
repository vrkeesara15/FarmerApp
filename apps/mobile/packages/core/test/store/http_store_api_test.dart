import 'dart:convert';
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// [HttpStoreApi] against a `MockClient`: the openapi.yaml request shapes
/// of the store endpoints, problem codes and offline mapping.
void main() {
  final session = AuthSession(
    accessToken: 'tok',
    refreshToken: 'r',
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    user: const AuthUser(
      id: 'u',
      tenantId: 't',
      phone: '+919876543210',
      name: 'Manager',
      role: 'store_manager',
      language: 'en',
      status: 'active',
      storeId: 'store-knd',
    ),
  );

  late List<http.Request> seen;

  HttpStoreApi api(http.Response Function(http.Request r) handler) {
    seen = <http.Request>[];
    return HttpStoreApi(
      store: InMemoryTokenStore(deviceId: 'd', session: session),
      config: const ApiConfig(baseUrl: 'http://api.test'),
      ids: () => 'idem-1',
      client: MockClient((r) async {
        seen.add(r);
        return handler(r);
      }),
    );
  }

  Map<String, dynamic> body(http.Request r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );

  test(
    'barcode lookup: store price, product nested; 404 = not found',
    () async {
      final client = api((r) {
        if (r.url.path.endsWith('/8901234500011')) {
          return json(<String, Object?>{
            'id': 'sku-1',
            'product_id': 'p-1',
            'pack_label': '250 ml',
            'barcode': '8901234500011',
            'mrp_paise': 48000,
            'price_paise': 42000,
            'active': true,
            'product': <String, Object?>{
              'id': 'p-1',
              'name': 'Imidacloprid 17.8% SL',
              'brand': 'FCC Shakti',
              'own_brand': true,
              'category': 'pesticide',
              'hsn': '38089199',
              'gst_rate_bp': 1800,
            },
          });
        }
        return json(<String, Object?>{'code': 'not_found', 'status': 404}, 404);
      });
      final found = await client.barcode('8901234500011', 'store-knd');
      expect(found.ok, isTrue);
      expect(found.value!.pricePaise, 42000);
      expect(found.value!.ownBrand, isTrue);
      expect(found.value!.gstRateBp, 1800);
      expect(seen.single.url.queryParameters['store_id'], 'store-knd');
      expect(seen.single.headers['Authorization'], 'Bearer tok');
      final missing = await client.barcode('000', 'store-knd');
      expect(missing.ok, isFalse);
      expect(missing.failure!.status, 404);
      expect(missing.failure!.isOffline, isFalse);
    },
  );

  test('POS sale body, idempotency key and invoice parsing', () async {
    final client = api(
      (r) => json(<String, Object?>{
        'order_id': 'o-1',
        'invoice': <String, Object?>{
          'id': 'inv-1',
          'order_id': 'o-1',
          'invoice_no': 'FCC/KND/2026-27/000123',
          'issued_at': '2026-09-20T05:42:00Z',
          'seller_name': 'FCC',
          'seller_gstin': '36AAAAA0000A1Z5',
          'buyer_name': 'Walk-in',
          'supply_type': 'intra',
          'taxable_paise': 84000,
          'cgst_paise': 7560,
          'sgst_paise': 7560,
          'igst_paise': 0,
          'round_off_paise': -20,
          'total_paise': 99100,
          'amount_in_words': 'Rupees Nine Hundred Ninety-One Only',
          'lines': <Object?>[
            <String, Object?>{
              'sl': 1,
              'description': 'Imidacloprid 250 ml',
              'hsn': '38089199',
              'qty': '2.000',
              'unit_price_paise': 42000,
              'taxable_paise': 84000,
              'gst_rate_bp': 1800,
              'cgst_paise': 7560,
              'sgst_paise': 7560,
              'igst_paise': 0,
            },
          ],
          'has_pdf': true,
        },
        'payment': <String, Object?>{
          'payment_id': 'pay-1',
          'mode': 'card_terminal',
          'status': 'paid',
          'amount_paise': 99100,
          'store_id': 'store-knd',
        },
      }, 201),
    );
    final result = await client.posSale(
      'store-knd',
      PosSaleRequest(
        lines: <StoreCartLine>[StoreCartLine(item: demoCatalog.first, qty: 2)],
        mode: SaleMode.card,
        farmerPhone: '+919000011122',
        referenceNote: 'TID 4471',
      ),
    );
    expect(result.ok, isTrue);
    final r = seen.single;
    expect(r.url.path, '/v1/stores/store-knd/pos/sales');
    expect(r.headers['Idempotency-Key'], 'idem-1');
    expect(jsonDecode(r.body), <String, Object?>{
      'farmer_phone': '+919000011122',
      'lines': <Object?>[
        <String, Object?>{'sku_id': 'sku-imd-250', 'qty': 2},
      ],
      'payment': <String, Object?>{
        'mode': 'card_terminal',
        'reference_note': 'TID 4471',
      },
    });
    final inv = result.value!.invoice;
    expect(inv.invoiceNo, 'FCC/KND/2026-27/000123');
    expect(inv.lines.single.qty, 2);
    expect(inv.lines.single.totalPaise, 84000 + 15120);
    expect(result.value!.payment.settled, isTrue);
  });

  test('credit_limit_exceeded carries the approval extras', () async {
    final client = api(
      (r) => json(<String, Object?>{
        'code': 'credit_limit_exceeded',
        'status': 402,
        'shortfall_paise': 650000,
        'approval_request_id': 'apr-1',
        'balance_paise': 3400000,
        'limit_paise': 4000000,
      }, 402),
    );
    final result = await client.posSale(
      'store-knd',
      PosSaleRequest(
        lines: <StoreCartLine>[StoreCartLine(item: demoCatalog.first, qty: 1)],
        mode: SaleMode.credit,
        farmerId: 'f-1',
      ),
    );
    expect(result.failure!.code, 'credit_limit_exceeded');
    expect(result.failure!.intExtra('shortfall_paise'), 650000);
    expect(body(seen.single)['farmer_id'], 'f-1');
  });

  test('POS preview posts the sale body and parses PosPreviewOut', () async {
    final client = api(
      (r) => json(<String, Object?>{
        'store_id': 'store-knd',
        'supply_type': 'intra',
        'taxable_paise': 84000,
        'cgst_paise': 7560,
        'sgst_paise': 7560,
        'igst_paise': 0,
        'tax_paise': 15120,
        'round_off_paise': -20,
        'total_paise': 99100,
        'amount_in_words': 'Rupees Nine Hundred Ninety One Only',
        'lines': <Object?>[
          <String, Object?>{
            'sl': 1,
            'description': 'Imidacloprid 250 ml',
            'hsn': '38089199',
            'qty': '2',
            'unit_price_paise': 42000,
            'taxable_paise': 84000,
            'gst_rate_bp': 1800,
            'cgst_paise': 7560,
            'sgst_paise': 7560,
            'igst_paise': 0,
          },
        ],
      }),
    );
    final result = await client.posPreview(
      'store-knd',
      PosSaleRequest(
        lines: <StoreCartLine>[StoreCartLine(item: demoCatalog.first, qty: 2)],
        mode: SaleMode.credit,
        farmerId: 'f-1',
        creditApprovalRequestId: 'apr-9',
      ),
    );
    final r = seen.single;
    expect(r.method, 'POST');
    expect(r.url.path, '/v1/stores/store-knd/pos/preview');
    expect(body(r)['credit_approval_request_id'], 'apr-9');
    expect(body(r)['payment'], <String, Object?>{'mode': 'credit'});
    final p = result.value!;
    expect(p.estimate, isFalse);
    expect(p.totalPaise, 99100);
    expect(p.roundOffPaise, -20);
    expect(p.lines.single.hsn, '38089199');
    expect(p.amountInWords, startsWith('Rupees'));
    // A non-credit sale never sends the approval key.
    expect(
      const PosSaleRequest(
        lines: <StoreCartLine>[],
        mode: SaleMode.cash,
        creditApprovalRequestId: 'apr-9',
      ).toJson().containsKey('credit_approval_request_id'),
      isFalse,
    );
  });

  test(
    'transfer destinations: from_store_id, nearest first; 403 codes',
    () async {
      final client = api((r) {
        if (r.url.queryParameters['from_store_id'] == 'store-x') {
          return json(<String, Object?>{
            'code': 'transfer_source_not_allowed',
            'status': 403,
          }, 403);
        }
        return json(<String, Object?>{
          'from_store_id': 'store-knd',
          'items': <Object?>[
            <String, Object?>{
              'id': 'store-sgr',
              'code': 'SGR',
              'name': 'Sangareddy FCC',
              'district': 'Sangareddy',
              'cluster_id': 'c-1',
              'distance_m': 38400.5,
            },
          ],
        });
      });
      final list = await client.transferDestinations(fromStoreId: 'store-knd');
      expect(seen.single.url.path, '/v1/stock/transfer-destinations');
      expect(seen.single.url.queryParameters, <String, String>{
        'from_store_id': 'store-knd',
      });
      expect(list.value!.single.name, 'Sangareddy FCC');
      expect(list.value!.single.distanceM, 38400.5);
      final refused = await client.transferDestinations(fromStoreId: 'store-x');
      expect(refused.failure!.status, 403);
      expect(refused.failure!.code, 'transfer_source_not_allowed');
    },
  );

  test('credit approvals filter by status and farmer', () async {
    final client = api(
      (r) => json(<String, Object?>{'items': <Object?>[], 'next_cursor': null}),
    );
    await client.creditApprovals(status: 'approved', farmerId: 'f-1');
    expect(seen.single.url.queryParameters['status'], 'approved');
    expect(seen.single.url.queryParameters['farmer_id'], 'f-1');
  });

  test('transport errors and gateway 503 are offline', () async {
    final down = HttpStoreApi(
      store: InMemoryTokenStore(deviceId: 'd', session: session),
      config: const ApiConfig(baseUrl: 'http://api.test'),
      client: MockClient((_) async => throw http.ClientException('down')),
    );
    expect((await down.daySummary('s')).failure!.isOffline, isTrue);
    final gateway = api((_) => http.Response('', 503));
    expect((await gateway.stores()).failure!.isOffline, isTrue);
  });

  test('queue asks for the tab statuses and follows cursors', () async {
    var page = 0;
    final client = api((r) {
      page++;
      return json(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'id': 'o-$page',
            'status': 'reserved',
            'channel': 'officer',
            'total_paise': 100,
            'lines': <Object?>[],
          },
        ],
        'next_cursor': page == 1 ? 'c2' : null,
      });
    });
    final result = await client.orderQueue('store-knd');
    expect(result.value!.map((o) => o.id), <String>['o-1', 'o-2']);
    expect(seen.first.url.queryParametersAll['status'], <String>[
      'placed',
      'reserved',
      'packed',
      'ready',
      'handed_over',
      'delivered',
    ]);
    expect(seen.last.url.queryParameters['cursor'], 'c2');
  });

  test(
    'status transition, stock writes, credit and day close shapes',
    () async {
      final client = api((r) {
        if (r.url.path.contains('/status')) {
          return json(<String, Object?>{'code': 'invalid_transition'}, 409);
        }
        if (r.url.path.endsWith('/day-close')) {
          return json(<String, Object?>{'code': 'day_already_closed'}, 409);
        }
        if (r.url.path.contains('credit-limit')) {
          return json(<String, Object?>{
            'code': 'credit_limit_needs_cluster_head',
          }, 403);
        }
        return json(<String, Object?>{
          'ref_type': 'transfer',
          'ref_id': 'ref-1',
          'movements': <Object?>[<String, Object?>{}, <String, Object?>{}],
        }, 201);
      });
      final moved = await client.setOrderStatus('o-1', OrderStatus.packed);
      expect(moved.failure!.code, 'invalid_transition');
      expect(jsonDecode(seen.last.body), <String, Object?>{'status': 'packed'});

      final t = await client.transferStock(
        fromStoreId: 'a',
        toStoreId: 'b',
        lines: <BatchQty>[BatchQty(batch: demoStock.first, qty: 3)],
      );
      expect(t.value!.movementCount, 2);
      expect(jsonDecode(seen.last.body), <String, Object?>{
        'from_store_id': 'a',
        'to_store_id': 'b',
        'lines': <Object?>[
          <String, Object?>{'batch_id': 'b-imd-1', 'qty': '3'},
        ],
      });

      await client.receiveStock('store-knd', <ReceiptLine>[
        ReceiptLine(
          item: demoCatalog.first,
          batchNo: 'IMD2609',
          expiry: DateTime(2027, 9, 30),
          qty: 24,
          costPaise: 33000,
        ),
      ]);
      expect(body(seen.last)['lines'], <Object?>[
        <String, Object?>{
          'sku_id': 'sku-imd-250',
          'batch_no': 'IMD2609',
          'expiry': '2027-09-30',
          'qty': '24',
          'cost_paise': 33000,
        },
      ]);

      await client.writeOff(
        'store-knd',
        line: BatchQty(batch: demoStock.first, qty: 1),
        reason: WriteOffReason.damage,
        photoUri: 'gs://x',
      );
      expect(body(seen.last)['photo_blob_uri'], 'gs://x');
      expect(
        ((body(seen.last)['lines'] as List).first as Map)['reason'],
        'damage',
      );

      final limit = await client.setCreditLimit(
        'f-1',
        storeId: 'store-knd',
        limitPaise: 6000000,
      );
      expect(limit.failure!.code, 'credit_limit_needs_cluster_head');
      expect(seen.last.method, 'PUT');

      final closed = await client.closeDay(
        'store-knd',
        const DayCloseRequest(
          businessDate: '2026-09-20',
          cashCountedPaise: 1240000,
          depositSlipUri: 'gs://slip',
          notes: ' counted twice ',
        ),
      );
      expect(closed.failure!.code, 'day_already_closed');
      expect(jsonDecode(seen.last.body), <String, Object?>{
        'business_date': '2026-09-20',
        'cash_counted_paise': 1240000,
        'deposit_slip_uri': 'gs://slip',
        'notes': 'counted twice',
      });
    },
  );

  test('photo upload: init, chunks with sha, complete', () async {
    final client = api((r) {
      if (r.url.path == '/v1/uploads') {
        return json(<String, Object?>{'upload_id': 'up-1'}, 201);
      }
      if (r.url.path.contains('/chunks/')) {
        return json(<String, Object?>{'upload_id': 'up-1'});
      }
      return json(<String, Object?>{'blob_uri': 'gs://bucket/slip.jpg'});
    });
    final bytes = Uint8List.fromList(
      List<int>.generate(300 * 1024, (i) => i % 251),
    );
    final uri = await client.uploadPhoto(bytes);
    expect(uri.value, 'gs://bucket/slip.jpg');
    expect(seen.map((r) => r.method), <String>['POST', 'PUT', 'PUT', 'POST']);
    expect(body(seen.first)['purpose'], 'receipt');
    expect(seen[1].headers['x-chunk-sha256'], isNotEmpty);
    expect(seen[1].bodyBytes.length, 256 * 1024);
  });
}
