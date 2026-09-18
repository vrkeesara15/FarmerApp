"""Small geography helpers shared by models, seed and tests (no shapely dependency).

Everything spatial is ``geography(<type>, 4326)`` — WGS84 lon/lat, metres for distances and
areas (``ST_Area`` / ``ST_DWithin`` use the spheroid). Values are written as EWKT strings;
PostGIS parses them, and reads come back as ``WKBElement`` (hex) unless a query asks for
``ST_AsGeoJSON`` / ``ST_X`` / ``ST_Y`` (the models expose those as column properties).
"""

from __future__ import annotations

import math
from collections.abc import Sequence

SRID = 4326
ACRE_M2 = 4046.8564224  # one acre in square metres (international acre)
EARTH_M_PER_DEG_LAT = 111_320.0


def point_wkt(lon: float, lat: float) -> str:
    """``SRID=4326;POINT(lon lat)`` for a ``geography(Point)`` column."""
    return f"SRID={SRID};POINT({lon:.7f} {lat:.7f})"


def polygon_wkt(ring: Sequence[tuple[float, float]]) -> str:
    """``SRID=4326;POLYGON((lon lat, ...))`` — closes the ring when the caller did not."""
    points = list(ring)
    if len(points) < 3:
        raise ValueError("a polygon ring needs at least three points")
    if points[0] != points[-1]:
        points.append(points[0])
    return f"SRID={SRID};POLYGON((" + ", ".join(f"{x:.7f} {y:.7f}" for x, y in points) + "))"


def offset(lon: float, lat: float, east_m: float, north_m: float) -> tuple[float, float]:
    """Move a lon/lat by metres east and north (flat-earth approximation, fine below ~50 km)."""
    dlat = north_m / EARTH_M_PER_DEG_LAT
    dlon = east_m / (EARTH_M_PER_DEG_LAT * math.cos(math.radians(lat)))
    return lon + dlon, lat + dlat


def acres_to_m2(acres: float) -> float:
    return acres * ACRE_M2


def m2_to_acres(m2: float) -> float:
    return m2 / ACRE_M2


__all__ = [
    "ACRE_M2",
    "EARTH_M_PER_DEG_LAT",
    "SRID",
    "acres_to_m2",
    "m2_to_acres",
    "offset",
    "point_wkt",
    "polygon_wkt",
]
