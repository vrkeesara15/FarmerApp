import '../catalog/rest_json_client.dart';

/// FM-012 mandi prices and FM-013 referrals: the farmer app's M8 REST calls.
/// Every call answers a [RestResponse]; status 0 means the request never
/// reached the server.
abstract interface class MarketApi {
  /// `GET /v1/me/mandi-prices?markets=`.
  Future<RestResponse> mandiPrices({int markets = 5});

  /// `GET /v1/me/referral`.
  Future<RestResponse> referral();

  /// `POST /v1/me/referral/invites` `{phone?}`.
  Future<RestResponse> createInvite({String? phone});

  /// `POST /v1/me/referral/claim` `{code}` — the code from the invite link.
  Future<RestResponse> claimReferral(String code);
}

/// [MarketApi] over HTTP.
class HttpMarketApi implements MarketApi {
  /// Creates the client.
  HttpMarketApi(this._rest);

  final RestJsonClient _rest;

  @override
  Future<RestResponse> mandiPrices({int markets = 5}) => _rest.get(
    '/v1/me/mandi-prices',
    query: <String, Object?>{'markets': markets},
  );

  @override
  Future<RestResponse> referral() => _rest.get('/v1/me/referral');

  @override
  Future<RestResponse> createInvite({String? phone}) =>
      _rest.post('/v1/me/referral/invites', <String, Object?>{'phone': ?phone});

  @override
  Future<RestResponse> claimReferral(String code) =>
      _rest.post('/v1/me/referral/claim', <String, Object?>{'code': code});
}

/// In-memory [MarketApi] for tests and previews.
class FakeMarketApi implements MarketApi {
  /// Creates the fake.
  FakeMarketApi();

  /// Every call answers status 0 while true.
  bool offline = false;

  /// Calls made, e.g. `GET /v1/me/mandi-prices`.
  final List<String> calls = <String>[];

  /// Bodies of the writes, by call.
  final List<(String, Map<String, Object?>)> writes =
      <(String, Map<String, Object?>)>[];

  /// `MandiPricesOut` body (null: nothing held yet).
  Map<String, Object?>? mandiPricesBody;

  /// `MyReferralOut` body (null: no referral profile yet).
  Map<String, Object?>? referralBody;

  /// Status the next claim answers with (201 by default).
  int claimStatus = 201;

  /// Problem code the next claim answers with when [claimStatus] is not 2xx.
  String claimProblem = 'referral_code_unknown';

  RestResponse _answer(int status, [Map<String, Object?>? body]) =>
      RestResponse(status, body ?? const <String, Object?>{});

  RestResponse _handle(
    String call,
    RestResponse Function() answer, {
    Map<String, Object?>? body,
  }) {
    calls.add(call);
    if (body != null) writes.add((call, body));
    if (offline) return const RestResponse(0);
    return answer();
  }

  @override
  Future<RestResponse> mandiPrices({int markets = 5}) async => _handle(
    'GET /v1/me/mandi-prices',
    () => mandiPricesBody == null
        ? _answer(404, <String, Object?>{'code': 'not_found'})
        : _answer(200, mandiPricesBody),
  );

  @override
  Future<RestResponse> referral() async => _handle(
    'GET /v1/me/referral',
    () => referralBody == null
        ? _answer(404, <String, Object?>{'code': 'not_found'})
        : _answer(200, referralBody),
  );

  @override
  Future<RestResponse> createInvite({String? phone}) async => _handle(
    'POST /v1/me/referral/invites',
    () => _answer(201, <String, Object?>{'status': 'pending'}),
    body: <String, Object?>{'phone': ?phone},
  );

  @override
  Future<RestResponse> claimReferral(String code) async => _handle(
    'POST /v1/me/referral/claim',
    () => claimStatus >= 200 && claimStatus < 300
        ? _answer(claimStatus, <String, Object?>{
            'status': 'attributed',
            'code': code,
          })
        : _answer(claimStatus, <String, Object?>{'code': claimProblem}),
    body: <String, Object?>{'code': code},
  );
}
