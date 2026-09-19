"""Trend buckets: daily for ranges up to 31 days, weekly (7-day buckets from ``from``) above."""

from __future__ import annotations

import bisect
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Literal

from farmerapp.analytics.schemas import SeriesPoint

DAILY_MAX_DAYS = 31
Granularity = Literal["day", "week"]


@dataclass(frozen=True)
class Bucket:
    start: date
    end: date  # inclusive


def granularity_for(first: date, last: date) -> Granularity:
    return "day" if (last - first).days + 1 <= DAILY_MAX_DAYS else "week"


def buckets(first: date, last: date, granularity: Granularity) -> list[Bucket]:
    step = 1 if granularity == "day" else 7
    out: list[Bucket] = []
    start = first
    while start <= last:
        end = min(start + timedelta(days=step - 1), last)
        out.append(Bucket(start, end))
        start = end + timedelta(days=1)
    return out


def index_of(bs: Sequence[Bucket], day: date) -> int | None:
    """The bucket containing ``day``, else ``None``."""
    if not bs or day < bs[0].start or day > bs[-1].end:
        return None
    return bisect.bisect_right([b.start for b in bs], day) - 1


def sum_by_bucket(bs: Sequence[Bucket], values: Iterable[tuple[date, float]]) -> list[float]:
    out = [0.0] * len(bs)
    starts = [b.start for b in bs]
    for day, value in values:
        if not bs or day < bs[0].start or day > bs[-1].end:
            continue
        out[bisect.bisect_right(starts, day) - 1] += value
    return out


def points(
    bs: Sequence[Bucket],
    values: Sequence[float | None],
    transform: Callable[[float], float] | None = None,
) -> list[SeriesPoint]:
    return [
        SeriesPoint(
            start=b.start,
            end=b.end,
            value=(transform(v) if transform and v is not None else v),
        )
        for b, v in zip(bs, values, strict=True)
    ]


__all__ = [
    "DAILY_MAX_DAYS",
    "Bucket",
    "Granularity",
    "buckets",
    "granularity_for",
    "index_of",
    "points",
    "sum_by_bucket",
]
