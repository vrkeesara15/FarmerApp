"""FA-014 .. FA-017, FA-028, VV-003 .. VV-005: the visit flow end to end through the REST
twins and ``POST /v1/sync``.

Check-in outside the geofence is rejected with the reason and distance, inside / at the
meeting point accepted, an override needs a note and the cluster head's approval (which
changes the score); gallery photos are refused, EXIF + server time stored, the perceptual
hash computed from the blob, mismatches flagged not rejected; each confirmation channel marks
the visit confirmed only on success (a wrong OTP does not); check-out computes the duration,
flags short visits without rejecting and scores the visit; late confirmations / photos /
override decisions rescore; farmers confirm only their own visits; sync ops are idempotent.
"""

from __future__ import annotations

import hashlib
import io
import logging
import uuid
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

import imagehash
import pytest
from fastapi import FastAPI
from httpx import AsyncClient, Response
from PIL import Image
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.deps import AuthServices
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.providers import FakeProvider
from farmerapp.auth.scheduler import InProcessScheduler
from farmerapp.db.geo import ACRE_M2, offset, point_wkt
from farmerapp.db.models.tenant import Tenant
from farmerapp.db.session import clear_tenant, tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.settings import get_settings
from farmerapp.tenants.models import Cluster, Village
from farmerapp.uploads.blobstore import LocalBlobStore, blob_key
from farmerapp.visits import events
from farmerapp.visits.models import OverrideRequest, Visit
from farmerapp.visits.scoring import status_for
from tests.auth.conftest import last_code
from tests.authz.conftest import World
from tests.farmers.write_fixtures import BASE_LAT, BASE_LON, WriteCtx
from tests.logcontract import assert_fields, capture, json_events, one_event
from tests.sync.conftest import op, sync

T0 = datetime(2026, 9, 18, 5, 0, tzinfo=UTC)  # 10:30 IST
FARMER_PHONE = "+919000199077"
SIDE_M = ACRE_M2**0.5  # the 1-acre square farm's side (~63.6 m)

INSIDE = offset(BASE_LON, BASE_LAT, 30, 30)  # centre of the farm
BUFFER = offset(BASE_LON, BASE_LAT, SIDE_M + 100, 30)  # 100 m past the boundary (< 150)
FAR = offset(BASE_LON, BASE_LAT, SIDE_M + 500, 30)  # ~500 m past the boundary
MEET = offset(BASE_LON, BASE_LAT, 0, 3000)  # village meeting point, 3 km north
AT_MEET = offset(MEET[0], MEET[1], 40, 0)


def _latlon(point: tuple[float, float]) -> dict[str, float]:
    return {"lon": point[0], "lat": point[1]}


def jpeg(seed: int = 1, *, exif: dict[str, Any] | None = None) -> bytes:
    """A small JPEG with a seed-dependent pattern (distinct perceptual hashes per seed)."""
    image = Image.new("RGB", (64, 48))
    image.putdata(
        [
            ((x * seed) % 256, (y * 3 + seed * 17) % 256, (x * y // (seed + 1)) % 256)
            for y in range(48)
            for x in range(64)
        ]
    )
    exif_bytes = b""
    if exif is not None:
        data = Image.Exif()
        ifd = data.get_ifd(0x8769)
        if "time" in exif:
            ifd[0x9003] = exif["time"]
        if "offset" in exif:
            ifd[0x9011] = exif["offset"]
        if "lat" in exif:
            gps = data.get_ifd(0x8825)
            gps[1], gps[2] = "N", exif["lat"]
            gps[3], gps[4] = "E", exif["lon"]
        exif_bytes = data.tobytes()
    buf = io.BytesIO()
    image.save(buf, "JPEG", exif=exif_bytes, quality=90)
    return buf.getvalue()


@dataclass
class Flow:
    world: World
    app: FastAPI
    services: AuthServices
    clock: FakeClock
    sms: FakeProvider
    blobs: LocalBlobStore
    officer: User
    headers: dict[str, str]
    other_officer: User
    other_headers: dict[str, str]
    head: User  # cluster head of the officer's cluster
    head_headers: dict[str, str]
    far_head: User  # cluster head of another cluster
    far_head_headers: dict[str, str]
    farmer_user: User
    farmer_headers: dict[str, str]
    farmer_id: uuid.UUID
    farm_id: uuid.UUID
    village_id: uuid.UUID
    ctx: WriteCtx

    @property
    def tenant_id(self) -> uuid.UUID:
        return self.world.a.tenant.id

    def mint(self, user: User) -> dict[str, str]:
        token = self.services.tokens.issue_access_token(user, self.clock.now())
        return {"Authorization": f"Bearer {token}"}

    def advance(self, delta: timedelta) -> None:
        """Move the auth clock and re-mint the 15-minute access tokens."""
        self.clock.advance(delta)
        self.headers = self.mint(self.officer)
        self.other_headers = self.mint(self.other_officer)
        self.head_headers = self.mint(self.head)
        self.far_head_headers = self.mint(self.far_head)
        self.farmer_headers = self.mint(self.farmer_user)

    def checkin_body(
        self,
        *,
        at: tuple[float, float] = INSIDE,
        farm: bool = True,
        purpose: str = "advisory",
        note: str | None = None,
        integrity: dict[str, Any] | None = None,
        checkin_at: datetime = T0,
        id: uuid.UUID | None = None,
        **extra: Any,
    ) -> dict[str, Any]:
        body: dict[str, Any] = {
            "farmer_id": str(self.farmer_id),
            "farm_id": str(self.farm_id) if farm else None,
            "purpose": purpose,
            "checkin_at": checkin_at.isoformat(),
            "checkin_point": {**_latlon(at), "accuracy_m": 8.0},
            "device_integrity": integrity
            or {"is_mock": False, "is_rooted": False, "clock_drift_s": 12},
        }
        if note is not None:
            body["override_note"] = note
        if id is not None:
            body["id"] = str(id)
        body.update(extra)
        return body

    async def put_blob(self, data: bytes, *, purpose: str = "visit_photo") -> str:
        sha = hashlib.sha256(data).hexdigest()
        return await self.blobs.put(
            blob_key(self.tenant_id, purpose, sha), data, content_type="image/jpeg"
        )


async def _check_in(client: AsyncClient, flow: Flow, **kwargs: Any) -> Response:
    headers = kwargs.pop("headers", flow.headers)
    return await client.post(
        "/v1/visits/check-in", json=flow.checkin_body(**kwargs), headers=headers
    )


async def _visit(client: AsyncClient, flow: Flow, **kwargs: Any) -> dict[str, Any]:
    resp = await _check_in(client, flow, **kwargs)
    assert resp.status_code == 201, resp.text
    body: dict[str, Any] = resp.json()
    return body


async def _photo(
    client: AsyncClient,
    flow: Flow,
    visit_id: str,
    data: bytes,
    *,
    minutes: float | None = 5,
    at: tuple[float, float] | None = INSIDE,
    headers: dict[str, str] | None = None,
    **extra: Any,
) -> Response:
    uri = await flow.put_blob(data)
    body: dict[str, Any] = {"blob_uri": uri, "taken_in_app": True, "device_time": T0.isoformat()}
    if minutes is not None:
        body["exif_time"] = (T0 + timedelta(minutes=minutes)).isoformat()
    if at is not None:
        body["exif_point"] = _latlon(at)
    body.update(extra)
    return await client.post(
        f"/v1/visits/{visit_id}/photos", json=body, headers=headers or flow.headers
    )


async def _check_out(
    client: AsyncClient, flow: Flow, visit_id: str, *, minutes: float = 20, **extra: Any
) -> Response:
    body = {
        "checkout_at": (T0 + timedelta(minutes=minutes)).isoformat(),
        "checkout_point": _latlon(INSIDE),
        **extra,
    }
    return await client.post(f"/v1/visits/{visit_id}/check-out", json=body, headers=flow.headers)


async def _confirm_by_sms(client: AsyncClient, flow: Flow, visit_id: str) -> dict[str, Any]:
    resp = await client.post(
        f"/v1/visits/{visit_id}/confirm/request", json={"channel": "sms_otp"}, headers=flow.headers
    )
    assert resp.status_code == 202, resp.text
    code = last_code(flow.sms, FARMER_PHONE)
    resp = await client.post(
        f"/v1/visits/{visit_id}/confirm",
        json={"channel": "sms_otp", "code": code},
        headers=flow.headers,
    )
    assert resp.status_code == 200, resp.text
    body: dict[str, Any] = resp.json()
    return body


async def _detail(
    client: AsyncClient, flow: Flow, visit_id: str, headers: dict[str, str] | None = None
) -> dict[str, Any]:
    resp = await client.get(f"/v1/visits/{visit_id}", headers=headers or flow.headers)
    assert resp.status_code == 200, resp.text
    body: dict[str, Any] = resp.json()
    return body


# ------------------------------------------------------------------ fixtures
@pytest.fixture
async def flow(
    app: FastAPI,
    client: AsyncClient,
    world: World,
    ctx: WriteCtx,
    db_session: AsyncSession,
    tmp_path: Any,
) -> Flow:
    clock = FakeClock(T0)
    sms = FakeProvider()
    services = AuthServices(
        settings=get_settings(),
        clock=clock,
        sms=sms,
        whatsapp=sms,
        scheduler=InProcessScheduler(clock),
    )
    app.state.auth = services
    blobs = LocalBlobStore(tmp_path / "blobs")
    app.state.blobs = blobs

    def mint(user: User) -> dict[str, str]:
        return {"Authorization": f"Bearer {services.tokens.issue_access_token(user, clock.now())}"}

    officer = ctx.officer
    tid = world.a.tenant.id
    resp = await client.post(
        "/v1/farmers",
        json=ctx.farmer(phone=FARMER_PHONE, farms=[ctx.farm(acres=1.0, name="Flow farm")]),
        headers=mint(officer),
    )
    assert resp.status_code == 201, resp.text
    farmer = resp.json()
    farmer_id = uuid.UUID(farmer["id"])
    farm_id = uuid.UUID(farmer["farms"][0]["id"])
    async with tenant_scope(db_session, tid):
        village = await db_session.get_one(Village, ctx.village_id)
        village.meeting_point = point_wkt(*MEET)
        village.meeting_point_radius_m = None
        farmer_user = User(
            tenant_id=tid,
            phone=FARMER_PHONE,
            name="Flow Farmer",
            role=UserRole.FARMER,
            language="te",
        )
        db_session.add(farmer_user)
        await db_session.flush()
        row = await db_session.get_one(Farmer, farmer_id)
        row.user_id = farmer_user.id
        other_cluster = Cluster(tenant_id=tid, name=f"Far cluster {uuid.uuid4().hex[:6]}")
        db_session.add(other_cluster)
        await db_session.flush()
        head = User(
            tenant_id=tid,
            phone="+919000199088",
            name="Head",
            role=UserRole.CLUSTER_HEAD,
            cluster_id=officer.cluster_id,
        )
        far_head = User(
            tenant_id=tid,
            phone="+919000199089",
            name="Far head",
            role=UserRole.CLUSTER_HEAD,
            cluster_id=other_cluster.id,
        )
        db_session.add_all([head, far_head])
        await db_session.flush()
    return Flow(
        world=world,
        app=app,
        services=services,
        clock=clock,
        sms=sms,
        blobs=blobs,
        officer=officer,
        headers=mint(officer),
        other_officer=ctx.other_officer,
        other_headers=mint(ctx.other_officer),
        head=head,
        head_headers=mint(head),
        far_head=far_head,
        far_head_headers=mint(far_head),
        farmer_user=farmer_user,
        farmer_headers=mint(farmer_user),
        farmer_id=farmer_id,
        farm_id=farm_id,
        village_id=ctx.village_id,
        ctx=ctx,
    )


@pytest.fixture
def captured() -> Iterator[list[Any]]:
    """Every visit event published during the test."""
    seen: list[Any] = []
    handlers = [
        events.bus.subscribe(kind, seen.append)
        for kind in (events.IntegrityEvent, events.OverrideRequested, events.ConfirmationRequested)
    ]
    yield seen
    for kind, handler in zip(
        (events.IntegrityEvent, events.OverrideRequested, events.ConfirmationRequested),
        handlers,
        strict=True,
    ):
        events.bus.unsubscribe(kind, handler)


# ------------------------------------------------------------------ FA-014 / VV-003 check-in
async def test_check_in_inside_the_farm_polygon(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    assert body["geofence_result"] == "inside"
    assert body["status"] == "open" and body["score"] is None
    assert body["score_components"] == {
        "geofence": 30,
        "confirmation": 0,
        "photo": 0,
        "duration": 0,
        "integrity": 10,
    }
    assert body["officer_id"] == str(flow.officer.id) and body["farmer_id"] == str(flow.farmer_id)
    assert body["farm_id"] == str(flow.farm_id) and body["village_id"] == str(flow.village_id)
    assert body["checkin_point"] == {
        "lat": pytest.approx(INSIDE[1]),
        "lon": pytest.approx(INSIDE[0]),
    }
    assert body["checkin_accuracy_m"] == 8.0
    assert body["integrity_issues"] == [] and body["flags"] == []
    assert body["override_request"] is None and body["photos"] == [] and body["confirmations"] == []
    assert body["client_visit_id"] == body["id"]  # defaults to the visit id


async def test_check_in_within_the_150m_buffer_is_inside(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow, at=BUFFER)
    assert body["geofence_result"] == "inside"


async def test_check_in_outside_is_rejected_with_reason_and_distance(
    client: AsyncClient, flow: Flow
) -> None:
    resp = await _check_in(client, flow, at=FAR)
    assert resp.status_code == 422, resp.text
    body = resp.json()
    assert body["code"] == "outside_geofence"
    assert body["target"] == "farm" and body["radius_m"] == 150
    assert 480 <= body["distance_m"] <= 520  # ~500 m past the boundary
    assert "m from the farm boundary" in body["detail"] and "150 m" in body["detail"]
    assert "override note" in body["detail"]
    listed = await client.get("/v1/visits", headers=flow.headers)
    assert all(
        v["farmer_id"] != str(flow.farmer_id) for v in listed.json()["items"]
    )  # nothing stored


async def test_tenant_geofence_radius_is_honoured(
    client: AsyncClient, flow: Flow, db_session: AsyncSession
) -> None:
    async with tenant_scope(db_session, flow.tenant_id):
        tenant = await db_session.get_one(Tenant, flow.tenant_id)
        tenant.settings = {**(tenant.settings or {}), "geofence_radius_m": 600}
        await db_session.flush()
    body = await _visit(client, flow, at=FAR)
    assert body["geofence_result"] == "inside"


async def test_check_in_at_the_village_meeting_point(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow, at=AT_MEET, farm=False, purpose="meeting")
    assert body["geofence_result"] == "meeting_point" and body["farm_id"] is None
    # A farm visit checked in at the meeting point is still a meeting-point check-in.
    body = await _visit(client, flow, at=AT_MEET)
    assert body["geofence_result"] == "meeting_point"
    resp = await _check_in(client, flow, at=offset(MEET[0], MEET[1], 400, 0), farm=False)
    assert resp.status_code == 422 and resp.json()["target"] == "meeting_point"
    assert 390 <= resp.json()["distance_m"] <= 410  # distance to the nearest target


async def test_village_meeting_point_radius_overrides_the_tenant_default(
    client: AsyncClient, flow: Flow, db_session: AsyncSession
) -> None:
    async with tenant_scope(db_session, flow.tenant_id):
        village = await db_session.get_one(Village, flow.village_id)
        village.meeting_point_radius_m = 500
    body = await _visit(
        client, flow, at=offset(MEET[0], MEET[1], 400, 0), farm=False, purpose="meeting"
    )
    assert body["geofence_result"] == "meeting_point"


async def test_no_geofence_target_needs_an_override(
    client: AsyncClient, flow: Flow, db_session: AsyncSession
) -> None:
    async with tenant_scope(db_session, flow.tenant_id):
        village = await db_session.get_one(Village, flow.village_id)
        village.meeting_point = None
    resp = await _check_in(client, flow, farm=False)
    assert resp.status_code == 422 and resp.json()["code"] == "outside_geofence"
    assert resp.json()["target"] is None and resp.json()["distance_m"] is None


async def test_check_in_scope_and_validation(client: AsyncClient, flow: Flow) -> None:
    assert (await _check_in(client, flow, farmer_id=str(uuid.uuid4()))).status_code == 404
    assert (await _check_in(client, flow, farm_id=str(uuid.uuid4()))).status_code == 404
    other_farm = flow.world.a.farm_id  # a farm of another farmer
    assert (await _check_in(client, flow, farm_id=str(other_farm))).status_code == 404
    foreign = flow.world.b.farmer.id
    assert (await _check_in(client, flow, farmer_id=str(foreign))).status_code == 404
    naive = flow.checkin_body()
    naive["checkin_at"] = "2026-09-18T10:30:00"
    resp = await client.post("/v1/visits/check-in", json=naive, headers=flow.headers)
    assert resp.status_code == 422 and resp.json()["code"] == "validation_error"
    resp = await client.post(
        "/v1/visits/check-in", json=flow.checkin_body(), headers=flow.farmer_headers
    )
    assert resp.status_code == 403


async def test_check_in_replay_returns_the_same_visit(client: AsyncClient, flow: Flow) -> None:
    visit_id = uuid.uuid4()
    first = await _visit(client, flow, id=visit_id)
    again = await _visit(client, flow, id=visit_id, at=FAR)  # replay ignores the new point
    assert first["id"] == again["id"] == str(visit_id) and again["geofence_result"] == "inside"
    resp = await _check_in(client, flow, id=visit_id, headers=flow.other_headers)
    assert resp.status_code == 409 and resp.json()["code"] == "conflict"
    # Idempotency-Key replays the stored response.
    key = {"Idempotency-Key": f"k-{uuid.uuid4()}"}
    body = flow.checkin_body()
    one = await client.post("/v1/visits/check-in", json=body, headers={**flow.headers, **key})
    two = await client.post("/v1/visits/check-in", json=body, headers={**flow.headers, **key})
    assert one.status_code == two.status_code == 201 and one.json()["id"] == two.json()["id"]


# ------------------------------------------------------------------ FA-014 override
async def test_override_needs_a_note_and_cluster_head_approval(
    client: AsyncClient, flow: Flow, captured: list[Any], db_session: AsyncSession
) -> None:
    body = await _visit(client, flow, at=FAR, note="Farmer met at the canal; the field is flooded")
    assert body["geofence_result"] == "override"
    assert body["override_note"] == "Farmer met at the canal; the field is flooded"
    assert body["override_approved_by"] is None
    request = body["override_request"]
    assert request["decision"] is None and request["approver_role"] == "cluster_head"
    assert (
        request["requested_by"] == str(flow.officer.id) and request["note"] == body["override_note"]
    )
    [event] = [e for e in captured if isinstance(e, events.OverrideRequested)]
    assert event.visit_id == uuid.UUID(body["id"]) and event.cluster_id == flow.officer.cluster_id
    assert (
        event.override_request_id == uuid.UUID(request["id"])
        and 480 <= (event.distance_m or 0) <= 520
    )

    # Pending: the geofence component scores 0.
    out = await _check_out(client, flow, body["id"])
    assert out.status_code == 200 and out.json()["score_components"]["geofence"] == 0
    assert (
        out.json()["score"] == 20 and out.json()["status"] == "unverified"
    )  # duration + integrity

    # A cluster head of another cluster cannot see it; the officer cannot decide it.
    resp = await client.post(
        f"/v1/visits/{body['id']}/override/approve", json={}, headers=flow.far_head_headers
    )
    assert resp.status_code == 404
    resp = await client.post(
        f"/v1/visits/{body['id']}/override/approve", json={}, headers=flow.headers
    )
    assert resp.status_code == 403

    resp = await client.post(
        f"/v1/visits/{body['id']}/override/approve",
        json={"note": "Known flooding"},
        headers=flow.head_headers,
    )
    assert resp.status_code == 200, resp.text
    decided = resp.json()
    assert decided["decision"] == "approved" and decided["decided_by"] == str(flow.head.id)
    assert decided["decision_note"] == "Known flooding" and decided[
        "decided_at"
    ] == T0.isoformat().replace("+00:00", "Z")
    detail = await _detail(client, flow, body["id"])
    assert detail["override_approved_by"] == str(flow.head.id)
    assert detail["score_components"]["geofence"] == 15 and detail["score"] == 35  # rescored
    assert detail["override_request"]["decision"] == "approved"
    resp = await client.post(
        f"/v1/visits/{body['id']}/override/approve", json={}, headers=flow.head_headers
    )
    assert resp.status_code == 409 and resp.json()["code"] == "override_not_pending"
    async with tenant_scope(db_session, flow.tenant_id):
        rows = (
            (
                await db_session.execute(
                    select(OverrideRequest).where(OverrideRequest.visit_id == uuid.UUID(body["id"]))
                )
            )
            .scalars()
            .all()
        )
    assert len(rows) == 1


async def test_override_rejected_keeps_no_geofence_credit(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow, at=FAR, note="Wrong pin on the map")
    await _check_out(client, flow, body["id"])
    resp = await client.post(
        f"/v1/visits/{body['id']}/override/reject", json={}, headers=flow.mint(flow.world.a.owner)
    )
    assert resp.status_code == 200 and resp.json()["decision"] == "rejected"
    detail = await _detail(client, flow, body["id"])
    assert detail["geofence_result"] == "override" and detail["override_approved_by"] is None
    assert detail["score_components"]["geofence"] == 0
    resp = await client.post(
        f"/v1/visits/{body['id']}/override/reject", json={}, headers=flow.head_headers
    )
    assert resp.status_code == 409
    inside = await _visit(client, flow)
    resp = await client.post(
        f"/v1/visits/{inside['id']}/override/approve", json={}, headers=flow.head_headers
    )
    assert resp.status_code == 409 and resp.json()["code"] == "override_not_pending"


async def test_override_note_is_ignored_when_inside(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow, note="just in case")
    assert (
        body["geofence_result"] == "inside"
        and body["override_note"] is None
        and body["override_request"] is None
    )


# ------------------------------------------------------------------ FA-028 integrity
async def test_integrity_is_recorded_never_blocking(
    client: AsyncClient, flow: Flow, captured: list[Any], caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.WARNING, logger="farmerapp.visits")
    body = await _visit(
        client, flow, integrity={"is_mock": True, "is_rooted": False, "clock_drift_s": 400}
    )
    assert body["device_integrity"] == {"is_mock": True, "is_rooted": False, "clock_drift_s": 400}
    assert body["integrity_issues"] == ["mock_location", "clock_drift"]
    assert body["score_components"]["integrity"] == 0
    [event] = [e for e in captured if isinstance(e, events.IntegrityEvent)]
    assert event.issues == ("mock_location", "clock_drift") and event.visit_id == uuid.UUID(
        body["id"]
    )
    assert event.is_mock and not event.is_rooted and event.clock_drift_s == 400
    records = [r for r in caplog.records if r.name == "farmerapp.visits"]
    signals = [
        r.msg
        for r in records
        if isinstance(r.msg, dict) and r.msg.get("event") == "integrity_signal"
    ]
    assert len(signals) == 1 and records[0].levelno == logging.WARNING
    assert (
        signals[0]["issues"] == ["mock_location", "clock_drift"]
        and signals[0]["visit_id"] == body["id"]
    )
    assert FARMER_PHONE not in str(signals[0])
    rooted = await _visit(client, flow, integrity={"is_rooted": True})
    assert rooted["integrity_issues"] == ["rooted_device"]
    drift_ok = await _visit(client, flow, integrity={"clock_drift_s": -300})
    assert drift_ok["integrity_issues"] == [] and drift_ok["score_components"]["integrity"] == 10
    assert len([e for e in captured if isinstance(e, events.IntegrityEvent)]) == 2


def test_event_bus_isolates_handler_failures(caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.ERROR, logger="farmerapp.visits.events")
    bus = events.EventBus()
    seen: list[Any] = []

    def boom(_event: Any) -> None:
        raise RuntimeError("no")

    bus.subscribe(events.IntegrityEvent, boom)
    bus.subscribe(events.IntegrityEvent, seen.append)
    bus.subscribe(events.IntegrityEvent, seen.append)  # once
    event = events.IntegrityEvent(
        tenant_id=uuid.uuid4(),
        officer_id=uuid.uuid4(),
        visit_id=uuid.uuid4(),
        issues=("rooted_device",),
        is_mock=False,
        is_rooted=True,
        clock_drift_s=0,
        at=T0,
    )
    assert bus.publish(event) == 1 and seen == [event]
    assert any("visit_event_handler_failed" in str(r.msg) for r in caplog.records)
    bus.unsubscribe(events.IntegrityEvent, seen.append)
    bus.unsubscribe(events.IntegrityEvent, seen.append)
    assert bus.handlers(events.IntegrityEvent) == (boom,)
    assert bus.publish(event) == 0


# ------------------------------------------------------------------ FA-015 capture + photos
async def test_capture_notes_crop_stage_and_purpose(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    resp = await client.patch(
        f"/v1/visits/{body['id']}",
        json={"notes": "Aphids on lower leaves", "crop_stage": "vegetative"},
        headers=flow.headers,
    )
    assert resp.status_code == 200, resp.text
    assert (
        resp.json()["notes"] == "Aphids on lower leaves"
        and resp.json()["crop_stage"] == "vegetative"
    )
    resp = await client.patch(
        f"/v1/visits/{body['id']}",
        json={"purpose": "scouting", "notes": "Sprayed neem"},
        headers=flow.headers,
    )
    assert (
        resp.json()["purpose"] == "scouting" and resp.json()["notes"] == "Sprayed neem"
    )  # last writer wins
    resp = await client.patch(f"/v1/visits/{body['id']}", json={"score": 100}, headers=flow.headers)
    assert resp.status_code == 422  # server-owned fields are not accepted
    resp = await client.patch(
        f"/v1/visits/{body['id']}", json={"notes": "x"}, headers=flow.other_headers
    )
    assert resp.status_code == 404  # not their visit
    resp = await client.patch(
        f"/v1/visits/{body['id']}", json={"notes": "x"}, headers=flow.head_headers
    )
    assert resp.status_code == 404  # readable for the cluster head, writable only by the officer


async def test_gallery_photo_is_rejected(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    resp = await _photo(client, flow, body["id"], jpeg(1), taken_in_app=False)
    assert resp.status_code == 422 and resp.json()["code"] == "gallery_not_allowed"
    assert (await _detail(client, flow, body["id"]))["photos"] == []


async def test_photo_stores_exif_server_time_and_phash(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    data = jpeg(7)
    flow.advance(timedelta(minutes=6))
    resp = await _photo(
        client, flow, body["id"], data, minutes=5, at=offset(INSIDE[0], INSIDE[1], 10, 0)
    )
    assert resp.status_code == 201, resp.text
    photo = resp.json()
    assert photo["sha256"] == hashlib.sha256(data).hexdigest()
    assert photo["phash"] == str(imagehash.phash(Image.open(io.BytesIO(data))))
    assert photo["exif_time"] == (T0 + timedelta(minutes=5)).isoformat().replace("+00:00", "Z")
    assert photo["exif_point"]["lat"] == pytest.approx(INSIDE[1], abs=1e-6)
    assert photo["server_time"] == (T0 + timedelta(minutes=6)).isoformat().replace("+00:00", "Z")
    assert photo["device_time"] == T0.isoformat().replace("+00:00", "Z")
    assert photo["taken_in_app"] is True and photo["photo_flags"] == []
    assert photo["signed_url"].startswith("file://") and photo["signed_url_expires_at"]
    detail = await _detail(client, flow, body["id"])
    assert [p["id"] for p in detail["photos"]] == [photo["id"]]
    assert detail["photos"][0]["signed_url"].startswith("file://")
    assert detail["score_components"]["photo"] == 20  # rescored while open
    # Another photo with different content has a different hash; the same content is a duplicate
    # only across visits (see below).
    second = await _photo(client, flow, body["id"], jpeg(9))
    assert second.json()["phash"] != photo["phash"] and second.json()["photo_flags"] == []


async def test_photo_mismatches_are_flagged_not_rejected(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    late = await _photo(client, flow, body["id"], jpeg(2), minutes=-45)  # 45 min before check-in
    assert late.status_code == 201 and late.json()["photo_flags"] == ["exif_time_mismatch"]
    far = await _photo(client, flow, body["id"], jpeg(3), at=offset(INSIDE[0], INSIDE[1], 1000, 0))
    assert far.json()["photo_flags"] == ["exif_gps_mismatch"]
    missing = await _photo(client, flow, body["id"], jpeg(4), minutes=None, at=None)
    assert missing.json()["photo_flags"] == ["exif_time_missing", "exif_gps_missing"]
    assert missing.json()["exif_time"] is None and missing.json()["exif_point"] is None
    detail = await _detail(client, flow, body["id"])
    assert len(detail["photos"]) == 3 and detail["score_components"]["photo"] == 0  # none matches
    # The same bytes on another visit: duplicate.
    other = await _visit(client, flow)
    dup = await _photo(client, flow, other["id"], jpeg(2))
    assert dup.json()["photo_flags"] == ["duplicate_photo"]
    # After check-out the window closes: a photo dated after it is flagged too.
    await _check_out(client, flow, other["id"], minutes=20)
    after = await _photo(client, flow, other["id"], jpeg(5), minutes=60)
    assert after.json()["photo_flags"] == ["exif_time_mismatch"]


async def test_photo_exif_fallback_reads_the_jpeg(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    data = jpeg(
        11,
        exif={
            "time": "2026:09:18 10:35:00",
            "offset": "+05:30",
            "lat": (18.0, 7.0, 12.0),
            "lon": (79.0, 27.0, 36.0),
        },
    )
    resp = await _photo(client, flow, body["id"], data, minutes=None, at=None)
    assert resp.status_code == 201, resp.text
    photo = resp.json()
    assert photo["exif_time"] == "2026-09-18T05:05:00Z"  # 10:35 IST
    assert photo["exif_point"] == {"lat": pytest.approx(18.12), "lon": pytest.approx(79.46)}
    assert photo["photo_flags"] == []  # ~50 m from the check-in, 5 min in
    garbage = await _photo(client, flow, body["id"], b"not a jpeg at all")
    assert garbage.status_code == 201 and garbage.json()["phash"] is None


async def test_photo_blob_checks(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    data = jpeg(6)
    resp = await _photo(client, flow, body["id"], data, sha256="0" * 64)
    assert resp.status_code == 422 and resp.json()["code"] == "photo_sha_mismatch"
    resp = await client.post(
        f"/v1/visits/{body['id']}/photos",
        json={"blob_uri": f"gs://local/{flow.tenant_id}/visit_photo/{'a' * 64}"},
        headers=flow.headers,
    )
    assert resp.status_code == 404
    foreign = await flow.blobs.put(
        blob_key(flow.world.b.tenant.id, "visit_photo", "f" * 64), data, content_type="image/jpeg"
    )
    resp = await client.post(
        f"/v1/visits/{body['id']}/photos", json={"blob_uri": foreign}, headers=flow.headers
    )
    assert resp.status_code == 404
    resp = await client.post(
        f"/v1/visits/{body['id']}/photos", json={"blob_uri": "https://x/y"}, headers=flow.headers
    )
    assert resp.status_code == 422
    resp = await _photo(client, flow, body["id"], data, headers=flow.other_headers)
    assert resp.status_code == 404
    # Client photo ids replay.
    photo_id = str(uuid.uuid4())
    one = await _photo(client, flow, body["id"], data, id=photo_id)
    two = await _photo(client, flow, body["id"], data, id=photo_id)
    assert (
        one.status_code == two.status_code == 201
        and one.json()["id"] == two.json()["id"] == photo_id
    )
    assert len((await _detail(client, flow, body["id"]))["photos"]) == 1


# ------------------------------------------------------------------ FA-016 confirmation
async def test_sms_otp_confirms_only_with_the_right_code(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm",
        json={"channel": "sms_otp", "code": "123456"},
        headers=flow.headers,
    )
    assert resp.status_code == 404 and resp.json()["code"] == "confirmation_not_requested"
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm/request",
        json={"channel": "sms_otp"},
        headers=flow.headers,
    )
    assert resp.status_code == 202, resp.text
    started = resp.json()
    assert started["channel"] == "sms_otp" and started["phone_masked"] == "+91******9077"
    assert (
        started["expires_in"] == 300 and started["resends_left"] == 3 and started["token"] is None
    )
    assert (
        started["confirmation"]["status"] == "pending"
        and started["confirmation"]["farmer_phone_last4"] == "9077"
    )
    assert (
        started["confirmation"]["confirmed_at"] is None
        and started["confirmation"]["otp_challenge_id"]
    )
    assert flow.sms.sent[-1].to == FARMER_PHONE and "FarmerApp" in flow.sms.sent[-1].body
    code = last_code(flow.sms, FARMER_PHONE)
    wrong = "000000" if code != "000000" else "111111"
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm",
        json={"channel": "sms_otp", "code": wrong},
        headers=flow.headers,
    )
    assert resp.status_code == 401 and resp.json()["code"] == "otp_invalid"
    detail = await _detail(client, flow, body["id"])
    assert detail["confirmed_at"] is None and detail["confirmation_channel"] == "none"
    assert detail["confirmations"][0]["status"] == "pending"
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm", json={"channel": "sms_otp"}, headers=flow.headers
    )
    assert resp.status_code == 422 and resp.json()["code"] == "confirmation_channel_invalid"
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm",
        json={"channel": "sms_otp", "code": code},
        headers=flow.headers,
    )
    assert resp.status_code == 200, resp.text
    confirmed = resp.json()
    assert confirmed["confirmation_channel"] == "sms_otp" and confirmed[
        "confirmed_at"
    ] == T0.isoformat().replace("+00:00", "Z")
    assert confirmed["confirmations"][0]["status"] == "confirmed"
    assert confirmed["confirmations"][0]["confirmed_via_device_id"] == flow.officer.device_id
    assert confirmed["score_components"]["confirmation"] == 30
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm/request",
        json={"channel": "sms_otp"},
        headers=flow.headers,
    )
    assert resp.status_code == 409 and resp.json()["code"] == "visit_already_confirmed"
    assert code not in resp.text and code not in str(started)  # the code is never echoed
    for message in flow.sms.sent:
        assert message.to == FARMER_PHONE  # the officer's phone never receives the farmer's code


async def test_sms_otp_resend_supersedes_the_pending_request(
    client: AsyncClient, flow: Flow
) -> None:
    body = await _visit(client, flow)
    for _ in range(2):
        resp = await client.post(
            f"/v1/visits/{body['id']}/confirm/request",
            json={"channel": "sms_otp"},
            headers=flow.headers,
        )
        assert resp.status_code == 202, resp.text
        flow.advance(timedelta(seconds=31))
    detail = await _detail(client, flow, body["id"])
    assert [c["status"] for c in detail["confirmations"]] == ["expired", "pending"]
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm",
        json={"channel": "sms_otp", "code": last_code(flow.sms, FARMER_PHONE)},
        headers=flow.headers,
    )
    assert resp.status_code == 200 and resp.json()["confirmation_channel"] == "sms_otp"
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm/request",
        json={"channel": "qr"},
        headers=flow.other_headers,
    )
    assert resp.status_code == 404


async def test_app_push_confirms_from_the_farmer_app(
    client: AsyncClient, flow: Flow, captured: list[Any]
) -> None:
    body = await _visit(client, flow)
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm/request",
        json={"channel": "app_push"},
        headers=flow.headers,
    )
    assert resp.status_code == 202, resp.text
    assert (
        resp.json()["token"] is None and resp.json()["expires_in"] == 86400
    )  # the token goes to the farmer only
    [event] = [e for e in captured if isinstance(e, events.ConfirmationRequested)]
    assert event.farmer_user_id == flow.farmer_user.id and event.channel == "app_push"
    assert event.visit_id == uuid.UUID(body["id"]) and event.confirmation_id == uuid.UUID(
        resp.json()["confirmation"]["id"]
    )
    # The officer cannot complete a push confirmation, nor can another farmer.
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm",
        json={"channel": "app_push", "token": event.token},
        headers=flow.headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "confirmation_channel_invalid"
    other_farmer = flow.mint(flow.world.a.user(UserRole.FARMER))
    resp = await client.post(
        f"/v1/visits/{body['id']}/farmer-confirm", json={"token": event.token}, headers=other_farmer
    )
    assert resp.status_code == 404
    resp = await client.post(
        f"/v1/visits/{body['id']}/farmer-confirm", json={"token": event.token}, headers=flow.headers
    )
    assert resp.status_code == 403
    resp = await client.post(
        f"/v1/visits/{body['id']}/farmer-confirm",
        json={"token": event.token[:-2] + "xx"},
        headers=flow.farmer_headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "confirmation_token_invalid"
    assert (await _detail(client, flow, body["id"]))["confirmed_at"] is None
    resp = await client.post(
        f"/v1/visits/{body['id']}/farmer-confirm",
        json={"token": event.token, "rating": 5, "reason": "Very helpful"},
        headers=flow.farmer_headers,
    )
    assert resp.status_code == 200, resp.text
    row = resp.json()
    assert (
        row["status"] == "confirmed"
        and row["rating"] == 5
        and row["rating_reason"] == "Very helpful"
    )
    assert row["confirmed_via_device_id"] == flow.farmer_user.device_id
    detail = await _detail(client, flow, body["id"])
    assert (
        detail["confirmation_channel"] == "app_push"
        and detail["score_components"]["confirmation"] == 30
    )
    # Replay is idempotent; a rating can still be added.
    resp = await client.post(
        f"/v1/visits/{body['id']}/farmer-confirm",
        json={"token": event.token, "rating": 4},
        headers=flow.farmer_headers,
    )
    assert resp.status_code == 200 and resp.json()["rating"] == 4
    # The farmer sees the visit made to them, the officer's other visit is not theirs.
    resp = await client.get(f"/v1/visits/{body['id']}", headers=flow.farmer_headers)
    assert resp.status_code == 200 and resp.json()["confirmations"][0]["rating"] == 4


async def test_app_push_needs_a_linked_farmer_account(
    client: AsyncClient, flow: Flow, db_session: AsyncSession
) -> None:
    async with tenant_scope(db_session, flow.tenant_id):
        farmer = await db_session.get_one(Farmer, flow.farmer_id)
        farmer.user_id = None
    body = await _visit(client, flow)
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm/request",
        json={"channel": "app_push"},
        headers=flow.headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "confirmation_channel_invalid"


async def test_qr_token_is_validated_later_by_the_server(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm/request", json={"channel": "qr"}, headers=flow.headers
    )
    assert resp.status_code == 202, resp.text
    token = resp.json()["token"]
    assert token and resp.json()["confirmation"]["status"] == "pending"
    # A token of another visit is refused; the right one confirms, even hours later.
    other = await _visit(client, flow)
    resp = await client.post(
        f"/v1/visits/{other['id']}/farmer-confirm",
        json={"token": token},
        headers=flow.farmer_headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "confirmation_token_invalid"
    flow.advance(timedelta(hours=6))
    resp = await client.post(
        f"/v1/visits/{body['id']}/farmer-confirm",
        json={"token": token},
        headers=flow.farmer_headers,
    )
    assert resp.status_code == 200 and resp.json()["channel"] == "qr"
    detail = await _detail(client, flow, body["id"])
    assert detail["confirmation_channel"] == "qr"
    assert detail["confirmed_at"] == (T0 + timedelta(hours=6)).isoformat().replace("+00:00", "Z")
    # A second channel after success is refused; an expired QR too.
    resp = await client.post(
        f"/v1/visits/{other['id']}/confirm/request", json={"channel": "qr"}, headers=flow.headers
    )
    expired = resp.json()["token"]
    flow.advance(timedelta(hours=25))
    resp = await client.post(
        f"/v1/visits/{other['id']}/farmer-confirm",
        json={"token": expired},
        headers=flow.farmer_headers,
    )
    assert resp.status_code == 422 and "expired" in resp.json()["detail"]


async def test_second_channel_after_success_is_rejected(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm/request", json={"channel": "qr"}, headers=flow.headers
    )
    token = resp.json()["token"]
    flow.advance(timedelta(seconds=5))
    await _confirm_by_sms(client, flow, body["id"])
    resp = await client.post(
        f"/v1/visits/{body['id']}/farmer-confirm",
        json={"token": token},
        headers=flow.farmer_headers,
    )
    assert resp.status_code == 409 and resp.json()["code"] == "visit_already_confirmed"
    detail = await _detail(client, flow, body["id"])
    assert [c["status"] for c in detail["confirmations"]] == ["expired", "confirmed"]


# ------------------------------------------------------------------ FA-017 check-out, VV-004/005
async def test_check_out_computes_duration_and_scores(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    resp = await _check_out(client, flow, body["id"], minutes=20)
    assert resp.status_code == 200, resp.text
    out = resp.json()
    assert out["duration_s"] == 1200 and out["checkout_point"]["lat"] == pytest.approx(INSIDE[1])
    assert out["score_components"] == {
        "geofence": 30,
        "confirmation": 0,
        "photo": 0,
        "duration": 10,
        "integrity": 10,
    }
    assert out["score"] == 50 and out["status"] == "partial" and out["flags"] == []
    # Replay with the same time is fine; a different time is a conflict.
    assert (await _check_out(client, flow, body["id"], minutes=20)).status_code == 200
    resp = await _check_out(client, flow, body["id"], minutes=25)
    assert resp.status_code == 409 and resp.json()["code"] == "visit_already_checked_out"
    listed = await client.get("/v1/visits", params={"status": "partial"}, headers=flow.headers)
    assert body["id"] in {v["id"] for v in listed.json()["items"]}


async def test_check_out_under_minimum_is_flagged_not_rejected(
    client: AsyncClient, flow: Flow
) -> None:
    body = await _visit(client, flow)
    resp = await _check_out(client, flow, body["id"], minutes=2)
    assert resp.status_code == 200, resp.text
    assert resp.json()["duration_s"] == 120 and resp.json()["flags"] == ["under_minimum"]
    assert resp.json()["score_components"]["duration"] == 0 and resp.json()["status"] == "partial"
    exact = await _visit(client, flow)
    resp = await _check_out(client, flow, exact["id"], minutes=5)  # exactly the minimum
    assert resp.json()["flags"] == [] and resp.json()["score_components"]["duration"] == 10


async def test_check_out_validation_and_scope(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    resp = await _check_out(client, flow, body["id"], minutes=-1)
    assert resp.status_code == 422 and resp.json()["code"] == "checkout_before_checkin"
    resp = await client.post(
        f"/v1/visits/{body['id']}/check-out",
        json={"checkout_at": (T0 + timedelta(minutes=5)).isoformat()},
        headers=flow.other_headers,
    )
    assert resp.status_code == 404
    resp = await client.post(
        f"/v1/visits/{body['id']}/check-out",
        json={"checkout_at": "2026-09-18T11:00:00"},
        headers=flow.headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "validation_error"
    resp = await client.post(
        f"/v1/visits/{body['id']}/check-out",
        json={"checkout_at": (T0 + timedelta(minutes=5)).isoformat()},
        headers=flow.headers,
    )
    assert resp.status_code == 200 and resp.json()["checkout_point"] is None


async def test_score_100_verified(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    assert (await _photo(client, flow, body["id"], jpeg(21))).status_code == 201
    await _confirm_by_sms(client, flow, body["id"])
    out = (await _check_out(client, flow, body["id"], minutes=20)).json()
    assert out["score_components"] == {
        "geofence": 30,
        "confirmation": 30,
        "photo": 20,
        "duration": 10,
        "integrity": 10,
    }
    assert out["score"] == 100 and out["status"] == "verified"


async def test_score_70_is_verified_boundary(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow, integrity={"is_mock": True})  # integrity 0
    await _confirm_by_sms(client, flow, body["id"])
    out = (await _check_out(client, flow, body["id"], minutes=20)).json()  # no photo
    assert out["score_components"] == {
        "geofence": 30,
        "confirmation": 30,
        "photo": 0,
        "duration": 10,
        "integrity": 0,
    }
    assert out["score"] == 70 and out["status"] == "verified"
    assert status_for(69) == "partial"  # the next value down is partial (VV-005)


async def test_score_65_partial_with_approved_override(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(
        client, flow, at=FAR, note="Boundary drawn on the wrong plot", integrity={"is_rooted": True}
    )
    assert (await _photo(client, flow, body["id"], jpeg(22), at=FAR)).status_code == 201
    await _confirm_by_sms(client, flow, body["id"])
    out = (await _check_out(client, flow, body["id"], minutes=3)).json()
    assert out["score"] == 50 and out["status"] == "partial"  # 0 + 30 + 20 + 0 + 0
    resp = await client.post(
        f"/v1/visits/{body['id']}/override/approve", json={}, headers=flow.head_headers
    )
    assert resp.status_code == 200
    detail = await _detail(client, flow, body["id"])
    assert detail["score_components"] == {
        "geofence": 15,
        "confirmation": 30,
        "photo": 20,
        "duration": 0,
        "integrity": 0,
    }
    assert (
        detail["score"] == 65
        and detail["status"] == "partial"
        and detail["flags"] == ["under_minimum"]
    )


async def test_score_40_partial_boundary_and_39_unverified(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow, integrity={"is_rooted": True})
    out = (await _check_out(client, flow, body["id"], minutes=10)).json()
    assert out["score_components"] == {
        "geofence": 30,
        "confirmation": 0,
        "photo": 0,
        "duration": 10,
        "integrity": 0,
    }
    assert out["score"] == 40 and out["status"] == "partial"
    assert status_for(39) == "unverified"
    short = await _visit(client, flow, integrity={"clock_drift_s": 400})
    out = (await _check_out(client, flow, short["id"], minutes=1)).json()
    assert (
        out["score"] == 30 and out["status"] == "unverified" and out["flags"] == ["under_minimum"]
    )


async def test_late_confirmation_and_photo_rescore_the_visit(
    client: AsyncClient, flow: Flow
) -> None:
    body = await _visit(client, flow)
    out = (await _check_out(client, flow, body["id"], minutes=20)).json()
    assert out["score"] == 50 and out["status"] == "partial" and out["version"] >= 2
    confirmed = await _confirm_by_sms(client, flow, body["id"])
    assert confirmed["score"] == 80 and confirmed["status"] == "verified"
    resp = await _photo(client, flow, body["id"], jpeg(31), minutes=15)
    assert resp.status_code == 201
    detail = await _detail(client, flow, body["id"])
    assert detail["score"] == 100 and detail["status"] == "verified"
    # A photo that does not match changes nothing (idempotent rescore: no version bump).
    version = detail["version"]
    await _photo(client, flow, body["id"], jpeg(32), minutes=-120)
    assert (await _detail(client, flow, body["id"]))["version"] == version


# ------------------------------------------------------------------ reads / scope
async def test_store_manager_reads_visits_but_never_tracks(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    manager = flow.mint(flow.world.a.user(UserRole.STORE_MANAGER))
    assert flow.officer.store_id == flow.world.a.user(UserRole.STORE_MANAGER).store_id
    detail = await _detail(client, flow, body["id"], headers=manager)
    assert not {"points", "track", "location_points"} & set(detail)
    resp = await client.get(
        f"/v1/officers/{flow.officer.id}/track", params={"day": "2026-09-18"}, headers=manager
    )
    assert resp.status_code == 403 and resp.json()["code"] == "forbidden"
    resp = await client.post(f"/v1/visits/{body['id']}/override/approve", json={}, headers=manager)
    assert resp.status_code == 403


async def test_override_request_rows_are_tenant_isolated(
    client: AsyncClient, flow: Flow, db_session: AsyncSession
) -> None:
    body = await _visit(client, flow, at=FAR, note="Road blocked, met at the pump house")
    b = flow.world.b
    async with tenant_scope(db_session, b.tenant.id):
        visit_b = await db_session.scalar(
            select(Visit).where(Visit.farmer_id == b.farmer.id).limit(1)
        )
        assert visit_b is not None
        db_session.add(
            OverrideRequest(
                tenant_id=b.tenant.id,
                visit_id=visit_b.id,
                note="B",
                requested_at=T0,
                requested_by=visit_b.officer_id,
            )
        )
        await db_session.flush()
        tenants = (await db_session.execute(select(OverrideRequest.tenant_id))).scalars().all()
        assert tenants == [b.tenant.id]
    async with tenant_scope(db_session, flow.tenant_id):
        rows = (await db_session.execute(select(OverrideRequest))).scalars().all()
        assert [str(r.visit_id) for r in rows] == [body["id"]]
    await clear_tenant(db_session)
    assert await db_session.scalar(text("SELECT count(*) FROM override_request")) == 0


# ------------------------------------------------------------------ sync ops (FA-025)
async def test_sync_check_in_capture_photo_confirm_and_check_out(
    client: AsyncClient, flow: Flow
) -> None:
    visit_id = uuid.uuid4()
    checkin = op("visit", "create", flow.checkin_body(), entity_id=visit_id)
    body = await sync(client, flow.ctx, [checkin], headers=flow.headers)
    [result] = body["results"]
    assert result["status"] == "applied" and result["entity_id"] == str(visit_id), result
    assert result["server"]["geofence_result"] == "inside" and result["server"]["status"] == "open"
    assert result["version"] == 1
    # Replay of the op: duplicate with the same result; a new op for the same id: conflict.
    again = await sync(client, flow.ctx, [checkin], headers=flow.headers)
    assert again["results"][0]["status"] == "duplicate" and again["results"][0]["server"][
        "id"
    ] == str(visit_id)
    fresh = await sync(
        client,
        flow.ctx,
        [op("visit", "create", flow.checkin_body(at=FAR), entity_id=visit_id)],
        headers=flow.headers,
    )
    assert (
        fresh["results"][0]["status"] == "conflict"
        and fresh["results"][0]["server"]["geofence_result"] == "inside"
    )
    # Photo + capture + check-out in one batch; server-owned fields in the payload are dropped.
    uri = await flow.put_blob(jpeg(41))
    photo = op(
        "visit_photo",
        "create",
        {
            "visit_id": str(visit_id),
            "blob_uri": uri,
            "exif_time": (T0 + timedelta(minutes=4)).isoformat(),
            "exif_point": _latlon(INSIDE),
        },
    )
    update = op(
        "visit",
        "update",
        {
            "notes": "From the outbox",
            "crop_stage": "flowering",
            "score": 100,
            "status": "verified",
            "checkout_at": (T0 + timedelta(minutes=15)).isoformat(),
            "checkout_point": _latlon(INSIDE),
        },
        entity_id=visit_id,
        base_version=1,
    )
    body = await sync(client, flow.ctx, [photo, update], headers=flow.headers)
    photo_result, update_result = body["results"]
    assert photo_result["status"] == "applied" and photo_result["server"]["photo_flags"] == []
    assert update_result["status"] == "applied", update_result
    server = update_result["server"]
    assert server["notes"] == "From the outbox" and server["crop_stage"] == "flowering"
    assert server["duration_s"] == 900 and server["score"] == 70 and server["status"] == "verified"
    # OTP typed on the officer's phone, queued and applied when online.
    resp = await client.post(
        f"/v1/visits/{visit_id}/confirm/request", json={"channel": "sms_otp"}, headers=flow.headers
    )
    assert resp.status_code == 202
    code = last_code(flow.sms, FARMER_PHONE)
    wrong = "000000" if code != "000000" else "111111"
    bad = await sync(
        client,
        flow.ctx,
        [
            op(
                "visit_confirmation",
                "create",
                {"visit_id": str(visit_id), "channel": "sms_otp", "code": wrong},
            )
        ],
        headers=flow.headers,
    )
    assert (
        bad["results"][0]["status"] == "rejected"
        and bad["results"][0]["error"]["code"] == "otp_invalid"
    )
    good = await sync(
        client,
        flow.ctx,
        [
            op(
                "visit_confirmation",
                "create",
                {"visit_id": str(visit_id), "channel": "sms_otp", "code": code},
            )
        ],
        headers=flow.headers,
    )
    assert (
        good["results"][0]["status"] == "applied"
        and good["results"][0]["server"]["status"] == "confirmed"
    )
    detail = await _detail(client, flow, str(visit_id))
    assert detail["score"] == 100 and detail["status"] == "verified"
    # The change feed carries the visit, the photo and the confirmation.
    feed = await sync(client, flow.ctx, [], headers=flow.headers)
    entities = {(c["entity"], c["entity_id"]) for c in feed["changes"]}
    assert ("visit", str(visit_id)) in entities and ("visit_photo", photo["entity_id"]) in entities
    assert ("visit_confirmation", good["results"][0]["server"]["id"]) in entities  # the request row


async def test_sync_check_in_outside_is_rejected_unless_overridden(
    client: AsyncClient, flow: Flow
) -> None:
    rejected = await sync(
        client, flow.ctx, [op("visit", "create", flow.checkin_body(at=FAR))], headers=flow.headers
    )
    [result] = rejected["results"]
    assert result["status"] == "rejected" and result["error"]["code"] == "outside_geofence"
    assert (
        result["error"]["status"] == 422 and "m from the farm boundary" in result["error"]["detail"]
    )
    applied = await sync(
        client,
        flow.ctx,
        [op("visit", "create", flow.checkin_body(at=FAR, note="Met at the canal"))],
        headers=flow.headers,
    )
    assert applied["results"][0]["status"] == "applied"
    assert applied["results"][0]["server"]["geofence_result"] == "override"
    assert applied["results"][0]["server"]["override_request"]["decision"] is None
    gallery = await sync(
        client,
        flow.ctx,
        [
            op(
                "visit_photo",
                "create",
                {
                    "visit_id": applied["results"][0]["entity_id"],
                    "blob_uri": "gs://local/x/y",
                    "taken_in_app": False,
                },
            )
        ],
        headers=flow.headers,
    )
    assert gallery["results"][0]["error"]["code"] == "gallery_not_allowed"
    immutable = await sync(
        client,
        flow.ctx,
        [
            op("visit_photo", "update", {"exif_time": None}, base_version=1),
            op("visit", "delete", {}, base_version=1),
        ],
        headers=flow.headers,
    )
    assert {r["error"]["code"] for r in immutable["results"]} == {"unsupported_action"}


async def test_sync_farmer_posts_a_scanned_qr_token(client: AsyncClient, flow: Flow) -> None:
    body = await _visit(client, flow)
    resp = await client.post(
        f"/v1/visits/{body['id']}/confirm/request", json={"channel": "qr"}, headers=flow.headers
    )
    token = resp.json()["token"]
    confirmation_id = resp.json()["confirmation"]["id"]
    confirm = op(
        "visit_confirmation",
        "create",
        {"visit_id": body["id"], "channel": "qr", "token": token, "rating": 3},
        entity_id=uuid.uuid4(),
    )
    result = await sync(
        client, flow.ctx, [confirm], headers=flow.farmer_headers, device_id="farmer-phone"
    )
    [applied] = result["results"]
    assert (
        applied["status"] == "applied"
        and applied["server"]["rating"] == 3
        and applied["server"]["status"] == "confirmed"
    )
    assert applied["server"]["id"] == confirmation_id  # the request row, not the client's id
    wrong_channel = await sync(
        client,
        flow.ctx,
        [
            op(
                "visit_confirmation",
                "create",
                {"visit_id": body["id"], "channel": "sms_otp", "code": "123456"},
            )
        ],
        headers=flow.farmer_headers,
    )
    assert wrong_channel["results"][0]["error"]["code"] == "confirmation_channel_invalid"
    # An officer replaying an existing confirmation id gets the server state.
    replay = await sync(
        client,
        flow.ctx,
        [
            op(
                "visit_confirmation",
                "create",
                {"visit_id": body["id"], "channel": "qr", "token": token},
                entity_id=confirmation_id,
            )
        ],
        headers=flow.headers,
    )
    assert (
        replay["results"][0]["status"] == "conflict"
        and replay["results"][0]["server"]["status"] == "confirmed"
    )


# ------------------------------------------------------------------ NF-014 log contract
async def test_visit_created_log_contract(
    client: AsyncClient, flow: Flow, caplog: pytest.LogCaptureFixture
) -> None:
    """``farmerapp_visits_created`` (business-ops dashboard) counts ``visit_created``."""
    capture(caplog)
    body = await _visit(client, flow)
    line = one_event(caplog, "visit_created")
    assert_fields(line, tenant_id=str, visit_id=str, officer_id=str, geofence_result=str)
    assert line["visit_id"] == body["id"] and line["officer_id"] == str(flow.officer.id)
    # A replay (same id) returns the existing visit and logs nothing new.
    before = len(json_events(caplog, "visit_created"))
    await _check_in(client, flow, id=body["id"])
    assert len(json_events(caplog, "visit_created")) == before
