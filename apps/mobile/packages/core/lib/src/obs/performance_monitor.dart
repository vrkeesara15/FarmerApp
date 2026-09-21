/// NF-005 / NF-001 / SPEC 8.4: performance traces behind a seam, and the cold
/// start measurement NF-001's reference devices are judged on.
///
/// NF-005 says "app cold start < 3 s on the reference low-end device" and
/// NF-001 names three such devices. A number measured on a developer's phone
/// proves nothing about a 2 GB Redmi, so the app has to measure itself, on the
/// device, in a release build: that is [AppStartTrace].
///
/// The transport is Firebase Performance, in the apps
/// (`apps/*/lib/observability.dart`), behind the same no-Firebase fallback as
/// push and Crashlytics. With no Firebase the start time is still measured and
/// still logged (`debugPrint`), so `flutter run --release` on a reference
/// device gives the number without any cloud at all -- which is how
/// docs/device-matrix.md tells a tester to take it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One running trace.
abstract interface class PerfTrace {
  /// Attaches a number to the trace (bytes, rows, milliseconds).
  void setMetric(String name, int value);

  /// Attaches a label (screen, crop, result) -- never personal data.
  void setAttribute(String name, String value);

  /// Stops the trace and reports it.
  Future<void> stop();
}

/// Starts traces.
abstract interface class PerformanceMonitor {
  /// Whether traces actually leave the device.
  bool get isEnabled;

  /// Starts a trace named [name] (`app_start`, `sync_batch`, `diagnosis`).
  Future<PerfTrace> start(String name);
}

/// A trace that goes nowhere.
class _NoTrace implements PerfTrace {
  const _NoTrace();

  @override
  void setMetric(String name, int value) {}

  @override
  void setAttribute(String name, String value) {}

  @override
  Future<void> stop() async {}
}

/// Measures nothing. The fallback when the build has no Firebase.
class NoPerformanceMonitor implements PerformanceMonitor {
  /// Creates the monitor.
  const NoPerformanceMonitor();

  @override
  bool get isEnabled => false;

  @override
  Future<PerfTrace> start(String name) async => const _NoTrace();
}

/// One trace recorded in memory (tests, previews).
class RecordedTrace implements PerfTrace {
  /// Creates the record.
  RecordedTrace(this.name);

  /// Trace name.
  final String name;

  /// Metrics set on it.
  final Map<String, int> metrics = <String, int>{};

  /// Attributes set on it.
  final Map<String, String> attributes = <String, String>{};

  /// Whether [stop] was called.
  bool stopped = false;

  @override
  void setMetric(String name, int value) => metrics[name] = value;

  @override
  void setAttribute(String name, String value) => attributes[name] = value;

  @override
  Future<void> stop() async => stopped = true;
}

/// Records traces in memory.
class FakePerformanceMonitor implements PerformanceMonitor {
  /// Traces started, in order.
  final List<RecordedTrace> traces = <RecordedTrace>[];

  @override
  bool get isEnabled => true;

  @override
  Future<PerfTrace> start(String name) async {
    final trace = RecordedTrace(name);
    traces.add(trace);
    return trace;
  }
}

/// The performance monitor; the apps override it with their Firebase adapter.
final Provider<PerformanceMonitor> performanceMonitorProvider =
    Provider<PerformanceMonitor>((ref) => const NoPerformanceMonitor());

/// Cold start, measured on the device (NF-005: < 3 s; NF-001: on each of the
/// three reference devices).
///
/// Two numbers, because they answer different questions:
///
/// * **to first frame** -- what the farmer experiences as "the app opened".
///   Measured from the first line of `main()` to the end of the frame the
///   engine actually rasterised, via [SchedulerBinding.addTimingsCallback],
///   not from a `addPostFrameCallback` (which fires before the raster work and
///   flatters the number by tens of milliseconds on a slow GPU).
/// * **to interactive** -- the point where the app has its database, settings
///   and session and the farmer can act. [markInteractive] is called from the
///   app's start-up path.
///
/// The process start itself is earlier than Dart's `main()` (the zygote fork,
/// the engine, the Dart isolate), so this under-reports what a stopwatch in a
/// tester's hand would show; docs/device-matrix.md says to take the manual
/// number as the acceptance one and this as the trend.
class AppStartTrace {
  /// Starts the clock. Call it as the first statement of `main()`.
  AppStartTrace({DateTime Function()? now, void Function(String)? log})
    : log = log ?? _printLine,
      _now = now ?? DateTime.now,
      _startedAt = (now ?? DateTime.now)();

  static void _printLine(String line) => debugPrint(line);

  final DateTime Function() _now;
  final DateTime _startedAt;

  /// Where the measured numbers are printed (a release build on a reference
  /// device has no Firebase, and `adb logcat` is the whole tool chain).
  final void Function(String) log;

  Duration? _toFirstFrame;
  Duration? _toInteractive;
  bool _reported = false;

  /// Time from `main()` to the first rasterised frame, once it has happened.
  Duration? get timeToFirstFrame => _toFirstFrame;

  /// Time from `main()` to the app being usable, once [markInteractive] ran.
  Duration? get timeToInteractive => _toInteractive;

  /// The app is ready for input (database open, settings loaded, session
  /// restored). Safe to call more than once; the first call wins.
  void markInteractive() {
    _toInteractive ??= _now().difference(_startedAt);
  }

  /// Listens for the first rasterised frame and reports both numbers to
  /// [monitor] as the `app_start` trace.
  ///
  /// Call after `runApp`. The callback removes itself: only the *first* frame
  /// is a cold start, and leaving it attached would cost a callback on every
  /// frame for the life of the app.
  ///
  /// [addTimingsCallback] / [removeTimingsCallback] default to
  /// [SchedulerBinding.instance]; they are injectable because the test binding
  /// does not deliver real [FrameTiming]s, and "did it report exactly once"
  /// is the part worth proving.
  void reportFirstFrame(
    PerformanceMonitor monitor, {
    void Function(TimingsCallback)? addTimingsCallback,
    void Function(TimingsCallback)? removeTimingsCallback,
  }) {
    final add =
        addTimingsCallback ?? SchedulerBinding.instance.addTimingsCallback;
    final remove =
        removeTimingsCallback ??
        SchedulerBinding.instance.removeTimingsCallback;
    late TimingsCallback callback;
    callback = (timings) {
      if (_reported || timings.isEmpty) return;
      _reported = true;
      remove(callback);
      _toFirstFrame = _now().difference(_startedAt);
      unawaited(report(monitor));
    };
    add(callback);
  }

  /// Reports the numbers gathered so far. Exposed for tests and for a caller
  /// that measures the first frame itself.
  Future<void> report(PerformanceMonitor monitor) async {
    final firstFrame = _toFirstFrame;
    final interactive = _toInteractive;
    log(
      'app_start: first frame ${firstFrame?.inMilliseconds ?? '-'} ms, '
      'interactive ${interactive?.inMilliseconds ?? '-'} ms '
      '(NF-005 budget ${coldStartBudget.inMilliseconds} ms)',
    );
    final trace = await monitor.start(appStartTraceName);
    if (firstFrame != null) {
      trace.setMetric('time_to_first_frame_ms', firstFrame.inMilliseconds);
    }
    if (interactive != null) {
      trace.setMetric('time_to_interactive_ms', interactive.inMilliseconds);
    }
    // Whichever number we have: first frame when the app drew, otherwise the
    // interactive mark. An unmeasured start is never "within budget".
    final measured = firstFrame ?? interactive;
    trace.setAttribute(
      'within_budget',
      '${measured != null && measured <= coldStartBudget}',
    );
    await trace.stop();
  }

  /// Trace name, also the Firebase Performance trace to look for.
  static const String appStartTraceName = 'app_start';

  /// NF-005: cold start under 3 s on the reference low-end device.
  static const Duration coldStartBudget = Duration(seconds: 3);
}
