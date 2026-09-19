"""AN-001 / WC-001 owner home on the hand-built ``Mini`` tenant (exact figures) and AN-011
filters / role scope."""

from __future__ import annotations

from datetime import date
from typing import Any

import pytest
from httpx import AsyncClient

from tests.analytics.builders import Mini, ist
from tests.analytics.conftest import get
from tests.authz.conftest import Bearer

FROM, TO = date(2026, 8, 1), date(2026, 8, 10)


async def build(m: Mini) -> None:
    m.tenant.settings = {"targets": {"revenue_paise": 30_000, "own_brand_share": 0.4}}
    # Sales in range: N1 (discounted, placed by O1), N2 walk-in, S1.
    await m.sale(
        "N1", "f1", ist(date(2026, 8, 3), 10), [("own", 2, 1000), ("multi", 1, 800)],
        discount=280, placed_by="o1",
    )  # fmt: skip
    await m.sale("N2", None, ist(date(2026, 8, 5), 11), [("multi", 2, 800)])
    await m.sale("S1", "f3", ist(date(2026, 8, 7), 12), [("own", 1, 1000)])
    # Not sales: cancelled, before the range; last year's sale.
    await m.sale("N1", "f1", ist(date(2026, 8, 4), 9), [("own", 5, 1000)], status="cancelled")
    await m.sale("N1", "f1", ist(date(2026, 7, 1), 9), [("own", 1, 1000)])
    await m.sale("N1", "f2", ist(date(2025, 8, 3), 9), [("own", 1, 1000)])
    # Visits.
    await m.visit("o1", "f1", ist(date(2026, 8, 2), 10), score=90, confirmed=True)
    await m.visit("o1", "f2", ist(date(2026, 8, 3), 11), score=50)
    await m.visit("o2", "f3", ist(date(2026, 8, 4), 12), score=75)
    await m.visit("o1", "f1", ist(date(2025, 8, 5), 10), score=80)
    # Duty: O1 two days, O2 one day.
    await m.duty("o1", ist(date(2026, 8, 2), 9), ist(date(2026, 8, 2), 18))
    await m.duty("o1", ist(date(2026, 8, 3), 9), ist(date(2026, 8, 3), 18))
    await m.duty("o2", ist(date(2026, 8, 4), 9), ist(date(2026, 8, 4), 18))
    # Khata.
    await m.khata("f1", "N1", "debit", 10_000, ist(date(2026, 5, 1), 10), due=date(2026, 6, 1))
    await m.khata("f1", "N1", "credit", 4_000, ist(date(2026, 7, 1), 10))
    await m.khata("f3", "S1", "debit", 5_000, ist(date(2026, 8, 1), 10), due=date(2026, 8, 5))
    await m.khata("f2", "N1", "debit", 3_000, ist(date(2026, 8, 9), 10), due=date(2026, 12, 1))
    await m.session.flush()


def kpis(body: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {k["key"]: k for k in body["kpis"]}


async def test_owner_home_figures(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    await build(mini)
    resp = await get(client, bearer, mini.user("owner"), "/owner-home", from_=FROM, to=TO)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["filters"] == {
        "from": "2026-08-01",
        "to": "2026-08-10",
        "cluster_id": None,
        "store_id": None,
        "officer_id": None,
        "crop_id": None,
        "days": 10,
        "scope": "tenant",
    }
    assert body["granularity"] == "day"
    k = kpis(body)
    assert list(k) == [
        "revenue",
        "own_brand_share",
        "credit_outstanding",
        "credit_overdue",
        "verified_visits",
        "active_farmers",
        "open_flags",
    ]
    # Revenue: N1 2,800 - 280 discount = 2,520; N2 1,600; S1 1,000.
    assert k["revenue"]["value"] == 5_120
    assert k["revenue"]["target"] == pytest.approx(10_000)  # 30,000 a month x 10 / 30
    assert k["revenue"]["last_year"] == 1_000
    assert len(k["revenue"]["trend"]) == 10
    trend = {p["start"]: p["value"] for p in k["revenue"]["trend"]}
    assert trend["2026-08-03"] == 2_520 and trend["2026-08-05"] == 1_600
    assert trend["2026-08-04"] == 0
    # Own brand: 2,000 - 200 (pro-rata discount) + 1,000.
    assert k["own_brand_share"]["value"] == pytest.approx(2_800 / 5_120)
    assert k["own_brand_share"]["target"] == pytest.approx(0.4)
    assert k["own_brand_share"]["last_year"] == pytest.approx(1.0)
    share = {p["start"]: p["value"] for p in k["own_brand_share"]["trend"]}
    assert share["2026-08-04"] is None and share["2026-08-05"] == 0
    # Credit as of 10 Aug: F1@N1 6,000 open (70 days overdue), F3@S1 5,000 (5 days), F2 not due.
    assert k["credit_outstanding"]["value"] == 14_000
    assert k["credit_overdue"]["value"] == 11_000
    assert k["credit_overdue"]["last_year"] == 0
    assert body["credit_overdue_buckets"] == {
        "0_30": 5_000,
        "31_60": 0,
        "61_90": 6_000,
        "90_plus": 0,
    }
    outstanding = {p["start"]: p["value"] for p in k["credit_outstanding"]["trend"]}
    assert outstanding["2026-08-08"] == 11_000 and outstanding["2026-08-09"] == 14_000
    # Visits: two verified in range, one last year.
    assert k["verified_visits"]["value"] == 2
    assert k["verified_visits"]["last_year"] == 1
    assert k["verified_visits"]["target"] is None
    # Active: F1 and F3 (F2 only had a partial visit); last year F1 (visit) and F2 (purchase).
    assert k["active_farmers"]["value"] == 2
    assert k["active_farmers"]["last_year"] == 2
    assert k["open_flags"]["value"] == 0
    assert body["notes"]["open_flags"] == "pending_flags_branch"

    # Series.
    assert len(body["series"]["revenue"]) == 10
    assert body["series"]["revenue_last_year"][2]["start"] == "2025-08-03"
    assert body["series"]["revenue_last_year"][2]["value"] == 1_000

    # Store map: scored against the best store.
    stores = {s["code"]: s for s in body["stores"]}
    assert (stores["N1"]["score"], stores["N1"]["band"]) == (100, "green")
    assert (stores["N2"]["score"], stores["N2"]["band"]) == (63, "amber")
    assert (stores["S1"]["score"], stores["S1"]["band"]) == (40, "red")
    assert stores["N1"]["lat"] == pytest.approx(17.97)
    assert stores["S1"]["overdue_paise"] == 5_000
    assert stores["N2"]["own_brand_share"] == 0

    # Officers: O2 1 verified / 1 duty day beats O1 1 / 2.
    assert [o["name"] for o in body["officers_top"]] == ["User o2", "User o1"]
    assert body["officers_top"][1]["verified_visits_per_day"] == pytest.approx(0.5)
    assert [o["name"] for o in body["officers_bottom"]] == ["User o1", "User o2"]
    assert body["high_severity_flags"] == []
    assert body["crop_health_alerts"] == []


async def test_weekly_trend_for_long_ranges(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    await build(mini)
    resp = await get(
        client, bearer, mini.user("owner"), "/owner-home", from_="2026-07-01", to="2026-08-31"
    )
    body = resp.json()
    assert body["granularity"] == "week"
    revenue = kpis(body)["revenue"]
    assert len(revenue["trend"]) == 9
    assert revenue["value"] == 6_120  # the 1 July sale is in range now
    assert sum(p["value"] for p in revenue["trend"]) == 6_120


@pytest.mark.parametrize(
    ("role", "revenue", "stores", "outstanding"),
    [
        ("director", 5_120, {"N1", "N2", "S1"}, 14_000),
        ("auditor", 5_120, {"N1", "N2", "S1"}, 14_000),
        ("tenant_admin", 5_120, {"N1", "N2", "S1"}, 14_000),
        ("cluster_head", 4_120, {"N1", "N2"}, 9_000),
        ("store_manager", 2_520, {"N1"}, 9_000),
    ],
)
async def test_owner_home_scope_per_role(
    client: AsyncClient,
    bearer: Bearer,
    mini: Mini,
    role: str,
    revenue: int,
    stores: set[str],
    outstanding: int,
) -> None:
    await build(mini)
    resp = await get(client, bearer, mini.user(role), "/owner-home", from_=FROM, to=TO)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert kpis(body)["revenue"]["value"] == revenue
    assert kpis(body)["credit_outstanding"]["value"] == outstanding
    assert {s["code"] for s in body["stores"]} == stores
    if role == "cluster_head":
        assert body["filters"]["scope"] == "cluster"
        assert [o["name"] for o in body["officers_top"]] == ["User o1"]
        assert kpis(body)["active_farmers"]["value"] == 1  # F1 (N1); F3 is in the south


@pytest.mark.parametrize("role", ["o1", "accountant", "agronomist", "farmer_user"])
async def test_owner_home_forbidden_roles(
    client: AsyncClient, bearer: Bearer, mini: Mini, role: str
) -> None:
    resp = await get(client, bearer, mini.user(role), "/owner-home", from_=FROM, to=TO)
    assert resp.status_code == 403
    assert resp.json()["code"] == "forbidden"


async def test_filters_narrow_and_echo(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    await build(mini)
    owner = mini.user("owner")
    n1 = mini.stores["N1"].id
    resp = await get(client, bearer, owner, "/owner-home", from_=FROM, to=TO, store_id=n1)
    body = resp.json()
    assert body["filters"]["store_id"] == str(n1)
    assert kpis(body)["revenue"]["value"] == 2_520
    assert [s["code"] for s in body["stores"]] == ["N1"]

    north = mini.clusters["north"].id
    resp = await get(client, bearer, owner, "/owner-home", from_=FROM, to=TO, cluster_id=north)
    assert kpis(resp.json())["revenue"]["value"] == 4_120

    paddy = mini.crops["paddy"].id
    resp = await get(client, bearer, owner, "/owner-home", from_=FROM, to=TO, crop_id=paddy)
    k = kpis(resp.json())
    assert k["revenue"]["value"] == 2_520  # F1 grows paddy
    assert k["verified_visits"]["value"] == 1

    o1 = mini.user("o1").id
    resp = await get(client, bearer, owner, "/owner-home", from_=FROM, to=TO, officer_id=o1)
    k = kpis(resp.json())
    assert k["revenue"]["value"] == 2_520  # the order O1 placed
    assert k["verified_visits"]["value"] == 1
    assert resp.json()["filters"]["officer_id"] == str(o1)


async def test_invalid_filters(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    owner = mini.user("owner")
    n1, south = mini.stores["N1"].id, mini.clusters["south"].id

    resp = await get(client, bearer, owner, "/owner-home", store_id=n1, cluster_id=south)
    assert resp.status_code == 422
    assert resp.json()["code"] == "invalid_filter_combination"

    o2 = mini.user("o2").id
    resp = await get(client, bearer, owner, "/owner-home", officer_id=o2, store_id=n1)
    assert resp.status_code == 422
    assert resp.json()["code"] == "invalid_filter_combination"

    resp = await get(client, bearer, owner, "/owner-home", from_="2026-08-10", to="2026-08-01")
    assert resp.status_code == 422
    assert resp.json()["code"] == "invalid_date_range"

    resp = await get(client, bearer, owner, "/owner-home", from_="2025-01-01", to="2026-08-01")
    assert resp.json()["code"] == "invalid_date_range"

    resp = await get(client, bearer, owner, "/owner-home", from_="not-a-date")
    assert resp.status_code == 422

    for key in ("store_id", "cluster_id", "officer_id", "crop_id"):
        resp = await get(
            client, bearer, owner, "/owner-home", **{key: "00000000-0000-0000-0000-000000000000"}
        )
        assert resp.status_code == 404, key

    # A cluster head may not look at another cluster or its stores.
    head = mini.user("cluster_head")
    resp = await get(client, bearer, head, "/owner-home", cluster_id=south)
    assert resp.status_code == 404
    resp = await get(client, bearer, head, "/owner-home", store_id=mini.stores["S1"].id)
    assert resp.status_code == 404
    resp = await get(client, bearer, head, "/owner-home", officer_id=o2)
    assert resp.status_code == 404


async def test_default_range_is_the_last_30_days(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    resp = await get(client, bearer, mini.user("owner"), "/owner-home")
    assert resp.status_code == 200
    f = resp.json()["filters"]
    assert f["days"] == 30
    assert (date.fromisoformat(f["to"]) - date.fromisoformat(f["from"])).days == 29
