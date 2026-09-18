"""Session km and stops from the stored points (FA-010 duty end; groundwork for VV-006).

A simple pass, deliberately: points with ``accuracy_m`` over 100 m are ignored, a point that
would need more than 90 km/h from the previous kept one is dropped (VA-E02 "impossible
travel" material, not distance), the km is the haversine sum of what is left, and a *stop*
is a run of consecutive kept points that stay within 100 m of the run's first point for at
least 5 minutes (SPEC VV-006). Road snapping and gap detection are VV-006 (P1).
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

from farmerapp.db.geo import haversine_m

MAX_ACCURACY_M = 100.0
MAX_SPEED_MPS = 90_000 / 3600  # 90 km/h (VA-E02)
STOP_RADIUS_M = 100.0
STOP_MIN_S = 5 * 60


@dataclass(frozen=True)
class TrackPoint:
    ts: datetime
    lat: float
    lon: float
    accuracy_m: float = 0.0


@dataclass(frozen=True)
class TrackSummary:
    km: Decimal
    stops: list[dict[str, Any]]
    kept: int  # points that passed the accuracy / speed filters


def _usable(points: Iterable[TrackPoint]) -> list[TrackPoint]:
    ordered = sorted((p for p in points if p.accuracy_m <= MAX_ACCURACY_M), key=lambda p: p.ts)
    kept: list[TrackPoint] = []
    for point in ordered:
        if kept:
            prev = kept[-1]
            dt = (point.ts - prev.ts).total_seconds()
            if dt <= 0:
                continue  # duplicate timestamp
            if haversine_m(prev.lat, prev.lon, point.lat, point.lon) / dt > MAX_SPEED_MPS:
                continue  # implausible jump: drop the point, keep the anchor
        kept.append(point)
    return kept


def _stop(run: Sequence[TrackPoint]) -> dict[str, Any] | None:
    duration = int((run[-1].ts - run[0].ts).total_seconds())
    if duration < STOP_MIN_S:
        return None
    return {
        "lat": round(sum(p.lat for p in run) / len(run), 6),
        "lon": round(sum(p.lon for p in run) / len(run), 6),
        "start": run[0].ts.isoformat(),
        "end": run[-1].ts.isoformat(),
        "duration_s": duration,
        "points": len(run),
    }


def summarise(points: Iterable[TrackPoint]) -> TrackSummary:
    kept = _usable(points)
    metres = 0.0
    stops: list[dict[str, Any]] = []
    run: list[TrackPoint] = []
    for point in kept:
        if run:
            prev = run[-1]
            metres += haversine_m(prev.lat, prev.lon, point.lat, point.lon)
            if haversine_m(run[0].lat, run[0].lon, point.lat, point.lon) <= STOP_RADIUS_M:
                run.append(point)
                continue
            stop = _stop(run)
            if stop is not None:
                stops.append(stop)
        run = [point]
    if run:
        stop = _stop(run)
        if stop is not None:
            stops.append(stop)
    km = (Decimal(metres) / Decimal(1000)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return TrackSummary(km=km, stops=stops, kept=len(kept))


__all__ = [
    "MAX_ACCURACY_M",
    "MAX_SPEED_MPS",
    "STOP_MIN_S",
    "STOP_RADIUS_M",
    "TrackPoint",
    "TrackSummary",
    "summarise",
]
