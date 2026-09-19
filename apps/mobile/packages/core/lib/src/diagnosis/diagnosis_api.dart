import '../catalog/rest_json_client.dart';

/// `GET /v1/diagnoses/{id}` (docs/prs/M6-diagnosis-api.md). Creating goes
/// through the outbox (`diagnosis` create op) so it works offline.
abstract interface class DiagnosisApi {
  /// The diagnosis (`DiagnosisOut`), 404 when not the caller's.
  Future<RestResponse> get(String id);
}

/// [DiagnosisApi] over the shared REST client.
class HttpDiagnosisApi implements DiagnosisApi {
  /// Creates the client.
  HttpDiagnosisApi(this._rest);

  final RestJsonClient _rest;

  @override
  Future<RestResponse> get(String id) => _rest.get('/v1/diagnoses/$id');
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
}
