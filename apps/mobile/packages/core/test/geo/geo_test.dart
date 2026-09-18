import 'dart:math' as math;

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// FA-012 A21b / VA-F03: pure-Dart polygon maths used before a farm is saved
/// offline (area in acres, centroid, self-intersection, GeoJSON codec).
void main() {
  const origin = GeoPoint(17.4, 78.4);

  /// A point [east] / [north] metres from [origin] (small-distance model).
  GeoPoint offset(double east, double north) {
    final dLat = north / metresPerDegreeLatitude;
    final dLon =
        east /
        (metresPerDegreeLatitude * math.cos(origin.latitude * math.pi / 180));
    return GeoPoint(origin.latitude + dLat, origin.longitude + dLon);
  }

  final square100 = <GeoPoint>[
    origin,
    offset(100, 0),
    offset(100, 100),
    offset(0, 100),
  ];

  group('area', () {
    test('a 100 m square is one hectare (2.47 acres)', () {
      expect(polygonAreaSquareMetres(square100), closeTo(10000, 25));
      expect(polygonAreaAcres(square100), closeTo(2.471, 0.01));
    });

    test('winding order does not change the area', () {
      expect(
        polygonAreaAcres(square100.reversed.toList()),
        closeTo(polygonAreaAcres(square100), 1e-9),
      );
    });

    test('the sync harness polygon (0.01 deg square) is about 292 acres', () {
      const ring = <GeoPoint>[
        GeoPoint(17.4, 78.4),
        GeoPoint(17.4, 78.41),
        GeoPoint(17.41, 78.41),
        GeoPoint(17.41, 78.4),
      ];
      expect(polygonAreaAcres(ring), closeTo(291.8, 3));
    });

    test('an explicitly closed ring gives the same area', () {
      expect(
        polygonAreaAcres(<GeoPoint>[...square100, origin]),
        closeTo(polygonAreaAcres(square100), 1e-9),
      );
    });

    test('fewer than three points have no area', () {
      expect(polygonAreaAcres(const <GeoPoint>[]), 0);
      expect(polygonAreaAcres(<GeoPoint>[origin, offset(10, 0)]), 0);
    });

    test('a triangle is half the square', () {
      final tri = <GeoPoint>[origin, offset(100, 0), offset(0, 100)];
      expect(polygonAreaSquareMetres(tri), closeTo(5000, 15));
    });
  });

  group('centroid', () {
    test('square centroid is the middle', () {
      final c = polygonCentroid(square100)!;
      final mid = offset(50, 50);
      expect(c.latitude, closeTo(mid.latitude, 1e-7));
      expect(c.longitude, closeTo(mid.longitude, 1e-7));
    });

    test('null for fewer than three points, mean for a degenerate ring', () {
      expect(polygonCentroid(const <GeoPoint>[]), isNull);
      final line = <GeoPoint>[origin, offset(100, 0), offset(200, 0)];
      final c = polygonCentroid(line)!;
      expect(c.longitude, closeTo(offset(100, 0).longitude, 1e-9));
    });
  });

  group('self-intersection', () {
    test('a square is simple', () {
      expect(isSelfIntersecting(square100), isFalse);
    });

    test('a bow-tie crosses itself', () {
      final bowTie = <GeoPoint>[
        origin,
        offset(100, 100),
        offset(100, 0),
        offset(0, 100),
      ];
      expect(isSelfIntersecting(bowTie), isTrue);
    });

    test('the closing edge is checked too', () {
      // Pentagon-like shape whose last-to-first edge crosses the first edge.
      final ring = <GeoPoint>[
        origin,
        offset(100, 0),
        offset(100, 100),
        offset(50, -50),
        offset(0, 100),
      ];
      expect(isSelfIntersecting(ring), isTrue);
    });

    test('a concave L-shape is simple', () {
      final l = <GeoPoint>[
        origin,
        offset(100, 0),
        offset(100, 50),
        offset(50, 50),
        offset(50, 100),
        offset(0, 100),
      ];
      expect(isSelfIntersecting(l), isFalse);
    });

    test('fewer than four points cannot self-intersect', () {
      expect(
        isSelfIntersecting(<GeoPoint>[origin, offset(1, 0), offset(0, 1)]),
        isFalse,
      );
    });
  });

  group('GeoJSON', () {
    test('encodes a closed [lon, lat] ring', () {
      final json = polygonToGeoJson(square100);
      expect(json['type'], 'Polygon');
      final rings = json['coordinates']! as List<Object?>;
      final ring = rings.single! as List<Object?>;
      expect(ring, hasLength(5));
      expect(ring.first, <double>[origin.longitude, origin.latitude]);
      expect(ring.last, ring.first);
    });

    test('decodes back without the closing point', () {
      final back = polygonFromGeoJson(polygonToGeoJson(square100));
      expect(back, hasLength(4));
      expect(back.first, origin);
      expect(back[2].latitude, closeTo(offset(100, 100).latitude, 1e-12));
    });

    test('decodes the JSON text stored in the farms table', () {
      final back = polygonFromGeoJson(
        '{"type":"Polygon","coordinates":[[[78.4,17.4],[78.41,17.4],'
        '[78.41,17.41],[78.4,17.41],[78.4,17.4]]]}',
      );
      expect(back, hasLength(4));
      expect(back[1], const GeoPoint(17.4, 78.41));
    });

    test('rejects anything that is not a polygon', () {
      expect(polygonFromGeoJson(null), isEmpty);
      expect(polygonFromGeoJson(<String, Object?>{'type': 'Point'}), isEmpty);
      expect(polygonFromGeoJson('not json'), isEmpty);
    });
  });

  group('VA-F03 area check', () {
    test('within 30 percent passes, beyond fails', () {
      expect(areaDiffersBeyondTolerance(2.5, 3.0), isFalse); // 17 %
      expect(areaDiffersBeyondTolerance(1.0, 2.0), isTrue); // 50 %
      expect(areaDiffersBeyondTolerance(2.0, 1.0), isTrue); // 100 %
      expect(areaDiffersBeyondTolerance(1.3, 1.0), isFalse); // exactly 30 %
      expect(areaDiffersBeyondTolerance(1.31, 1.0), isTrue);
    });

    test('no computed area means nothing to compare', () {
      expect(areaDiffersBeyondTolerance(2.0, 0), isFalse);
      expect(areaDiffersBeyondTolerance(2.0, null), isFalse);
    });
  });

  test('haversine distance of the 100 m edge', () {
    expect(distanceMetres(origin, offset(100, 0)), closeTo(100, 0.5));
    expect(distanceMetres(origin, origin), 0);
  });

  test('GeoPoint equality and JSON', () {
    const a = GeoPoint(1.5, 2.5);
    expect(a, const GeoPoint(1.5, 2.5));
    expect(a.hashCode, const GeoPoint(1.5, 2.5).hashCode);
    expect(a.toJson(), <String, Object?>{'lat': 1.5, 'lon': 2.5});
    expect(GeoPoint.fromJson(a.toJson()), a);
    expect(a.toString(), 'GeoPoint(1.5, 2.5)');
  });
}
