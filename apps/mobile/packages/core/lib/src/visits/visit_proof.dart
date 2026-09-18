import 'package:flutter/foundation.dart' show immutable, mapEquals;

import '../duty/duty_models.dart';
import '../geo/geo.dart';
import '../widgets/visit_score_badge.dart';
import 'visit_models.dart';

/// VV-004 weights, identical to `farmerapp/visits/scoring.py`.
abstract final class VisitScoreWeights {
  /// Inside the geofence (or at the meeting point).
  static const int geofence = 30;

  /// Farmer confirmed through one channel.
  static const int confirmation = 30;

  /// One in-app photo with matching EXIF time and GPS.
  static const int photo = 20;

  /// Duration at or above the tenant minimum.
  static const int duration = 10;

  /// No mock location, no root, drift within 300 s.
  static const int integrity = 10;

  /// An approved override earns this much of [geofence].
  static const int override = 15;

  /// Photo EXIF time may fall this far outside the visit window.
  static const Duration photoTimeTolerance = Duration(minutes: 10);

  /// Photo EXIF GPS may be this far from the check-in point.
  static const double photoDistanceM = 150;

  /// Component keys in the server's order.
  static const List<String> components = <String>[
    'geofence',
    'confirmation',
    'photo',
    'duration',
    'integrity',
  ];
}

/// What the scorer needs of a `visit_photo`.
@immutable
class PhotoEvidence {
  /// Creates the evidence.
  const PhotoEvidence({
    required this.takenInApp,
    this.exifTime,
    this.exifLat,
    this.exifLon,
  });

  /// From the in-app camera (a gallery photo never counts).
  final bool takenInApp;

  /// EXIF capture time (UTC).
  final DateTime? exifTime;

  /// EXIF GPS latitude.
  final double? exifLat;

  /// EXIF GPS longitude.
  final double? exifLon;

  /// FA-015 / VA-E08 match: in-app, EXIF time inside the widened window
  /// `[checkinAt - tol, windowEnd + tol]`, EXIF GPS near the check-in point.
  bool matches({
    required DateTime checkinAt,
    required DateTime windowEnd,
    required GeoPoint checkinPoint,
  }) {
    final time = exifTime;
    final lat = exifLat;
    final lon = exifLon;
    if (!takenInApp || time == null || lat == null || lon == null) {
      return false;
    }
    const tol = VisitScoreWeights.photoTimeTolerance;
    if (time.isBefore(checkinAt.subtract(tol)) ||
        time.isAfter(windowEnd.add(tol))) {
      return false;
    }
    return distanceMetres(checkinPoint, GeoPoint(lat, lon)) <=
        VisitScoreWeights.photoDistanceM;
  }
}

/// The expected score and the four proofs of A31 / A33.
@immutable
class VisitProof {
  /// Creates the proof.
  const VisitProof({
    required this.components,
    required this.elapsed,
    required this.minDuration,
  });

  /// Points per component (`geofence`, `confirmation`, `photo`,
  /// `duration`, `integrity`).
  final Map<String, int> components;

  /// Time from check-in to check-out (or to now while open).
  final Duration elapsed;

  /// Tenant minimum.
  final Duration minDuration;

  /// Total 0-100.
  int get score => components.values.fold<int>(0, (a, b) => a + b);

  /// VV-005 status for [score].
  VisitStatus get status => VisitStatus.fromScore(score);

  /// Inside the geofence, at the meeting point or approved override.
  bool get geofenceOk => (components['geofence'] ?? 0) > 0;

  /// Farmer confirmed.
  bool get confirmed => (components['confirmation'] ?? 0) > 0;

  /// A matching in-app photo exists.
  bool get photoOk => (components['photo'] ?? 0) > 0;

  /// Duration at or above the minimum.
  bool get durationOk => (components['duration'] ?? 0) > 0;

  /// Device integrity fine.
  bool get integrityOk => (components['integrity'] ?? 0) > 0;

  /// Component keys scoring 0, in the server's order.
  List<String> get missing => <String>[
    for (final k in VisitScoreWeights.components)
      if ((components[k] ?? 0) == 0) k,
  ];

  /// Time still needed to reach the minimum (zero once reached).
  Duration get remaining =>
      elapsed >= minDuration ? Duration.zero : minDuration - elapsed;

  @override
  bool operator ==(Object other) =>
      other is VisitProof &&
      mapEquals(other.components, components) &&
      other.elapsed == elapsed &&
      other.minDuration == minDuration;

  @override
  int get hashCode => Object.hash(components.toString(), elapsed, minDuration);
}

/// Device-side twin of the server's `score_visit` (VV-004 / VV-005), so the
/// officer sees the score the server will store before checking out.
///
/// While the visit is open ([checkoutAt] null), [now] stands in for the
/// check-out: the duration ticks and photos taken until now count.
VisitProof evaluateVisitProof({
  required String geofenceResult,
  required bool confirmed,
  required List<PhotoEvidence> photos,
  required DateTime checkinAt,
  required GeoPoint checkinPoint,
  required int minDurationS,
  required IntegritySnapshot integrity,
  DateTime? checkoutAt,
  DateTime? now,
  bool overrideApproved = false,
}) {
  final end = checkoutAt ?? now ?? checkinAt;
  final elapsed = end.difference(checkinAt);
  final durationOk = !elapsed.isNegative && elapsed.inSeconds >= minDurationS;
  final geofence = switch (geofenceResult) {
    GeofenceResults.inside ||
    GeofenceResults.meetingPoint => VisitScoreWeights.geofence,
    GeofenceResults.override =>
      overrideApproved ? VisitScoreWeights.override : 0,
    _ => 0,
  };
  final photoOk = photos.any(
    (p) => p.matches(
      checkinAt: checkinAt,
      windowEnd: end,
      checkinPoint: checkinPoint,
    ),
  );
  final drift = integrity.clockDriftS ?? 0;
  final integrityOk =
      !integrity.isMock &&
      !integrity.isRooted &&
      drift.abs() <= IntegritySnapshot.driftLimitS;
  return VisitProof(
    components: <String, int>{
      'geofence': geofence,
      'confirmation': confirmed ? VisitScoreWeights.confirmation : 0,
      'photo': photoOk ? VisitScoreWeights.photo : 0,
      'duration': durationOk ? VisitScoreWeights.duration : 0,
      'integrity': integrityOk ? VisitScoreWeights.integrity : 0,
    },
    elapsed: elapsed.isNegative ? Duration.zero : elapsed,
    minDuration: Duration(seconds: minDurationS),
  );
}
