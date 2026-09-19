import 'dart:async';
import 'dart:convert';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// SEC-024 Play Integrity: which requests are sensitive, the headers they
/// carry, and "flag, don't block" when no token can be produced.
List<int> _json(Object body) => utf8.encode(jsonEncode(body));

class _NeverAttestation implements DeviceAttestation {
  @override
  Future<String> token(String requestHash) => Completer<String>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sensitive requests', () {
    Uri u(String path) => Uri.parse('https://api.test$path');

    test('login, day close, payments, POS sales', () {
      expect(
        sensitiveActionsOf('POST', u('/v1/auth/otp/verify'), <int>[]),
        <SensitiveAction>[SensitiveAction.login],
      );
      expect(
        sensitiveActionsOf('POST', u('/v1/auth/otp/send'), <int>[]),
        isEmpty,
      );
      expect(
        sensitiveActionsOf('POST', u('/v1/stores/s1/day-close'), <int>[]),
        <SensitiveAction>[SensitiveAction.dayClose],
      );
      expect(
        sensitiveActionsOf('POST', u('/v1/payments'), <int>[]),
        <SensitiveAction>[SensitiveAction.paymentCollection],
      );
      expect(sensitiveActionsOf('GET', u('/v1/payments/p1'), <int>[]), isEmpty);
      expect(
        sensitiveActionsOf(
          'POST',
          u('/v1/stores/s1/pos/sales'),
          _json(<String, Object?>{'mode': 'credit'}),
        ),
        <SensitiveAction>[SensitiveAction.creditSale],
      );
      expect(
        sensitiveActionsOf(
          'POST',
          u('/v1/stores/s1/pos/sales'),
          _json(<String, Object?>{'mode': 'cash'}),
        ),
        <SensitiveAction>[SensitiveAction.paymentCollection],
      );
      expect(
        sensitiveActionsOf('POST', u('/v1/stores/s1/pos/preview'), <int>[]),
        isEmpty,
      );
    });

    test('sync batches with a credit order or a payment op', () {
      Map<String, Object?> op(String entity, Map<String, Object?> payload) =>
          <String, Object?>{
            'entity': entity,
            'action': 'create',
            'payload': payload,
          };
      List<SensitiveAction> of(List<Object?> ops) => sensitiveActionsOf(
        'POST',
        u('/v1/sync'),
        _json(<String, Object?>{'device_id': 'd', 'ops': ops}),
      );
      expect(of(<Object?>[op('farmer', <String, Object?>{})]), isEmpty);
      expect(
        of(<Object?>[
          op('order', <String, Object?>{'payment_mode': 'cash'}),
        ]),
        isEmpty,
      );
      expect(
        of(<Object?>[
          op('payment', <String, Object?>{'mode': 'cash'}),
          op('order', <String, Object?>{'payment_mode': 'credit'}),
        ]),
        <SensitiveAction>[
          SensitiveAction.creditSale,
          SensitiveAction.paymentCollection,
        ],
      );
      expect(
        sensitiveActionsOf('POST', u('/v1/sync'), utf8.encode('not json')),
        isEmpty,
      );
    });
  });

  group('SecureApiClient headers', () {
    late List<http.Request> sent;

    SecureApiClient client(
      DeviceAttestation? attestation, {
      Duration? timeout,
    }) {
      sent = <http.Request>[];
      return SecureApiClient(
        inner: MockClient((request) async {
          sent.add(request);
          return http.Response('{}', 200);
        }),
        attestation: attestation,
        attestationTimeout: timeout ?? const Duration(seconds: 3),
      );
    }

    test('login carries a token bound to the request', () async {
      final attestation = FakeDeviceAttestation();
      final body = jsonEncode(<String, Object?>{'phone': '+91', 'code': '1'});
      await client(attestation)
          .post(Uri.parse('https://api.test/v1/auth/otp/verify'), body: body);
      final expected = integrityRequestHash(
        method: 'POST',
        path: '/v1/auth/otp/verify',
        body: utf8.encode(body),
        actions: <SensitiveAction>[SensitiveAction.login],
      );
      expect(attestation.requests, <String>[expected]);
      expect(expected, hasLength(43));
      final headers = sent.single.headers;
      expect(headers['X-Integrity-Token'], 'token-$expected');
      expect(headers['X-Integrity-Action'], 'login');
      expect(headers.containsKey('X-Integrity-Status'), isFalse);
    });

    test('a different body gives a different hash (no replay)', () {
      String hash(String body) => integrityRequestHash(
        method: 'POST',
        path: '/v1/stores/s1/day-close',
        body: utf8.encode(body),
        actions: <SensitiveAction>[SensitiveAction.dayClose],
      );
      expect(hash('{"a":1}'), isNot(hash('{"a":2}')));
    });

    test('unavailable: the request still goes out, flagged', () async {
      final attestation = FakeDeviceAttestation(available: false);
      final response = await client(
        attestation,
      ).post(Uri.parse('https://api.test/v1/stores/s1/day-close'), body: '{}');
      expect(response.statusCode, 200);
      expect(sent.single.headers['X-Integrity-Status'], 'unavailable');
      expect(sent.single.headers['X-Integrity-Action'], 'day_close');
      expect(sent.single.headers.containsKey('X-Integrity-Token'), isFalse);
    });

    test('a hanging attestation times out as unavailable', () async {
      await client(
        _NeverAttestation(),
        timeout: const Duration(milliseconds: 10),
      ).post(Uri.parse('https://api.test/v1/payments'), body: '{}');
      expect(sent.single.headers['X-Integrity-Status'], 'unavailable');
    });

    test('ordinary requests are not attested', () async {
      final attestation = FakeDeviceAttestation();
      await client(attestation).get(Uri.parse('https://api.test/v1/me'));
      await client(attestation).post(
        Uri.parse('https://api.test/v1/sync'),
        body: jsonEncode(<String, Object?>{'ops': <Object?>[]}),
      );
      expect(attestation.requests, isEmpty);
      expect(sent.single.headers.containsKey('X-Integrity-Action'), isFalse);
    });

    test('HttpAuthApi login goes through the attested client; 409 '
        'device_not_bound is its own outcome (SEC-020)', () async {
      final attestation = FakeDeviceAttestation();
      final requests = <http.Request>[];
      final auth = HttpAuthApi(
        store: InMemoryTokenStore(deviceId: 'dev-1'),
        client: SecureApiClient(
          inner: MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode(<String, Object?>{
                'status': 409,
                'code': 'device_not_bound',
              }),
              409,
            );
          }),
          attestation: attestation,
        ),
        config: const ApiConfig(baseUrl: 'https://api.test'),
        appVersion: '1.2.3',
      );
      final out = await auth.verifyOtp('9000000004', '123456');
      expect(out.result, OtpVerifyResult.deviceNotBound);
      expect(requests.single.headers['X-Integrity-Action'], 'login');
      expect(
        requests.single.headers['X-Integrity-Token'],
        startsWith('token-'),
      );
      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(body['device_id'], 'dev-1');
      expect(body['platform'], 'android');
      expect(body['app_version'], '1.2.3');
    });
  });

  group('PlayIntegrityAttestation', () {
    const channel = MethodChannel('farmerapp/integrity-test');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('not configured (project number 0): unavailable, no call', () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls += 1;
            return 't';
          });
      await expectLater(
        const PlayIntegrityAttestation(channel: channel).token('h'),
        throwsA(isA<AttestationUnavailable>()),
      );
      expect(calls, 0);
    });

    test('standard request through the channel', () async {
      MethodCall? seen;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            seen = call;
            return 'play-token';
          });
      final token = await const PlayIntegrityAttestation(
        cloudProjectNumber: 123456789,
        channel: channel,
      ).token('hash-1');
      expect(token, 'play-token');
      expect(seen!.method, 'requestToken');
      expect(seen!.arguments, <String, Object?>{
        'cloudProjectNumber': 123456789,
        'requestHash': 'hash-1',
      });
    });

    test('Play services errors become unavailable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'PLAY_SERVICES_NOT_FOUND');
          });
      await expectLater(
        const PlayIntegrityAttestation(
          cloudProjectNumber: 1,
          channel: channel,
        ).token('h'),
        throwsA(
          isA<AttestationUnavailable>().having(
            (e) => e.reason,
            'reason',
            'PLAY_SERVICES_NOT_FOUND',
          ),
        ),
      );
    });
  });
}
