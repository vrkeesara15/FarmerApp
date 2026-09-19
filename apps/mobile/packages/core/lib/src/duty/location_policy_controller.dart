import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/open_database.dart';
import '../state/auth_flow.dart';
import '../sync/sync_models.dart';
import '../sync/sync_providers.dart';
import 'duty_models.dart';
import 'duty_providers.dart';

/// A05 / VV-010 state: the current location policy (bundled, then cached
/// from `GET /v1/policies/location`), what the officer accepted, and the
/// cached duty policy.
@immutable
class LocationPolicyState {
  /// Creates the state.
  const LocationPolicyState({
    required this.current,
    this.duty = const DutyPolicy(),
    this.acceptedVersion,
    this.acceptedHash,
    this.acceptedAt,
    this.loaded = false,
  });

  /// The policy the officer must accept.
  final LocationPolicyDoc current;

  /// Sampling / upload / auto-end settings (`GET /v1/duty/policy`).
  final DutyPolicy duty;

  /// Version accepted on this device, if any.
  final String? acceptedVersion;

  /// Hash accepted on this device, if any.
  final String? acceptedHash;

  /// When it was accepted (UTC).
  final DateTime? acceptedAt;

  /// The persisted state has been read.
  final bool loaded;

  /// The duty toggle may be used (FA-011: blocked until accepted for the
  /// current version).
  bool get accepted => loaded && acceptedVersion == current.version;

  /// An older version was accepted; A05 is shown again.
  bool get needsReacceptance =>
      loaded && acceptedVersion != null && acceptedVersion != current.version;

  /// Copy with overrides.
  LocationPolicyState copyWith({
    LocationPolicyDoc? current,
    DutyPolicy? duty,
    String? acceptedVersion,
    String? acceptedHash,
    DateTime? acceptedAt,
    bool? loaded,
    bool clearAcceptance = false,
  }) => LocationPolicyState(
    current: current ?? this.current,
    duty: duty ?? this.duty,
    acceptedVersion: clearAcceptance
        ? null
        : acceptedVersion ?? this.acceptedVersion,
    acceptedHash: clearAcceptance ? null : acceptedHash ?? this.acceptedHash,
    acceptedAt: clearAcceptance ? null : acceptedAt ?? this.acceptedAt,
    loaded: loaded ?? this.loaded,
  );
}

/// Drives A05 (FA-011): loads the cached policy and acceptance from `kv`,
/// records an acceptance locally **and** as a `policy_acceptance` op, and
/// refreshes the policy from the server when online (a newer version
/// clears [LocationPolicyState.accepted] so A05 is shown again).
class LocationPolicyController extends Notifier<LocationPolicyState> {
  /// `kv` key of the cached policy document (JSON).
  static const String currentKey = 'policy.location.current';

  /// `kv` key of the acceptance record (JSON).
  static const String acceptanceKey = 'policy.location.acceptance';

  /// `kv` key of the cached duty policy (JSON).
  static const String dutyPolicyKey = 'duty.policy';

  Future<void>? _loading;
  bool _disposed = false;

  @override
  LocationPolicyState build() {
    ref.onDispose(() => _disposed = true);
    unawaited(load());
    return LocationPolicyState(current: LocationPolicyDoc.bundled());
  }

  void _set(LocationPolicyState next) {
    if (_disposed) return;
    state = next;
  }

  /// Reads the persisted state once (idempotent).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    var current = LocationPolicyDoc.bundled();
    final rawCurrent = await db.getValue(currentKey);
    if (rawCurrent != null) {
      current = LocationPolicyDoc.fromJson(
        Map<String, Object?>.from(jsonDecode(rawCurrent) as Map),
      );
    }
    var duty = const DutyPolicy();
    final rawDuty = await db.getValue(dutyPolicyKey);
    if (rawDuty != null) {
      duty = DutyPolicy.fromJson(
        Map<String, Object?>.from(jsonDecode(rawDuty) as Map),
      );
    }
    String? version;
    String? hash;
    DateTime? at;
    final rawAcceptance = await db.getValue(acceptanceKey);
    if (rawAcceptance != null) {
      final a = Map<String, Object?>.from(jsonDecode(rawAcceptance) as Map);
      version = a['version'] as String?;
      hash = a['text_hash'] as String?;
      final t = a['accepted_at'];
      at = t is String ? DateTime.tryParse(t)?.toUtc() : null;
    }
    _set(
      LocationPolicyState(
        current: current,
        duty: duty,
        acceptedVersion: version,
        acceptedHash: hash,
        acceptedAt: at,
        loaded: true,
      ),
    );
  }

  /// Records the officer's "I agree" for the current version: `kv`
  /// (version, hash, timestamp, device) and a `policy_acceptance` op.
  Future<void> accept() async {
    await load();
    final db = ref.read(appDatabaseProvider);
    final now = ref.read(clockProvider)();
    final deviceId = await ref.read(tokenStoreProvider).deviceId();
    final appVersion = ref.read(appVersionProvider);
    final doc = state.current;
    final record = <String, Object?>{
      'policy_key': locationPolicyKey,
      'version': doc.version,
      'text_hash': doc.textHash,
      'accepted_at': now.toIso8601String(),
      'device_id': deviceId,
      'app_version': appVersion,
    };
    await db.setValue(acceptanceKey, jsonEncode(record));
    await ref
        .read(outboxProvider)
        .enqueueCreate(
          SyncEntities.policyAcceptance,
          ref.read(idGeneratorProvider)(),
          record,
        );
    _set(
      state.copyWith(
        acceptedVersion: doc.version,
        acceptedHash: doc.textHash,
        acceptedAt: now,
      ),
    );
  }

  /// Re-reads the cached duty policy (a tenant settings pull changed the
  /// sampling cadence or the auto-end time).
  Future<void> reloadDutyPolicy() async {
    await load();
    final raw = await ref.read(appDatabaseProvider).getValue(dutyPolicyKey);
    if (raw == null) return;
    _set(
      state.copyWith(
        duty: DutyPolicy.fromJson(
          Map<String, Object?>.from(jsonDecode(raw) as Map),
        ),
      ),
    );
  }

  /// Forgets the acceptance (the server answered `policy_not_accepted`):
  /// A05 is shown again before the next duty start.
  Future<void> markNotAccepted() async {
    await load();
    await ref.read(appDatabaseProvider).removeValue(acceptanceKey);
    _set(state.copyWith(clearAcceptance: true));
  }

  /// Fetches the policy and the duty settings when online and caches
  /// them; returns true when a version newer than the accepted one
  /// arrived. Transport failures keep the cached copy.
  Future<bool> refresh() async {
    await load();
    final api = ref.read(policyApiProvider);
    final db = ref.read(appDatabaseProvider);
    var newer = false;
    try {
      final doc = await api.fetchLocationPolicy();
      await db.setValue(currentKey, jsonEncode(doc.toJson()));
      newer =
          state.acceptedVersion != null && state.acceptedVersion != doc.version;
      _set(state.copyWith(current: doc));
    } on SyncTransportException {
      // Offline: keep the bundled / cached copy.
    }
    try {
      final duty = await api.fetchDutyPolicy();
      await db.setValue(dutyPolicyKey, jsonEncode(duty.toJson()));
      _set(state.copyWith(duty: duty));
    } on SyncTransportException {
      // Offline: keep the defaults.
    }
    return newer;
  }
}
