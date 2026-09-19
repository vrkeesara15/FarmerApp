import 'dart:convert';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const Map<String, Object?> _user = <String, Object?>{
  'id': 'u1',
  'tenant_id': 't1',
  'phone': '+919000000004',
  'name': 'Ramesh',
  'role': 'field_officer',
  'store_id': null,
  'cluster_id': null,
  'language': 'te',
  'status': 'active',
};

http.Response _json(int status, Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{
    'content-type': status >= 400
        ? 'application/problem+json'
        : 'application/json',
  },
);

http.Response _problem(
  int status,
  String code, [
  Map<String, Object?>? extra,
]) => _json(status, <String, Object?>{
  'type': 'https://farmerapp.dev/problems/$code',
  'title': 'Error',
  'status': status,
  'code': code,
  ...?extra,
});

class _Recorded {
  final List<http.Request> requests = <http.Request>[];

  Map<String, Object?> body(int i) =>
      jsonDecode(requests[i].body) as Map<String, Object?>;
}

(HttpAuthApi, _Recorded, InMemoryTokenStore) _api(
  http.Response Function(http.Request) handler,
) {
  final rec = _Recorded();
  final store = InMemoryTokenStore(deviceId: 'dev-1');
  final client = MockClient((request) async {
    rec.requests.add(request);
    return handler(request);
  });
  final api = HttpAuthApi(
    store: store,
    client: client,
    config: const ApiConfig(baseUrl: 'http://api.test'),
    deviceName: 'Test phone',
  );
  return (api, rec, store);
}

void main() {
  group('requestOtp', () {
    test('sends E.164 phone + device id and reads the hints', () async {
      final (api, rec, _) = _api(
        (_) => _json(202, <String, Object?>{
          'challenge_id': 'c1',
          'phone_masked': '+91******0004',
          'channel': 'sms',
          'expires_in': 300,
          'resend_after': 30,
          'resends_left': 3,
        }),
      );
      final out = await api.requestOtp('9000000004');
      expect(out.result, OtpRequestResult.sent);
      expect(out.resendsLeft, 3);
      expect(out.expiresIn, const Duration(minutes: 5));
      expect(
        rec.requests.single.url.toString(),
        'http://api.test/v1/auth/otp/send',
      );
      expect(rec.body(0), <String, Object?>{
        'phone': '+919000000004',
        'purpose': 'login',
        'device_id': 'dev-1',
      });
    });

    test('maps 429 otp_rate_limited with retry_after', () async {
      final (api, _, _) = _api(
        (_) => _problem(429, 'otp_rate_limited', <String, Object?>{
          'retry_after': 776,
        }),
      );
      final out = await api.requestOtp('9000000004');
      expect(out.result, OtpRequestResult.rateLimited);
      expect(out.retryAfter, const Duration(seconds: 776));
    });

    test('maps 423 otp_locked, 404 user_not_found, 422 validation', () async {
      final (locked, _, _) = _api(
        (_) =>
            _problem(423, 'otp_locked', <String, Object?>{'retry_after': 900}),
      );
      expect(
        (await locked.requestOtp('9000000004')).result,
        OtpRequestResult.locked,
      );
      final (missing, _, _) = _api((_) => _problem(404, 'user_not_found'));
      expect(
        (await missing.requestOtp('9000000004')).result,
        OtpRequestResult.notFound,
      );
      final (invalid, _, _) = _api((_) => _problem(422, 'validation_error'));
      expect(
        (await invalid.requestOtp('123')).result,
        OtpRequestResult.invalidNumber,
      );
    });

    test('network failure maps to network', () async {
      final (api, _, _) = _api((_) => throw http.ClientException('down'));
      expect(
        (await api.requestOtp('9000000004')).result,
        OtpRequestResult.network,
      );
    });
  });

  group('verifyOtp', () {
    test('persists the session and returns the user', () async {
      final (api, rec, store) = _api(
        (_) => _json(200, <String, Object?>{
          'access_token': 'a.b.c',
          'refresh_token': 'r1',
          'token_type': 'Bearer',
          'expires_in': 900,
          'user': _user,
        }),
      );
      final out = await api.verifyOtp('9000000004', '123456');
      expect(out.result, OtpVerifyResult.ok);
      expect(out.session!.user.role, 'field_officer');
      expect(rec.body(0), <String, Object?>{
        'phone': '+919000000004',
        'code': '123456',
        'device_id': 'dev-1',
        'device_name': 'Test phone',
        // M4 admin contract: shown in C101's device list.
        'platform': 'android',
      });
      final stored = await store.read();
      expect(stored!.accessToken, 'a.b.c');
      expect(stored.refreshToken, 'r1');
      expect(stored.user.name, 'Ramesh');
      expect(stored.isExpired(now: DateTime.now().toUtc()), isFalse);
      expect(
        stored.isExpired(
          now: DateTime.now().toUtc().add(const Duration(minutes: 16)),
        ),
        isTrue,
      );
      // Round-trips through JSON for secure storage.
      final again = AuthSession.fromJson(stored.toJson());
      expect(again.expiresAt, stored.expiresAt);
      expect(again.user.tenantId, 't1');
    });

    test('maps otp_invalid with attempts_left', () async {
      final (api, _, store) = _api(
        (_) =>
            _problem(401, 'otp_invalid', <String, Object?>{'attempts_left': 4}),
      );
      final out = await api.verifyOtp('9000000004', '000000');
      expect(out.result, OtpVerifyResult.invalid);
      expect(out.attemptsLeft, 4);
      expect(await store.read(), isNull);
    });

    test('maps otp_expired, otp_not_found, otp_locked and network', () async {
      final (expired, _, _) = _api((_) => _problem(401, 'otp_expired'));
      expect(
        (await expired.verifyOtp('9000000004', '1')).result,
        OtpVerifyResult.expired,
      );
      final (missing, _, _) = _api((_) => _problem(404, 'otp_not_found'));
      expect(
        (await missing.verifyOtp('9000000004', '1')).result,
        OtpVerifyResult.notFound,
      );
      final (locked, _, _) = _api(
        (_) =>
            _problem(423, 'otp_locked', <String, Object?>{'retry_after': 900}),
      );
      final out = await locked.verifyOtp('9000000004', '1');
      expect(out.result, OtpVerifyResult.locked);
      expect(out.retryAfter, const Duration(minutes: 15));
      final (down, _, _) = _api((_) => throw http.ClientException('down'));
      expect(
        (await down.verifyOtp('9000000004', '1')).result,
        OtpVerifyResult.network,
      );
      // SEC-020: an officer on a phone that is not their bound device.
      final (unbound, _, store) = _api(
        (_) => _problem(409, 'device_not_bound'),
      );
      expect(
        (await unbound.verifyOtp('9000000004', '1')).result,
        OtpVerifyResult.deviceNotBound,
      );
      expect(await store.read(), isNull);
    });
  });

  group('refresh / logout / me', () {
    final session = AuthSession(
      accessToken: 'old',
      refreshToken: 'r-old',
      expiresAt: DateTime.utc(2026, 1, 2),
      user: AuthUser.fromJson(_user),
    );

    test('refresh rotates and stores the new tokens', () async {
      final (api, rec, store) = _api(
        (_) => _json(200, <String, Object?>{
          'access_token': 'new',
          'refresh_token': 'r-new',
          'expires_in': 900,
          'user': _user,
        }),
      );
      await store.write(session);
      final out = await api.refresh();
      expect(out!.refreshToken, 'r-new');
      expect((await store.read())!.accessToken, 'new');
      expect(rec.body(0), <String, Object?>{
        'refresh_token': 'r-old',
        'device_id': 'dev-1',
      });
    });

    test('refresh reuse (401) clears the session', () async {
      final (api, _, store) = _api((_) => _problem(401, 'refresh_reused'));
      await store.write(session);
      expect(await api.refresh(), isNull);
      expect(await store.read(), isNull);
    });

    test('logout clears locally and calls the server', () async {
      final (api, rec, store) = _api((_) => http.Response('', 204));
      await store.write(session);
      await api.logout();
      expect(await store.read(), isNull);
      expect(rec.requests.single.url.path, '/v1/auth/logout');
      expect(rec.body(0), <String, Object?>{'refresh_token': 'r-old'});
    });

    test('me sends the bearer token', () async {
      final (api, rec, store) = _api((_) => _json(200, _user));
      await store.write(session);
      final me = await api.me();
      expect(me!.phone, '+919000000004');
      expect(rec.requests.single.headers['Authorization'], 'Bearer old');
    });
  });

  test('device id is a v4 uuid and stable per store', () async {
    final store = InMemoryTokenStore();
    final a = await store.deviceId();
    final b = await store.deviceId();
    expect(a, b);
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(a),
      isTrue,
      reason: a,
    );
  });
}
