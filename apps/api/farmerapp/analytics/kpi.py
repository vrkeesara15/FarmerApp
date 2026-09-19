"""SPEC 5.2 KPI definitions as pure functions (unit-tested on hand-built facts).

=========================== ==================================================================
KPI                         definition (SPEC 5.2) -> implementation
=========================== ==================================================================
Verified visit              score >= 70 (VV-004) -> ``is_verified``
Unique farmers reached      distinct farmers with >= 1 verified visit in the period
Confirmation rate           visits confirmed by the farmer / all visits (``confirmed_at`` set;
                            open visits count in the denominator: they are visits)
Visit conversion            farmers with a purchase within 30 days *after* a verified visit /
                            farmers visited (distinct farmers with any visit in the period)
Own-brand share             own-brand net sales / total net sales (net = pre-GST line total
                            less its pro-rata share of the order discount)
Active farmer               a purchase, a verified visit or an app session in the last 60 days
                            (``as_of - 59`` .. ``as_of``, inclusive). App session proxy: a
                            ``refresh_token`` issued to the farmer's own login (FM-001) -- the
                            farmer app refreshes its session on every launch, and there is no
                            session table until P1 analytics events
Credit overdue              open khata debits past their due date (credits settle the oldest due
                            first, ``farmerapp.khata.aging``), bucketed 0-30 / 31-60 / 61-90 /
                            90+ days overdue
Farmer LTV                  cumulative gross margin: net sales - cost of goods, the cost from
                            the sold stock batch (``stock_batch.cost_paise``; the store's average
                            batch cost of the SKU when the line has no batch)
Time on farm                sum of (check-out - check-in) of verified visits
=========================== ==================================================================

Money is integer paise; ratios are floats in ``[0, 1]`` or ``None`` when the denominator is
zero (the console shows "--", never a fake 0 %).
"""

from __future__ import annotations

import bisect
import uuid
from collections import defaultdict
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from farmerapp.khata.aging import BUCKETS, open_debits, overdue_buckets
from farmerapp.khata.models import KhataEntry
from farmerapp.visits.scoring import VERIFIED_MIN

ACTIVE_WINDOW_DAYS = 60
CONVERSION_WINDOW = timedelta(days=30)
BUCKET_NAMES: tuple[str, ...] = tuple(name for name, _, _ in BUCKETS)


def ratio(numerator: float, denominator: float) -> float | None:
    if not denominator:
        return None
    return numerator / denominator


# --------------------------------------------------------------------------- visits
@dataclass(frozen=True)
class VisitFact:
    officer_id: uuid.UUID
    farmer_id: uuid.UUID
    checkin_at: datetime
    checkout_at: datetime | None = None
    score: int | None = None
    confirmed_at: datetime | None = None
    id: uuid.UUID | None = None

    @property
    def verified(self) -> bool:
        return is_verified(self.score)

    @property
    def duration_s(self) -> int | None:
        if self.checkout_at is None:
            return None
        return max(int((self.checkout_at - self.checkin_at).total_seconds()), 0)


def is_verified(score: int | None) -> bool:
    """SPEC 5.2 / VV-004: a visit with score >= 70."""
    return score is not None and score >= VERIFIED_MIN


def verified_visits(visits: Iterable[VisitFact]) -> list[VisitFact]:
    return [v for v in visits if v.verified]


def unique_farmers_reached(visits: Iterable[VisitFact]) -> int:
    return len({v.farmer_id for v in visits if v.verified})


def confirmation_rate(visits: Iterable[VisitFact]) -> float | None:
    rows = list(visits)
    return ratio(sum(1 for v in rows if v.confirmed_at is not None), len(rows))


def time_on_farm_s(visits: Iterable[VisitFact]) -> int:
    """Sum of check-in -> check-out of verified visits (seconds)."""
    return sum(v.duration_s or 0 for v in visits if v.verified)


@dataclass(frozen=True)
class Conversion:
    converted: int
    visited: int

    @property
    def rate(self) -> float | None:
        return ratio(self.converted, self.visited)


def visit_conversion(
    visits: Iterable[VisitFact], purchases: Iterable[tuple[uuid.UUID, datetime]]
) -> Conversion:
    """Farmers who bought within 30 days after one of their verified visits / farmers visited.

    ``purchases`` are ``(farmer_id, purchased_at)``; a purchase at or before the visit's
    check-in does not count ("after"), one exactly 30 days later does.
    """
    rows = list(visits)
    visited = {v.farmer_id for v in rows}
    checkins: dict[uuid.UUID, list[datetime]] = defaultdict(list)
    for v in rows:
        if v.verified:
            checkins[v.farmer_id].append(v.checkin_at)
    converted: set[uuid.UUID] = set()
    for farmer_id, at in purchases:
        if farmer_id in converted or farmer_id not in checkins:
            continue
        if any(c < at <= c + CONVERSION_WINDOW for c in checkins[farmer_id]):
            converted.add(farmer_id)
    return Conversion(converted=len(converted), visited=len(visited))


# --------------------------------------------------------------------------- sales
@dataclass(frozen=True)
class SaleFact:
    """Net sales and their cost (paise); a line, or any aggregate of lines."""

    net_paise: int
    cost_paise: int = 0
    own_brand: bool = False
    farmer_id: uuid.UUID | None = None
    day: date | None = None


def net_sales(sales: Iterable[SaleFact]) -> int:
    return sum(s.net_paise for s in sales)


def own_brand_share(sales: Iterable[SaleFact]) -> float | None:
    rows = list(sales)
    return ratio(sum(s.net_paise for s in rows if s.own_brand), sum(s.net_paise for s in rows))


def gross_margin(sales: Iterable[SaleFact]) -> int:
    return sum(s.net_paise - s.cost_paise for s in sales)


def farmer_ltv(sales: Iterable[SaleFact]) -> dict[uuid.UUID, int]:
    """Cumulative gross margin per farmer (walk-in sales have no farmer and are skipped)."""
    out: dict[uuid.UUID, int] = defaultdict(int)
    for s in sales:
        if s.farmer_id is not None:
            out[s.farmer_id] += s.net_paise - s.cost_paise
    return dict(out)


# --------------------------------------------------------------------------- active
def active_window(as_of: date, days: int = ACTIVE_WINDOW_DAYS) -> tuple[date, date]:
    """The inclusive day window of "the last ``days`` days" ending on ``as_of``."""
    return as_of - timedelta(days=days - 1), as_of


def active_farmers(
    as_of: date,
    *,
    purchases: Iterable[tuple[uuid.UUID, date]] = (),
    verified_visits: Iterable[tuple[uuid.UUID, date]] = (),
    app_sessions: Iterable[tuple[uuid.UUID, date]] = (),
    days: int = ACTIVE_WINDOW_DAYS,
) -> set[uuid.UUID]:
    """Farmers with a purchase, a verified visit or an app session in the last 60 days."""
    first, last = active_window(as_of, days)
    out: set[uuid.UUID] = set()
    for events in (purchases, verified_visits, app_sessions):
        for farmer_id, day in events:
            if first <= day <= last:
                out.add(farmer_id)
    return out


def active_counts(
    as_of_days: Sequence[date],
    events: Iterable[tuple[uuid.UUID, date]],
    days: int = ACTIVE_WINDOW_DAYS,
) -> list[int]:
    """``len(active_farmers(d, ...))`` for many days at once (trend series)."""
    by_farmer: dict[uuid.UUID, set[date]] = defaultdict(set)
    for farmer_id, day in events:
        by_farmer[farmer_id].add(day)
    ordered = [sorted(ds) for ds in by_farmer.values()]
    out: list[int] = []
    for as_of in as_of_days:
        first, last = active_window(as_of, days)
        count = 0
        for ds in ordered:
            i = bisect.bisect_left(ds, first)  # the first event on or after the window start
            if i < len(ds) and ds[i] <= last:
                count += 1
        out.append(count)
    return out


# --------------------------------------------------------------------------- credit
@dataclass(frozen=True)
class CreditBook:
    outstanding_paise: int
    overdue_paise: int
    buckets: dict[str, int]
    accounts: int  # farmer x store ledgers with an open balance


def credit_book(
    entries: Iterable[KhataEntry], as_of: date, default_due_days: int, *, until: datetime
) -> CreditBook:
    """Outstanding and overdue credit as of the end of ``as_of`` (``until``: that instant).

    Each farmer x store ledger is aged on its own (``open_debits``: credits settle the
    oldest due first); entries written after ``until`` are ignored.
    """
    accounts: dict[tuple[uuid.UUID, uuid.UUID], list[KhataEntry]] = defaultdict(list)
    for e in entries:
        if e.created_at < until:
            accounts[(e.farmer_id, e.store_id)].append(e)
    outstanding = 0
    buckets = dict.fromkeys(BUCKET_NAMES, 0)
    open_accounts = 0
    for rows in accounts.values():
        debits = open_debits(rows, as_of, default_due_days)
        if not debits:
            continue
        open_accounts += 1
        outstanding += sum(d.open_paise for d in debits)
        for name, paise in overdue_buckets(debits).items():
            buckets[name] += paise
    return CreditBook(
        outstanding_paise=outstanding,
        overdue_paise=sum(buckets.values()),
        buckets=buckets,
        accounts=open_accounts,
    )


def credit_risk(buckets: dict[str, int]) -> str:
    """``high``: anything more than 60 days overdue; ``medium``: overdue at all; else ``low``."""
    if buckets.get("61_90", 0) or buckets.get("90_plus", 0):
        return "high"
    if any(buckets.values()):
        return "medium"
    return "low"


__all__ = [
    "ACTIVE_WINDOW_DAYS",
    "BUCKET_NAMES",
    "CONVERSION_WINDOW",
    "Conversion",
    "CreditBook",
    "SaleFact",
    "VisitFact",
    "active_counts",
    "active_farmers",
    "active_window",
    "confirmation_rate",
    "credit_book",
    "credit_risk",
    "farmer_ltv",
    "gross_margin",
    "is_verified",
    "net_sales",
    "own_brand_share",
    "ratio",
    "time_on_farm_s",
    "unique_farmers_reached",
    "verified_visits",
    "visit_conversion",
]
