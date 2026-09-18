import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../geo/geo.dart';
import 'duty_models.dart';

/// Raw GPS fixes for the duty tracker (VV-001).
///
/// FA-010 rule: the `DutyController` calls [start] only after a duty
/// session row exists and [stop] before the session ends; nothing else in
/// the app subscribes. Tests assert that [FakeLocationSampler.starts] stays
/// 0 while off duty.
abstract interface class LocationSampler {
  /// Raw fixes while running (the controller applies [SamplingCadence]).
  Stream<LocationFix> get fixes;

  /// Begins sampling with [policy]'s moving interval as the provider hint.
  Future<void> start(DutyPolicy policy);

  /// Stops sampling; no fix is emitted afterwards.
  Future<void> stop();

  /// Sampling right now.
  bool get isRunning;

  /// One fix now (duty start / end point), or null when unavailable.
  Future<LocationFix?> current();
}

/// Scriptable sampler for tests and previews.
class FakeLocationSampler implements LocationSampler {
  /// Creates the sampler.
  FakeLocationSampler({this.initial});

  final StreamController<LocationFix> _controller =
      StreamController<LocationFix>.broadcast();

  /// What [current] answers.
  LocationFix? initial;

  /// Times [start] was called.
  int starts = 0;

  /// Times [stop] was called.
  int stops = 0;

  /// Policy of the last [start].
  DutyPolicy? lastPolicy;

  bool _running = false;

  /// Fixes emitted while not running (must stay empty: FA-010).
  final List<LocationFix> droppedWhileStopped = <LocationFix>[];

  /// Emits a fix to the controller (ignored while stopped, and counted).
  void emit(LocationFix fix) {
    initial = fix;
    if (!_running) {
      droppedWhileStopped.add(fix);
      return;
    }
    _controller.add(fix);
  }

  @override
  Stream<LocationFix> get fixes => _controller.stream;

  @override
  Future<void> start(DutyPolicy policy) async {
    starts += 1;
    lastPolicy = policy;
    _running = true;
  }

  @override
  Future<void> stop() async {
    stops += 1;
    _running = false;
  }

  @override
  bool get isRunning => _running;

  @override
  Future<LocationFix?> current() async => initial;

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}

/// [LocationSampler] over `geolocator`'s fused provider.
///
/// Android settings: high accuracy, `intervalDuration` = the moving
/// interval (the provider then batches at that rate; the cadence filter
/// drops to the stationary interval when the officer is not moving). The
/// persistent notification comes from the foreground service, not from
/// geolocator's own foreground config.
class GeolocatorLocationSampler implements LocationSampler {
  /// Creates the sampler.
  GeolocatorLocationSampler();

  final StreamController<LocationFix> _out =
      StreamController<LocationFix>.broadcast();
  StreamSubscription<Position>? _sub;

  /// Maps a geolocator [Position] to a [LocationFix].
  static LocationFix fromPosition(Position p) => LocationFix(
    point: GeoPoint(p.latitude, p.longitude),
    accuracyM: p.accuracy,
    time: p.timestamp.toUtc(),
    speedMps: p.speed.isNaN || p.speed < 0 ? null : p.speed,
    bearing: p.heading.isNaN || p.heading < 0 ? null : p.heading,
    isMock: p.isMocked,
    provider: 'fused',
  );

  @override
  Stream<LocationFix> get fixes => _out.stream;

  @override
  bool get isRunning => _sub != null;

  @override
  Future<void> start(DutyPolicy policy) async {
    if (_sub != null) return;
    _sub =
        Geolocator.getPositionStream(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            intervalDuration: policy.movingInterval,
          ),
        ).listen(
          (p) => _out.add(fromPosition(p)),
          onError: (Object _) {
            // A provider hiccup must not end the shift; the next fix
            // resumes the stream.
          },
        );
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  @override
  Future<LocationFix?> current() async {
    try {
      return fromPosition(
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        ),
      );
    } on Exception {
      return null;
    }
  }
}

/// VV-001 cadence: keep a fix every [DutyPolicy.movingInterval] while
/// moving (speed > [movingSpeedMps] or moved > [movedMetres] since the last
/// kept fix) and every [DutyPolicy.stationaryInterval] otherwise. The first
/// fix is always kept. Pure and clock-free: decisions use the fix times.
class SamplingCadence {
  /// Creates the filter.
  SamplingCadence(
    this.policy, {
    this.movingSpeedMps = 0.5,
    this.movedMetres = 50,
  });

  /// Intervals.
  final DutyPolicy policy;

  /// Speed above which the officer counts as moving.
  final double movingSpeedMps;

  /// Displacement above which the officer counts as moving.
  final double movedMetres;

  LocationFix? _last;

  /// The last kept fix.
  LocationFix? get last => _last;

  /// Restores the filter after a restart from the last stored point.
  void seed(LocationFix? last) => _last = last;

  /// Whether [fix] would count as moving relative to the last kept fix.
  bool isMoving(LocationFix fix) {
    final last = _last;
    if (last == null) return true;
    if ((fix.speedMps ?? 0) > movingSpeedMps) return true;
    return distanceMetres(last.point, fix.point) > movedMetres;
  }

  /// Keeps or drops [fix]; kept fixes become the reference.
  bool accept(LocationFix fix) {
    final last = _last;
    if (last == null) {
      _last = fix;
      return true;
    }
    final elapsed = fix.time.difference(last.time);
    if (elapsed.isNegative) return false;
    final interval = isMoving(fix)
        ? policy.movingInterval
        : policy.stationaryInterval;
    if (elapsed < interval) return false;
    _last = fix;
    return true;
  }
}
