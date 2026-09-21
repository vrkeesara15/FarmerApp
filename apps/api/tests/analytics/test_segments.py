"""AN-004 farmer segments: preview, saved segments and the churn-risk list (``Mini`` tenant)."""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

import pytest
from httpx import AsyncClient

from farmerapp.analytics.farmers import CHURN_WINDOW_DAYS
from tests.analytics.builders import Mini, ist
from tests.analytics.conftest import get
from tests.analytics.test_owner_home import FROM, TO
from tests.analytics.test_owner_home import build as build_home
from tests.authz.conftest import Bearer
from tests.growth.conftest import consent

# The AN-011 range the preview is measured from (its end is "now" for relative windows).
SEG_TO = TO


async def build(m: Mini) -> None:
    """The owner-home world plus marketing consent for f1 and f3 (f2 never asked)."""
    await build_home(m)
    await consent(m, m.farmers["f1"], granted=True, at=ist(date(2026, 1, 10), 9))
    await consent(m, m.farmers["f3"], granted=True, at=ist(date(2026, 1, 10), 9))


async def preview(
    client: AsyncClient, mint: Bearer, m: Mini, role: str, definition: dict[str, Any]
) -> Any:
    return await client.post(
        "/v1/analytics/segments/preview",
        params={"from": FROM.isoformat(), "to": SEG_TO.isoformat()},
        json={"definition": definition},
        headers=mint(m.user(role)),
    )


def facet(body: dict[str, Any], key: str) -> dict[str, int]:
    return {f["key"]: f["count"] for f in body[key]}


async def test_preview_counts_and_breakdowns(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    await build(mini)
    resp = await preview(client, bearer, mini, "owner", {})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["matched"] == 3  # every live farmer of the tenant
    assert body["consented"] == 2 and body["excluded_no_consent"] == 1
    assert facet(body, "by_consent") == {"granted": 2, "withheld": 1}
    assert facet(body, "by_crop") == {"paddy": 1, "cotton": 1}
    assert facet(body, "by_stage") == {"vegetative": 2}
    assert facet(body, "by_district") == {"District N1": 2, "District S1": 1}
    # Every Mini farm is 2.5 acres.
    assert facet(body, "by_acreage_band") == {"under_2": 0, "2_5": 3, "5_10": 0, "over_10": 0}
    assert facet(body, "by_app_usage") == {"app_user": 1, "no_app": 2}
    assert body["app_users"] == 1
    assert body["filters"]["to"] == SEG_TO.isoformat()
    # Spend bands: f1 3,520 paise, f2 1,000 (last year), f3 1,000 -- all under 5,000 rupees.
    assert facet(body, "by_spend_band") == {
        "none": 0,
        "under_5k": 3,
        "5k_25k": 0,
        "25k_1l": 0,
        "over_1l": 0,
    }
    assert body["spend_paise"] == 3_520 + 1_000 + 1_000


async def test_preview_applies_criteria_and_role_scope(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    await build(mini)
    crop = {"crop_ids": [str(mini.crops["paddy"].id)]}
    body = (await preview(client, bearer, mini, "owner", crop)).json()
    assert body["matched"] == 1 and facet(body, "by_crop") == {"paddy": 1}

    acres = {"min_acres": 5}
    assert (await preview(client, bearer, mini, "owner", acres)).json()["matched"] == 0

    # A cluster head only ever sees their own cluster's farmers (SPEC 2.6): f1, f2 at N1.
    head = (await preview(client, bearer, mini, "cluster_head", {})).json()
    assert head["matched"] == 2 and head["filters"]["scope"] == "cluster"


async def test_preview_rejects_inconsistent_definition(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    resp = await preview(client, bearer, mini, "owner", {"min_acres": 10, "max_acres": 2})
    assert resp.status_code == 422


@pytest.mark.parametrize(
    ("role", "status"),
    [
        ("owner", 200),
        ("cluster_head", 200),
        ("auditor", 200),
        ("store_manager", 403),
        ("o1", 403),
        ("agronomist", 403),
    ],
)
async def test_preview_roles(
    client: AsyncClient, bearer: Bearer, mini: Mini, role: str, status: int
) -> None:
    assert (await preview(client, bearer, mini, role, {})).status_code == status


# --------------------------------------------------------------------------- saved segments
async def test_saved_segment_round_trip(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    await build(mini)
    owner = mini.user("owner")
    created = await client.post(
        "/v1/analytics/segments",
        params={"from": FROM.isoformat(), "to": SEG_TO.isoformat()},
        json={
            "name": "Paddy growers",
            "description": "Kharif paddy, for the seed campaign",
            "definition": {"crop_ids": [str(mini.crops["paddy"].id)]},
        },
        headers=bearer(owner),
    )
    assert created.status_code == 201, created.text
    row = created.json()
    assert row["name"] == "Paddy growers"
    assert row["definition"]["crop_ids"] == [str(mini.crops["paddy"].id)]
    assert row["last_count"] == 1  # f1 grows paddy and has consented
    assert row["created_by"] == str(owner.id)

    listed = await client.get("/v1/analytics/segments", headers=bearer(owner))
    assert [s["id"] for s in listed.json()["items"]] == [row["id"]]

    patched = await client.patch(
        f"/v1/analytics/segments/{row['id']}",
        params={"from": FROM.isoformat(), "to": SEG_TO.isoformat()},
        json={"name": "Paddy growers (kharif)", "definition": {}},
        headers=bearer(owner),
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["name"] == "Paddy growers (kharif)"
    assert patched.json()["last_count"] == 2  # the whole consented tenant

    deleted = await client.delete(f"/v1/analytics/segments/{row['id']}", headers=bearer(owner))
    assert deleted.status_code == 204
    assert await client.get("/v1/analytics/segments", headers=bearer(owner)) is not None
    gone = await client.get(f"/v1/analytics/segments/{row['id']}", headers=bearer(owner))
    assert gone.status_code == 404


async def test_saved_segment_name_is_unique(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    body = {"name": "Big farms", "definition": {"min_acres": 5}}
    first = await client.post(
        "/v1/analytics/segments", json=body, headers=bearer(mini.user("owner"))
    )
    assert first.status_code == 201
    again = await client.post(
        "/v1/analytics/segments",
        json={**body, "name": "big farms"},
        headers=bearer(mini.user("owner")),
    )
    assert again.status_code == 409
    assert again.json()["code"] == "segment_name_taken"


@pytest.mark.parametrize(
    ("role", "status"), [("owner", 201), ("tenant_admin", 201), ("cluster_head", 403)]
)
async def test_saved_segment_write_roles(
    client: AsyncClient, bearer: Bearer, mini: Mini, role: str, status: int
) -> None:
    resp = await client.post(
        "/v1/analytics/segments",
        json={"name": f"Segment {role}", "definition": {}},
        headers=bearer(mini.user(role)),
    )
    assert resp.status_code == status


async def test_campaign_from_saved_segment(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    """AN-004 / WC-008: a campaign takes a copy of the saved definition."""
    await build(mini)
    owner = mini.user("owner")
    saved = (
        await client.post(
            "/v1/analytics/segments",
            json={"name": "Paddy", "definition": {"crop_ids": [str(mini.crops["paddy"].id)]}},
            headers=bearer(owner),
        )
    ).json()
    campaign = await client.post(
        "/v1/campaigns",
        json={
            "name": "Seed offer",
            "channel": "sms",
            "saved_segment_id": saved["id"],
            "messages": {"en": "Seed offer this week."},
        },
        headers=bearer(owner),
    )
    assert campaign.status_code == 201, campaign.text
    assert campaign.json()["segment"] == {"crop_ids": [str(mini.crops["paddy"].id)]}

    missing = await client.post(
        "/v1/campaigns",
        json={
            "name": "Nowhere",
            "channel": "sms",
            "saved_segment_id": "00000000-0000-0000-0000-000000000000",
            "messages": {"en": "Hello."},
        },
        headers=bearer(owner),
    )
    assert missing.status_code == 404


# --------------------------------------------------------------------------- churn risk
async def test_churn_risk_list(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    await build(mini)
    # f1 bought on 3 August and was visited on 2 August: recent, so not at risk yet.
    resp = await get(client, bearer, mini.user("owner"), "/farmers-churn-risk", from_=FROM, to=TO)
    assert resp.status_code == 200, resp.text
    assert resp.json()["total"] == 0
    assert resp.json()["window_days"] == CHURN_WINDOW_DAYS

    # Looked at from far enough in the future, the same farmer has gone quiet.
    later = date(2026, 8, 3) + timedelta(days=CHURN_WINDOW_DAYS + 5)
    body = (
        await get(
            client,
            bearer,
            mini.user("owner"),
            "/farmers-churn-risk",
            from_=later - timedelta(days=29),
            to=later,
        )
    ).json()
    # Every Mini farmer has bought at some point, and none was seen in the window.
    assert [r["name"] for r in body["items"]] == ["Farmer F1", "Farmer F2", "Farmer F3"]
    row = body["items"][0]  # biggest LTV first
    assert row["orders"] == 2 and row["ltv_paise"] == 920 and row["spend_paise"] == 3_520
    assert row["days_since_last_purchase"] >= CHURN_WINDOW_DAYS
    assert row["phone_masked"].startswith("*") and len(row["phone_masked"]) == 13
    assert row["credit_risk"] == "high"
    assert body["total"] == 3

    short = (
        await get(
            client,
            bearer,
            mini.user("owner"),
            "/farmers-churn-risk",
            from_=later - timedelta(days=29),
            to=later,
            days=365,
        )
    ).json()
    assert short["total"] == 0 and short["window_days"] == 365


async def test_churn_flag_on_directory_and_360(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    await build(mini)
    later = date(2026, 8, 3) + timedelta(days=CHURN_WINDOW_DAYS + 5)
    rows = (
        await get(
            client,
            bearer,
            mini.user("owner"),
            "/farmers",
            from_=later - timedelta(days=29),
            to=later,
        )
    ).json()["items"]
    flags = {r["name"]: r["churn_risk"] for r in rows}
    assert flags == {"Farmer F1": True, "Farmer F2": True, "Farmer F3": True}
    assert next(r for r in rows if r["name"] == "Farmer F1")["spend_paise"] == 3_520

    profile = (
        await get(
            client,
            bearer,
            mini.user("owner"),
            f"/farmers/{mini.farmers['f1'].id}/360",
            from_=later - timedelta(days=29),
            to=later,
        )
    ).json()
    assert profile["churn_risk"]["at_risk"] is True
    assert profile["churn_risk"]["window_days"] == CHURN_WINDOW_DAYS
    assert profile["churn_risk"]["orders"] == 2
    assert profile["ltv_paise"] == 920 and profile["spend_paise"] == 3_520
