import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the SQLCipher key of the on-device database (SEC-024).
///
/// The key is 32 random bytes (hex encoded, 64 characters) generated on the
/// first run. [SecureDatabaseKeyStore] keeps it in `flutter_secure_storage`,
/// whose Android backend encrypts it with AES-GCM under a key held in the
/// Android Keystore.
abstract interface class DatabaseKeyStore {
  /// The stored key, or `null` before the first run.
  Future<String?> read();

  /// The stored key, generating and storing a fresh one when none exists.
  Future<String> readOrCreate();

  /// Forgets the key (remote wipe, SEC-025). The database it protected is
  /// unreadable afterwards.
  Future<void> delete();
}

/// 32 random bytes from a secure source as 64 lower-case hex characters.
String generateDatabaseKey({Random? random}) {
  final rng = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 32; i++) {
    buffer.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Whether [key] has the shape [generateDatabaseKey] produces.
bool isValidDatabaseKey(String? key) =>
    key != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(key);

/// Volatile key store for tests.
class InMemoryDatabaseKeyStore implements DatabaseKeyStore {
  /// Creates the store, optionally with a fixed [key].
  InMemoryDatabaseKeyStore([this.key]);

  /// The current key.
  String? key;

  /// Keys generated so far (a wipe followed by a new run makes a second).
  int generated = 0;

  @override
  Future<String?> read() async => key;

  @override
  Future<String> readOrCreate() async {
    final existing = key;
    if (existing != null) return existing;
    generated += 1;
    return key = generateDatabaseKey();
  }

  @override
  Future<void> delete() async => key = null;
}

/// Keystore-backed key store (`flutter_secure_storage`).
///
/// `flutter_secure_storage` 11 replaced Jetpack `EncryptedSharedPreferences`
/// (deprecated upstream) with its own ciphers: the value is AES-256-GCM
/// encrypted and the AES key is wrapped by an RSA-OAEP key that never
/// leaves the Android Keystore. `resetOnError` is off so a transient
/// Keystore error surfaces instead of silently replacing the key.
class SecureDatabaseKeyStore implements DatabaseKeyStore {
  /// Creates the store.
  SecureDatabaseKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(aOptions: options);

  /// Android options: Keystore-wrapped AES-GCM, no silent reset.
  static const AndroidOptions options = AndroidOptions(resetOnError: false);

  final FlutterSecureStorage _storage;

  /// Secure-storage key of the database key.
  static const String storageKey = 'farmerapp.db_key.v1';

  @override
  Future<String?> read() async {
    final value = await _storage.read(key: storageKey);
    return isValidDatabaseKey(value) ? value : null;
  }

  @override
  Future<String> readOrCreate() async {
    final existing = await read();
    if (existing != null) return existing;
    final fresh = generateDatabaseKey();
    await _storage.write(key: storageKey, value: fresh);
    return fresh;
  }

  @override
  Future<void> delete() => _storage.delete(key: storageKey);
}
