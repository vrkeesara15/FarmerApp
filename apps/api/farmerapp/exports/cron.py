"""Five-field cron expressions evaluated in IST (WC-013 ``report_schedule.cron``).

``minute hour day-of-month month day-of-week`` with ``*``, lists (``1,15``), ranges
(``1-5``) and steps (``*/15``, ``0-30/10``); day of week ``0``-``7`` (0 and 7 = Sunday).
As in Vixie cron, when both day-of-month and day-of-week are restricted a day matches
either. ``next_fire(expr, after)`` returns the first UTC instant strictly after ``after``.

``WEEKLY_MONDAY_0800 = "0 8 * * 1"`` is the WC-013 / AN-015 "Monday 8:00 IST" schedule.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

IST = ZoneInfo("Asia/Kolkata")
WEEKLY_MONDAY_0800 = "0 8 * * 1"
_LIMITS = ((0, 59), (0, 23), (1, 31), (1, 12), (0, 7))
_MAX_DAYS = 366 * 5


class CronError(ValueError):
    """Not a valid five-field cron expression."""


def _field(text: str, lo: int, hi: int) -> frozenset[int]:
    out: set[int] = set()
    for part in text.split(","):
        base, _, step_text = part.partition("/")
        step = int(step_text) if step_text else 1
        if step < 1:
            raise CronError(f"bad step in {part!r}")
        if base == "*":
            first, last = lo, hi
        elif "-" in base:
            a, _, b = base.partition("-")
            first, last = int(a), int(b)
        else:
            first = int(base)
            last = hi if step_text else first
        if first < lo or last > hi or first > last:
            raise CronError(f"{part!r} is outside {lo}-{hi}")
        out.update(range(first, last + 1, step))
    return frozenset(out)


@dataclass(frozen=True)
class Cron:
    minutes: frozenset[int]
    hours: frozenset[int]
    days: frozenset[int]
    months: frozenset[int]
    weekdays: frozenset[int]  # 0 = Sunday .. 6 = Saturday
    dom_any: bool
    dow_any: bool

    def day_matches(self, day: date) -> bool:
        if day.month not in self.months:
            return False
        dom = day.day in self.days
        dow = (day.isoweekday() % 7) in self.weekdays
        if self.dom_any and self.dow_any:
            return True
        if self.dom_any:
            return dow
        if self.dow_any:
            return dom
        return dom or dow


def parse(expr: str) -> Cron:
    parts = expr.split()
    if len(parts) != 5:
        raise CronError("a cron expression has five fields: minute hour day month weekday")
    try:
        fields = [_field(p, lo, hi) for p, (lo, hi) in zip(parts, _LIMITS, strict=True)]
    except ValueError as exc:
        raise CronError(str(exc)) from exc
    weekdays = frozenset(d % 7 for d in fields[4])
    return Cron(
        minutes=fields[0],
        hours=fields[1],
        days=fields[2],
        months=fields[3],
        weekdays=weekdays,
        dom_any=parts[2] == "*",
        dow_any=parts[4] == "*",
    )


def next_fire(expr: str | Cron, after: datetime) -> datetime:
    """The first matching IST minute strictly after ``after`` (returned in UTC)."""
    cron = parse(expr) if isinstance(expr, str) else expr
    local = after.astimezone(IST).replace(second=0, microsecond=0) + timedelta(minutes=1)
    day = local.date()
    for offset in range(_MAX_DAYS):
        current = day + timedelta(days=offset)
        if not cron.day_matches(current):
            continue
        for hour in sorted(cron.hours):
            for minute in sorted(cron.minutes):
                candidate = datetime.combine(current, time(hour, minute), tzinfo=IST)
                if candidate >= local:
                    return candidate.astimezone(UTC)
    raise CronError("the expression never fires")


def validate(expr: str) -> str:
    """Parse and check that the expression fires at all (raises ``CronError``)."""
    next_fire(expr, datetime(2026, 1, 1, tzinfo=UTC))
    return " ".join(expr.split())


__all__ = ["IST", "WEEKLY_MONDAY_0800", "Cron", "CronError", "next_fire", "parse", "validate"]
