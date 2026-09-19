"""SPEC 5.2 KPI definitions on hand-built facts (no database)."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

import pytest

from farmerapp.analytics import kpi
from farmerapp.analytics.kpi import SaleFact, VisitFact
from farmerapp.analytics.periods import buckets, granularity_for, index_of, sum_by_bucket
from farmerapp.khata.models import KhataEntry

O1, O2 = uuid.uuid4(), uuid.uuid4()
F1, F2, F3 = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
S1, S2 = uuid.uuid4(), uuid.uuid4()
T0 = datetime(2026, 8, 10, 5, 0, tzinfo=UTC)


def visit(
    farmer: uuid.UUID,
    score: int | None,
    *,
    at: datetime = T0,
    minutes: int | None = 20,
    confirmed: bool = False,
    officer: uuid.UUID = O1,
) -> VisitFact:
    return VisitFact(
        officer_id=officer,
        farmer_id=farmer,
        checkin_at=at,
        checkout_at=at + timedelta(minutes=minutes) if minutes is not None else None,
        score=score,
        confirmed_at=at + timedelta(minutes=5) if confirmed else None,
    )


# --------------------------------------------------------------------------- verified visit
@pytest.mark.parametrize(
    ("score", "verified"), [(None, False), (0, False), (69, False), (70, True), (100, True)]
)
def test_verified_visit_is_score_at_least_70(score: int | None, verified: bool) -> None:
    assert kpi.is_verified(score) is verified
    assert visit(F1, score).verified is verified


def test_unique_farmers_reached_counts_distinct_farmers_with_a_verified_visit() -> None:
    visits = [visit(F1, 90), visit(F1, 75), visit(F2, 69), visit(F3, None), visit(F3, 70)]
    assert kpi.unique_farmers_reached(visits) == 2  # F1 twice, F3 once; F2 only partial
    assert len(kpi.verified_visits(visits)) == 3
    assert kpi.unique_farmers_reached([]) == 0


def test_confirmation_rate_is_confirmed_over_all_visits() -> None:
    visits = [
        visit(F1, 90, confirmed=True),
        visit(F2, 40, confirmed=True),
        visit(F3, 20),
        visit(F3, None),  # open visits are visits too
    ]
    assert kpi.confirmation_rate(visits) == 0.5
    assert kpi.confirmation_rate([]) is None


def test_time_on_farm_sums_verified_visit_durations() -> None:
    visits = [
        visit(F1, 90, minutes=30),
        visit(F2, 70, minutes=15),
        visit(F3, 60, minutes=120),  # partial: not counted
        visit(F3, 80, minutes=None),  # open: no duration yet
    ]
    assert kpi.time_on_farm_s(visits) == 45 * 60


# --------------------------------------------------------------------------- conversion
def test_visit_conversion_counts_purchases_within_30_days_after_a_verified_visit() -> None:
    visits = [
        visit(F1, 90, at=T0),
        visit(F2, 80, at=T0),
        visit(F3, 50, at=T0),  # visited, but not verified: can never convert
    ]
    purchases = [
        (F1, T0 + timedelta(days=30)),  # exactly 30 days later: counts
        (F2, T0 - timedelta(hours=1)),  # before the visit: does not count
        (F2, T0 + timedelta(days=31)),  # too late
        (F3, T0 + timedelta(days=1)),  # the visit was not verified
        (uuid.uuid4(), T0 + timedelta(days=1)),  # someone never visited
    ]
    conv = kpi.visit_conversion(visits, purchases)
    assert (conv.converted, conv.visited) == (1, 3)
    assert conv.rate == pytest.approx(1 / 3)
    assert kpi.visit_conversion([], purchases).rate is None


def test_visit_conversion_uses_any_verified_visit_of_the_farmer() -> None:
    visits = [visit(F1, 20, at=T0), visit(F1, 90, at=T0 + timedelta(days=40))]
    conv = kpi.visit_conversion(visits, [(F1, T0 + timedelta(days=45))])
    assert (conv.converted, conv.visited) == (1, 1)


# --------------------------------------------------------------------------- sales
def test_own_brand_share_is_own_net_over_total_net() -> None:
    sales = [
        SaleFact(net_paise=3_000, cost_paise=2_100, own_brand=True, farmer_id=F1),
        SaleFact(net_paise=1_000, cost_paise=500, own_brand=False, farmer_id=F1),
        SaleFact(net_paise=6_000, cost_paise=4_000, own_brand=False, farmer_id=None),
    ]
    assert kpi.own_brand_share(sales) == pytest.approx(0.3)
    assert kpi.net_sales(sales) == 10_000
    assert kpi.gross_margin(sales) == 3_400
    assert kpi.own_brand_share([]) is None


def test_farmer_ltv_is_cumulative_gross_margin_per_farmer() -> None:
    sales = [
        SaleFact(net_paise=3_000, cost_paise=2_100, farmer_id=F1),
        SaleFact(net_paise=1_000, cost_paise=500, farmer_id=F1),
        SaleFact(net_paise=2_000, cost_paise=2_500, farmer_id=F2),  # sold below cost
        SaleFact(net_paise=6_000, cost_paise=4_000, farmer_id=None),  # walk-in
    ]
    assert kpi.farmer_ltv(sales) == {F1: 1_400, F2: -500}


# --------------------------------------------------------------------------- active
def test_active_farmer_needs_an_event_in_the_last_60_days() -> None:
    as_of = date(2026, 9, 18)
    first = as_of - timedelta(days=59)
    active = kpi.active_farmers(
        as_of,
        purchases=[(F1, first)],  # the 60th day back: still active
        verified_visits=[(F2, first - timedelta(days=1))],  # 61 days: lapsed
        app_sessions=[(F3, as_of)],
    )
    assert active == {F1, F3}
    assert kpi.active_farmers(as_of, purchases=[(F1, as_of + timedelta(days=1))]) == set()


def test_active_counts_matches_active_farmers_per_day() -> None:
    events = [(F1, date(2026, 6, 1)), (F2, date(2026, 7, 15)), (F3, date(2026, 8, 1))]
    days = [date(2026, 6, 1), date(2026, 7, 31), date(2026, 8, 1), date(2026, 9, 30)]
    expected = [len(kpi.active_farmers(d, purchases=events)) for d in days]
    assert kpi.active_counts(days, events) == expected == [1, 1, 2, 0]


# --------------------------------------------------------------------------- credit
def entry(
    kind: str,
    amount: int,
    at: datetime,
    due: date | None = None,
    farmer: uuid.UUID = F1,
    store: uuid.UUID = S1,
) -> KhataEntry:
    return KhataEntry(
        id=uuid.uuid4(),
        farmer_id=farmer,
        store_id=store,
        type=kind,
        amount_paise=amount,
        due_date=due,
        ref_type="adjustment",
        created_at=at,
    )


def test_credit_overdue_buckets_age_open_debits_per_account() -> None:
    as_of = date(2026, 9, 18)
    until = datetime(2026, 9, 19, tzinfo=UTC)
    entries = [
        entry("debit", 10_000, T0, due=as_of - timedelta(days=100)),  # 90+
        entry("debit", 5_000, T0, due=as_of - timedelta(days=45)),  # 31-60
        entry("debit", 2_000, T0, due=as_of - timedelta(days=1)),  # 0-30
        entry("debit", 7_000, T0, due=as_of + timedelta(days=10)),  # not due yet
        entry("credit", 12_000, T0),  # settles the 90+ debit and 2,000 of the 31-60
        # Another store's ledger is aged on its own: its credit does not cover F1 at S1.
        entry("credit", 50_000, T0, store=S2),
        entry("debit", 3_000, T0, due=as_of - timedelta(days=70), farmer=F2),  # 61-90
        # Written after the as-of instant: ignored.
        entry("debit", 99_000, until + timedelta(hours=1), due=as_of - timedelta(days=5)),
    ]
    book = kpi.credit_book(entries, as_of, 90, until=until)
    assert book.buckets == {"0_30": 2_000, "31_60": 3_000, "61_90": 3_000, "90_plus": 0}
    assert book.overdue_paise == 8_000
    assert book.outstanding_paise == 3_000 + 2_000 + 7_000 + 3_000
    assert book.accounts == 2


@pytest.mark.parametrize(
    ("buckets", "risk"),
    [
        ({"0_30": 0, "31_60": 0, "61_90": 0, "90_plus": 0}, "low"),
        ({"0_30": 1, "31_60": 0, "61_90": 0, "90_plus": 0}, "medium"),
        ({"0_30": 0, "31_60": 5, "61_90": 0, "90_plus": 0}, "medium"),
        ({"0_30": 0, "31_60": 0, "61_90": 1, "90_plus": 0}, "high"),
        ({"0_30": 0, "31_60": 0, "61_90": 0, "90_plus": 1}, "high"),
    ],
)
def test_credit_risk(buckets: dict[str, int], risk: str) -> None:
    assert kpi.credit_risk(buckets) == risk


# --------------------------------------------------------------------------- buckets
def test_trend_buckets_are_daily_up_to_31_days_then_weekly() -> None:
    assert granularity_for(date(2026, 8, 1), date(2026, 8, 31)) == "day"
    assert granularity_for(date(2026, 8, 1), date(2026, 9, 1)) == "week"
    weeks = buckets(date(2026, 8, 1), date(2026, 8, 20), "week")
    assert [(b.start.day, b.end.day) for b in weeks] == [(1, 7), (8, 14), (15, 20)]
    assert index_of(weeks, date(2026, 8, 14)) == 1
    assert index_of(weeks, date(2026, 8, 21)) is None
    assert sum_by_bucket(
        weeks, [(date(2026, 8, 2), 2), (date(2026, 8, 20), 3), (date(2026, 9, 1), 9)]
    ) == [
        2,
        0,
        3,
    ]
    assert kpi.ratio(1, 0) is None
