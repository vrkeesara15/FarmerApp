import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:geolocator/geolocator.dart';

import '../geo/geo.dart';

/// One GPS fix.
@immutable
class GeoFix {
  /// Creates the fix.
  const GeoFix({
    required this.point,
    required this.accuracyMetres,
    required this.time,
  });

  /// Position.
  final GeoPoint point;

  /// Horizontal accuracy (68 %) in metres.
  final double accuracyMetres;

  /// When the fix was taken (UTC).
  final DateTime time;
}

/// Why no fix can be obtained.
enum LocationAvailability {
  /// Ready.
  available,

  /// Location services are switched off on the device.
  serviceDisabled,

  /// The user denied the permission.
  permissionDenied,
}

/// GPS access for A21b walk-around capture (FA-012).
///
/// FA-010: location is read only while the officer has explicitly started
/// a walk on the boundary step; nothing subscribes outside that.
abstract interface class LocationSource {
  /// Checks the service and permission, asking once when undetermined.
  Future<LocationAvailability> ensureAvailable();

  /// Continuous fixes (highest accuracy) until the subscription is cancelled.
  Stream<GeoFix> watch();

  /// One fix now, or `null` when unavailable.
  Future<GeoFix?> current();
}

/// Scriptable source for tests and previews.
class FakeLocationSource implements LocationSource {
  /// Creates the source.
  FakeLocationSource({
    this.availability = LocationAvailability.available,
    this.initial,
  });

  /// What [ensureAvailable] answers.
  LocationAvailability availability;

  /// What [current] answers.
  GeoFix? initial;

  final StreamController<GeoFix> _controller =
      StreamController<GeoFix>.broadcast();

  /// Active [watch] subscriptions.
  int get listeners => _listeners;
  int _listeners = 0;

  /// Emits a fix to every watcher.
  void emit(GeoFix fix) {
    initial = fix;
    _controller.add(fix);
  }

  @override
  Future<LocationAvailability> ensureAvailable() async => availability;

  @override
  Stream<GeoFix> watch() {
    late StreamController<GeoFix> out;
    StreamSubscription<GeoFix>? sub;
    out = StreamController<GeoFix>(
      onListen: () {
        _listeners += 1;
        sub = _controller.stream.listen(out.add);
      },
      onCancel: () async {
        _listeners -= 1;
        await sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<GeoFix?> current() async => initial;

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}

/// [LocationSource] over `geolocator`.
class GeolocatorLocationSource implements LocationSource {
  /// Creates the source.
  const GeolocatorLocationSource({this.settings = const LocationSettings()});

  /// Stream settings.
  final LocationSettings settings;

  static GeoFix _fix(Position p) => GeoFix(
    point: GeoPoint(p.latitude, p.longitude),
    accuracyMetres: p.accuracy,
    time: p.timestamp.toUtc(),
  );

  @override
  Future<LocationAvailability> ensureAvailable() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAvailability.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAvailability.available,
      _ => LocationAvailability.permissionDenied,
    };
  }

  @override
  Stream<GeoFix> watch() =>
      Geolocator.getPositionStream(locationSettings: settings).map(_fix);

  @override
  Future<GeoFix?> current() async {
    try {
      return _fix(
        await Geolocator.getCurrentPosition(locationSettings: settings),
      );
    } on Exception {
      return null;
    }
  }
}
