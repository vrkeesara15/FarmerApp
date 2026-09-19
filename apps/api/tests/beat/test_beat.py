"""FA-018 acceptance: "plan generated at 6:00 local; officer can reorder and add"."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, timedelta

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.beat.models import BeatPlan
from farmerapp.beat.service import generate_for_tenant
from farmerapp.demo_plots.models import DemoPlot
from farmerapp.diagnosis.models import Diagnosis
from farmerapp.farmers.models import CropPlot, Farm
from farmerapp.notifications.models import Notification
from tests.analytics.builders import Mini, ist
from tests.authz.conftest import Bearer
from tests.field_tokens import mint_bearer


@pytest.fixture
def bearer(app: FastAPI) -> Bearer:
    return mint_bearer(app)


DAY = date(2026, 8, 12)


@dataclass
class Beat:
    m: Mini
    headers: dict[str, str]


@pytest.fixture
async def beat(app: FastAPI, db_session: AsyncSession, bearer: Bearer) -> Beat:
    """O1's farmers: F4 (paddy; pest alert in the district + a demo due), F1 (paddy; pest
    alert + last visit 20 days ago), F2 (credit due in 3 days, never visited). O2 owns F3."""
    app.state.auth.clock = FakeClock(ist(DAY, 6, 5))  # just after the 06:00 run
    m = await Mini.create(db_session, settings={"beat_daily_target": 3})
    f4 = await m.farmer("f4", "N1", "o1", "paddy", name="Farmer F4")
    await m.visit("o1", "f1", ist(DAY - timedelta(days=20), 10))
    await m.visit("o1", "f4", ist(DAY - timedelta(days=2), 10))
    await m.khata("f2", "N1", "debit", 5_000, ist(DAY - timedelta(days=30), 10), DAY + timedelta(3))
    diag = Diagnosis(
        tenant_id=m.tid,
        subject="officer",
        farmer_id=f4.id,
        images=[],
        crop_id=m.crops["paddy"].id,
        status="answered",
        created_at=ist(DAY - timedelta(days=3), 11),
        updated_at=ist(DAY - timedelta(days=3), 11),
    )
    farm = await db_session.scalar(select(Farm).where(Farm.farmer_id == f4.id))
    assert farm is not None
    plot = await db_session.scalar(select(CropPlot).where(CropPlot.farm_id == farm.id))
    assert plot is not None
    demo = DemoPlot(
        tenant_id=m.tid,
        officer_id=m.user("o1").id,
        farmer_id=f4.id,
        farm_id=farm.id,
        crop_plot_id=plot.id,
        baseline="farmer_practice",
        treatment="Own Guard 200 ml / acre",
        status="active",
        started_at=ist(DAY - timedelta(days=30), 9),
        last_observed_at=ist(DAY - timedelta(days=10), 9),
    )
    await m.add(diag, demo)
    return Beat(m=m, headers=bearer(m.user("o1")))


def codes(item: dict[str, object]) -> set[str]:
    reasons = item["reasons"]
    assert isinstance(reasons, list)
    return {r["code"] for r in reasons}


async def test_plan_is_generated_with_reasons_in_priority_order(
    client: AsyncClient, beat: Beat
) -> None:
    resp = await client.get("/v1/me/beat", params={"date": str(DAY)}, headers=beat.headers)
    assert resp.status_code == 200, resp.text
    plan = resp.json()
    assert plan["status"] == "generated" and plan["target"] == 3
    names = [i["farmer_name"] for i in plan["items"]]
    assert names == ["Farmer F4", "Farmer F1", "Farmer F2"]
    f4, f1, f2 = plan["items"]
    assert codes(f4) == {"pest_alert", "demo_plot_stage"} and f4["priority"] == 65
    assert codes(f1) == {"pest_alert", "follow_up_due"} and f1["priority"] == 60
    assert codes(f2) == {"credit_due", "follow_up_due"} and f2["priority"] == 55
    credit = next(r for r in f2["reasons"] if r["code"] == "credit_due")
    assert credit["detail"]["open_paise"] == 5_000 and credit["detail"]["overdue"] is False
    assert all(i["source"] == "system" for i in plan["items"])
    assert plan["villages"] == [
        {"village_id": f4["village_id"], "village_name": "Village N1", "items": 3}
    ]
    # Reading again returns the same plan (never regenerated).
    again = await client.get("/v1/me/beat", params={"date": str(DAY)}, headers=beat.headers)
    assert again.json()["id"] == plan["id"]


async def test_officer_reorders_adds_and_removes(client: AsyncClient, beat: Beat) -> None:
    plan = (await client.get("/v1/me/beat", params={"date": str(DAY)}, headers=beat.headers)).json()
    f4, f1, f2 = plan["items"]
    body = {
        "version": plan["version"],
        "items": [
            {"id": f1["id"], "note": "Morning first"},
            {"id": f4["id"]},
            {"kind": "farmer", "farmer_id": str(beat.m.farmers["f2"].id)},  # dup of f2: dropped
            {"kind": "village", "village_id": str(beat.m.villages["N2"].id)},
        ],
    }
    body["items"].insert(2, {"id": f2["id"]})
    resp = await client.put(
        "/v1/me/beat", params={"date": str(DAY)}, json=body, headers=beat.headers
    )
    assert resp.status_code == 200, resp.text
    edited = resp.json()
    assert edited["status"] == "edited" and edited["edited_at"] is not None
    assert [i["id"] for i in edited["items"][:3]] == [f1["id"], f4["id"], f2["id"]]
    assert edited["items"][0]["note"] == "Morning first"
    added = edited["items"][3]
    assert added["kind"] == "village" and added["source"] == "officer"
    assert added["village_name"] == "Village N2" and added["reasons"] == []
    assert len(edited["items"]) == 4

    # Remove by omission.
    resp = await client.put(
        "/v1/me/beat",
        params={"date": str(DAY)},
        json={"items": [{"id": f2["id"]}]},
        headers=beat.headers,
    )
    assert [i["id"] for i in resp.json()["items"]] == [f2["id"]]

    # A stale version, an unknown item and a farmer outside the officer's scope.
    stale = await client.put(
        "/v1/me/beat",
        params={"date": str(DAY)},
        json={"version": plan["version"], "items": []},
        headers=beat.headers,
    )
    assert stale.status_code == 409 and stale.json()["code"] == "version_conflict"
    for item in (
        {"id": str(uuid.uuid4())},
        {"kind": "farmer", "farmer_id": str(beat.m.farmers["f3"].id)},
        {"kind": "village", "village_id": str(uuid.uuid4())},
    ):
        resp = await client.put(
            "/v1/me/beat", params={"date": str(DAY)}, json={"items": [item]}, headers=beat.headers
        )
        assert resp.status_code == 422 and resp.json()["code"] == "beat_item_unknown", item


async def test_six_am_job_keeps_edited_plans_and_notifies(
    client: AsyncClient, beat: Beat, db_session: AsyncSession
) -> None:
    await client.put(
        "/v1/me/beat", params={"date": str(DAY)}, json={"items": []}, headers=beat.headers
    )
    report = await generate_for_tenant(db_session, beat.m.tid, DAY, now=ist(DAY, 6))
    assert report.generated == 1  # O2 only; O1's edited plan stands
    o1_plan = await db_session.scalar(
        select(BeatPlan).where(BeatPlan.officer_id == beat.m.user("o1").id)
    )
    assert o1_plan is not None and o1_plan.items == [] and o1_plan.status == "edited"
    o2_plan = await db_session.scalar(
        select(BeatPlan).where(BeatPlan.officer_id == beat.m.user("o2").id)
    )
    assert o2_plan is not None
    assert [i["farmer_name"] for i in o2_plan.items] == ["Farmer F3"]  # never visited
    note = await db_session.scalar(
        select(Notification).where(
            Notification.user_id == beat.m.user("o2").id, Notification.kind == "beat_plan_ready"
        )
    )
    assert note is not None and note.data["date"] == str(DAY)
    assert (await generate_for_tenant(db_session, beat.m.tid, DAY)).generated == 0


async def test_plan_dates_and_roles(client: AsyncClient, beat: Beat, bearer: Bearer) -> None:
    far = DAY + timedelta(days=5)
    resp = await client.get("/v1/me/beat", params={"date": str(far)}, headers=beat.headers)
    assert resp.status_code == 404 and resp.json()["code"] == "beat_plan_not_found"
    tomorrow = DAY + timedelta(days=1)
    resp = await client.get("/v1/me/beat", params={"date": str(tomorrow)}, headers=beat.headers)
    assert resp.status_code == 200
    for role in ("cluster_head", "owner", "farmer_user"):
        resp = await client.get(
            "/v1/me/beat", params={"date": str(DAY)}, headers=bearer(beat.m.user(role))
        )
        assert resp.status_code == 403, role


async def test_plan_offline_through_sync(client: AsyncClient, beat: Beat) -> None:
    plan = (await client.get("/v1/me/beat", params={"date": str(DAY)}, headers=beat.headers)).json()
    resp = await client.post(
        "/v1/sync", json={"device_id": "d1", "cursor": None, "ops": []}, headers=beat.headers
    )
    feed = [c for c in resp.json()["changes"] if c["entity"] == "beat_plan"]
    assert [c["entity_id"] for c in feed] == [plan["id"]]
    assert feed[0]["data"]["items"][0]["farmer_name"] == "Farmer F4"

    reversed_items = [{"id": i["id"]} for i in reversed(plan["items"])]
    op = {
        "op_id": str(uuid.uuid4()),
        "entity": "beat_plan",
        "action": "update",
        "entity_id": plan["id"],
        "base_version": plan["version"],
        "payload": {"items": reversed_items},
        "client_ts": ist(DAY, 7).isoformat(),
    }
    resp = await client.post(
        "/v1/sync", json={"device_id": "d1", "cursor": None, "ops": [op]}, headers=beat.headers
    )
    result = resp.json()["results"][0]
    assert result["status"] == "applied", result
    assert [i["id"] for i in result["server"]["items"]] == [i["id"] for i in reversed_items]
