import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter/services.dart';

/// SEC-024 Play Integrity on login and sensitive actions.
///
/// Contract with the API (server-side verification is an API follow-up):
/// * `X-Integrity-Action`: the comma-separated [SensitiveAction] wire names
///   the request performs (`login`, `credit_sale`, `payment_collection`,
///   `day_close`).
/// * `X-Integrity-Token`: a Play Integrity *standard request* token whose
///   `requestHash` is [integrityRequestHash] of the request (method, path,
///   SHA-256 of the body, actions), so a token cannot be replayed on another
///   request.
/// * `X-Integrity-Status: unavailable` instead of the token when the device
///   could not produce one (no Play services, not configured, timeout,
///   quota). The request is **never blocked** on attestation (FA-028: flag,
///   don't block); the server records and flags.

/// Actions that carry an integrity token.
enum SensitiveAction {
  /// OTP verification (sign in).
  login('login'),

  /// A sale or order on credit.
  creditSale('credit_sale'),

  /// Collecting a payment (cash, UPI QR, payment link).
  paymentCollection('payment_collection'),

  /// Store day close.
  dayClose('day_close');

  const SensitiveAction(this.wire);

  /// Header value.
  final String wire;
}

/// Why no token was produced.
class AttestationUnavailable implements Exception {
  /// Creates the exception.
  const AttestationUnavailable(this.reason);

  /// Short reason for the log (never shown to the user).
  final String reason;

  @override
  String toString() => 'AttestationUnavailable($reason)';
}

/// Obtains a device integrity token bound to [requestHash].
abstract interface class DeviceAttestation {
  /// Returns the token or throws [AttestationUnavailable].
  Future<String> token(String requestHash);
}

/// `requestHash` for a request: base64url (no padding) SHA-256 of
/// `METHOD\npath\nsha256hex(body)\nactions` — 43 characters, well under
/// Play Integrity's 500-character limit.
String integrityRequestHash({
  required String method,
  required String path,
  required List<int> body,
  required List<SensitiveAction> actions,
}) {
  final material = [
    method.toUpperCase(),
    path,
    sha256.convert(body).toString(),
    actions.map((a) => a.wire).join(','),
  ].join('\n');
  return base64Url
      .encode(sha256.convert(utf8.encode(material)).bytes)
      .replaceAll('=', '');
}

/// The headers to add for [actions] (see the library comment).
@immutable
class AttestationHeaders {
  /// Creates the headers.
  const AttestationHeaders(this.values);

  /// Header map.
  final Map<String, String> values;

  /// Name of the token header.
  static const String token = 'X-Integrity-Token';

  /// Name of the status header (`unavailable`).
  static const String status = 'X-Integrity-Status';

  /// Name of the action header.
  static const String action = 'X-Integrity-Action';
}

/// Asks [attestation] for a token and builds the headers; never throws and
/// never waits longer than [timeout].
Future<AttestationHeaders> attestationHeaders(
  DeviceAttestation attestation, {
  required String method,
  required String path,
  required List<int> body,
  required List<SensitiveAction> actions,
  Duration timeout = const Duration(seconds: 3),
  void Function(String message)? log,
}) async {
  final action = actions.map((a) => a.wire).join(',');
  try {
    final token = await attestation
        .token(
          integrityRequestHash(
            method: method,
            path: path,
            body: body,
            actions: actions,
          ),
        )
        .timeout(timeout);
    return AttestationHeaders(<String, String>{
      AttestationHeaders.action: action,
      AttestationHeaders.token: token,
    });
  } on Object catch (e) {
    (log ?? debugPrint)('SEC-024: integrity token unavailable for $action: $e');
    return AttestationHeaders(<String, String>{
      AttestationHeaders.action: action,
      AttestationHeaders.status: 'unavailable',
    });
  }
}

/// Play Integrity standard requests through the app's `farmerapp/integrity`
/// method channel (`MainActivity.kt`: `prepareIntegrityToken` once with the
/// Cloud project number, then `request` with the request hash).
class PlayIntegrityAttestation implements DeviceAttestation {
  /// Creates the attestation for [cloudProjectNumber] (from
  /// `--dart-define=PLAY_INTEGRITY_PROJECT_NUMBER`; 0 = not configured).
  const PlayIntegrityAttestation({
    this.cloudProjectNumber = configuredProjectNumber,
    this._channel = const MethodChannel('farmerapp/integrity'),
  });

  /// Compile-time Google Cloud project number.
  static const int configuredProjectNumber = int.fromEnvironment(
    'PLAY_INTEGRITY_PROJECT_NUMBER',
  );

  /// Google Cloud project linked in Play Console.
  final int cloudProjectNumber;

  final MethodChannel _channel;

  @override
  Future<String> token(String requestHash) async {
    if (cloudProjectNumber <= 0) {
      throw const AttestationUnavailable('not_configured');
    }
    try {
      final token = await _channel.invokeMethod<String>(
        'requestToken',
        <String, Object?>{
          'cloudProjectNumber': cloudProjectNumber,
          'requestHash': requestHash,
        },
      );
      if (token == null || token.isEmpty) {
        throw const AttestationUnavailable('empty_token');
      }
      return token;
    } on PlatformException catch (e) {
      throw AttestationUnavailable(e.code);
    } on MissingPluginException {
      throw const AttestationUnavailable('no_channel');
    }
  }
}

/// Scriptable attestation for tests: returns `token-<hash>` or throws.
class FakeDeviceAttestation implements DeviceAttestation {
  /// Creates the fake.
  FakeDeviceAttestation({this.available = true});

  /// When false every call throws [AttestationUnavailable].
  bool available;

  /// Request hashes asked for, in order.
  final List<String> requests = <String>[];

  @override
  Future<String> token(String requestHash) async {
    requests.add(requestHash);
    if (!available) throw const AttestationUnavailable('fake_unavailable');
    return 'token-$requestHash';
  }
}
