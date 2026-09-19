"""FA-023 travel allowance and expense claims.

Acceptance "km within 10 % of the Google Maps route distance on test routes": the fixture
routes of ``tests/duty/test_processing.py`` driven end to end through the duty end (VV-006
processing) and read back as the day's allowance; the real Google Maps comparison is a human
gate (docs/prs/M7-field-p1-api.md).
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import date, timedelta
from decimal import Decimal
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.duty.service import close_session
from farmerapp.notifications.models import Notification
from farmerapp.tenants.settings import TenantSettings
from farmerapp.travel import events
from farmerapp.travel.service import ta_for, travel_day
from tests.analytics.builders import Mini, ist
from tests.authz.conftest import Bearer
from tests.duty.test_processing import ROUTES, drive, road_length
from tests.field_tokens import mint_bearer


@pytest.fixture
def bearer(app: FastAPI) -> Bearer:
    return mint_bearer(app)


DAY = date(2026, 8, 12)


@pytest.fixture
async def mini(app: FastAPI, db_session: AsyncSession) -> Mini:
    app.state.auth.clock = FakeClock(ist(DAY, 18))  # claims are checked against "today"
    return await Mini.create(db_session)


async def receipt(app: FastAPI, tenant_id: uuid.UUID) -> str:
    data = uuid.uuid4().bytes
    sha = hashlib.sha256(data).hexdigest()
    uri: str = await app.state.blobs.put(
        f"{tenant_id}/receipt/{sha}", data, content_type="image/jpeg"
    )
    return uri


def test_ta_is_capped_km_times_rate() -> None:
    settings = TenantSettings(ta_rate_per_km_paise=350, ta_daily_km_cap=100)
    assert ta_for(Decimal("42.37"), settings) == (Decimal("42.37"), 14830)  # 14829.5 -> up
    assert ta_for(Decimal("180.00"), settings) == (Decimal("100.00"), 35000)


@pytest.mark.parametrize("name", sorted(ROUTES))
async def test_daily_km_within_10_percent_of_the_route(
    db_session: AsyncSession, mini: Mini, name: str
) -> None:
    legs = ROUTES[name]
    points = drive(legs, start=ist(DAY, 9))
    duty = await mini.duty(
        "o1", ist(DAY, 9), None, km="0", points=[(p.ts, p.lat, p.lon) for p in points]
    )
    await close_session(
        db_session, duty, end_at=points[-1].ts + timedelta(minutes=5), end_reason="manual"
    )
    day = await travel_day(db_session, mini.tid, mini.user("o1").id, DAY)
    truth = road_length(legs) / 1000
    assert abs(float(day.km) - truth) / truth <= 0.10, (name, day.km, truth)
    assert day.ta_paise == int((day.km_capped * 300).to_integral_value())


async def test_day_sums_sessions_caps_and_ignores_open_ones(
    db_session: AsyncSession, mini: Mini
) -> None:
    await mini.duty("o1", ist(DAY, 7), ist(DAY, 12), km="90.00")
    await mini.duty("o1", ist(DAY, 13), ist(DAY, 19), km="75.50")
    await mini.duty("o1", ist(DAY + timedelta(days=1), 9), None, km="0")  # open
    first = await travel_day(db_session, mini.tid, mini.user("o1").id, DAY)
    assert first.sessions == 2 and first.km == Decimal("165.50")
    assert first.km_capped == Decimal("150.00") and first.ta_paise == 45_000
    nxt = await travel_day(db_session, mini.tid, mini.user("o1").id, DAY + timedelta(days=1))
    assert nxt.open_session is True and nxt.ta_paise == 0
    none = await travel_day(db_session, mini.tid, mini.user("o2").id, DAY)
    assert none.sessions == 0 and none.ta_paise == 0


async def test_claim_submit_approve_and_statement(
    app: FastAPI, client: AsyncClient, bearer: Bearer, mini: Mini, db_session: AsyncSession
) -> None:
    await mini.duty("o1", ist(DAY, 9), ist(DAY, 18), km="42.00")
    seen: list[events.TravelClaimSubmitted] = []

    async def spy(_session: AsyncSession, event: events.TravelClaimSubmitted) -> None:
        seen.append(event)

    events.bus.subscribe_async(events.TravelClaimSubmitted, spy)
    try:
        o1 = mini.user("o1")
        body: dict[str, Any] = {
            "claim_date": str(DAY),
            "type": "fuel",
            "amount_paise": 25_000,
            "receipt_uri": await receipt(app, mini.tid),
            "note": "Petrol",
        }
        resp = await client.post(
            "/v1/travel/claims",
            json=body,
            headers={**bearer(o1), "Idempotency-Key": "claim-1"},
        )
        assert resp.status_code == 201, resp.text
        claim = resp.json()
        assert claim["status"] == "submitted" and claim["km_computed"] == "42.00"
        replay = await client.post(
            "/v1/travel/claims", json=body, headers={**bearer(o1), "Idempotency-Key": "claim-1"}
        )
        assert replay.json()["id"] == claim["id"]
    finally:
        events.bus.unsubscribe_async(events.TravelClaimSubmitted, spy)
    assert len(seen) == 1
    assert seen[0].km_computed == Decimal("42.00") and seen[0].ta_paise == 12_600
    assert seen[0].amount_paise == 25_000 and seen[0].claim_type == "fuel"

    # The cluster head of the officer's cluster is notified and decides.
    head = mini.user("cluster_head")
    note = await db_session.scalar(
        select(Notification).where(
            Notification.user_id == head.id, Notification.kind == "travel_claim_submitted"
        )
    )
    assert note is not None and note.data["claim_id"] == claim["id"]
    listed = await client.get("/v1/travel/claims", headers=bearer(head))
    assert [c["id"] for c in listed.json()["items"]] == [claim["id"]]
    resp = await client.post(
        f"/v1/travel/claims/{claim['id']}/approve", json={"note": "OK"}, headers=bearer(head)
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "approved" and resp.json()["decided_by"] == str(head.id)
    again = await client.post(
        f"/v1/travel/claims/{claim['id']}/reject", json={}, headers=bearer(head)
    )
    assert again.status_code == 409 and again.json()["code"] == "claim_not_pending"
    decided = await db_session.scalar(
        select(Notification).where(
            Notification.user_id == o1.id, Notification.kind == "travel_claim_decided"
        )
    )
    assert decided is not None and decided.body_key.endswith(".approved")

    statement = await client.get(
        "/v1/travel/statement", params={"month": "2026-08"}, headers=bearer(o1)
    )
    assert statement.status_code == 200, statement.text
    s = statement.json()
    assert s["ta_total_paise"] == 12_600 and s["claims_approved_paise"] == 25_000
    assert s["payable_paise"] == 37_600 and len(s["days"]) == 1
    # The owner and the accountant read it for the officer; o2 cannot see o1.
    for viewer in ("owner", "accountant"):
        resp = await client.get(
            "/v1/travel/statement",
            params={"month": "2026-08", "officer_id": str(o1.id)},
            headers=bearer(mini.user(viewer)),
        )
        assert resp.json()["payable_paise"] == 37_600, viewer
    resp = await client.get(
        "/v1/travel/statement", params={"month": "2026-08"}, headers=bearer(mini.user("owner"))
    )
    assert resp.status_code == 422 and resp.json()["code"] == "officer_required"
    resp = await client.get(
        "/v1/travel/statement",
        params={"month": "2026-08", "officer_id": str(o1.id)},
        headers=bearer(mini.user("o2")),
    )
    assert resp.status_code == 404
    resp = await client.get(f"/v1/travel/claims/{claim['id']}", headers=bearer(mini.user("o2")))
    assert resp.status_code == 404


async def test_claim_rules(
    app: FastAPI, client: AsyncClient, bearer: Bearer, mini: Mini, db_session: AsyncSession
) -> None:
    o2 = mini.user("o2")
    base = {"claim_date": str(DAY), "type": "bus", "amount_paise": 4_000}
    resp = await client.post(
        "/v1/travel/claims",
        json={**base, "receipt_uri": f"gs://local/{uuid.uuid4()}/receipt/{'0' * 64}"},
        headers=bearer(o2),
    )
    assert resp.status_code == 422 and resp.json()["code"] == "invalid_blob"
    for bad_day in (DAY + timedelta(days=1), DAY - timedelta(days=91)):
        resp = await client.post(
            "/v1/travel/claims",
            json={**base, "claim_date": str(bad_day), "receipt_uri": await receipt(app, mini.tid)},
            headers=bearer(o2),
        )
        assert resp.status_code == 422 and resp.json()["code"] == "claim_date_invalid"
    resp = await client.post(
        "/v1/travel/claims",
        json={**base, "receipt_uri": await receipt(app, mini.tid)},
        headers=bearer(o2),
    )
    claim = resp.json()
    assert claim["km_computed"] is None  # no processed duty that day
    # o2 is in the South cluster: the North cluster head cannot see or decide it.
    resp = await client.post(
        f"/v1/travel/claims/{claim['id']}/approve",
        json={},
        headers=bearer(mini.user("cluster_head")),
    )
    assert resp.status_code == 404
    resp = await client.post(
        f"/v1/travel/claims/{claim['id']}/reject",
        json={"note": "No receipt date"},
        headers=bearer(mini.user("owner")),
    )
    assert resp.json()["status"] == "rejected"


async def test_claim_offline_through_sync(
    app: FastAPI, client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    o1 = mini.user("o1")
    claim_id = uuid.uuid4()
    op = {
        "op_id": str(uuid.uuid4()),
        "entity": "travel_claim",
        "action": "create",
        "entity_id": str(claim_id),
        "base_version": 0,
        "payload": {
            "claim_date": str(DAY),
            "type": "other",
            "amount_paise": 1_500,
            "receipt_uri": await receipt(app, mini.tid),
        },
        "client_ts": ist(DAY, 17).isoformat(),
    }
    resp = await client.post(
        "/v1/sync", json={"device_id": "d1", "cursor": None, "ops": [op]}, headers=bearer(o1)
    )
    result = resp.json()["results"][0]
    assert result["status"] == "applied", result
    assert result["server"]["id"] == str(claim_id)
    feed = [c for c in resp.json()["changes"] if c["entity"] == "travel_claim"]
    assert [c["entity_id"] for c in feed] == [str(claim_id)]
    # A replay with a new op id: the stored claim comes back as a conflict.
    op2 = {**op, "op_id": str(uuid.uuid4())}
    resp = await client.post(
        "/v1/sync", json={"device_id": "d1", "cursor": None, "ops": [op2]}, headers=bearer(o1)
    )
    assert resp.json()["results"][0]["status"] == "conflict"
