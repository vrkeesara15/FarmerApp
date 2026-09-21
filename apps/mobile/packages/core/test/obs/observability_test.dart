import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// NF-014 / SPEC 8.4: crash reporting, performance traces and remote config,
/// all behind seams with a working no-Firebase fallback.
void main() {
  group('CrashReporter', () {
    test('the no-Firebase fallback swallows everything and says so', () async {
      const reporter = NoCrashReporter();
      expect(reporter.isEnabled, isFalse);
      // A build with no google-services.json must not crash *because* it
      // cannot report crashes.
      await reporter.recordError(StateError('x'), StackTrace.current);
      await reporter.log('breadcrumb');
      await reporter.setCustomKey(CrashKeys.traceId, 'abc');
      await reporter.setUserId('u-1');
    });

    test('the default provider is the fallback, so tests never report', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(crashReporterProvider), isA<NoCrashReporter>());
    });

    test('fatal and handled errors are distinguishable', () async {
      final reporter = FakeCrashReporter();
      await reporter.recordError(StateError('crash'), null, fatal: true);
      await reporter.recordError(
        Exception('upload gave up'),
        null,
        reason: 'photo upload',
      );

      expect(reporter.errors.map((e) => e.fatal), <bool>[true, false]);
      expect(reporter.errors.last.reason, 'photo upload');
    });

    test(
      'runWithCrashReporting reports a synchronous throw in the body',
      () async {
        final reporter = FakeCrashReporter();
        final previous = FlutterError.onError;
        addTearDown(() => FlutterError.onError = previous);

        await runWithCrashReporting(reporter, () async {
          throw StateError('start-up failed');
        });

        expect(reporter.errors.single.fatal, isTrue);
        expect(reporter.errors.single.error, isA<StateError>());
      },
    );

    test('runWithCrashReporting reports a widget error as fatal', () async {
      final reporter = FakeCrashReporter();
      final previous = FlutterError.onError;
      addTearDown(() => FlutterError.onError = previous);

      await runWithCrashReporting(reporter, () async {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: ArgumentError('bad widget'),
            context: ErrorDescription('building Foo'),
          ),
        );
      });

      expect(reporter.errors.single.error, isA<ArgumentError>());
      expect(reporter.errors.single.reason, contains('building Foo'));
    });

    test('the body still completes normally when nothing throws', () async {
      final reporter = FakeCrashReporter();
      final previous = FlutterError.onError;
      addTearDown(() => FlutterError.onError = previous);
      var ran = false;

      await runWithCrashReporting(reporter, () async => ran = true);

      expect(ran, isTrue);
      expect(reporter.errors, isEmpty);
    });
  });

  group('AppStartTrace (NF-005 / NF-001)', () {
    test('reports both numbers and whether the budget was met', () async {
      final clock = _Clock();
      final monitor = FakePerformanceMonitor();
      final logs = <String>[];
      final trace = AppStartTrace(now: clock.now, log: logs.add);

      clock.advance(const Duration(milliseconds: 1400));
      trace.markInteractive();
      clock.advance(const Duration(milliseconds: 500));
      // Stand in for the first-frame callback.
      await trace.report(monitor);

      expect(trace.timeToInteractive, const Duration(milliseconds: 1400));
      final recorded = monitor.traces.single;
      expect(recorded.name, AppStartTrace.appStartTraceName);
      expect(recorded.metrics['time_to_interactive_ms'], 1400);
      expect(recorded.stopped, isTrue);
      // Printed too: a release build on a reference device has no Firebase,
      // and `adb logcat` is the whole tool chain (docs/device-matrix.md).
      expect(logs.single, contains('interactive 1400 ms'));
    });

    test('markInteractive is idempotent: the first moment wins', () {
      final clock = _Clock();
      final trace = AppStartTrace(now: clock.now, log: (_) {});
      clock.advance(const Duration(milliseconds: 900));
      trace.markInteractive();
      clock.advance(const Duration(seconds: 5));
      trace.markInteractive();
      expect(trace.timeToInteractive, const Duration(milliseconds: 900));
    });

    test('a start over the NF-005 budget is marked, not hidden', () async {
      final clock = _Clock();
      final monitor = FakePerformanceMonitor();
      final trace = AppStartTrace(now: clock.now, log: (_) {});
      clock.advance(const Duration(milliseconds: 4200));
      trace.markInteractive();
      await trace.report(monitor);
      expect(monitor.traces.single.attributes['within_budget'], 'false');
    });

    test('the first rasterised frame ends the trace exactly once', () async {
      final clock = _Clock();
      final monitor = FakePerformanceMonitor();
      final trace = AppStartTrace(now: clock.now, log: (_) {});
      final added = <TimingsCallback>[];
      final removed = <TimingsCallback>[];
      trace.reportFirstFrame(
        monitor,
        addTimingsCallback: added.add,
        removeTimingsCallback: removed.add,
      );

      clock.advance(const Duration(milliseconds: 1900));
      added.single(<FrameTiming>[_timing()]);
      // A second frame, as every app has 60 of per second.
      clock.advance(const Duration(seconds: 30));
      added.single(<FrameTiming>[_timing()]);
      await Future<void>.delayed(Duration.zero);

      expect(trace.timeToFirstFrame, const Duration(milliseconds: 1900));
      expect(
        monitor.traces,
        hasLength(1),
        reason: 'only the first frame is a cold start',
      );
      expect(monitor.traces.single.metrics['time_to_first_frame_ms'], 1900);
      expect(monitor.traces.single.attributes['within_budget'], 'true');
      expect(
        removed.single,
        same(added.single),
        reason: 'the callback must detach, or it costs a call every frame',
      );
    });

    test('a frame callback with no timings is not a first frame', () async {
      final monitor = FakePerformanceMonitor();
      final trace = AppStartTrace(log: (_) {});
      final added = <TimingsCallback>[];
      trace.reportFirstFrame(
        monitor,
        addTimingsCallback: added.add,
        removeTimingsCallback: (_) {},
      );
      added.single(const <FrameTiming>[]);
      await Future<void>.delayed(Duration.zero);
      expect(trace.timeToFirstFrame, isNull);
      expect(monitor.traces, isEmpty);
    });

    test(
      'NoPerformanceMonitor accepts a whole trace and reports nothing',
      () async {
        const monitor = NoPerformanceMonitor();
        expect(monitor.isEnabled, isFalse);
        final trace = await monitor.start('x');
        trace
          ..setMetric('a', 1)
          ..setAttribute('b', 'c');
        await trace.stop();
      },
    );
  });

  group('FeatureFlags (SPEC 8.4 remote config)', () {
    test('the local defaults are the last release behaviour', () {
      const flags = FeatureFlags();
      expect(flags.onDeviceCropGuessKilled, isFalse);
      expect(flags.crashReportingEnabled, isTrue);
      expect(flags.samplingMovingS, 120);
      expect(flags.samplingStationaryS, 600);
      expect(flags.samplingUploadS, 900);
      expect(flags.traceSampleRatio, 1);
      expect(flags.minSupportedVersion, '');
    });

    test('a remote payload overrides only the keys it names', () {
      final flags = FeatureFlags.fromMap(const <String, Object?>{
        'on_device_crop_guess_killed': true,
        'sampling_moving_s': 300,
        'unknown_future_key': 'ignored',
      });
      expect(flags.onDeviceCropGuessKilled, isTrue);
      expect(flags.samplingMovingS, 300);
      // Untouched keys keep the default, so an old app and a new config never
      // disagree dangerously.
      expect(flags.samplingStationaryS, 600);
      expect(flags.crashReportingEnabled, isTrue);
    });

    test('Remote Config strings are accepted (its values are strings)', () {
      final flags = FeatureFlags.fromMap(const <String, Object?>{
        'crash_reporting_enabled': 'false',
        'sampling_upload_s': '600',
        'trace_sample_ratio': '0.25',
      });
      expect(flags.crashReportingEnabled, isFalse);
      expect(flags.samplingUploadS, 600);
      expect(flags.traceSampleRatio, 0.25);
    });

    test('a dangerous or malformed value keeps the default', () {
      final flags = FeatureFlags.fromMap(const <String, Object?>{
        // 0 s sampling would flatten the battery within an hour (FA-010).
        'sampling_moving_s': 0,
        // A day is not sampling; the officer's track would be two points.
        'sampling_stationary_s': 90000,
        'sampling_upload_s': 'soon',
        'trace_sample_ratio': 7,
        'crash_reporting_enabled': 'maybe',
      });
      expect(flags.samplingMovingS, 120);
      expect(flags.samplingStationaryS, 600);
      expect(flags.samplingUploadS, 900);
      expect(flags.traceSampleRatio, 1);
      expect(flags.crashReportingEnabled, isTrue);
    });

    test('the kill switch can only take the crop guess away', () {
      const live = FeatureFlags();
      const killed = FeatureFlags(onDeviceCropGuessKilled: true);
      // The tenant opts in (WC-012 / DX-001); we can only veto.
      expect(live.onDeviceCropGuess(tenantEnabled: true), isTrue);
      expect(killed.onDeviceCropGuess(tenantEnabled: true), isFalse);
      // And we never turn on what a tenant has not asked for.
      expect(live.onDeviceCropGuess(tenantEnabled: false), isFalse);
      expect(killed.onDeviceCropGuess(tenantEnabled: false), isFalse);
    });
  });

  group('remoteFlagOverrides', () {
    test('activates the fetched values before the first frame', () async {
      final source = FakeRemoteFlags(
        remote: <String, Object?>{'on_device_crop_guess_killed': true},
      );
      final container = ProviderContainer(
        overrides: await remoteFlagOverrides(source),
      );
      addTearDown(container.dispose);

      expect(source.refreshes, 1);
      expect(
        container.read(featureFlagsProvider).onDeviceCropGuessKilled,
        isTrue,
      );
    });

    test('a failed fetch starts the app on the local defaults', () async {
      final source = FakeRemoteFlags(fails: true);
      final container = ProviderContainer(
        overrides: await remoteFlagOverrides(source),
      );
      addTearDown(container.dispose);

      expect(container.read(featureFlagsProvider), const FeatureFlags());
    });

    test('the default provider is the local source', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(remoteFlagsProvider), isA<LocalRemoteFlags>());
      expect(container.read(featureFlagsProvider), const FeatureFlags());
    });
  });
}

FrameTiming _timing() => FrameTiming(
  vsyncStart: 0,
  buildStart: 0,
  buildFinish: 8000,
  rasterStart: 8000,
  rasterFinish: 16000,
  rasterFinishWallTime: 16000,
);

class _Clock {
  DateTime _now = DateTime.utc(2026, 9, 19, 6);

  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);
}
