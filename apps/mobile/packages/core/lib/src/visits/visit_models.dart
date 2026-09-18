import 'package:flutter/foundation.dart' show immutable;

import '../geo/geo.dart';
import '../i18n/generated/core_localizations.dart';

/// Wire values of `visit.geofence_result` (FA-014 / VV-003).
abstract final class GeofenceResults {
  /// Inside the farm polygon buffered by the tenant radius.
  static const String inside = 'inside';

  /// Within the village meeting point radius.
  static const String meetingPoint = 'meeting_point';

  /// Outside every target (only stored with an override).
  static const String outside = 'outside';

  /// Checked in outside with an `override_note`; the cluster head decides.
  static const String override = 'override';
}

/// Wire values of `visit.status` (VV-005; `open` until check-out).
abstract final class VisitStatuses {
  /// Not checked out yet.
  static const String open = 'open';

  /// Score >= 70.
  static const String verified = 'verified';

  /// Score 40-69.
  static const String partial = 'partial';

  /// Score < 40.
  static const String unverified = 'unverified';
}

/// `visit.confirmation_channel` / `visit_confirmation.channel` (FA-016).
enum ConfirmationChannel {
  /// OTP sent to the farmer's phone, typed on the officer's phone.
  smsOtp,

  /// Push prompt in the farmer app (Kisan).
  appPush,

  /// QR shown by the officer, scanned by the farmer app.
  qr;

  /// Wire value.
  String get wire => switch (this) {
    ConfirmationChannel.smsOtp => 'sms_otp',
    ConfirmationChannel.appPush => 'app_push',
    ConfirmationChannel.qr => 'qr',
  };

  /// Parses a wire value; unknown values give `null`.
  static ConfirmationChannel? parse(String? wire) {
    for (final c in ConfirmationChannel.values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

/// `visit_confirmation.status` wire values.
abstract final class ConfirmationStatuses {
  /// Requested, waiting for the farmer.
  static const String pending = 'pending';

  /// The farmer confirmed.
  static const String confirmed = 'confirmed';

  /// The code / token lapsed.
  static const String expired = 'expired';

  /// Local only: the officer asked while offline; the request goes out
  /// when the network is back.
  static const String queued = 'queued';
}

/// Crop stages accepted by `VisitCapture.crop_stage` (API enum `CropStage`).
abstract final class CropStages {
  /// Wire values in growth order.
  static const List<String> values = <String>[
    'sown',
    'vegetative',
    'flowering',
    'fruiting',
    'maturity',
    'harvested',
  ];

  /// Localised label.
  static String label(CoreLocalizations l10n, String value) => switch (value) {
    'sown' => l10n.cropStageSown,
    'vegetative' => l10n.stageVegetative,
    'flowering' => l10n.stageFlowering,
    'fruiting' => l10n.stageFruiting,
    'maturity' => l10n.cropStageMaturity,
    'harvested' => l10n.cropStageHarvested,
    _ => value,
  };
}

/// Tenant settings the visit flow needs offline (WC-102 values cached in
/// `kv`; the SPEC defaults until a settings pull lands).
@immutable
class VisitSettings {
  /// Creates the settings.
  const VisitSettings({
    this.geofenceRadiusM = 150,
    this.minVisitDurationS = 300,
  });

  /// Parses the cached / pulled shape; missing keys keep the defaults.
  factory VisitSettings.fromJson(Map<String, Object?> json) {
    const d = VisitSettings();
    final radius = json['geofence_radius_m'];
    final minimum = json['min_visit_duration_s'];
    return VisitSettings(
      geofenceRadiusM: radius is num && radius > 0
          ? radius.toDouble()
          : d.geofenceRadiusM,
      minVisitDurationS: minimum is num && minimum >= 0
          ? minimum.toInt()
          : d.minVisitDurationS,
    );
  }

  /// `kv` key of the cached settings.
  static const String kvKey = 'visits.settings';

  /// Farm polygon buffer (VV-003 default 150 m).
  final double geofenceRadiusM;

  /// FA-017 minimum duration (default 5 min); shorter visits are flagged.
  final int minVisitDurationS;

  /// Wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'geofence_radius_m': geofenceRadiusM,
    'min_visit_duration_s': minVisitDurationS,
  };

  @override
  bool operator ==(Object other) =>
      other is VisitSettings &&
      other.geofenceRadiusM == geofenceRadiusM &&
      other.minVisitDurationS == minVisitDurationS;

  @override
  int get hashCode => Object.hash(geofenceRadiusM, minVisitDurationS);
}

/// Client-side geofence decision (VV-003).
enum GeofenceOutcome {
  /// Inside the buffered farm polygon.
  inside,

  /// Within the meeting point radius.
  meetingPoint,

  /// Outside every target.
  outside,
}

/// The result of [evaluateGeofence]: the same fields the server's
/// `outside_geofence` problem carries (`distance_m`, `target`, `radius_m`).
@immutable
class GeofenceCheck {
  /// Creates the check.
  const GeofenceCheck({
    required this.outcome,
    required this.radiusM,
    this.distanceM,
    this.target,
  });

  /// Decision.
  final GeofenceOutcome outcome;

  /// Distance to the target geometry in metres (0 inside the polygon);
  /// null when there is nothing to check against.
  final double? distanceM;

  /// `farm` | `meeting_point` | null.
  final String? target;

  /// Radius applied to [target].
  final double radiusM;

  /// Check-in allowed without an override.
  bool get allowed => outcome != GeofenceOutcome.outside;

  /// `visit.geofence_result` wire value.
  String get wire => switch (outcome) {
    GeofenceOutcome.inside => GeofenceResults.inside,
    GeofenceOutcome.meetingPoint => GeofenceResults.meetingPoint,
    GeofenceOutcome.outside => GeofenceResults.outside,
  };

  /// Stored on the local visit row (`_local.precheck`).
  Map<String, Object?> toJson() => <String, Object?>{
    'result': wire,
    'distance_m': distanceM,
    'target': target,
    'radius_m': radiusM,
  };

  /// Parses [toJson].
  static GeofenceCheck? fromJson(Object? json) {
    if (json is! Map) return null;
    final result = json['result'] as String?;
    final outcome = switch (result) {
      GeofenceResults.inside => GeofenceOutcome.inside,
      GeofenceResults.meetingPoint => GeofenceOutcome.meetingPoint,
      GeofenceResults.outside => GeofenceOutcome.outside,
      _ => null,
    };
    if (outcome == null) return null;
    return GeofenceCheck(
      outcome: outcome,
      distanceM: (json['distance_m'] as num?)?.toDouble(),
      target: json['target'] as String?,
      radiusM: (json['radius_m'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GeofenceCheck &&
      other.outcome == outcome &&
      other.distanceM == distanceM &&
      other.target == target &&
      other.radiusM == radiusM;

  @override
  int get hashCode => Object.hash(outcome, distanceM, target, radiusM);
}

/// VV-003 on the device, mirroring `farmerapp/visits/geofence.py`: the farm
/// polygon buffered by [radiusM] first, then the village [meetingPoint]
/// within [meetingRadiusM] (or [radiusM] when the village has none);
/// otherwise `outside` with the distance to the nearer target.
GeofenceCheck evaluateGeofence({
  required GeoPoint point,
  required double radiusM,
  List<GeoPoint>? farmBoundary,
  GeoPoint? meetingPoint,
  double? meetingRadiusM,
}) {
  double? farmDistance;
  if (farmBoundary != null && farmBoundary.length >= 3) {
    farmDistance = distanceToPolygonMetres(point, farmBoundary);
    if (farmDistance <= radiusM) {
      return GeofenceCheck(
        outcome: GeofenceOutcome.inside,
        distanceM: farmDistance,
        target: 'farm',
        radiusM: radiusM,
      );
    }
  }
  double? meetingDistance;
  final meetingRadius = meetingRadiusM ?? radiusM;
  if (meetingPoint != null) {
    meetingDistance = distanceMetres(point, meetingPoint);
    if (meetingDistance <= meetingRadius) {
      return GeofenceCheck(
        outcome: GeofenceOutcome.meetingPoint,
        distanceM: meetingDistance,
        target: 'meeting_point',
        radiusM: meetingRadius,
      );
    }
  }
  if (farmDistance == null && meetingDistance == null) {
    return GeofenceCheck(outcome: GeofenceOutcome.outside, radiusM: radiusM);
  }
  final farmNearer =
      farmDistance != null &&
      (meetingDistance == null || farmDistance <= meetingDistance);
  return GeofenceCheck(
    outcome: GeofenceOutcome.outside,
    distanceM: farmNearer ? farmDistance : meetingDistance,
    target: farmNearer ? 'farm' : 'meeting_point',
    radiusM: farmNearer ? radiusM : meetingRadius,
  );
}
