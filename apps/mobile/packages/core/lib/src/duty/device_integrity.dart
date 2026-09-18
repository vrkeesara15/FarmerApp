import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:safe_device/safe_device.dart';

import 'duty_models.dart';

/// Root and mock-location probes (FA-028); the real one asks the platform.
abstract interface class DeviceIntegrityProbe {
  /// Root / Magisk / test-keys / su binaries detected.
  Future<bool> isRooted();

  /// "Allow mock locations" is on or a mock provider is installed.
  Future<bool> mockLocationAllowed();
}

/// Scriptable probe for tests and previews.
class FakeDeviceIntegrityProbe implements DeviceIntegrityProbe {
  /// Creates the probe.
  FakeDeviceIntegrityProbe({this.rooted = false, this.mockAllowed = false});

  /// What [isRooted] answers.
  bool rooted;

  /// What [mockLocationAllowed] answers.
  bool mockAllowed;

  @override
  Future<bool> isRooted() async => rooted;

  @override
  Future<bool> mockLocationAllowed() async => mockAllowed;
}

/// [DeviceIntegrityProbe] over `safe_device` (su binaries, test-keys,
/// Magisk paths, `ALLOW_MOCK_LOCATION` / mock provider apps). Any
/// platform failure reads as "not detected": detection never blocks.
class SafeDeviceIntegrityProbe implements DeviceIntegrityProbe {
  /// Creates the probe.
  const SafeDeviceIntegrityProbe();

  @override
  Future<bool> isRooted() async {
    try {
      return await SafeDevice.isJailBroken;
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> mockLocationAllowed() async {
    try {
      return await SafeDevice.isMockLocation;
    } on Exception {
      return false;
    }
  }
}

/// Monotonic elapsed time (`SystemClock.elapsedRealtime` on Android via
/// Dart's [Stopwatch], which the VM backs with the monotonic clock).
typedef MonotonicClock = Duration Function();

/// Tracks the device clock against the server (`Date` header of any API
/// response) and against the monotonic clock (time tamper, FA-028).
///
/// `driftSeconds` = device − server, refreshed on every response. A
/// wall-clock jump against the monotonic clock between two [checkpoint]s
/// moves the drift by the same amount (the server did not move) and sets
/// [clockJumped] until the next server response corrects it.
class ClockDriftTracker {
  /// Creates the tracker; [initialDrift] restores a persisted value.
  ClockDriftTracker({
    int? initialDrift,
    MonotonicClock? monotonic,
    this.jumpThreshold = const Duration(seconds: 60),
    this.onChanged,
  }) : _drift = initialDrift,
       _monotonic = monotonic ?? _stopwatchClock();

  static MonotonicClock _stopwatchClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  final MonotonicClock _monotonic;

  /// Smallest wall-vs-monotonic disagreement treated as a jump.
  final Duration jumpThreshold;

  /// Called with the new drift after every change (persist it here).
  final void Function(int drift)? onChanged;

  int? _drift;
  bool _jumped = false;
  DateTime? _lastWall;
  Duration? _lastMono;

  /// Device − server in seconds; null until the first server response.
  int? get driftSeconds => _drift;

  /// A jump was detected since the last server response.
  bool get clockJumped => _jumped;

  /// Records a server `Date` header ([serverUtc]) received at [deviceUtc].
  void record(DateTime serverUtc, DateTime deviceUtc) {
    _drift = deviceUtc.toUtc().difference(serverUtc.toUtc()).inSeconds;
    _jumped = false;
    _lastWall = deviceUtc.toUtc();
    _lastMono = _monotonic();
    onChanged?.call(_drift!);
  }

  /// Compares the wall clock with the monotonic clock since the previous
  /// checkpoint; returns the detected jump in seconds (0 when none).
  int checkpoint(DateTime deviceUtc) {
    final wall = deviceUtc.toUtc();
    final mono = _monotonic();
    var jump = 0;
    final lastWall = _lastWall;
    final lastMono = _lastMono;
    if (lastWall != null && lastMono != null) {
      final expected = lastWall.add(mono - lastMono);
      final delta = wall.difference(expected);
      if (delta.abs() >= jumpThreshold) {
        jump = delta.inSeconds;
        _drift = (_drift ?? 0) + jump;
        _jumped = true;
        onChanged?.call(_drift!);
      }
    }
    _lastWall = wall;
    _lastMono = mono;
    return jump;
  }

  /// Restores a persisted drift when nothing fresher is known.
  void restore(int drift) => _drift ??= drift;

  /// Test hook: the drift as the tracker would persist it.
  @visibleForTesting
  int? get persistedDrift => _drift;
}

/// FA-028 device integrity: combines the probes, the clock tracker and the
/// per-fix mock flag into an [IntegritySnapshot] for duty starts, location
/// points and visits.
class DeviceIntegrity {
  /// Creates the service.
  DeviceIntegrity({
    required this.probe,
    required this.clock,
    this.probeCacheFor = const Duration(minutes: 5),
  });

  /// Root / mock probes.
  final DeviceIntegrityProbe probe;

  /// Clock drift and jumps.
  final ClockDriftTracker clock;

  /// Probes are slow-ish native calls; results are cached this long.
  final Duration probeCacheFor;

  bool _rooted = false;
  bool _mockAllowed = false;
  Duration? _probedAtMono;
  final Stopwatch _sw = Stopwatch()..start();

  Future<void> _probeIfStale() async {
    final at = _probedAtMono;
    if (at != null && _sw.elapsed - at < probeCacheFor) return;
    _rooted = await probe.isRooted();
    _mockAllowed = await probe.mockLocationAllowed();
    _probedAtMono = _sw.elapsed;
  }

  /// The current signals; [fixIsMock] is the per-fix `Position.isMocked`
  /// (OR-ed with the "allow mock locations" probe).
  Future<IntegritySnapshot> snapshot({
    bool fixIsMock = false,
    DateTime? now,
  }) async {
    await _probeIfStale();
    if (now != null) clock.checkpoint(now);
    return IntegritySnapshot(
      isMock: fixIsMock || _mockAllowed,
      isRooted: _rooted,
      clockDriftS: clock.driftSeconds,
      clockJumped: clock.clockJumped,
    );
  }
}
