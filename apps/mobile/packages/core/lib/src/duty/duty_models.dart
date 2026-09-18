import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show immutable, mapEquals;

import '../geo/geo.dart';

/// Wire key of the employee location policy (FA-011 / VV-010).
const String locationPolicyKey = 'location_policy';

/// Version of the location policy bundled with this build (matches the
/// tenant default `location_policy_version`, TODO-LEGAL until HR signs).
const String bundledLocationPolicyVersion = '2026-09-v1';

/// The English location policy shipped with the app, byte-for-byte the
/// text in `design/copy/location_policy_en.md`. The API computes
/// `text_hash = sha256(text_en.strip())` over the same copy, so an offline
/// first run records the same hash the server expects.
const String bundledLocationPolicyEnglish = '''
Mitra location policy (version 2026-09-v1)

1. What we collect. While you are on duty, Mitra records your location (latitude, longitude, accuracy, speed, direction), the time, your battery level and basic device checks (mock-location, rooted device, clock difference). It also records the photos, notes and farmer confirmations you capture during visits.

2. Only while on duty. Location is recorded only after you switch duty on, and it stops the moment you switch duty off, when the day ends at the tenant’s set time (20:00 by default) or after 60 minutes idle at your home location. Nothing is recorded while you are off duty, and a notification is always visible while location is on.

3. Why we collect it. Your track computes the kilometres for your travel allowance, and your location at a visit gives you credit for that visit. No track means no automatic travel allowance and no verified visit.

4. Who can see it. Your cluster head, the directors and the owner of your organisation can see your track and visits for their area, and auditors can review flagged visits. Store managers and farmers never see your location. Raw points are kept for 180 days and then reduced to daily totals.
''';

/// `sha256(text.strip())` as lower-case hex: the `text_hash` of a policy.
String policyTextHash(String text) =>
    sha256.convert(utf8.encode(text.trim())).toString();

/// A location policy document (`GET /v1/policies/location`).
@immutable
class LocationPolicyDoc {
  /// Creates the document.
  const LocationPolicyDoc({
    required this.version,
    required this.textHash,
    required this.text,
  });

  /// The copy bundled with the app, used until the server answers.
  factory LocationPolicyDoc.bundled() => LocationPolicyDoc(
    version: bundledLocationPolicyVersion,
    textHash: policyTextHash(bundledLocationPolicyEnglish),
    text: const <String, String>{'en': bundledLocationPolicyEnglish},
  );

  /// Parses the wire shape.
  factory LocationPolicyDoc.fromJson(Map<String, Object?> json) {
    final raw = json['text'];
    return LocationPolicyDoc(
      version: json['version']! as String,
      textHash: (json['text_hash'] as String?) ?? '',
      text: raw is Map
          ? <String, String>{
              for (final e in raw.entries)
                if (e.value is String) e.key as String: e.value! as String,
            }
          : const <String, String>{},
    );
  }

  /// Policy version, e.g. `2026-09-v1`.
  final String version;

  /// `sha256(text_en.strip())`.
  final String textHash;

  /// Full text per language code (`en`, `te`, `kn`, `hi`, `mr`).
  final Map<String, String> text;

  /// The text in [language], falling back to English.
  String textFor(String language) =>
      text[language] ?? text['en'] ?? bundledLocationPolicyEnglish;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'text_hash': textHash,
    'text': text,
  };

  @override
  bool operator ==(Object other) =>
      other is LocationPolicyDoc &&
      other.version == version &&
      other.textHash == textHash &&
      mapEquals(other.text, text);

  @override
  int get hashCode => Object.hash(version, textHash);
}

/// Sampling and upload policy (`GET /v1/duty/policy`, VV-001 / VV-007).
@immutable
class DutyPolicy {
  /// Creates the policy.
  const DutyPolicy({
    this.movingInterval = const Duration(minutes: 2),
    this.stationaryInterval = const Duration(minutes: 10),
    this.uploadInterval = const Duration(minutes: 15),
    this.uploadOnWifiOrCharging = true,
    this.autoEndLocalTime = '20:00',
    this.utcOffset = const Duration(hours: 5, minutes: 30),
  });

  /// Parses the wire shape; missing fields keep the defaults.
  factory DutyPolicy.fromJson(Map<String, Object?> json) {
    const d = DutyPolicy();
    Duration seconds(String key, Duration fallback) {
      final v = json[key];
      return v is num && v > 0 ? Duration(seconds: v.toInt()) : fallback;
    }

    final offset = json['utc_offset_minutes'];
    return DutyPolicy(
      movingInterval: seconds('moving_interval_s', d.movingInterval),
      stationaryInterval: seconds(
        'stationary_interval_s',
        d.stationaryInterval,
      ),
      uploadInterval: seconds('upload_interval_s', d.uploadInterval),
      uploadOnWifiOrCharging:
          (json['upload_on_wifi_or_charging'] as bool?) ??
          d.uploadOnWifiOrCharging,
      autoEndLocalTime:
          (json['auto_end_local_time'] as String?) ?? d.autoEndLocalTime,
      utcOffset: offset is num
          ? Duration(minutes: offset.toInt())
          : d.utcOffset,
    );
  }

  /// Sampling interval while moving (speed > 0.5 m/s or moved > 50 m).
  final Duration movingInterval;

  /// Sampling interval while stationary.
  final Duration stationaryInterval;

  /// Batch upload interval.
  final Duration uploadInterval;

  /// Flush the buffer as soon as the device is on Wi-Fi or charging.
  final bool uploadOnWifiOrCharging;

  /// Tenant auto-end wall time `HH:mm` in the tenant zone (VV-007).
  final String autoEndLocalTime;

  /// Tenant zone offset from UTC (IST by default).
  final Duration utcOffset;

  /// Wire shape (the cache in `kv`).
  Map<String, Object?> toJson() => <String, Object?>{
    'moving_interval_s': movingInterval.inSeconds,
    'stationary_interval_s': stationaryInterval.inSeconds,
    'upload_interval_s': uploadInterval.inSeconds,
    'upload_on_wifi_or_charging': uploadOnWifiOrCharging,
    'auto_end_local_time': autoEndLocalTime,
    'utc_offset_minutes': utcOffset.inMinutes,
  };

  /// The next auto-end instant (UTC) strictly after [after]: today's
  /// [autoEndLocalTime] in the tenant zone, or tomorrow's when that has
  /// passed.
  DateTime nextAutoEnd(DateTime after) {
    final parts = autoEndLocalTime.split(':');
    final hour = int.tryParse(parts.first) ?? 20;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final local = after.toUtc().add(utcOffset);
    var candidate = DateTime.utc(
      local.year,
      local.month,
      local.day,
      hour,
      minute,
    ).subtract(utcOffset);
    if (!candidate.isAfter(after.toUtc())) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  @override
  bool operator ==(Object other) =>
      other is DutyPolicy &&
      other.movingInterval == movingInterval &&
      other.stationaryInterval == stationaryInterval &&
      other.uploadInterval == uploadInterval &&
      other.uploadOnWifiOrCharging == uploadOnWifiOrCharging &&
      other.autoEndLocalTime == autoEndLocalTime &&
      other.utcOffset == utcOffset;

  @override
  int get hashCode => Object.hash(
    movingInterval,
    stationaryInterval,
    uploadInterval,
    uploadOnWifiOrCharging,
    autoEndLocalTime,
    utcOffset,
  );
}

/// How a duty session ended (`duty_session.end_reason`).
enum DutyEndReason {
  /// The officer switched duty off.
  manual,

  /// The tenant auto-end time was reached (VV-007).
  autoTime,

  /// Idle at home for the tenant idle window (server-side, VV-007).
  autoIdle,

  /// A manager ended it (server-side).
  forced,

  /// The server rejected the start (`duty_already_active`,
  /// `policy_not_accepted`); nothing was recorded server-side.
  rejected;

  /// Wire value (`auto_time`, ...).
  String get wire => switch (this) {
    DutyEndReason.manual => 'manual',
    DutyEndReason.autoTime => 'auto_time',
    DutyEndReason.autoIdle => 'auto_idle',
    DutyEndReason.forced => 'forced',
    DutyEndReason.rejected => 'rejected',
  };

  /// Parses a wire value; unknown values give `null`.
  static DutyEndReason? parse(String? wire) {
    for (final r in DutyEndReason.values) {
      if (r.wire == wire) return r;
    }
    return null;
  }
}

/// One raw fix from the sampler (before the VV-001 cadence filter).
@immutable
class LocationFix {
  /// Creates the fix.
  const LocationFix({
    required this.point,
    required this.accuracyM,
    required this.time,
    this.speedMps,
    this.bearing,
    this.isMock = false,
    this.provider,
  });

  /// Position.
  final GeoPoint point;

  /// Horizontal accuracy (m).
  final double accuracyM;

  /// Fix time (UTC).
  final DateTime time;

  /// Speed over ground (m/s), if known.
  final double? speedMps;

  /// Bearing (degrees), if known.
  final double? bearing;

  /// The fix came from a mock provider (`Position.isMocked`, FA-028).
  final bool isMock;

  /// `fused` | `gps` | `network`.
  final String? provider;

  /// `{lat, lon, accuracy_m}` for the duty session start / end point.
  Map<String, Object?> toPointJson() => <String, Object?>{
    'lat': point.latitude,
    'lon': point.longitude,
    'accuracy_m': accuracyM,
  };
}

/// FA-028 signals attached to every duty start, location point and visit.
/// They never block the user (SPEC: "flagged to validation agents, not
/// blocked").
@immutable
class IntegritySnapshot {
  /// Creates the snapshot.
  const IntegritySnapshot({
    this.isMock = false,
    this.isRooted = false,
    this.clockDriftS,
    this.clockJumped = false,
  });

  /// Parses the wire shape.
  factory IntegritySnapshot.fromJson(Map<String, Object?> json) =>
      IntegritySnapshot(
        isMock: json['is_mock'] == true,
        isRooted: json['is_rooted'] == true,
        clockDriftS: (json['clock_drift_s'] as num?)?.toInt(),
      );

  /// A mock-location provider is active or allowed.
  final bool isMock;

  /// Root / Magisk / test-keys detected.
  final bool isRooted;

  /// Device clock minus server clock in seconds; null until the first
  /// response with a `Date` header.
  final int? clockDriftS;

  /// The wall clock jumped against the monotonic clock since the last
  /// check (time tamper); local only, folded into [clockDriftS].
  final bool clockJumped;

  /// VV-004 integrity component fails at more than this drift.
  static const int driftLimitS = 300;

  /// Something to show the "device checks reported issues" banner for.
  bool get hasIssues =>
      isMock ||
      isRooted ||
      clockJumped ||
      (clockDriftS != null && clockDriftS!.abs() > driftLimitS);

  /// Contract shape `{is_mock, is_rooted, clock_drift_s}`.
  Map<String, Object?> toJson() => <String, Object?>{
    'is_mock': isMock,
    'is_rooted': isRooted,
    'clock_drift_s': clockDriftS,
  };

  /// Copy with overrides.
  IntegritySnapshot copyWith({bool? isMock}) => IntegritySnapshot(
    isMock: isMock ?? this.isMock,
    isRooted: isRooted,
    clockDriftS: clockDriftS,
    clockJumped: clockJumped,
  );

  @override
  bool operator ==(Object other) =>
      other is IntegritySnapshot &&
      other.isMock == isMock &&
      other.isRooted == isRooted &&
      other.clockDriftS == clockDriftS &&
      other.clockJumped == clockJumped;

  @override
  int get hashCode => Object.hash(isMock, isRooted, clockDriftS, clockJumped);
}

/// Maximum points in one `location_batch` op (contract).
const int maxPointsPerBatch = 500;
