"""``farmerapp.duty.track``: km and stops from points (FA-010 duty end; VV-006 groundwork)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from decimal import Decimal

from farmerapp.db.geo import offset
from farmerapp.duty.track import STOP_MIN_S, TrackPoint, summarise

T0 = datetime(2026, 9, 21, 4, 0, tzinfo=UTC)
LON, LAT = 79.55, 18.02


def _p(minutes: float, east_m: float = 0.0, north_m: float = 0.0, acc: float = 8.0) -> TrackPoint:
    lon, lat = offset(LON, LAT, east_m, north_m)
    return TrackPoint(ts=T0 + timedelta(minutes=minutes), lat=lat, lon=lon, accuracy_m=acc)


def test_empty_and_single_point() -> None:
    empty = summarise([])
    assert empty.km == Decimal("0.00") and empty.stops == [] and empty.kept == 0
    one = summarise([_p(0)])
    assert one.km == Decimal("0.00") and one.stops == [] and one.kept == 1


def test_km_is_the_haversine_sum_of_kept_points() -> None:
    points = [_p(i * 3, east_m=i * 1000) for i in range(5)]  # 1 km every 3 min (20 km/h)
    result = summarise(points)
    assert Decimal("3.99") <= result.km <= Decimal("4.01")
    assert result.stops == [] and result.kept == 5


def test_inaccurate_points_and_implausible_jumps_are_skipped() -> None:
    points = [_p(i * 3, east_m=i * 1000) for i in range(5)]
    points.append(_p(13, east_m=60_000, acc=500))  # 500 m accuracy: ignored
    points.append(_p(14, east_m=100_000))  # 96 km in 2 min: dropped (VA-E02)
    points.append(_p(17, east_m=5000))  # back on the road, 1 km from the anchor
    result = summarise(points)
    assert Decimal("4.99") <= result.km <= Decimal("5.01")
    assert result.kept == 6


def test_unsorted_input_and_duplicate_timestamps() -> None:
    points = [_p(3, east_m=1000), _p(0), _p(3, east_m=1000)]
    result = summarise(points)
    assert Decimal("0.99") <= result.km <= Decimal("1.01") and result.kept == 2


def test_stop_is_five_minutes_within_100_m() -> None:
    points = [_p(0), _p(2, east_m=20), _p(4, east_m=40), _p(6, east_m=10)]  # 6 min, < 100 m
    points += [_p(9, east_m=1000), _p(11, east_m=1020)]  # 2 minutes: not a stop
    points += [_p(14, east_m=3000), _p(16, east_m=3050), _p(19, east_m=3080)]  # 5 min: stop
    result = summarise(points)
    assert len(result.stops) == 2
    first, second = result.stops
    assert first["duration_s"] == 6 * 60 and first["points"] == 4
    assert (
        first["start"] == T0.isoformat() and first["end"] == (T0 + timedelta(minutes=6)).isoformat()
    )
    assert abs(first["lat"] - LAT) < 1e-5 and first["lon"] > LON
    assert second["duration_s"] == STOP_MIN_S and second["points"] == 3
    assert Decimal("3.0") <= result.km <= Decimal("3.2")


def test_a_stop_needs_at_least_five_minutes() -> None:
    points = [_p(0), _p(2, east_m=10), _p(4.9, east_m=20)]
    assert summarise(points).stops == []
    points.append(_p(5, east_m=30))
    assert len(summarise(points).stops) == 1
