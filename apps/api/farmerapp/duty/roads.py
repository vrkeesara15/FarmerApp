"""VV-006 road snapping behind a port (``RoadSnapper``).

``snap(points)`` returns the path the km are measured on, as ``(lat, lon)`` pairs in time
order. Two adapters:

* ``FilterSnapper`` (``name = "haversine"``, the default and the fallback) snaps nothing: it
  returns the *moving* points of the already filtered track (accuracy <= 100 m, no jump over
  90 km/h, ``farmerapp.duty.track``) after a jitter filter — a point only extends the path
  once it is at least ``max(MIN_MOVE_M, accuracy of either fix)`` from the last point kept on
  the path. GPS scatter while parked at a farm therefore adds nothing, while a road drive
  sampled every 2 minutes (VV-001) is measured point to point.
* ``GoogleRoadsSnapper`` (``name = "google_roads"``, ``ROAD_SNAPPER=google``, off by default)
  calls the Roads API ``snapToRoads`` with ``interpolate=true`` in chunks of 100 points (one
  point of overlap) and returns the snapped, interpolated path, so a bend between two samples
  is measured along the road. The API key comes from Secret Manager (``GOOGLE_MAPS_API_KEY``;
  never in code); any failure raises ``RoadSnapError`` and the track processing falls back
  to ``FilterSnapper`` (the km is then marked ``haversine``).

Comparing the km with a real Google Maps route is a human gate (docs/prs/M7-field-p1-api.md);
the automated acceptance uses fixture routes whose road distance is known
(``tests/duty/test_processing.py``).
"""

from __future__ import annotations

from collections.abc import Sequence
from itertools import pairwise
from typing import Any, Protocol

import httpx

from farmerapp.db.geo import haversine_m
from farmerapp.duty.track import TrackPoint

#: Jitter floor: a fix closer than this to the last path point is scatter, not travel.
MIN_MOVE_M = 25.0
ROADS_URL = "https://roads.googleapis.com/v1/snapToRoads"
ROADS_CHUNK = 100  # the API's maximum path length per request


class RoadSnapError(RuntimeError):
    """The snapping provider failed; the caller falls back to the filter."""


class RoadSnapper(Protocol):
    name: str

    async def snap(self, points: Sequence[TrackPoint]) -> list[tuple[float, float]]: ...


def moving_path(points: Sequence[TrackPoint]) -> list[TrackPoint]:
    """The points that extend the path (jitter filter); ``points`` are filtered and sorted."""
    path: list[TrackPoint] = []
    for point in points:
        if not path:
            path.append(point)
            continue
        anchor = path[-1]
        threshold = max(MIN_MOVE_M, anchor.accuracy_m, point.accuracy_m)
        if haversine_m(anchor.lat, anchor.lon, point.lat, point.lon) >= threshold:
            path.append(point)
    if len(points) > 1 and path[-1] is not points[-1]:
        last = points[-1]  # the final fix still counts when it moved at all (end of the trip)
        if haversine_m(path[-1].lat, path[-1].lon, last.lat, last.lon) >= MIN_MOVE_M:
            path.append(last)
    return path


def path_m(path: Sequence[tuple[float, float]]) -> float:
    return sum(haversine_m(a[0], a[1], b[0], b[1]) for a, b in pairwise(path))


class FilterSnapper:
    """Haversine + speed / accuracy / jitter filter (no road network)."""

    name = "haversine"

    async def snap(self, points: Sequence[TrackPoint]) -> list[tuple[float, float]]:
        return [(p.lat, p.lon) for p in moving_path(points)]


class GoogleRoadsSnapper:
    """Roads API ``snapToRoads`` (interpolated). Needs ``GOOGLE_MAPS_API_KEY``."""

    name = "google_roads"

    def __init__(
        self, api_key: str, *, client: httpx.AsyncClient | None = None, url: str = ROADS_URL
    ) -> None:
        if not api_key:
            raise ValueError("GoogleRoadsSnapper needs an API key (Secret Manager)")
        self._key = api_key
        self._client = client
        self._url = url

    async def _call(self, chunk: Sequence[TrackPoint]) -> list[tuple[float, float]]:
        params = {
            "path": "|".join(f"{p.lat:.6f},{p.lon:.6f}" for p in chunk),
            "interpolate": "true",
            "key": self._key,
        }
        try:
            if self._client is not None:
                resp = await self._client.get(self._url, params=params)
            else:  # pragma: no cover - real network (human gate)
                async with httpx.AsyncClient(timeout=15.0) as client:
                    resp = await client.get(self._url, params=params)
            resp.raise_for_status()
            body: dict[str, Any] = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise RoadSnapError(f"roads api failed: {type(exc).__name__}") from exc
        out: list[tuple[float, float]] = []
        for item in body.get("snappedPoints") or []:
            loc = item.get("location") or {}
            try:
                out.append((float(loc["latitude"]), float(loc["longitude"])))
            except (KeyError, TypeError, ValueError) as exc:
                raise RoadSnapError("roads api returned a malformed point") from exc
        return out

    async def snap(self, points: Sequence[TrackPoint]) -> list[tuple[float, float]]:
        moving = moving_path(points)
        if len(moving) < 2:
            return [(p.lat, p.lon) for p in moving]
        path: list[tuple[float, float]] = []
        start = 0
        while start < len(moving) - 1:
            chunk = moving[start : start + ROADS_CHUNK]
            snapped = await self._call(chunk)
            if not snapped:
                snapped = [(p.lat, p.lon) for p in chunk]  # off-road stretch: keep the fixes
            if path and snapped and path[-1] == snapped[0]:
                snapped = snapped[1:]
            path.extend(snapped)
            start += ROADS_CHUNK - 1  # one point of overlap keeps the chunks joined
        return path


def build_snapper(mode: str, api_key: str | None) -> RoadSnapper:
    """``ROAD_SNAPPER``: ``off`` (default) -> ``FilterSnapper``; ``google`` -> Roads API."""
    if mode == "google" and api_key:
        return GoogleRoadsSnapper(api_key)
    return FilterSnapper()


__all__ = [
    "MIN_MOVE_M",
    "FilterSnapper",
    "GoogleRoadsSnapper",
    "RoadSnapError",
    "RoadSnapper",
    "build_snapper",
    "moving_path",
    "path_m",
]
