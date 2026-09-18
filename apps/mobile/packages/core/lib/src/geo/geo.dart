import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

/// Mean Earth radius (IUGG) in metres.
const double earthRadiusMetres = 6371008.8;

/// Metres in one degree of latitude (and of longitude at the equator).
const double metresPerDegreeLatitude = 2 * math.pi * earthRadiusMetres / 360;

/// Square metres in one acre.
const double squareMetresPerAcre = 4046.8564224;

/// VA-F03: declared acres may differ from the polygon area by at most this.
const double areaToleranceRatio = 0.30;

double _rad(double degrees) => degrees * math.pi / 180;

/// A WGS84 position (latitude, longitude in degrees).
@immutable
class GeoPoint {
  /// Creates the point.
  const GeoPoint(this.latitude, this.longitude);

  /// Parses `{lat, lon}`.
  factory GeoPoint.fromJson(Map<String, Object?> json) => GeoPoint(
    (json['lat']! as num).toDouble(),
    (json['lon']! as num).toDouble(),
  );

  /// Degrees north.
  final double latitude;

  /// Degrees east.
  final double longitude;

  /// `{lat, lon}` (draft storage; GeoJSON uses [polygonToGeoJson]).
  Map<String, Object?> toJson() => <String, Object?>{
    'lat': latitude,
    'lon': longitude,
  };

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}

/// Great-circle distance between [a] and [b] in metres (haversine).
double distanceMetres(GeoPoint a, GeoPoint b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) *
          math.cos(_rad(b.latitude)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusMetres * math.asin(math.sqrt(h.toDouble()));
}

/// The ring without a repeated closing point.
List<GeoPoint> _open(List<GeoPoint> ring) {
  if (ring.length > 1 && ring.first == ring.last) {
    return ring.sublist(0, ring.length - 1);
  }
  return ring;
}

/// Area of the polygon [ring] (any winding, closed or not) in square metres
/// using the spherical shoelace formula (Chamberlain and Duquette 2007).
double polygonAreaSquareMetres(List<GeoPoint> ring) {
  final pts = _open(ring);
  if (pts.length < 3) return 0;
  var sum = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p1 = pts[i];
    final p2 = pts[(i + 1) % pts.length];
    sum +=
        (_rad(p2.longitude) - _rad(p1.longitude)) *
        (2 + math.sin(_rad(p1.latitude)) + math.sin(_rad(p2.latitude)));
  }
  return (sum * earthRadiusMetres * earthRadiusMetres / 2).abs();
}

/// [polygonAreaSquareMetres] in acres.
double polygonAreaAcres(List<GeoPoint> ring) =>
    polygonAreaSquareMetres(ring) / squareMetresPerAcre;

/// Centroid of [ring] (area-weighted in a local equirectangular plane), the
/// mean of the points for a degenerate ring, `null` for fewer than three.
GeoPoint? polygonCentroid(List<GeoPoint> ring) {
  final pts = _open(ring);
  if (pts.length < 3) return null;
  final lat0 = pts.fold<double>(0, (a, p) => a + p.latitude) / pts.length;
  final lon0 = pts.fold<double>(0, (a, p) => a + p.longitude) / pts.length;
  final k = math.cos(_rad(lat0));
  double x(GeoPoint p) => (p.longitude - lon0) * k;
  double y(GeoPoint p) => p.latitude - lat0;
  var area = 0.0;
  var cx = 0.0;
  var cy = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    final cross = x(a) * y(b) - x(b) * y(a);
    area += cross;
    cx += (x(a) + x(b)) * cross;
    cy += (y(a) + y(b)) * cross;
  }
  if (area.abs() < 1e-18) return GeoPoint(lat0, lon0);
  area /= 2;
  return GeoPoint(lat0 + cy / (6 * area), lon0 + cx / (6 * area) / k);
}

int _orientation(GeoPoint a, GeoPoint b, GeoPoint c) {
  final v =
      (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);
  if (v.abs() < 1e-15) return 0;
  return v > 0 ? 1 : -1;
}

bool _onSegment(GeoPoint a, GeoPoint b, GeoPoint p) =>
    p.longitude <= math.max(a.longitude, b.longitude) &&
    p.longitude >= math.min(a.longitude, b.longitude) &&
    p.latitude <= math.max(a.latitude, b.latitude) &&
    p.latitude >= math.min(a.latitude, b.latitude);

bool _segmentsCross(GeoPoint p1, GeoPoint p2, GeoPoint q1, GeoPoint q2) {
  final o1 = _orientation(p1, p2, q1);
  final o2 = _orientation(p1, p2, q2);
  final o3 = _orientation(q1, q2, p1);
  final o4 = _orientation(q1, q2, p2);
  if (o1 != o2 && o3 != o4) return true;
  if (o1 == 0 && _onSegment(p1, p2, q1)) return true;
  if (o2 == 0 && _onSegment(p1, p2, q2)) return true;
  if (o3 == 0 && _onSegment(q1, q2, p1)) return true;
  if (o4 == 0 && _onSegment(q1, q2, p2)) return true;
  return false;
}

/// True when any two non-adjacent edges of [ring] (closing edge included)
/// cross or touch (VA-F03 "no self-intersection").
bool isSelfIntersecting(List<GeoPoint> ring) {
  final pts = _open(ring);
  final n = pts.length;
  if (n < 4) return false;
  for (var i = 0; i < n; i++) {
    final a1 = pts[i];
    final a2 = pts[(i + 1) % n];
    for (var j = i + 2; j < n; j++) {
      if (i == 0 && j == n - 1) continue; // adjacent through the closing edge
      final b1 = pts[j];
      final b2 = pts[(j + 1) % n];
      if (_segmentsCross(a1, a2, b1, b2)) return true;
    }
  }
  return false;
}

/// Encodes [ring] as a GeoJSON `Polygon` with one closed `[lon, lat]` ring
/// (the shape `FarmCreate.boundary` accepts).
Map<String, Object?> polygonToGeoJson(List<GeoPoint> ring) {
  final pts = _open(ring);
  return <String, Object?>{
    'type': 'Polygon',
    'coordinates': <Object?>[
      <Object?>[
        for (final p in pts) <double>[p.longitude, p.latitude],
        if (pts.isNotEmpty) <double>[pts.first.longitude, pts.first.latitude],
      ],
    ],
  };
}

/// Decodes a GeoJSON `Polygon` (a map or its JSON text) into the outer ring
/// without the closing point; anything else gives an empty list.
List<GeoPoint> polygonFromGeoJson(Object? json) {
  Object? value = json;
  if (value is String) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return const <GeoPoint>[];
    }
  }
  if (value is! Map || value['type'] != 'Polygon') return const <GeoPoint>[];
  final rings = value['coordinates'];
  if (rings is! List || rings.isEmpty) return const <GeoPoint>[];
  final outer = rings.first;
  if (outer is! List) return const <GeoPoint>[];
  final pts = <GeoPoint>[];
  for (final c in outer) {
    if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
      pts.add(GeoPoint((c[1] as num).toDouble(), (c[0] as num).toDouble()));
    }
  }
  return _open(pts);
}

/// VA-F03: true when the declared acres differ from the computed acres by
/// more than [tolerance] of the computed value. Nothing to compare (no
/// computed area) is not a mismatch.
bool areaDiffersBeyondTolerance(
  double declaredAcres,
  double? computedAcres, {
  double tolerance = areaToleranceRatio,
}) {
  if (computedAcres == null || computedAcres <= 0) return false;
  final ratio = (declaredAcres - computedAcres).abs() / computedAcres;
  return ratio > tolerance + 1e-9;
}

// --- geofence geometry (VV-003 on the device) ------------------------------

/// Ray-casting point-in-polygon on the outer [ring] (closed or open, any
/// winding). Points on an edge count as inside. Fewer than three points is
/// never inside.
bool pointInPolygon(GeoPoint p, List<GeoPoint> ring) {
  final pts = _open(ring);
  final n = pts.length;
  if (n < 3) return false;
  var inside = false;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final a = pts[i];
    final b = pts[j];
    if (_orientation(a, b, p) == 0 && _onSegment(a, b, p)) return true;
    final crosses =
        (a.latitude > p.latitude) != (b.latitude > p.latitude) &&
        p.longitude <
            (b.longitude - a.longitude) *
                    (p.latitude - a.latitude) /
                    (b.latitude - a.latitude) +
                a.longitude;
    if (crosses) inside = !inside;
  }
  return inside;
}

/// Distance in metres from [p] to the segment [a]-[b], computed in a local
/// equirectangular plane centred on [p] (accurate to well under a percent
/// at field scale).
double distanceToSegmentMetres(GeoPoint p, GeoPoint a, GeoPoint b) {
  final k = metresPerDegreeLatitude * math.cos(_rad(p.latitude));
  double x(GeoPoint q) => (q.longitude - p.longitude) * k;
  double y(GeoPoint q) => (q.latitude - p.latitude) * metresPerDegreeLatitude;
  final ax = x(a);
  final ay = y(a);
  final bx = x(b);
  final by = y(b);
  final dx = bx - ax;
  final dy = by - ay;
  final len2 = dx * dx + dy * dy;
  double t = 0;
  if (len2 > 0) {
    t = ((-ax) * dx + (-ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
  }
  final cx = ax + t * dx;
  final cy = ay + t * dy;
  return math.sqrt(cx * cx + cy * cy);
}

/// Distance in metres from [p] to the polygon [ring]: 0 inside, otherwise
/// the distance to the nearest edge. `NaN` for fewer than three points.
double distanceToPolygonMetres(GeoPoint p, List<GeoPoint> ring) {
  final pts = _open(ring);
  if (pts.length < 3) return double.nan;
  if (pointInPolygon(p, pts)) return 0;
  var best = double.infinity;
  for (var i = 0; i < pts.length; i++) {
    final d = distanceToSegmentMetres(p, pts[i], pts[(i + 1) % pts.length]);
    if (d < best) best = d;
  }
  return best;
}
