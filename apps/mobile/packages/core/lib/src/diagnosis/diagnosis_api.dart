import '../catalog/rest_json_client.dart';

/// `GET /v1/diagnoses/{id}` and `POST /v1/diagnoses/{id}/ask-expert`
/// (docs/prs/M6-diagnosis-api.md). Creating goes through the outbox
/// (`diagnosis` create op) so it works offline.
abstract interface class DiagnosisApi {
  /// The diagnosis (`DiagnosisOut`), 404 when not the caller's.
  Future<RestResponse> get(String id);

  /// FM-006: puts an answered case in the agronomist queue (same photos, no
  /// second diagnosis). Idempotent; 409 `diagnosis_already_reviewed`.
  Future<RestResponse> askExpert(String id, {String? note});
}

/// [DiagnosisApi] over the shared REST client.
class HttpDiagnosisApi implements DiagnosisApi {
  /// Creates the client.
  HttpDiagnosisApi(this._rest);

  final RestJsonClient _rest;

  @override
  Future<RestResponse> get(String id) => _rest.get('/v1/diagnoses/$id');

  @override
  Future<RestResponse> askExpert(String id, {String? note}) => _rest.post(
    '/v1/diagnoses/$id/ask-expert',
    <String, Object?>{'note': ?note},
  );
}

/// Scriptable [DiagnosisApi] (tests, previews).
class FakeDiagnosisApi implements DiagnosisApi {
  /// Server rows by id.
  final Map<String, Map<String, Object?>> rows =
      <String, Map<String, Object?>>{};

  /// Every call fails with status 0 while true.
  bool offline = false;

  /// Calls made.
  final List<String> calls = <String>[];

  /// `ask-expert` calls made (ids).
  final List<String> askExpertCalls = <String>[];

  @override
  Future<RestResponse> get(String id) async {
    calls.add(id);
    if (offline) return const RestResponse(0);
    final row = rows[id];
    if (row == null) {
      return const RestResponse(404, <String, Object?>{'code': 'not_found'});
    }
    return RestResponse(200, row);
  }

  @override
  Future<RestResponse> askExpert(String id, {String? note}) async {
    askExpertCalls.add(id);
    if (offline) return const RestResponse(0);
    final row = rows[id];
    if (row == null) {
      return const RestResponse(404, <String, Object?>{'code': 'not_found'});
    }
    if (row['reviewed_at'] != null) {
      return const RestResponse(409, <String, Object?>{
        'code': 'diagnosis_already_reviewed',
      });
    }
    if (row['flagged'] != true) {
      rows[id] = <String, Object?>{
        ...row,
        'flagged': true,
        'expert_requested_at': '2026-09-19T05:00:00Z',
        'version': ((row['version'] as num?)?.toInt() ?? 0) + 1,
      };
    }
    return RestResponse(200, rows[id]!);
  }
}
