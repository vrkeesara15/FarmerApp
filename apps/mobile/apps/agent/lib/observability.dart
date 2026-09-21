import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// NF-014 / SPEC 8.4 transports for the officer app: Crashlytics, Performance
/// and Remote Config behind the core's seams, like the FA-007 push transport
/// in `push.dart`. Nothing above this file knows about Firebase.
///
/// **Builds without Firebase.** `firebase_core` compiles on Android with no
/// `google-services.json`; what fails is `Firebase.initializeApp()` at
/// runtime. [MitraObservability.create] catches that and returns
/// [MitraObservability.disabled], so a developer build, CI and a reference
/// device all run with reporting simply switched off. Observability is
/// diagnostics; an officer's day never depends on it.
///
/// **The background isolate.** `callbackDispatcher` (FA-025 WorkManager sync)
/// runs in an isolate with no `ProviderContainer` and no Firebase app. It does
/// not report, by design: a failed background sync is already visible as
/// outbox backlog and in the sync SLO, and initialising Firebase in that
/// isolate would cost a second Firebase app on every 15-minute wake-up.
class MitraObservability {
  /// Creates the bundle.
  const MitraObservability({
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
  static const MitraObservability disabled = MitraObservability(
    crashes: NoCrashReporter(),
    performance: NoPerformanceMonitor(),
    flags: LocalRemoteFlags(),
  );

  /// Initialises Firebase and the three services.
  ///
  /// [appVersion] becomes a Crashlytics custom key, which is what makes
  /// "crash-free sessions per app version" readable and so what halts a
  /// staged rollout (docs/runbooks/bad-mobile-release-rollback.md).
  ///
  /// Reporting is off in debug: a developer's own crashes would swamp the
  /// number that decides whether a release ships.
  static Future<MitraObservability> create({
    required String appVersion,
    bool enableInDebug = false,
  }) async {
    try {
      // Safe to call twice: main() may already have initialised Firebase for
      // push, and initializeApp returns the existing default app.
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
          // An officer is offline for hours at a time (NF-002), so the fetch
          // is opportunistic; an hour is the shortest interval Firebase's
          // quota allows in the field, and a kill switch nobody can pull for
          // 12 hours is not a kill switch.
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );

      return MitraObservability(
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
  // become a second error, and never the error the officer sees.
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
/// The in-app defaults come from [FeatureFlags]'s own defaults, so a phone
/// that has never fetched behaves exactly like the shipped build and the
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
