/// SPEC 8.4 / NF-014: "remote config for feature flags and thresholds".
///
/// Two config planes already exist and this is the third, so the division of
/// labour matters more than the mechanism:
///
/// * **tenant settings** (`GET /v1/settings/public`, `PublicTenantSettings`)
///   are what a *tenant owner* decides: geofence radius, languages, whether
///   `on_device_crop_guess` is on for their officers. Audited, per tenant,
///   changed in the console.
/// * **remote config** (this file) is what *we* decide across every tenant
///   without shipping an APK: kill switches and thresholds. It is the
///   "remote-config kill switch" the bad-release runbook asks for -- the lever
///   that works when a release is already on 200,000 phones and the fix is a
///   week away.
/// * **build constants** are the floor: every flag here has a local default
///   that makes the app behave exactly as the last release did, so a phone
///   that never reaches Firebase, or a build with no Firebase at all, is not a
///   degraded phone.
///
/// Precedence where both planes speak (only `on_device_crop_guess` does
/// today): the tenant's *opt-in* is required, and remote config can only take
/// it away. A tenant cannot turn on a feature we have killed; we never turn on
/// a feature a tenant has not asked for. [FeatureFlags.onDeviceCropGuess]
/// implements exactly that.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// The flags and thresholds this app version understands, with the defaults
/// that apply when nothing has been fetched.
///
/// Adding a key here and reading it is the whole contract: an unknown key in
/// the remote payload is ignored, and a key missing from the payload keeps its
/// default, so an old app and a new config never disagree dangerously.
@immutable
class FeatureFlags {
  /// Creates the flags.
  const FeatureFlags({
    this.onDeviceCropGuessKilled = false,
    this.crashReportingEnabled = true,
    this.performanceMonitoringEnabled = true,
    this.traceSampleRatio = defaultTraceSampleRatio,
    this.samplingMovingS = defaultSamplingMovingS,
    this.samplingStationaryS = defaultSamplingStationaryS,
    this.samplingUploadS = defaultSamplingUploadS,
    this.minSupportedVersion = '',
  });

  /// Parses a remote payload leniently: wrong types and out-of-range values
  /// keep the default rather than breaking the app that reads them.
  factory FeatureFlags.fromMap(Map<String, Object?> values) {
    const d = FeatureFlags();
    bool flag(String key, {required bool fallback}) {
      final raw = values[key];
      if (raw is bool) return raw;
      if (raw is String) {
        if (raw.toLowerCase() == 'true') return true;
        if (raw.toLowerCase() == 'false') return false;
      }
      return fallback;
    }

    int seconds(String key, int fallback) {
      final raw = values[key];
      final parsed = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
      // A sampling interval of 0 would drain the battery in an hour and one of
      // a day would lose the officer's track: clamp, never trust.
      return parsed != null && parsed >= minSamplingS && parsed <= maxSamplingS
          ? parsed
          : fallback;
    }

    final ratioRaw = values['trace_sample_ratio'];
    final ratio = ratioRaw is num
        ? ratioRaw.toDouble()
        : double.tryParse('${ratioRaw ?? ''}');
    final minVersion = values['min_supported_version'];

    return FeatureFlags(
      onDeviceCropGuessKilled: flag(
        'on_device_crop_guess_killed',
        fallback: d.onDeviceCropGuessKilled,
      ),
      crashReportingEnabled: flag(
        'crash_reporting_enabled',
        fallback: d.crashReportingEnabled,
      ),
      performanceMonitoringEnabled: flag(
        'performance_monitoring_enabled',
        fallback: d.performanceMonitoringEnabled,
      ),
      traceSampleRatio: ratio != null && ratio >= 0 && ratio <= 1
          ? ratio
          : d.traceSampleRatio,
      samplingMovingS: seconds('sampling_moving_s', d.samplingMovingS),
      samplingStationaryS: seconds(
        'sampling_stationary_s',
        d.samplingStationaryS,
      ),
      samplingUploadS: seconds('sampling_upload_s', d.samplingUploadS),
      minSupportedVersion: minVersion is String ? minVersion : '',
    );
  }

  /// DX-001 kill switch. The tenant setting `on_device_crop_guess` opts a
  /// tenant *in*; this takes it away from everyone at once when the model
  /// misbehaves in the field, with no app release.
  final bool onDeviceCropGuessKilled;

  /// NF-014 / OPS-002: whether crash reports leave the device. A farmer who
  /// has not consented, or a country we have not cleared, is turned off here
  /// rather than by an app update.
  final bool crashReportingEnabled;

  /// NF-005: whether performance traces leave the device.
  final bool performanceMonitoringEnabled;

  /// NF-014 head sampling of app -> API traces (0..1).
  final double traceSampleRatio;

  /// FA-010 location sampling while moving, in seconds.
  final int samplingMovingS;

  /// FA-010 location sampling while stationary, in seconds.
  final int samplingStationaryS;

  /// FA-010 upload interval of buffered points, in seconds.
  final int samplingUploadS;

  /// The oldest app version still supported (`major.minor.patch`). Empty
  /// means "no floor". The app shows the update prompt; it never blocks the
  /// outbox, because an officer with unsynced work must always be able to
  /// sync it.
  final String minSupportedVersion;

  /// Whether the DX-001 crop guess may be used, given the tenant's opt-in.
  ///
  /// Tenant opt-in AND not killed: the two planes can only ever agree to turn
  /// it on.
  bool onDeviceCropGuess({required bool tenantEnabled}) =>
      tenantEnabled && !onDeviceCropGuessKilled;

  /// Defaults (SPEC 3 / FA-010), duplicated nowhere: `PublicTenantSettings`
  /// reads the same numbers from the API.
  static const int defaultSamplingMovingS = 120;

  /// Stationary sampling default, in seconds.
  static const int defaultSamplingStationaryS = 600;

  /// Upload interval default, in seconds.
  static const int defaultSamplingUploadS = 900;

  /// Trace sampling default: every request, until traffic makes that costly.
  static const double defaultTraceSampleRatio = 1;

  /// Clamp for any remotely configured interval.
  static const int minSamplingS = 30;

  /// Clamp for any remotely configured interval (one hour).
  static const int maxSamplingS = 3600;

  @override
  bool operator ==(Object other) =>
      other is FeatureFlags &&
      other.onDeviceCropGuessKilled == onDeviceCropGuessKilled &&
      other.crashReportingEnabled == crashReportingEnabled &&
      other.performanceMonitoringEnabled == performanceMonitoringEnabled &&
      other.traceSampleRatio == traceSampleRatio &&
      other.samplingMovingS == samplingMovingS &&
      other.samplingStationaryS == samplingStationaryS &&
      other.samplingUploadS == samplingUploadS &&
      other.minSupportedVersion == minSupportedVersion;

  @override
  int get hashCode => Object.hash(
    onDeviceCropGuessKilled,
    crashReportingEnabled,
    performanceMonitoringEnabled,
    traceSampleRatio,
    samplingMovingS,
    samplingStationaryS,
    samplingUploadS,
    minSupportedVersion,
  );
}

/// Fetches [FeatureFlags]. The apps implement it with Firebase Remote Config.
abstract interface class RemoteFlagSource {
  /// The flags in force right now (the local defaults until a fetch lands).
  FeatureFlags get flags;

  /// Fetches and activates. Returns the flags in force afterwards; a failure
  /// (offline, no Firebase, throttled) is not an error -- the last known good
  /// values stay in force.
  Future<FeatureFlags> refresh();
}

/// Always the local defaults. The fallback when the build has no Firebase.
class LocalRemoteFlags implements RemoteFlagSource {
  /// Creates the source, optionally with non-default values (tests).
  const LocalRemoteFlags([this.flags = const FeatureFlags()]);

  @override
  final FeatureFlags flags;

  @override
  Future<FeatureFlags> refresh() async => flags;
}

/// Serves a payload like a remote config would (tests, previews).
class FakeRemoteFlags implements RemoteFlagSource {
  /// Creates the fake over a remote payload that [refresh] will activate.
  FakeRemoteFlags({Map<String, Object?>? remote, this.fails = false})
    : _remote = remote ?? const <String, Object?>{};

  final Map<String, Object?> _remote;

  /// Whether [refresh] throws (an offline phone, a throttled fetch).
  final bool fails;

  /// How many times [refresh] was called.
  int refreshes = 0;

  FeatureFlags _flags = const FeatureFlags();

  @override
  FeatureFlags get flags => _flags;

  @override
  Future<FeatureFlags> refresh() async {
    refreshes += 1;
    if (fails) throw StateError('remote config unavailable');
    return _flags = FeatureFlags.fromMap(_remote);
  }
}

/// The flag source; the apps override it with their Firebase adapter.
final Provider<RemoteFlagSource> remoteFlagsProvider =
    Provider<RemoteFlagSource>((ref) => const LocalRemoteFlags());

/// The flags in force. Overridden at start-up with whatever was fetched, so
/// a widget reads flags synchronously and never rebuilds mid-frame.
final Provider<FeatureFlags> featureFlagsProvider = Provider<FeatureFlags>(
  (ref) => ref.watch(remoteFlagsProvider).flags,
);

/// Refreshes the flags and returns an override for [featureFlagsProvider].
///
/// Called before the first frame like `settingsOverrides` (FA-004): a kill
/// switch that only takes effect on the *second* start is not a kill switch.
/// A failure keeps the defaults and is swallowed -- the app starts either way.
Future<List<Override>> remoteFlagOverrides(RemoteFlagSource source) async {
  FeatureFlags flags;
  try {
    flags = await source.refresh();
  } on Object catch (e) {
    debugPrint('remote config: using local defaults ($e)');
    flags = source.flags;
  }
  return <Override>[
    remoteFlagsProvider.overrideWithValue(source),
    featureFlagsProvider.overrideWithValue(flags),
  ];
}
