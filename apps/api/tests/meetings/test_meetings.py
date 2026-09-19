"""FA-027 acceptance: "attendance list linked to farmers" (OTP and the farmer app's QR)."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import timedelta
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.geo import offset, point_wkt
from farmerapp.meetings.service import decode_qr, issue_qr
from farmerapp.settings import get_settings
from tests.analytics.builders import Mini
from tests.auth.conftest import last_code
from tests.authz.conftest import Bearer
from tests.field_tokens import mint_bearer


@pytest.fixture
def bearer(app: FastAPI) -> Bearer:
    return mint_bearer(app)


MEETING_LON, MEETING_LAT = 79.64, 18.02


@dataclass
class Meet:
    m: Mini
    headers: dict[str, str]

    def body(self, east_m: float = 20.0) -> dict[str, Any]:
        lon, lat = offset(MEETING_LON, MEETING_LAT, east_m, 0)
        return {
            "village_id": str(self.m.villages["N1"].id),
            "topic": "Paddy stem borer: scouting and control",
            "held_at": "2026-08-20T05:00:00+00:00",
            "checkin_point": {"lat": lat, "lon": lon, "accuracy_m": 12},
        }


@pytest.fixture
async def meet(db_session: AsyncSession, bearer: Bearer) -> Meet:
    m = await Mini.create(db_session)
    m.villages["N1"].meeting_point = point_wkt(MEETING_LON, MEETING_LAT)
    await db_session.flush()
    return Meet(m=m, headers=bearer(m.user("o1")))


async def test_attendance_by_qr_and_otp_linked_to_farmers(
    app: FastAPI, client: AsyncClient, bearer: Bearer, meet: Meet
) -> None:
    resp = await client.post("/v1/meetings", json=meet.body(), headers=meet.headers)
    assert resp.status_code == 201, resp.text
    meeting = resp.json()
    assert meeting["geofence_result"] == "meeting_point" and meeting["status"] == "open"
    mid = meeting["id"]

    # QR: the farmer app shows a signed token; the officer scans it.
    qr = await client.get("/v1/me/attendance-qr", headers=bearer(meet.m.user("farmer_user")))
    assert qr.status_code == 200, qr.text
    assert qr.json()["farmer_id"] == str(meet.m.farmers["f1"].id)
    resp = await client.post(
        f"/v1/meetings/{mid}/attendance",
        json={"method": "qr", "token": qr.json()["token"]},
        headers=meet.headers,
    )
    assert resp.status_code == 201, resp.text
    first = resp.json()
    assert first["farmer_id"] == str(meet.m.farmers["f1"].id) and first["method"] == "qr"
    again = await client.post(
        f"/v1/meetings/{mid}/attendance",
        json={"method": "qr", "token": qr.json()["token"]},
        headers=meet.headers,
    )
    assert again.json()["id"] == first["id"]  # a farmer attends once

    # OTP: a code to F2's phone, read out to the officer.
    f2 = meet.m.farmers["f2"]
    sent = await client.post(
        f"/v1/meetings/{mid}/attendance/otp", json={"farmer_id": str(f2.id)}, headers=meet.headers
    )
    assert sent.status_code == 200, sent.text
    assert sent.json()["phone_masked"].endswith(f2.phone[-4:])
    wrong = await client.post(
        f"/v1/meetings/{mid}/attendance",
        json={"method": "otp", "farmer_id": str(f2.id), "code": "000000"},
        headers=meet.headers,
    )
    assert wrong.status_code == 401 and wrong.json()["code"] == "otp_invalid"
    code = last_code(app.state.auth.sms, f2.phone)
    resp = await client.post(
        f"/v1/meetings/{mid}/attendance",
        json={"method": "otp", "farmer_id": str(f2.id), "code": code},
        headers=meet.headers,
    )
    assert resp.status_code == 201, resp.text

    # The attendance list is linked to farmer records.
    detail = await client.get(f"/v1/meetings/{mid}", headers=bearer(meet.m.user("cluster_head")))
    assert detail.status_code == 200
    body = detail.json()
    assert body["attendees"] == 2
    assert {(a["farmer_id"], a["farmer_name"], a["method"]) for a in body["attendance"]} == {
        (str(meet.m.farmers["f1"].id), "Farmer F1", "qr"),
        (str(f2.id), "Farmer F2", "otp"),
    }

    # Closed: no more attendance; O2 cannot see O1's meeting.
    closed = await client.post(f"/v1/meetings/{mid}/close", headers=meet.headers)
    assert closed.json()["status"] == "closed"
    late = await client.post(
        f"/v1/meetings/{mid}/attendance",
        json={"method": "qr", "token": qr.json()["token"]},
        headers=meet.headers,
    )
    assert late.status_code == 409 and late.json()["code"] == "meeting_closed"
    assert (
        await client.get(f"/v1/meetings/{mid}", headers=bearer(meet.m.user("o2")))
    ).status_code == 404
    listed = await client.get("/v1/meetings", headers=bearer(meet.m.user("owner")))
    assert [(i["id"], i["attendees"]) for i in listed.json()["items"]] == [(mid, 2)]


async def test_meeting_outside_the_meeting_point_is_refused(
    client: AsyncClient, meet: Meet
) -> None:
    resp = await client.post("/v1/meetings", json=meet.body(east_m=900), headers=meet.headers)
    assert resp.status_code == 422 and resp.json()["code"] == "outside_geofence"
    assert resp.json()["target"] == "meeting_point" and resp.json()["distance_m"] > 700
    no_point = {**meet.body(), "village_id": str(meet.m.villages["S1"].id)}
    resp = await client.post("/v1/meetings", json=no_point, headers=meet.headers)
    assert resp.status_code == 422 and resp.json()["target"] is None
    resp = await client.post(
        "/v1/meetings", json={**meet.body(), "village_id": str(uuid.uuid4())}, headers=meet.headers
    )
    assert resp.status_code == 404


async def test_qr_tokens_are_checked(client: AsyncClient, meet: Meet, bearer: Bearer) -> None:
    settings = get_settings()
    farmer = meet.m.farmers["f2"]
    now = meet.m.farmers["f2"].created_at
    token = issue_qr(settings, farmer, now=now).token
    assert decode_qr(settings, token, tenant_id=meet.m.tid, at=now) == str(farmer.id)
    meeting = (await client.post("/v1/meetings", json=meet.body(), headers=meet.headers)).json()
    for bad in (token, "x" * 40):  # expired (issued at registration time) / garbage
        resp = await client.post(
            f"/v1/meetings/{meeting['id']}/attendance",
            json={"method": "qr", "token": bad},
            headers=meet.headers,
        )
        assert resp.status_code == 422 and resp.json()["code"] == "attendance_token_invalid"
    # Scanned offline before expiry, synced later: accepted against the scan time.
    op = {
        "op_id": str(uuid.uuid4()),
        "entity": "meeting_attendance",
        "action": "create",
        "entity_id": str(uuid.uuid4()),
        "base_version": 0,
        "payload": {"meeting_id": meeting["id"], "method": "qr", "token": token},
        "client_ts": (now + timedelta(minutes=1)).isoformat(),
    }
    resp = await client.post(
        "/v1/sync", json={"device_id": "d1", "cursor": None, "ops": [op]}, headers=meet.headers
    )
    result = resp.json()["results"][0]
    assert result["status"] == "applied", result
    assert result["server"]["farmer_id"] == str(farmer.id)
    # Only farmers have an attendance QR.
    resp = await client.get("/v1/me/attendance-qr", headers=meet.headers)
    assert resp.status_code == 403


async def test_meeting_created_offline_through_sync(client: AsyncClient, meet: Meet) -> None:
    mid = uuid.uuid4()
    op = {
        "op_id": str(uuid.uuid4()),
        "entity": "farmer_meeting",
        "action": "create",
        "entity_id": str(mid),
        "base_version": 0,
        "payload": meet.body(),
        "client_ts": "2026-08-20T05:00:00+00:00",
    }
    resp = await client.post(
        "/v1/sync", json={"device_id": "d1", "cursor": None, "ops": [op]}, headers=meet.headers
    )
    assert resp.json()["results"][0]["status"] == "applied"
    feed = [c for c in resp.json()["changes"] if c["entity"] == "farmer_meeting"]
    assert [c["entity_id"] for c in feed] == [str(mid)]
