import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_api.dart';

/// Persists the [AuthSession] and a stable per-install device id
/// (refresh tokens are bound to it, SEC-020).
abstract interface class TokenStore {
  /// The stored session, if any.
  Future<AuthSession?> read();

  /// Replaces the stored session.
  Future<void> write(AuthSession session);

  /// Forgets the session (device id is kept).
  Future<void> clear();

  /// Stable device id, generated on first use.
  Future<String> deviceId();
}

/// RFC 4122 version-4 UUID from a secure random source (no extra package).
String generateUuidV4({Random? random}) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Volatile store for tests and previews.
class InMemoryTokenStore implements TokenStore {
  /// Creates the store, optionally with a fixed [deviceId].
  InMemoryTokenStore({this._deviceId, this._session});

  String? _deviceId;
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;

  @override
  Future<String> deviceId() async => _deviceId ??= generateUuidV4();
}

/// Keystore-backed store (`flutter_secure_storage`).
class SecureTokenStore implements TokenStore {
  /// Creates the store.
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _sessionKey = 'farmerapp.auth.session';
  static const String _deviceKey = 'farmerapp.device_id';

  @override
  Future<AuthSession?> read() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      await _storage.delete(key: _sessionKey);
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) =>
      _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);

  @override
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = generateUuidV4();
    await _storage.write(key: _deviceKey, value: fresh);
    return fresh;
  }
}
