import 'dart:math' as math;

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// VV-003 on the device: point-in-polygon, distance to a polygon in metres
/// and the buffered geofence decision that mirrors the server's
/// `farmerapp/visits/geofence.py` (farm polygon buffered by the tenant
/// radius first, then the village meeting point).
void main() {
  const origin = GeoPoint(17.4, 78.4);

  GeoPoint at(double east, double north) {
    final dLat = north / metresPerDegreeLatitude;
    final dLon =
        east /
        (metresPerDegreeLatitude * math.cos(origin.latitude * math.pi / 180));
    return GeoPoint(origin.latitude + dLat, origin.longitude + dLon);
  }

  // A 100 m square from the origin, corners counter-clockwise.
  final square = <GeoPoint>[origin, at(100, 0), at(100, 100), at(0, 100)];
  // An L shape (concave).
  final lShape = <GeoPoint>[
    origin,
    at(200, 0),
    at(200, 100),
    at(100, 100),
    at(100, 200),
    at(0, 200),
  ];

  group('pointInPolygon', () {
    test('centre is inside, far point is outside', () {
      expect(pointInPolygon(at(50, 50), square), isTrue);
      expect(pointInPolygon(at(500, 500), square), isFalse);
    });

    test('works with a closed ring and either winding', () {
      final closed = <GeoPoint>[...square, square.first];
      expect(pointInPolygon(at(10, 10), closed), isTrue);
      expect(pointInPolygon(at(10, 10), square.reversed.toList()), isTrue);
    });

    test('concave notch of the L is outside', () {
      expect(pointInPolygon(at(150, 150), lShape), isFalse);
      expect(pointInPolygon(at(50, 150), lShape), isTrue);
      expect(pointInPolygon(at(150, 50), lShape), isTrue);
    });

    test('fewer than three points is never inside', () {
      expect(pointInPolygon(origin, <GeoPoint>[origin, at(10, 0)]), isFalse);
      expect(pointInPolygon(origin, const <GeoPoint>[]), isFalse);
    });
  });

  group('distanceToPolygonMetres', () {
    test('zero inside, edge distance outside', () {
      expect(distanceToPolygonMetres(at(50, 50), square), 0);
      expect(distanceToPolygonMetres(at(150, 50), square), closeTo(50, 1));
      expect(distanceToPolygonMetres(at(50, -120), square), closeTo(120, 1));
    });

    test('corner distance is the diagonal', () {
      expect(
        distanceToPolygonMetres(at(130, 140), square),
        closeTo(50, 1), // 30 east, 40 north of the corner
      );
    });

    test('no polygon gives infinity', () {
      expect(distanceToPolygonMetres(origin, const <GeoPoint>[]), isNaN);
    });
  });

  group('evaluateGeofence (mirrors the server)', () {
    test('inside the polygon', () {
      final c = evaluateGeofence(
        point: at(50, 50),
        farmBoundary: square,
        radiusM: 150,
      );
      expect(c.outcome, GeofenceOutcome.inside);
      expect(c.allowed, isTrue);
      expect(c.target, 'farm');
      expect(c.distanceM, 0);
      expect(c.radiusM, 150);
      expect(c.wire, 'inside');
    });

    test('100 m past the boundary is inside the 150 m buffer', () {
      final c = evaluateGeofence(
        point: at(200, 50),
        farmBoundary: square,
        radiusM: 150,
      );
      expect(c.outcome, GeofenceOutcome.inside);
      expect(c.distanceM, closeTo(100, 1));
    });

    test('500 m away is outside with the distance and the radius', () {
      final c = evaluateGeofence(
        point: at(600, 50),
        farmBoundary: square,
        radiusM: 150,
      );
      expect(c.outcome, GeofenceOutcome.outside);
      expect(c.allowed, isFalse);
      expect(c.target, 'farm');
      expect(c.distanceM, closeTo(500, 1));
      expect(c.radiusM, 150);
      expect(c.wire, 'outside');
    });

    test('a smaller tenant radius flips the buffer decision', () {
      final c = evaluateGeofence(
        point: at(200, 50),
        farmBoundary: square,
        radiusM: 50,
      );
      expect(c.outcome, GeofenceOutcome.outside);
      expect(c.distanceM, closeTo(100, 1));
    });

    test('meeting point within the village radius', () {
      final c = evaluateGeofence(
        point: at(2000, 40),
        farmBoundary: square,
        meetingPoint: at(2000, 0),
        radiusM: 150,
        meetingRadiusM: 60,
      );
      expect(c.outcome, GeofenceOutcome.meetingPoint);
      expect(c.allowed, isTrue);
      expect(c.target, 'meeting_point');
      expect(c.distanceM, closeTo(40, 1));
      expect(c.radiusM, 60);
      expect(c.wire, 'meeting_point');
    });

    test('meeting point radius falls back to the tenant radius', () {
      final c = evaluateGeofence(
        point: at(2000, 120),
        meetingPoint: at(2000, 0),
        radiusM: 150,
      );
      expect(c.outcome, GeofenceOutcome.meetingPoint);
      expect(c.radiusM, 150);
    });

    test('outside both reports the nearer target', () {
      final c = evaluateGeofence(
        point: at(2400, 0),
        farmBoundary: square,
        meetingPoint: at(2000, 0),
        radiusM: 150,
      );
      expect(c.outcome, GeofenceOutcome.outside);
      expect(c.target, 'meeting_point');
      expect(c.distanceM, closeTo(400, 1));
    });

    test('no farm boundary and no meeting point needs an override', () {
      final c = evaluateGeofence(point: origin, radiusM: 150);
      expect(c.outcome, GeofenceOutcome.outside);
      expect(c.target, isNull);
      expect(c.distanceM, isNull);
      expect(c.allowed, isFalse);
    });
  });
}
