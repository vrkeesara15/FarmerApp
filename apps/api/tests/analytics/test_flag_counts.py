"""The real ``FlagCountsPort`` adapter (``farmerapp.flags.analytics``) over the ``flag`` table:
open flags by severity, per officer for the scorecard, the open high-severity list, history
(open as of a bucket end) and the caller's role scope (the WC-010 inbox rule)."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.ports import FlagQuery
from farmerapp.flags.analytics import FLAG_TABLE_COUNTS
from farmerapp.flags.models import Flag
from tests.analytics.builders import Mini, ist
from tests.analytics.conftest import get
from tests.analytics.test_owner_home import FROM, TO
from tests.authz.conftest import Bearer


class Flags:
    def __init__(self, mini: Mini) -> None:
        self.mini = mini
        self.ids: dict[str, uuid.UUID] = {}

    async def add(
        self,
        key: str,
        subject_type: str,
        subject_id: uuid.UUID,
        severity: str,
        store: str,
        opened: datetime,
        resolved: datetime | None = None,
    ) -> None:
        m = self.mini
        flag = Flag(
            tenant_id=m.tid,
            rule_id="VA-E02" if subject_type != "farmer" else "VA-F02",
            rule_version=1,
            subject_type=subject_type,
            subject_id=subject_id,
            severity=severity,
            title=f"flag {key}",
            evidence={"records": []},
            raised_by_mode="batch",
            scope_cluster_id=m.stores[store].cluster_id,
            scope_store_id=m.stores[store].id,
            status="resolved_valid" if resolved else "open",
            resolved_at=resolved,
            sla_due_at=opened + timedelta(hours=48),
            dedupe_key=f"test:{key}",
            created_at=opened,
            updated_at=resolved or opened,
        )
        await m.add(flag)
        self.ids[key] = flag.id


def _noon(day: int, month: int = 8) -> datetime:
    return ist(date(2026, month, day), 12)


@pytest.fixture
async def flags(mini: Mini) -> Flags:
    """A: o1 high (Aug 3); B: a visit of o1, medium (Aug 4); C: farmer F1 at N1, medium
    (Aug 2); D: farmer F3 at S1, high (Aug 5); E: o2 high, Aug 2 resolved Aug 6; F: o1 high
    after the range (Aug 20)."""
    f = Flags(mini)
    o1, o2 = mini.user("o1").id, mini.user("o2").id
    visit = await mini.visit("o1", "f1", _noon(4))
    await f.add("A", "employee", o1, "high", "N1", _noon(3))
    await f.add("B", "visit", visit.id, "medium", "N1", _noon(4))
    await f.add("C", "farmer", mini.farmers["f1"].id, "medium", "N1", _noon(2))
    await f.add("D", "farmer", mini.farmers["f3"].id, "high", "S1", _noon(5))
    await f.add("E", "employee", o2, "high", "S1", _noon(2), resolved=_noon(6))
    await f.add("F", "employee", o1, "high", "N1", _noon(20))
    return f


def _kpi(body: dict[str, object], key: str) -> dict[str, object]:
    kpis = body["kpis"]
    assert isinstance(kpis, list)
    return next(k for k in kpis if k["key"] == key)


def _team(body: dict[str, object]) -> dict[str, int]:
    items = body["items"]
    assert isinstance(items, list)
    return {i["officer_id"]: i["flags"] for i in items}


async def test_owner_home_counts_open_flags_as_of_the_range(
    client: AsyncClient, bearer: Bearer, mini: Mini, flags: Flags
) -> None:
    body = (await get(client, bearer, mini.user("owner"), "/owner-home", from_=FROM, to=TO)).json()
    kpi = _kpi(body, "open_flags")
    assert kpi["value"] == 4  # A B C D (E resolved on Aug 6, F raised after the range)
    trend = kpi["trend"]
    assert isinstance(trend, list)
    assert [p["value"] for p in trend] == [0, 2, 3, 4, 5, 4, 4, 4, 4, 4]
    assert kpi["last_year"] == 0
    assert "open_flags" not in body["notes"]
    high = body["high_severity_flags"]
    assert [h["id"] for h in high] == [str(flags.ids["D"]), str(flags.ids["A"])]
    assert high[0]["farmer_id"] == str(mini.farmers["f3"].id)
    assert high[0]["store_id"] == str(mini.stores["S1"].id)
    assert high[1]["officer_id"] == str(mini.user("o1").id)


async def test_scorecard_flags_per_officer(
    client: AsyncClient, bearer: Bearer, mini: Mini, flags: Flags
) -> None:
    body = (await get(client, bearer, mini.user("owner"), "/field-team", from_=FROM, to=TO)).json()
    o1, o2 = str(mini.user("o1").id), str(mini.user("o2").id)
    assert _team(body) == {o1: 2, o2: 0}  # A and the visit flag B; E was resolved


@pytest.mark.parametrize(
    ("role", "total", "high"),
    [
        ("owner", 4, 2),
        ("director", 4, 2),
        ("auditor", 4, 2),
        ("tenant_admin", 4, 2),
        ("cluster_head", 3, 1),  # North only: A B C
        ("store_manager", 1, 0),  # the inbox rule: farmer-data flags of N1 only (C)
    ],
)
async def test_owner_home_respects_the_role_scope(
    client: AsyncClient, bearer: Bearer, mini: Mini, flags: Flags, role: str, total: int, high: int
) -> None:
    body = (await get(client, bearer, mini.user(role), "/owner-home", from_=FROM, to=TO)).json()
    assert _kpi(body, "open_flags")["value"] == total
    assert len(body["high_severity_flags"]) == high


async def test_field_officer_sees_only_flags_about_themselves(
    client: AsyncClient, bearer: Bearer, mini: Mini, flags: Flags
) -> None:
    body = (await get(client, bearer, mini.user("o1"), "/field-team", from_=FROM, to=TO)).json()
    assert _team(body) == {str(mini.user("o1").id): 1}  # A (visit flags are not in their inbox)
    sm = await get(client, bearer, mini.user("store_manager"), "/field-team", from_=FROM, to=TO)
    assert _team(sm.json()) == {str(mini.user("o1").id): 0}  # employee flags go to the cluster


async def test_filters_narrow_the_counts(
    client: AsyncClient, bearer: Bearer, mini: Mini, flags: Flags
) -> None:
    owner = mini.user("owner")
    by_officer = await get(
        client, bearer, owner, "/owner-home", from_=FROM, to=TO, officer_id=mini.user("o1").id
    )
    assert _kpi(by_officer.json(), "open_flags")["value"] == 2  # A and B, not the farmer flag
    by_store = await get(
        client, bearer, owner, "/owner-home", from_=FROM, to=TO, store_id=mini.stores["S1"].id
    )
    assert _kpi(by_store.json(), "open_flags")["value"] == 1  # D


async def test_adapter_without_a_time_counts_what_is_open_now(
    db_session: AsyncSession, mini: Mini, flags: Flags
) -> None:
    counts = await FLAG_TABLE_COUNTS.counts(db_session, FlagQuery(tenant_id=mini.tid))
    assert (counts.open_total, counts.open_high) == (5, 3)  # A B C D F
    assert counts.by_officer == {mini.user("o1").id: 3}
    other = await FLAG_TABLE_COUNTS.counts(
        db_session, FlagQuery(tenant_id=uuid.uuid4(), viewer=mini.user("owner"))
    )
    assert other.open_total == 0
    listed = await FLAG_TABLE_COUNTS.open_high_severity(db_session, FlagQuery(mini.tid), 2)
    assert [s.id for s in listed] == [flags.ids["F"], flags.ids["D"]]
