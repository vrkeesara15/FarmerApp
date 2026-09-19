"""WC-003 farmers directory and farmer 360 (``Mini`` tenant)."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient

from farmerapp.farmers.models import ConsentRecord, CropPlot
from tests.analytics.builders import Mini, ist
from tests.analytics.conftest import get
from tests.analytics.test_owner_home import FROM, TO
from tests.analytics.test_owner_home import build as build_home
from tests.authz.conftest import Bearer


async def build(m: Mini) -> None:
    await build_home(m)
    await m.session_token("farmer_user", ist(date(2026, 7, 20), 8))
    await m.session_token("farmer_user", ist(date(2026, 8, 5), 8))
    f1 = m.farmers["f1"].id
    base = {"tenant_id": m.tid, "subject_type": "farmer", "subject_id": f1, "version": "v1"}
    await m.add(
        ConsentRecord(
            **base, purpose="data", channel="officer", granted_at=ist(date(2026, 1, 5), 12),
            created_at=ist(date(2026, 1, 5), 12),
        ),
        ConsentRecord(
            **base, purpose="marketing", channel="officer", granted_at=ist(date(2026, 1, 5), 12),
            created_at=ist(date(2026, 1, 5), 12, 1),
        ),
        ConsentRecord(
            **base, purpose="marketing", channel="app", withdrawn_at=ist(date(2026, 3, 1), 9),
            created_at=ist(date(2026, 3, 1), 9),
        ),
    )  # fmt: skip


def names(body: dict[str, Any]) -> list[str]:
    return [r["name"] for r in body["items"]]


async def test_directory_rows(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    await build(mini)
    resp = await get(client, bearer, mini.user("owner"), "/farmers", from_=FROM, to=TO)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["total"] == 3 and body["next_cursor"] is None
    assert names(body) == ["Farmer F1", "Farmer F2", "Farmer F3"]
    f1, f2, f3 = body["items"]
    assert f1["crops"] == ["paddy"] and f1["stages"] == ["vegetative"]
    assert f1["acres"] == pytest.approx(2.5)
    assert f1["last_visit_at"].startswith("2026-08-02")
    assert datetime.fromisoformat(f1["last_purchase_at"]) == ist(date(2026, 8, 3), 10)
    assert (f1["balance_paise"], f1["overdue_paise"], f1["credit_risk"]) == (6_000, 6_000, "high")
    assert f1["ltv_paise"] == 620 + 300  # 3 Aug (2,520 - 1,900) and 1 July (1,000 - 700)
    assert f1["app_user"] is True
    assert f1["village"] == "Village N1" and f1["district"] == "District N1"
    assert (f2["balance_paise"], f2["overdue_paise"], f2["credit_risk"]) == (3_000, 0, "low")
    assert f2["ltv_paise"] == 300 and f2["crops"] == []
    assert (f3["overdue_paise"], f3["credit_risk"]) == (5_000, "medium")
    # AN-014: the directory never carries the full phone.
    for farmer in mini.farmers.values():
        assert farmer.phone not in resp.text
        assert f"{'*' * (len(farmer.phone) - 4)}{farmer.phone[-4:]}" in resp.text


async def test_directory_search_filters_and_sort(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    await build(mini)
    owner = mini.user("owner")

    async def query(**params: object) -> list[str]:
        resp = await get(client, bearer, owner, "/farmers", from_=FROM, to=TO, **params)
        assert resp.status_code == 200, resp.text
        return names(resp.json())

    assert await query(q=mini.farmers["f2"].phone[-4:]) == ["Farmer F2"]
    assert await query(q="village s1") == ["Farmer F3"]
    assert await query(q="farmer f") == ["Farmer F1", "Farmer F2", "Farmer F3"]
    assert await query(district="district n1") == ["Farmer F1", "Farmer F2"]
    assert await query(stage="vegetative") == ["Farmer F1", "Farmer F3"]
    assert await query(credit_risk="high") == ["Farmer F1"]
    assert await query(credit_risk="medium") == ["Farmer F3"]
    assert await query(last_visit="7d") == ["Farmer F3"]  # 4 Aug; the others 2-3 Aug
    assert await query(last_visit="30d") == ["Farmer F1", "Farmer F2", "Farmer F3"]
    assert await query(last_visit="never") == []
    assert await query(last_visit="over_90d") == []
    assert await query(sort="-ltv") == ["Farmer F1", "Farmer F2", "Farmer F3"]
    assert await query(sort="balance") == ["Farmer F2", "Farmer F3", "Farmer F1"]
    assert (await query(sort="-last_visit"))[0] == "Farmer F3"
    assert await query(sort="-overdue") == ["Farmer F1", "Farmer F3", "Farmer F2"]
    assert (await query(sort="last_purchase"))[0] == "Farmer F2"  # a year ago
    assert await query(crop_id=mini.crops["paddy"].id) == ["Farmer F1"]
    assert await query(officer_id=mini.user("o2").id) == ["Farmer F3"]
    assert await query(store_id=mini.stores["N1"].id) == ["Farmer F1", "Farmer F2"]

    resp = await get(client, bearer, owner, "/farmers", sort="phone")
    assert resp.status_code == 422 and resp.json()["code"] == "invalid_sort"
    resp = await get(client, bearer, owner, "/farmers", cursor="!!!")
    assert resp.status_code == 400 and resp.json()["code"] == "invalid_cursor"
    resp = await get(client, bearer, owner, "/farmers", credit_risk="extreme")
    assert resp.status_code == 422


async def test_directory_cursor(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    owner = mini.user("owner")
    first = (await get(client, bearer, owner, "/farmers", limit=2)).json()
    assert names(first) == ["Farmer F1", "Farmer F2"] and first["total"] == 3
    assert first["next_cursor"]
    second = (
        await get(client, bearer, owner, "/farmers", limit=2, cursor=first["next_cursor"])
    ).json()
    assert names(second) == ["Farmer F3"] and second["next_cursor"] is None


@pytest.mark.parametrize(
    ("role", "expected"),
    [
        ("cluster_head", ["Farmer F1", "Farmer F2"]),
        ("store_manager", ["Farmer F1", "Farmer F2"]),
        ("o1", ["Farmer F1", "Farmer F2"]),
        ("o2", ["Farmer F3"]),
        ("auditor", ["Farmer F1", "Farmer F2", "Farmer F3"]),
    ],
)
async def test_directory_scope(
    client: AsyncClient, bearer: Bearer, mini: Mini, role: str, expected: list[str]
) -> None:
    resp = await get(client, bearer, mini.user(role), "/farmers")
    assert names(resp.json()) == expected


@pytest.mark.parametrize("role", ["accountant", "agronomist", "farmer_user"])
async def test_directory_forbidden(
    client: AsyncClient, bearer: Bearer, mini: Mini, role: str
) -> None:
    assert (await get(client, bearer, mini.user(role), "/farmers")).status_code == 403
    path = f"/farmers/{mini.farmers['f1'].id}/360"
    assert (await get(client, bearer, mini.user(role), path)).status_code == 403


async def test_farmer_360(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    await build(mini)
    f1 = mini.farmers["f1"]
    resp = await get(client, bearer, mini.user("owner"), f"/farmers/{f1.id}/360", from_=FROM, to=TO)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["profile"]["phone"] == f1.phone
    assert body["profile"]["registered_by_name"] == "User o1"
    assert body["profile"]["store_id"] == str(mini.stores["N1"].id)
    (farm,) = body["farms"]
    assert farm["boundary"]["type"] == "Polygon"
    assert farm["centroid"]["type"] == "Point"
    assert [p["crop_code"] for p in farm["crop_plots"]] == ["paddy"]
    assert [v["checkin_at"][:10] for v in body["visits"]] == ["2026-08-02", "2025-08-05"]
    assert body["visits"][0]["confirmed"] is True
    assert body["visits"][0]["officer_name"] == "User o1"
    assert body["diagnoses"] == [] and body["notes"]["diagnoses"] == "pending_m6_diagnosis"
    assert [o["status"] for o in body["orders"]] == ["cancelled", "delivered", "delivered"]
    assert body["orders"][1]["lines"] == 2
    khata = body["khata"]
    assert (khata["balance_paise"], khata["overdue_paise"]) == (6_000, 6_000)
    assert khata["overdue_buckets"]["61_90"] == 6_000
    assert khata["credit_risk"] == "high"
    assert khata["next_due_date"] is None
    assert body["consent"]["current"] == {"data": True, "marketing": False}
    assert [e["granted"] for e in body["consent"]["history"]] == [True, True, False]
    usage = body["app_usage"]
    assert usage["has_app_login"] is True
    assert usage["sessions_last_60_days"] == 2
    assert usage["last_session_at"].startswith("2026-08-05")
    assert usage["proxy"] == "refresh_token_issuance"
    assert body["ltv_paise"] == 920
    assert body["last_visit_at"].startswith("2026-08-02")
    assert datetime.fromisoformat(body["last_purchase_at"]) == ist(date(2026, 8, 3), 10)
    assert body["active"] is True

    f2 = (await get(client, bearer, mini.user("owner"), f"/farmers/{mini.farmers['f2'].id}/360",
                    from_=FROM, to=TO)).json()  # fmt: skip
    assert f2["active"] is False  # partial visit only, last purchase a year ago
    assert f2["app_usage"]["has_app_login"] is False
    assert f2["khata"]["next_due_date"] == "2026-12-01"


async def test_farmer_360_reflects_the_latest_writes(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    """WC-003 "profile reflects latest sync": the 360 reads the live tables."""
    f2 = mini.farmers["f2"]
    path = f"/farmers/{f2.id}/360"
    owner = mini.user("owner")
    before = (await get(client, bearer, owner, path)).json()
    assert before["visits"] == [] and before["farms"][0]["crop_plots"] == []

    # What a sync merge writes: a visit and a crop plot on the farmer's farm.
    now = datetime.now(UTC)
    await mini.visit("o1", "f2", now - timedelta(minutes=30), score=90)
    farm_id = before["farms"][0]["id"]
    await mini.add(
        CropPlot(
            tenant_id=mini.tid,
            farm_id=farm_id,
            crop_id=mini.crops["cotton"].id,
            season="kharif",
            sowing_date=date(2026, 7, 1),
            stage="flowering",
        )
    )
    f2.landmark = "near the new borewell"
    await mini.session.flush()
    after = (await get(client, bearer, owner, path)).json()
    assert len(after["visits"]) == 1 and after["visits"][0]["status"] == "verified"
    assert [p["crop_code"] for p in after["farms"][0]["crop_plots"]] == ["cotton"]
    assert after["profile"]["landmark"] == "near the new borewell"
    assert after["active"] is True


@pytest.mark.parametrize(
    ("role", "farmer", "status"),
    [
        ("o1", "f1", 200),
        ("o1", "f3", 404),  # another officer's farmer
        ("store_manager", "f2", 200),
        ("store_manager", "f3", 404),  # another store's farmer
        ("cluster_head", "f3", 404),  # another cluster
        ("director", "f3", 200),
    ],
)
async def test_farmer_360_scope(
    client: AsyncClient, bearer: Bearer, mini: Mini, role: str, farmer: str, status: int
) -> None:
    path = f"/farmers/{mini.farmers[farmer].id}/360"
    resp = await get(client, bearer, mini.user(role), path)
    assert resp.status_code == status
