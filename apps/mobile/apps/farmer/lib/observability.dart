import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// NF-014 / SPEC 8.4 transports for the farmer app: Crashlytics, Performance
/// and Remote Config behind the core's seams. Nothing above this file knows
/// about Firebase, exactly as with the FA-007 push transport.
///
/// [FarmerObservability.create] initialises all three and, on any failure,
/// returns the core's no-op implementations: a build without
/// `android/app/google-services.json` (a human gate), a device with no Play
/// services, or a Firebase project that has not been created yet all end up
/// with an app that works and reports nothing. Observability is diagnostics;
/// it is never a dependency of the farmer's work.
class FarmerObservability {
  /// Creates the bundle.
  const FarmerObservability({
    required this.crashes,
    required this.performance,
    required this.flags,
  });

  /// Crash and non-fatal reporting (OPS-002 crash-free sessions per version).
  final CrashReporter crashes;

  /// Performance traces (NF-005 cold start, network timings).
  final PerformanceMonitor performance;

  /// Remote flags and thresholds, with the local defaults as the floor.
  final RemoteFlagSource flags;

  /// Everything off. The fallback, and what tests get.
  static const FarmerObservability disabled = FarmerObservability(
    crashes: NoCrashReporter(),
    performance: NoPerformanceMonitor(),
    flags: LocalRemoteFlags(),
  );

  /// Initialises Firebase and the three services.
  ///
  /// [appVersion] is set as a Crashlytics custom key so a Crashlytics issue
  /// can be read per version, which is what halts a staged rollout
  /// (docs/runbooks/bad-mobile-release-rollback.md).
  ///
  /// Reporting is off in debug: a developer's own crashes would swamp the
  /// crash-free-sessions number that decides whether a release ships.
  static Future<FarmerObservability> create({
    required String appVersion,
    bool enableInDebug = false,
  }) async {
    try {
      await Firebase.initializeApp();
      final collect = !kDebugMode || enableInDebug;

      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(collect);
      await crashlytics.setCustomKey(CrashKeys.appVersion, appVersion);

      final performance = FirebasePerformance.instance;
      await performance.setPerformanceCollectionEnabled(collect);

      final config = FirebaseRemoteConfig.instance;
      await config.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          // A kill switch nobody can pull for 12 hours is not a kill switch;
          // an hour is the compromise Firebase's quota allows in the field.
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );

      return FarmerObservability(
        crashes: FirebaseCrashReporter(crashlytics, isEnabled: collect),
        performance: FirebasePerformanceMonitor(
          performance,
          isEnabled: collect,
        ),
        flags: FirebaseRemoteFlags(config),
      );
    } on Object catch (e) {
      debugPrint('observability: Firebase unavailable ($e); reporting is off');
      return disabled;
    }
  }
}

/// [CrashReporter] over Firebase Crashlytics.
class FirebaseCrashReporter implements CrashReporter {
  /// Creates the reporter.
  const FirebaseCrashReporter(this._crashlytics, {this.isEnabled = true});

  final FirebaseCrashlytics _crashlytics;

  @override
  final bool isEnabled;

  // Every method swallows its own failures: a reporting error must never
  // become a second error, and never the error the farmer sees.
  Future<void> _guard(Future<void> Function() body) async {
    if (!isEnabled) return;
    try {
      await body();
    } on Object catch (e) {
      debugPrint('crashlytics: $e');
    }
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) => _guard(
    () => _crashlytics.recordError(error, stack, reason: reason, fatal: fatal),
  );

  @override
  Future<void> log(String message) =>
      _guard(() async => _crashlytics.log(message));

  @override
  Future<void> setCustomKey(String key, Object value) =>
      _guard(() => _crashlytics.setCustomKey(key, value));

  @override
  Future<void> setUserId(String? id) =>
      _guard(() => _crashlytics.setUserIdentifier(id ?? ''));
}

/// [PerformanceMonitor] over Firebase Performance.
class FirebasePerformanceMonitor implements PerformanceMonitor {
  /// Creates the monitor.
  const FirebasePerformanceMonitor(this._performance, {this.isEnabled = true});

  final FirebasePerformance _performance;

  @override
  final bool isEnabled;

  @override
  Future<PerfTrace> start(String name) async {
    if (!isEnabled) return const NoPerformanceMonitor().start(name);
    try {
      final trace = _performance.newTrace(name);
      await trace.start();
      return _FirebaseTrace(trace);
    } on Object catch (e) {
      debugPrint('performance: $e');
      return const NoPerformanceMonitor().start(name);
    }
  }
}

class _FirebaseTrace implements PerfTrace {
  const _FirebaseTrace(this._trace);

  final Trace _trace;

  @override
  void setMetric(String name, int value) => _trace.setMetric(name, value);

  @override
  void setAttribute(String name, String value) =>
      _trace.putAttribute(name, value);

  @override
  Future<void> stop() async {
    try {
      await _trace.stop();
    } on Object catch (e) {
      debugPrint('performance: $e');
    }
  }
}

/// [RemoteFlagSource] over Firebase Remote Config.
///
/// The in-app defaults are set from [FeatureFlags]'s own defaults, so a phone
/// that has never fetched behaves exactly like the shipped build, and the
/// Firebase console shows the same numbers the code uses.
class FirebaseRemoteFlags implements RemoteFlagSource {
  /// Creates the source.
  FirebaseRemoteFlags(this._config);

  final FirebaseRemoteConfig _config;

  FeatureFlags _flags = const FeatureFlags();

  @override
  FeatureFlags get flags => _flags;

  @override
  Future<FeatureFlags> refresh() async {
    const defaults = FeatureFlags();
    await _config.setDefaults(<String, Object>{
      'on_device_crop_guess_killed': defaults.onDeviceCropGuessKilled,
      'crash_reporting_enabled': defaults.crashReportingEnabled,
      'performance_monitoring_enabled': defaults.performanceMonitoringEnabled,
      'trace_sample_ratio': defaults.traceSampleRatio,
      'sampling_moving_s': defaults.samplingMovingS,
      'sampling_stationary_s': defaults.samplingStationaryS,
      'sampling_upload_s': defaults.samplingUploadS,
      'min_supported_version': defaults.minSupportedVersion,
    });
    await _config.fetchAndActivate();
    return _flags = FeatureFlags.fromMap(<String, Object?>{
      for (final entry in _config.getAll().entries)
        entry.key: entry.value.asString(),
    });
  }
}
