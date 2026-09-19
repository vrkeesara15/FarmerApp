// Contracts the M6 mobile work codes against: `GET /v1/diagnoses/{id}`,
// `POST/GET /v1/me/deletion-request` (FM-015, real response shape), the
// `officer {id, name, phone}` object on the farmer's own profile (F62) and
// the `on_device_crop_guess` tenant flag (DX-001, default off).
import 'dart:convert';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

RestJsonClient _rest(
  List<http.Request> requests,
  http.Response Function(http.Request) answer,
) => RestJsonClient(
  store: InMemoryTokenStore(
    session: AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      user: const AuthUser(
        id: 'u',
        tenantId: 't',
        phone: '+919000000004',
        name: 'Lakshmi',
        role: 'farmer',
        language: 'te',
        status: 'active',
      ),
    ),
  ),
  config: const ApiConfig(baseUrl: 'https://api.test'),
  client: MockClient((request) async {
    requests.add(request);
    return answer(request);
  }),
);

void main() {
  test('FM-015: POST then GET /v1/me/deletion-request', () async {
    final requests = <http.Request>[];
    const ticket = <String, Object?>{
      'ticket_id': '7c9e6679-7425-40de-944b-e07fc1f90ae7',
      'type': 'deletion',
      'status': 'received',
      'due_by': '2026-10-19T04:30:00Z',
      'created_at': '2026-09-19T04:30:00Z',
    };
    final api = HttpKisanApi(
      _rest(
        requests,
        (r) => r.method == 'POST'
            ? http.Response(jsonEncode(ticket), 201)
            : http.Response(
                jsonEncode(<String, Object?>{
                  ...ticket,
                  'status': 'in_progress',
                }),
                200,
              ),
      ),
    );
    final created = await api.requestDeletion(reason: 'farmer_app');
    expect(created.status, 201);
    expect(requests.first.method, 'POST');
    expect(requests.first.url.path, '/v1/me/deletion-request');
    expect(jsonDecode(requests.first.body), <String, Object?>{
      'reason': 'farmer_app',
    });
    final t = DeletionRequest.fromJson(created.body);
    expect(t.shortTicket, '7C9E6679');
    expect(t.dueBy, DateTime.utc(2026, 10, 19, 4, 30));
    final latest = await api.deletionRequest();
    expect(requests.last.method, 'GET');
    expect(DeletionRequest.fromJson(latest.body).status, 'in_progress');
  });

  test('GET /v1/diagnoses/{id} is parsed into a Diagnosis', () async {
    final requests = <http.Request>[];
    final api = HttpDiagnosisApi(
      _rest(
        requests,
        (_) => http.Response.bytes(
          utf8.encode(
            jsonEncode(
              FakeDiagnosisServer.diagnosisOut(
                id: 'dx-1',
                outcome: FakeDiagnosisOutcome.provisional,
              ),
            ),
          ),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      ),
    );
    final r = await api.get('dx-1');
    expect(requests.single.url.path, '/v1/diagnoses/dx-1');
    final d = Diagnosis.fromData('dx-1', r.body);
    expect(d.status, DiagnosisStatus.provisional);
    expect(d.confidence, ConfidenceLevel.medium);
    expect(d.showBuy, isFalse);
    expect(d.modelVersions['on_device'], 'ondevice-v1.0');
    expect(d.corpusVersion, 7);
  });

  test('F62: the officer object on the farmer profile', () {
    final p = FarmerProfile.fromJson(const <String, Object?>{
      'id': 'f-1',
      'name': 'Lakshmi Devi',
      'registered_by': 'officer-1',
      'officer': <String, Object?>{
        'id': 'officer-1',
        'name': 'Ramesh Kumar',
        'phone': '+919100000001',
      },
    });
    expect(p.officer!.name, 'Ramesh Kumar');
    expect(p.officer!.phone, '+919100000001');
    final absent = FarmerProfile.fromJson(const <String, Object?>{
      'id': 'f-1',
      'name': 'Lakshmi Devi',
      'registered_by': 'officer-1',
    });
    expect(absent.officer!.id, 'officer-1');
    expect(absent.officer!.phone, isNull, reason: 'graceful when absent');
  });

  test('DX-001: on_device_crop_guess is off unless the tenant turns it on', () {
    expect(const PublicTenantSettings().onDeviceCropGuess, isFalse);
    expect(
      PublicTenantSettings.fromJson(const <String, Object?>{})
          .onDeviceCropGuess,
      isFalse,
    );
    final on = PublicTenantSettings.fromJson(const <String, Object?>{
      'features': <String, Object?>{'on_device_crop_guess': true},
    });
    expect(on.onDeviceCropGuess, isTrue);
    expect(
      PublicTenantSettings.fromJson(on.toJson()).onDeviceCropGuess,
      isTrue,
    );
  });
}
