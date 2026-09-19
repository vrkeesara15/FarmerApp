"""VV-006 track processing: km (road snapping port + filter fallback), stops, gaps.

FA-023 acceptance "km within 10 % of the Google Maps route distance on test routes": the
fixture routes below are polylines whose road distance is known exactly (the sum of their
segments). A synthetic officer drives them with the VV-001 sampling (a fix every 2 minutes
while moving), GPS noise and an implausible jump; the processed km must be within 10 % of the
road distance with the filter alone, and within 2 % when a road snapper returns the road
geometry. Comparing against a real Google Maps route on a real drive is a human gate
(docs/prs/M7-field-p1-api.md).
"""

from __future__ import annotations

import math
import random
from collections.abc import Sequence
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from itertools import pairwise

import httpx
import pytest

from farmerapp.db.geo import haversine_m, offset
from farmerapp.duty.processing import GAP_MIN, find_gaps, process_points
from farmerapp.duty.roads import (
    MIN_MOVE_M,
    FilterSnapper,
    GoogleRoadsSnapper,
    RoadSnapError,
    build_snapper,
    moving_path,
)
from farmerapp.duty.track import TrackPoint

T0 = datetime(2026, 9, 21, 3, 30, tzinfo=UTC)  # 09:00 IST
LON, LAT = 79.55, 18.02

#: Test routes: legs of (east_m, north_m); the road distance is the sum of the leg lengths.
ROUTES: dict[str, list[tuple[float, float]]] = {
    "straight_12km": [(12_000, 0)],
    "l_shape_7km": [(3_000, 0), (0, 4_000)],
    "village_loop_10km": [
        (2_000, 0),
        (0, 1_500),
        (1_500, 0),
        (0, -2_500),
        (-1_000, 0),
        (0, -1_500),
        (-1_500, 0),
    ],
    "state_highway_15km": [(3_000, 4_000), (6_000, 0), (0, -4_000)],
}
#: Dense hairpins (300 m apart): 2-minute fixes cut every bend, so only snapping measures them.
HAIRPINS_9KM = [
    (1_500, 0),
    (0, 300),
    (-1_500, 0),
    (0, 300),
    (1_500, 0),
    (0, 300),
    (-1_500, 0),
    (0, 300),
    (1_500, 0),
    (0, 300),
]


def road_length(legs: Sequence[tuple[float, float]]) -> float:
    return sum(math.hypot(e, n) for e, n in legs)


def route_points(legs: Sequence[tuple[float, float]]) -> list[tuple[float, float]]:
    """(east_m, north_m) of every corner, starting at the origin."""
    out = [(0.0, 0.0)]
    for e, n in legs:
        x, y = out[-1]
        out.append((x + e, y + n))
    return out


def position(corners: list[tuple[float, float]], dist: float) -> tuple[float, float]:
    """The point ``dist`` metres along the polyline."""
    for (x1, y1), (x2, y2) in pairwise(corners):
        leg = math.hypot(x2 - x1, y2 - y1)
        if dist <= leg:
            f = dist / leg if leg else 0.0
            return x1 + f * (x2 - x1), y1 + f * (y2 - y1)
        dist -= leg
    return corners[-1]


def drive(
    legs: Sequence[tuple[float, float]],
    *,
    speed_kmh: float = 30.0,
    every_s: int = 120,
    noise_m: float = 8.0,
    seed: int = 7,
    start: datetime = T0,
) -> list[TrackPoint]:
    """Fixes every ``every_s`` along the route at ``speed_kmh`` (+ GPS noise), end included."""
    rng = random.Random(seed)
    corners = route_points(legs)
    total = road_length(legs)
    step = speed_kmh / 3.6 * every_s
    points: list[TrackPoint] = []
    d, i = 0.0, 0
    while True:
        x, y = position(corners, min(d, total))
        x += rng.uniform(-noise_m, noise_m)
        y += rng.uniform(-noise_m, noise_m)
        lon, lat = offset(LON, LAT, x, y)
        points.append(TrackPoint(start + timedelta(seconds=every_s * i), lat, lon, 10.0))
        if d >= total:
            return points
        d += step
        i += 1


def road_geometry(legs: Sequence[tuple[float, float]]) -> list[tuple[float, float]]:
    """(lat, lon) of the route corners densified every 50 m (what a snapper returns)."""
    corners = route_points(legs)
    total = road_length(legs)
    out: list[tuple[float, float]] = []
    d = 0.0
    while d < total:
        x, y = position(corners, d)
        lon, lat = offset(LON, LAT, x, y)
        out.append((lat, lon))
        d += 50.0
    x, y = corners[-1]
    lon, lat = offset(LON, LAT, x, y)
    out.append((lat, lon))
    return out


class RouteSnapper:
    """A stand-in for the Roads API that knows the fixture road (snaps onto it)."""

    name = "google_roads"

    def __init__(self, legs: Sequence[tuple[float, float]]) -> None:
        self.path = road_geometry(legs)

    async def snap(self, points: Sequence[TrackPoint]) -> list[tuple[float, float]]:
        return self.path


def _end(points: Sequence[TrackPoint]) -> datetime:
    return points[-1].ts


# --------------------------------------------------------------------------- acceptance
@pytest.mark.parametrize("name", sorted(ROUTES))
async def test_km_within_10_percent_of_the_road_distance(name: str) -> None:
    legs = ROUTES[name]
    truth = road_length(legs) / 1000
    points = drive(legs)
    result = await process_points(points, start=points[0].ts, end=_end(points))
    assert result.km_source == "haversine"
    assert abs(float(result.km) - truth) / truth <= 0.10, (name, result.km, truth)
    snapped = await process_points(
        points, start=points[0].ts, end=_end(points), snapper=RouteSnapper(legs)
    )
    assert snapped.km_source == "google_roads"
    assert abs(float(snapped.km) - truth) / truth <= 0.02, (name, snapped.km, truth)


async def test_dense_hairpins_need_road_snapping() -> None:
    truth = road_length(HAIRPINS_9KM) / 1000
    points = drive(HAIRPINS_9KM)
    filtered = await process_points(points, start=T0, end=_end(points))
    assert float(filtered.km) < truth * 0.9  # bends between two fixes are cut short
    snapped = await process_points(
        points, start=T0, end=_end(points), snapper=RouteSnapper(HAIRPINS_9KM)
    )
    assert abs(float(snapped.km) - truth) / truth <= 0.02


async def test_an_implausible_jump_and_bad_fixes_do_not_add_km() -> None:
    legs = ROUTES["straight_12km"]
    points = drive(legs)
    jump = TrackPoint(points[3].ts + timedelta(seconds=30), LAT + 1.0, LON, 10.0)  # 111 km
    fuzzy = TrackPoint(points[4].ts + timedelta(seconds=30), LAT, LON + 0.5, 800.0)
    clean = await process_points(points, start=T0, end=_end(points))
    dirty = await process_points([*points, jump, fuzzy], start=T0, end=_end(points))
    assert dirty.km == clean.km
    assert dirty.kept == clean.kept


async def test_gps_scatter_while_parked_is_not_distance() -> None:
    rng = random.Random(3)
    parked = []
    for i in range(46):  # 90 minutes at a farm, a fix every 2 minutes, 15 m scatter
        lon, lat = offset(LON, LAT, rng.uniform(-15, 15), rng.uniform(-15, 15))
        parked.append(TrackPoint(T0 + timedelta(minutes=2 * i), lat, lon, 12.0))
    result = await process_points(parked, start=T0, end=parked[-1].ts)
    assert result.km == Decimal("0.00")
    assert result.km_raw > Decimal("0.3")  # the naive haversine sum would have paid ~0.5 km
    assert len(result.stops) == 1 and result.stops[0]["duration_s"] == 90 * 60


# --------------------------------------------------------------------------- stops and gaps
async def test_synthetic_day_with_a_stop_and_a_gap() -> None:
    """Drive 4 km (09:00-09:16), stop 20 min at a farm, no signal 50 min, drive 3 km."""
    first = drive([(4_000, 0)], speed_kmh=15)
    farm_x, farm_y = 4_000.0, 0.0
    stop = []
    t = first[-1].ts
    for i in range(1, 11):  # 20 minutes within 30 m of the farm
        lon, lat = offset(LON, LAT, farm_x + (i % 3) * 5, farm_y + (i % 2) * 5)
        stop.append(TrackPoint(t + timedelta(minutes=2 * i), lat, lon, 10.0))
    gap_start = stop[-1].ts
    resume = gap_start + timedelta(minutes=50)
    second = [  # 3 km east at 15 km/h: 500 m every 2 minutes
        TrackPoint(resume + timedelta(minutes=2 * i), *offset_latlon(farm_x + 500 * i, 0), 10.0)
        for i in range(7)
    ]
    points = [*first, *stop, *second]
    end = second[-1].ts + timedelta(minutes=10)
    result = await process_points(points, start=T0, end=end)

    assert Decimal("6.7") <= result.km <= Decimal("7.3")  # 4 km + 3 km
    assert len(result.stops) == 1
    assert result.stops[0]["duration_s"] >= 5 * 60
    assert len(result.gaps) == 1
    gap = result.gaps[0]
    assert gap.start == gap_start and gap.end == resume and gap.duration_s == 50 * 60


def offset_latlon(east: float, north: float) -> tuple[float, float]:
    lon, lat = offset(LON, LAT, east, north)
    return lat, lon


def test_find_gaps_counts_the_session_edges() -> None:
    start, end = T0, T0 + timedelta(hours=3)
    times = [T0 + timedelta(minutes=40), T0 + timedelta(minutes=50), T0 + timedelta(minutes=80)]
    gaps = find_gaps(start, end, times)
    assert [(g.start, g.end) for g in gaps] == [
        (start, times[0]),  # 40 min after the start
        (times[2], end),  # 100 min before the end
    ]
    assert find_gaps(start, start, []) == []
    assert find_gaps(start, start + GAP_MIN, []) == []  # exactly 30 min is not a gap
    assert len(find_gaps(start, start + GAP_MIN + timedelta(seconds=1), [])) == 1


# --------------------------------------------------------------------------- snappers
def test_moving_path_keeps_real_moves_only() -> None:
    a = TrackPoint(T0, LAT, LON, 5.0)
    near = TrackPoint(T0 + timedelta(minutes=2), *offset_latlon(10, 0), 5.0)
    far = TrackPoint(T0 + timedelta(minutes=4), *offset_latlon(300, 0), 5.0)
    path = moving_path([a, near, far])
    assert path == [a, far]
    assert MIN_MOVE_M == 25.0
    assert moving_path([]) == []


async def test_google_roads_snapper_chunks_and_parses() -> None:
    legs = ROUTES["straight_12km"]
    points = drive(legs, speed_kmh=10, every_s=20)  # ~220 fixes: several 100-point chunks
    calls: list[int] = []

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["interpolate"] == "true"
        assert request.url.params["key"] == "test-key"
        path = request.url.params["path"].split("|")
        calls.append(len(path))
        snapped = []
        for item in path:
            _lat, lon = (float(v) for v in item.split(","))
            snapped.append({"location": {"latitude": LAT, "longitude": lon}})  # onto the road
        return httpx.Response(200, json={"snappedPoints": snapped})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    snapper = GoogleRoadsSnapper("test-key", client=client)
    result = await process_points(points, start=T0, end=_end(points), snapper=snapper)
    assert len(calls) >= 3 and max(calls) <= 100
    assert result.km_source == "google_roads"
    assert abs(float(result.km) - 12.0) / 12.0 <= 0.02


async def test_road_snapper_failure_falls_back_to_the_filter() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503, json={"error": {"status": "UNAVAILABLE"}})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    points = drive(ROUTES["l_shape_7km"])
    result = await process_points(
        points,
        start=T0,
        end=_end(points),
        snapper=GoogleRoadsSnapper("test-key", client=client),
    )
    assert result.km_source == "haversine"
    assert result.km > Decimal("6")

    with pytest.raises(RoadSnapError):
        await GoogleRoadsSnapper("k", client=client).snap(points)


def test_build_snapper_is_off_by_default() -> None:
    assert isinstance(build_snapper("off", None), FilterSnapper)
    assert isinstance(build_snapper("google", None), FilterSnapper)  # no key: stays off
    assert isinstance(build_snapper("google", "k"), GoogleRoadsSnapper)
    with pytest.raises(ValueError):
        GoogleRoadsSnapper("")


def test_fixture_routes_are_what_they_claim() -> None:
    assert road_length(ROUTES["l_shape_7km"]) == 7_000
    geometry = road_geometry(ROUTES["l_shape_7km"])
    measured = sum(haversine_m(a[0], a[1], b[0], b[1]) for a, b in pairwise(geometry))
    assert abs(measured - 7_000) < 20
