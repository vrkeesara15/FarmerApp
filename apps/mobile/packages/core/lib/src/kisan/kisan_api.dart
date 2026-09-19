import '../catalog/rest_json_client.dart';

/// The farmer app's REST calls (FM-001 .. FM-015). Every call answers a
/// [RestResponse]: status 0 means the request never reached the server.
///
/// Money, stock and khata calls reuse the shared clients (`PaymentsApi`,
/// `KhataApi`, `CatalogApi`); offline writes go through the sync outbox.
abstract interface class KisanApi {
  /// `GET /v1/farmers?limit=1`: the farmer role sees only its own record.
  Future<RestResponse> ownFarmer();

  /// `GET /v1/farmers/{id}`: farms, crop plots and consent history.
  Future<RestResponse> farmer(String id);

  /// `POST /v1/farmers/{id}/consents` `{purpose, granted, language}`; the
  /// server records `channel: app` and the tenant's consent version.
  Future<RestResponse> recordConsent(
    String farmerId, {
    required String purpose,
    required bool granted,
    String? language,
  });

  /// `PATCH /v1/farmers/{id}` (`FarmerUpdate`).
  Future<RestResponse> updateFarmer(String id, Map<String, Object?> body);

  /// `PATCH /v1/farms/{id}` (`FarmUpdate`).
  Future<RestResponse> updateFarm(String id, Map<String, Object?> body);

  /// `PATCH /v1/crop-plots/{id}` (`CropPlotUpdate`).
  Future<RestResponse> updateCropPlot(String id, Map<String, Object?> body);

  /// `POST /v1/farmers/{id}/farms` (`FarmCreate` with crop plots).
  Future<RestResponse> createFarm(String farmerId, Map<String, Object?> body);

  /// `GET /v1/orders?limit=50` (own orders, newest first).
  Future<RestResponse> orders();

  /// `GET /v1/orders/{id}` (`OrderDetailOut`).
  Future<RestResponse> order(String id);

  /// `POST /v1/orders` (`OrderCreate`; a farmer orders for themselves).
  Future<RestResponse> placeOrder(Map<String, Object?> body);

  /// `POST /v1/visits/{id}/farmer-confirm` `{token, rating?, reason?}`.
  Future<RestResponse> farmerConfirm(
    String visitId, {
    required String token,
    int? rating,
    String? reason,
  });

  /// `POST /v1/me/deletion-request {reason?}` →
  /// `{ticket_id, status: "received", due_by}`.
  Future<RestResponse> requestDeletion({String? reason});

  /// `GET /v1/me/deletion-request` (404 when none).
  Future<RestResponse> deletionRequest();
}

/// [KisanApi] over HTTP.
class HttpKisanApi implements KisanApi {
  /// Creates the client.
  HttpKisanApi(this._rest);

  final RestJsonClient _rest;

  @override
  Future<RestResponse> ownFarmer() =>
      _rest.get('/v1/farmers', query: const <String, Object?>{'limit': 1});

  @override
  Future<RestResponse> farmer(String id) => _rest.get('/v1/farmers/$id');

  @override
  Future<RestResponse> recordConsent(
    String farmerId, {
    required String purpose,
    required bool granted,
    String? language,
  }) => _rest.post('/v1/farmers/$farmerId/consents', <String, Object?>{
    'purpose': purpose,
    'granted': granted,
    'language': ?language,
  });

  @override
  Future<RestResponse> updateFarmer(String id, Map<String, Object?> body) =>
      _rest.patch('/v1/farmers/$id', body);

  @override
  Future<RestResponse> updateFarm(String id, Map<String, Object?> body) =>
      _rest.patch('/v1/farms/$id', body);

  @override
  Future<RestResponse> updateCropPlot(String id, Map<String, Object?> body) =>
      _rest.patch('/v1/crop-plots/$id', body);

  @override
  Future<RestResponse> createFarm(String farmerId, Map<String, Object?> body) =>
      _rest.post('/v1/farmers/$farmerId/farms', body);

  @override
  Future<RestResponse> orders() =>
      _rest.get('/v1/orders', query: const <String, Object?>{'limit': 50});

  @override
  Future<RestResponse> order(String id) => _rest.get('/v1/orders/$id');

  @override
  Future<RestResponse> placeOrder(Map<String, Object?> body) =>
      _rest.post('/v1/orders', body);

  @override
  Future<RestResponse> farmerConfirm(
    String visitId, {
    required String token,
    int? rating,
    String? reason,
  }) => _rest.post('/v1/visits/$visitId/farmer-confirm', <String, Object?>{
    'token': token,
    'rating': ?rating,
    'reason': ?reason,
  });

  @override
  Future<RestResponse> requestDeletion({String? reason}) => _rest.post(
    '/v1/me/deletion-request',
    <String, Object?>{'reason': ?reason},
  );

  @override
  Future<RestResponse> deletionRequest() =>
      _rest.get('/v1/me/deletion-request');
}

/// In-memory farmer API for tests and previews: one farmer, their orders,
/// visit tokens and the deletion request, with the server's rules that the
/// screens depend on (versions, `credit_limit_exceeded`, token checks).
class FakeKisanApi implements KisanApi {
  /// Creates the fake.
  FakeKisanApi({DateTime Function()? clock, this.farmerRecord})
    : _now = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _now;

  /// `FarmerDetailOut` of the signed-in farmer (null: no record).
  Map<String, Object?>? farmerRecord;

  /// Every call answers status 0 while true.
  bool offline = false;

  /// Calls made, e.g. `GET /v1/farmers/f-1`.
  final List<String> calls = <String>[];

  /// Bodies of the writes, by call.
  final List<(String, Map<String, Object?>)> writes =
      <(String, Map<String, Object?>)>[];

  /// `OrderDetailOut` by id.
  final Map<String, Map<String, Object?>> ordersById =
      <String, Map<String, Object?>>{};

  /// Unit price per SKU (paise).
  final Map<String, int> prices = <String, int>{};

  /// Credit orders are refused with 402 while true.
  bool creditLimitExceeded = false;

  /// Valid confirmation token per visit id.
  final Map<String, String> visitTokens = <String, String>{};

  /// Confirmed visits: `(rating, reason)`.
  final Map<String, (int?, String?)> confirmedVisits =
      <String, (int?, String?)>{};

  /// The deletion request, once made.
  Map<String, Object?>? deletion;

  /// The deletion endpoint is not deployed yet (404 on POST too).
  bool deletionMissing = false;

  int _n = 0;

  RestResponse _answer(int status, [Map<String, Object?>? body]) =>
      RestResponse(status, body ?? const <String, Object?>{});

  Future<RestResponse> _handle(
    String call,
    RestResponse Function() answer, {
    Map<String, Object?>? body,
  }) async {
    calls.add(call);
    if (body != null) writes.add((call, body));
    if (offline) return const RestResponse(0);
    return answer();
  }

  String _iso() => _now().toIso8601String();

  List<Map<String, Object?>> _farms() => <Map<String, Object?>>[
    for (final f in (farmerRecord?['farms'] as List?) ?? const <Object?>[])
      if (f is Map<String, Object?>) f,
  ];

  @override
  Future<RestResponse> ownFarmer() => _handle('GET /v1/farmers', () {
    final f = farmerRecord;
    return _answer(200, <String, Object?>{
      'items': <Object?>[?f],
      'next_cursor': null,
    });
  });

  @override
  Future<RestResponse> farmer(String id) => _handle('GET /v1/farmers/$id', () {
    final f = farmerRecord;
    if (f == null || f['id'] != id) {
      return _answer(404, <String, Object?>{'code': 'not_found'});
    }
    return _answer(200, f);
  });

  @override
  Future<RestResponse> recordConsent(
    String farmerId, {
    required String purpose,
    required bool granted,
    String? language,
  }) => _handle(
    'POST /v1/farmers/$farmerId/consents',
    () {
      final f = farmerRecord;
      if (f == null || f['id'] != farmerId) {
        return _answer(404, <String, Object?>{'code': 'not_found'});
      }
      final row = <String, Object?>{
        'id': 'consent-${++_n}',
        'subject_id': farmerId,
        'purpose': purpose,
        'version': '2026-09-v1',
        'language': language,
        'granted_at': granted ? _iso() : null,
        'withdrawn_at': granted ? null : _iso(),
        'channel': 'app',
        'recorded_by': null,
        'created_at': _iso(),
      };
      f['consents'] = <Object?>[
        ...(f['consents'] as List?) ?? <Object?>[],
        row,
      ];
      if (purpose == 'marketing') f['consent_marketing'] = granted;
      return _answer(201, row);
    },
    body: <String, Object?>{
      'purpose': purpose,
      'granted': granted,
      'language': language,
    },
  );

  RestResponse _patch(Map<String, Object?>? row, Map<String, Object?> body) {
    if (row == null) {
      return _answer(404, <String, Object?>{'code': 'not_found'});
    }
    final expected = body['version'];
    if (expected is int && expected != row['version']) {
      return _answer(409, <String, Object?>{'code': 'version_conflict'});
    }
    for (final e in body.entries) {
      if (e.key != 'version') row[e.key] = e.value;
    }
    row['version'] = ((row['version'] as num?)?.toInt() ?? 0) + 1;
    row['updated_at'] = _iso();
    return _answer(200, row);
  }

  @override
  Future<RestResponse> updateFarmer(String id, Map<String, Object?> body) =>
      _handle(
        'PATCH /v1/farmers/$id',
        () => _patch(farmerRecord?['id'] == id ? farmerRecord : null, body),
        body: body,
      );

  @override
  Future<RestResponse> updateFarm(String id, Map<String, Object?> body) =>
      _handle(
        'PATCH /v1/farms/$id',
        () => _patch(_farms().where((f) => f['id'] == id).firstOrNull, body),
        body: body,
      );

  @override
  Future<RestResponse> updateCropPlot(String id, Map<String, Object?> body) =>
      _handle('PATCH /v1/crop-plots/$id', () {
        for (final f in _farms()) {
          for (final p in (f['crop_plots'] as List?) ?? const <Object?>[]) {
            if (p is Map<String, Object?> && p['id'] == id) {
              return _patch(p, body);
            }
          }
        }
        return _answer(404, <String, Object?>{'code': 'not_found'});
      }, body: body);

  @override
  Future<RestResponse> createFarm(String farmerId, Map<String, Object?> body) =>
      _handle('POST /v1/farmers/$farmerId/farms', () {
        final f = farmerRecord;
        if (f == null || f['id'] != farmerId) {
          return _answer(404, <String, Object?>{'code': 'not_found'});
        }
        final farmId = (body['id'] as String?) ?? 'farm-${++_n}';
        final farm = <String, Object?>{
          ...body,
          'id': farmId,
          'farmer_id': farmerId,
          'version': 1,
          'crop_plots': <Object?>[
            for (final p in (body['crop_plots'] as List?) ?? const <Object?>[])
              if (p is Map)
                <String, Object?>{
                  ...Map<String, Object?>.from(p),
                  'id': p['id'] ?? 'plot-${++_n}',
                  'farm_id': farmId,
                  'version': 1,
                },
          ],
        };
        f['farms'] = <Object?>[..._farms(), farm];
        return _answer(201, farm);
      }, body: body);

  @override
  Future<RestResponse> orders() => _handle('GET /v1/orders', () {
    final items = ordersById.values.toList()
      ..sort((a, b) => '${b['placed_at']}'.compareTo('${a['placed_at']}'));
    return _answer(200, <String, Object?>{'items': items, 'next_cursor': null});
  });

  @override
  Future<RestResponse> order(String id) => _handle('GET /v1/orders/$id', () {
    final o = ordersById[id];
    if (o == null) return _answer(404, <String, Object?>{'code': 'not_found'});
    return _answer(200, o);
  });

  @override
  Future<RestResponse> placeOrder(Map<String, Object?> body) =>
      _handle('POST /v1/orders', () {
        final mode = body['payment_mode'] as String?;
        if (mode == 'credit' && creditLimitExceeded) {
          return _answer(402, <String, Object?>{
            'code': 'credit_limit_exceeded',
            'errors': <Object?>[
              <String, Object?>{'approval_request_id': 'approval-${++_n}'},
            ],
          });
        }
        final id = (body['id'] as String?) ?? 'order-${++_n}';
        var total = 0;
        final lines = <Map<String, Object?>>[];
        for (final l in (body['lines'] as List?) ?? const <Object?>[]) {
          if (l is! Map) continue;
          final sku = '${l['sku_id']}';
          final qty = (l['qty'] as num?)?.toInt() ?? 1;
          final line = (prices[sku] ?? 10000) * qty;
          total += line;
          lines.add(<String, Object?>{
            'sku_id': sku,
            'qty': '$qty',
            'line_total_paise': line,
          });
        }
        final order = <String, Object?>{
          'id': id,
          'farmer_id': farmerRecord?['id'],
          'store_id': body['store_id'] ?? 'store-1',
          'channel': 'farmer_app',
          'status': 'placed',
          'fulfilment': body['fulfilment'] ?? 'pickup',
          'total_paise': total,
          'placed_at': _iso(),
          'created_at': _iso(),
          'lines': lines,
          'payments': <Object?>[
            if (mode == 'credit')
              <String, Object?>{
                'mode': 'credit',
                'status': 'paid',
                'amount_paise': total,
              },
          ],
          'events': <Object?>[
            <String, Object?>{'to_status': 'placed', 'created_at': _iso()},
          ],
          'version': 1,
        };
        ordersById[id] = order;
        return _answer(201, order);
      }, body: body);

  /// Moves an order on (store side) and records the event.
  void advanceOrder(String id, String status) {
    final o = ordersById[id]!;
    o['status'] = status;
    o['events'] = <Object?>[
      ...(o['events'] as List?) ?? <Object?>[],
      <String, Object?>{'to_status': status, 'created_at': _iso()},
    ];
  }

  /// Marks an order paid by [mode].
  void markOrderPaid(String id, {String mode = 'upi_qr'}) {
    final o = ordersById[id]!;
    o['payments'] = <Object?>[
      ...(o['payments'] as List?) ?? <Object?>[],
      <String, Object?>{
        'mode': mode,
        'status': 'paid',
        'amount_paise': o['total_paise'],
      },
    ];
  }

  @override
  Future<RestResponse> farmerConfirm(
    String visitId, {
    required String token,
    int? rating,
    String? reason,
  }) => _handle(
    'POST /v1/visits/$visitId/farmer-confirm',
    () {
      if (confirmedVisits.containsKey(visitId)) {
        return _answer(409, <String, Object?>{
          'code': 'visit_already_confirmed',
        });
      }
      if (visitTokens[visitId] != token) {
        return _answer(422, <String, Object?>{
          'code': 'confirmation_token_invalid',
        });
      }
      confirmedVisits[visitId] = (rating, reason);
      return _answer(200, <String, Object?>{
        'id': 'conf-${++_n}',
        'visit_id': visitId,
        'status': 'confirmed',
        'confirmed_at': _iso(),
        'rating': rating,
        'rating_reason': reason,
      });
    },
    body: <String, Object?>{'token': token, 'rating': rating, 'reason': reason},
  );

  @override
  Future<RestResponse> requestDeletion({String? reason}) =>
      _handle('POST /v1/me/deletion-request', () {
        if (deletionMissing) {
          return _answer(404, <String, Object?>{'code': 'not_found'});
        }
        return _answer(
          201,
          deletion ??= <String, Object?>{
            'ticket_id': 'DEL-${1000 + ++_n}',
            'status': 'received',
            'due_by': _now().add(const Duration(days: 30)).toIso8601String(),
          },
        );
      }, body: <String, Object?>{'reason': reason});

  @override
  Future<RestResponse> deletionRequest() =>
      _handle('GET /v1/me/deletion-request', () {
        final d = deletion;
        if (d == null) {
          return _answer(404, <String, Object?>{'code': 'not_found'});
        }
        return _answer(200, d);
      });
}
