"""``GET /v1/visits[/{id}]``, ``GET /v1/duty-sessions`` and ``GET /v1/officers/{id}/track``:
SPEC 2.6 scope per role (store managers never see tracks or duty sessions, an officer only
their own), filters, cursor pagination and the nested photos / confirmation / score
components on the detail."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.jobs.seed import SEED_TODAY
from farmerapp.location.models import LocationPoint
from farmerapp.visits.models import VisitStatus
from tests.authz.conftest import Bearer
from tests.visits.conftest import M2World

DAY = SEED_TODAY.isoformat()


async def _pages(
    client: AsyncClient, path: str, headers: dict[str, str], limit: int = 50, **params: str
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    cursor: str | None = None
    for _ in range(100):
        # ``from_`` -> ``from`` (reserved word as a query parameter name).
        query = {"limit": str(limit), **{k.rstrip("_"): v for k, v in params.items()}}
        if cursor:
            query["cursor"] = cursor
        resp = await client.get(path, params=query, headers=headers)
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert len(body["items"]) <= limit
        items.extend(body["items"])
        cursor = body["next_cursor"]
        if cursor is None:
            return items
    raise AssertionError("pagination did not terminate")


# ------------------------------------------------------------------ visits
async def test_owner_lists_every_visit_with_pagination(
    client: AsyncClient, m2: M2World, bearer: Bearer
) -> None:
    items = await _pages(client, "/v1/visits", bearer(m2.world.a.owner), limit=3)
    expected = m2.all_visits()
    assert len(items) == len(expected) > 0
    assert {i["id"] for i in items} == {str(v.id) for v in expected}
    assert [(i["created_at"], i["id"]) for i in items] == sorted(
        (i["created_at"], i["id"]) for i in items
    )
    first = items[0]
    assert set(first) >= {
        "id", "tenant_id", "officer_id", "farmer_id", "farm_id", "village_id", "purpose",
        "checkin_at", "checkout_at", "checkin_point", "checkin_accuracy_m", "checkout_point",
        "geofence_result", "override_note", "override_approved_by", "notes", "crop_stage",
        "duration_s", "score", "status", "confirmation_channel", "confirmed_at",
        "device_integrity", "created_at", "updated_at", "version",
    }  # fmt: skip
    assert set(first["checkin_point"]) == {"lat", "lon"}
    assert set(first["device_integrity"]) == {"is_mock", "is_rooted", "clock_drift_s"}
    assert all(i["tenant_id"] == str(m2.world.a.tenant.id) for i in items)
    assert {i["status"] for i in items} <= {s.value for s in VisitStatus}
    assert "score_components" not in first  # detail only


async def test_visit_filters(client: AsyncClient, m2: M2World, bearer: Bearer) -> None:
    headers = bearer(m2.world.a.owner)
    officer = m2.officer
    by_officer = await _pages(client, "/v1/visits", headers, officer_id=str(officer.id))
    assert by_officer and all(i["officer_id"] == str(officer.id) for i in by_officer)
    assert len(by_officer) == len(m2.visits[officer.id])
    farmer_id = m2.visits[officer.id][0].farmer_id
    by_farmer = await _pages(client, "/v1/visits", headers, farmer_id=str(farmer_id))
    assert by_farmer and all(i["farmer_id"] == str(farmer_id) for i in by_farmer)
    verified = await _pages(client, "/v1/visits", headers, status="verified")
    assert all(i["status"] == "verified" for i in verified)
    assert len(verified) == sum(v.status == "verified" for v in m2.all_visits())
    start = datetime(SEED_TODAY.year, SEED_TODAY.month, SEED_TODAY.day, tzinfo=UTC)
    today = await _pages(
        client, "/v1/visits", headers, from_=start.isoformat(), to=f"{DAY}T23:59:59Z"
    )
    assert today and all(
        i["checkin_at"] >= start.isoformat().replace("+00:00", "Z")[:10] for i in today
    )
    assert len(today) == sum(v.checkin_at >= start for v in m2.all_visits())
    resp = await client.get("/v1/visits", params={"status": "great"}, headers=headers)
    assert resp.status_code == 422


async def test_field_officer_sees_own_visits_only(
    client: AsyncClient, m2: M2World, bearer: Bearer
) -> None:
    officer = m2.officer
    items = await _pages(client, "/v1/visits", bearer(officer))
    assert items and {i["officer_id"] for i in items} == {str(officer.id)}
    assert len(items) == len(m2.visits[officer.id])
    other = next(o for o in m2.officers if o.id != officer.id)
    foreign = m2.visits[other.id][0]
    resp = await client.get(f"/v1/visits/{foreign.id}", headers=bearer(officer))
    assert resp.status_code == 404 and resp.json()["code"] == "not_found"
    resp = await client.get(f"/v1/visits/{m2.visits[officer.id][0].id}", headers=bearer(officer))
    assert resp.status_code == 200


async def test_cluster_head_sees_own_cluster(
    client: AsyncClient, m2: M2World, bearer: Bearer
) -> None:
    head = m2.world.a.user(UserRole.CLUSTER_HEAD)
    items = await _pages(client, "/v1/visits", bearer(head))
    inside = {str(o.id) for o in m2.officers if o.cluster_id == head.cluster_id}
    outside = {str(o.id) for o in m2.officers if o.cluster_id != head.cluster_id}
    assert inside and outside
    seen = {i["officer_id"] for i in items}
    assert seen == inside and not seen & outside
    other = m2.officer_in_cluster(head.cluster_id, same=False)
    resp = await client.get(f"/v1/visits/{m2.visits[other.id][0].id}", headers=bearer(head))
    assert resp.status_code == 404


async def test_store_manager_sees_own_store_officers(
    client: AsyncClient, m2: M2World, bearer: Bearer
) -> None:
    manager = m2.world.a.user(UserRole.STORE_MANAGER)
    items = await _pages(client, "/v1/visits", bearer(manager))
    store_officers = {str(o.id) for o in m2.officers if o.store_id == manager.store_id}
    assert items and {i["officer_id"] for i in items} == store_officers
    assert len(store_officers) == 1


async def test_farmer_sees_visits_to_themselves(
    client: AsyncClient, m2: M2World, bearer: Bearer, db_session: AsyncSession
) -> None:
    farmer_user = m2.world.a.user(UserRole.FARMER)
    async with tenant_scope(db_session, m2.world.a.tenant.id):
        farmer_id = await db_session.scalar(
            select(Farmer.id).where(Farmer.user_id == farmer_user.id)
        )
    items = await _pages(client, "/v1/visits", bearer(farmer_user))
    assert items and {i["farmer_id"] for i in items} == {str(farmer_id)}
    other = next(v for v in m2.all_visits() if v.farmer_id != farmer_id)
    resp = await client.get(f"/v1/visits/{other.id}", headers=bearer(farmer_user))
    assert resp.status_code == 404


async def test_visit_detail_has_photos_confirmation_and_score_components(
    client: AsyncClient, m2: M2World, bearer: Bearer
) -> None:
    headers = bearer(m2.world.a.owner)
    confirmed = next(v for v in m2.all_visits() if v.confirmed_at is not None)
    resp = await client.get(f"/v1/visits/{confirmed.id}", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["id"] == str(confirmed.id)
    assert body["photos"] and set(body["photos"][0]) >= {
        "id", "blob_uri", "sha256", "phash", "exif_time", "exif_point", "taken_in_app",
        "device_time", "server_time",
    }  # fmt: skip
    assert body["confirmations"] and body["confirmations"][0]["channel"] in (
        "sms_otp",
        "app_push",
        "qr",
    )
    assert body["confirmation_channel"] == body["confirmations"][0]["channel"]
    assert set(body["score_components"]) == {
        "geofence",
        "confirmation",
        "photo",
        "duration",
        "integrity",
    }
    assert sum(body["score_components"].values()) == body["score"]
    assert body["score_components"]["confirmation"] == 30
    unconfirmed = next(v for v in m2.all_visits() if v.confirmed_at is None and v.score is not None)
    body = (await client.get(f"/v1/visits/{unconfirmed.id}", headers=headers)).json()
    assert body["confirmations"] == [] and body["score_components"]["confirmation"] == 0


async def test_unknown_or_other_tenant_visit_is_404(
    client: AsyncClient, m2: M2World, bearer: Bearer, db_session: AsyncSession
) -> None:
    headers = bearer(m2.world.a.owner)
    assert (await client.get(f"/v1/visits/{uuid.uuid4()}", headers=headers)).status_code == 404
    from farmerapp.visits.models import Visit

    async with tenant_scope(db_session, m2.world.b.tenant.id):
        foreign = await db_session.scalar(select(Visit.id).limit(1))
    assert foreign is not None
    resp = await client.get(f"/v1/visits/{foreign}", headers=headers)
    assert resp.status_code == 404 and resp.json()["code"] == "not_found"


# ------------------------------------------------------------------ duty sessions
async def test_duty_sessions_scope(client: AsyncClient, m2: M2World, bearer: Bearer) -> None:
    a = m2.world.a
    everything = await _pages(client, "/v1/duty-sessions", bearer(a.owner))
    assert len(everything) == sum(len(s) for s in m2.sessions.values()) > 0
    row = everything[0]
    assert set(row) >= {
        "id", "officer_id", "start_at", "end_at", "start_point", "end_point", "km", "stops",
        "end_reason", "policy_version", "device_id", "app_version", "duration_s",
    }  # fmt: skip
    for role in (UserRole.DIRECTOR, UserRole.AUDITOR, UserRole.TENANT_ADMIN):
        assert len(await _pages(client, "/v1/duty-sessions", bearer(a.user(role)))) == len(
            everything
        )
    officer = m2.officer
    own = await _pages(client, "/v1/duty-sessions", bearer(officer))
    assert own and {i["officer_id"] for i in own} == {str(officer.id)}
    head = a.user(UserRole.CLUSTER_HEAD)
    cluster = await _pages(client, "/v1/duty-sessions", bearer(head))
    assert {i["officer_id"] for i in cluster} == {
        str(o.id) for o in m2.officers if o.cluster_id == head.cluster_id
    }
    filtered = await _pages(
        client, "/v1/duty-sessions", bearer(a.owner), officer_id=str(officer.id)
    )
    assert len(filtered) == len(m2.sessions[officer.id])
    # Store managers never see duty sessions or tracks (SPEC 2.6).
    resp = await client.get("/v1/duty-sessions", headers=bearer(a.user(UserRole.STORE_MANAGER)))
    assert resp.status_code == 403 and resp.json()["code"] == "forbidden"
    resp = await client.get("/v1/duty-sessions", headers=bearer(a.user(UserRole.AGRONOMIST)))
    assert resp.status_code == 403


async def test_duty_session_time_filters(client: AsyncClient, m2: M2World, bearer: Bearer) -> None:
    headers = bearer(m2.world.a.owner)
    start = datetime(SEED_TODAY.year, SEED_TODAY.month, SEED_TODAY.day, tzinfo=UTC)
    today = await _pages(client, "/v1/duty-sessions", headers, from_=start.isoformat())
    assert today and len(today) == sum(
        1 for sessions in m2.sessions.values() for s in sessions if s.start_at >= start
    )
    before = await _pages(client, "/v1/duty-sessions", headers, to=start.isoformat())
    assert len(before) + len(today) == sum(len(s) for s in m2.sessions.values())


# ------------------------------------------------------------------ tracks
async def _points_on_day(session: AsyncSession, tenant_id: uuid.UUID, officer: User) -> int:
    from farmerapp.location.router import day_bounds

    lower, upper = day_bounds(SEED_TODAY)
    async with tenant_scope(session, tenant_id):
        return int(
            await session.scalar(
                select(func.count())
                .select_from(LocationPoint)
                .where(
                    LocationPoint.officer_id == officer.id,
                    LocationPoint.ts >= lower,
                    LocationPoint.ts < upper,
                )
            )
            or 0
        )


async def test_officer_reads_own_track_only(
    client: AsyncClient, m2: M2World, bearer: Bearer, db_session: AsyncSession
) -> None:
    officer = m2.officer
    resp = await client.get(
        f"/v1/officers/{officer.id}/track", params={"day": DAY}, headers=bearer(officer)
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["officer_id"] == str(officer.id) and body["day"] == DAY
    expected = await _points_on_day(db_session, m2.world.a.tenant.id, officer)
    assert body["count"] == len(body["points"]) == expected > 10
    point = body["points"][0]
    assert set(point) >= {
        "ts", "lat", "lon", "accuracy_m", "speed_mps", "bearing", "battery_pct", "is_mock",
        "is_rooted", "clock_drift_s", "provider", "duty_session_id",
    }  # fmt: skip
    assert [p["ts"] for p in body["points"]] == sorted(p["ts"] for p in body["points"])
    assert point["duty_session_id"] in {str(s.id) for s in m2.sessions[officer.id]}
    other = next(o for o in m2.officers if o.id != officer.id)
    resp = await client.get(
        f"/v1/officers/{other.id}/track", params={"day": DAY}, headers=bearer(officer)
    )
    assert resp.status_code == 404


async def test_store_manager_gets_403_on_tracks(
    client: AsyncClient, m2: M2World, bearer: Bearer
) -> None:
    manager = m2.world.a.user(UserRole.STORE_MANAGER)
    officer = m2.officer
    assert officer.store_id == manager.store_id  # even their own store's officer
    resp = await client.get(
        f"/v1/officers/{officer.id}/track", params={"day": DAY}, headers=bearer(manager)
    )
    assert resp.status_code == 403 and resp.json()["code"] == "forbidden"
    for role in (UserRole.AGRONOMIST, UserRole.ACCOUNTANT, UserRole.FARMER):
        resp = await client.get(
            f"/v1/officers/{officer.id}/track",
            params={"day": DAY},
            headers=bearer(m2.world.a.user(role)),
        )
        assert resp.status_code == 403, role


async def test_managers_read_tracks_within_their_scope(
    client: AsyncClient, m2: M2World, bearer: Bearer
) -> None:
    a = m2.world.a
    head = a.user(UserRole.CLUSTER_HEAD)
    inside = m2.officer_in_cluster(head.cluster_id, same=True)
    outside = m2.officer_in_cluster(head.cluster_id, same=False)
    ok = await client.get(
        f"/v1/officers/{inside.id}/track", params={"day": DAY}, headers=bearer(head)
    )
    assert ok.status_code == 200 and ok.json()["count"] > 0
    no = await client.get(
        f"/v1/officers/{outside.id}/track", params={"day": DAY}, headers=bearer(head)
    )
    assert no.status_code == 404
    for role in (UserRole.OWNER, UserRole.DIRECTOR, UserRole.AUDITOR, UserRole.TENANT_ADMIN):
        resp = await client.get(
            f"/v1/officers/{outside.id}/track", params={"day": DAY}, headers=bearer(a.user(role))
        )
        assert resp.status_code == 200 and resp.json()["count"] > 0, role
    # A day without duty is an empty track, not an error; the day is required.
    empty = await client.get(
        f"/v1/officers/{outside.id}/track", params={"day": "2020-01-01"}, headers=bearer(a.owner)
    )
    assert empty.status_code == 200 and empty.json() == {
        "officer_id": str(outside.id), "day": "2020-01-01", "count": 0, "points": []
    }  # fmt: skip
    assert (
        await client.get(f"/v1/officers/{outside.id}/track", headers=bearer(a.owner))
    ).status_code == 422
    # Other tenant's officer: nothing to see.
    foreign = m2.world.b.user(UserRole.FIELD_OFFICER)
    resp = await client.get(
        f"/v1/officers/{foreign.id}/track", params={"day": DAY}, headers=bearer(a.owner)
    )
    assert resp.status_code == 404


async def test_track_day_is_an_ist_day(client: AsyncClient, m2: M2World, bearer: Bearer) -> None:
    """Sessions run 09:00-18:00 IST, so a day's points sit between 03:30 and 12:30 UTC."""
    officer = m2.officer
    body = (
        await client.get(
            f"/v1/officers/{officer.id}/track", params={"day": DAY}, headers=bearer(officer)
        )
    ).json()
    hours = {datetime.fromisoformat(p["ts"]).astimezone(UTC).hour for p in body["points"]}
    assert hours and min(hours) >= 3 and max(hours) <= 14
