"""Small helpers shared by the employee (field data) rules: IST days, GeoJSON points."""

from __future__ import annotations

from datetime import date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo

IST = ZoneInfo("Asia/Kolkata")


def ist_day(ts: datetime) -> date:
    """The officers' working day (IST calendar day) of an aware timestamp."""
    return ts.astimezone(IST).date()


def ist_day_bounds(day: date) -> tuple[datetime, datetime]:
    """``[start, end)`` of an IST day as aware datetimes."""
    start = datetime.combine(day, time(0), tzinfo=IST)
    return start, start + timedelta(days=1)


def geo_point(lon: float, lat: float) -> dict[str, Any]:
    """A GeoJSON Point geometry for ``Evidence.points`` (WC-010 draws it on the map)."""
    return {"type": "Point", "coordinates": [round(lon, 7), round(lat, 7)]}


__all__ = ["IST", "geo_point", "ist_day", "ist_day_bounds"]
