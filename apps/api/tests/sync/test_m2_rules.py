"""M2 entities in the sync contract (FA-025): conflict rules (``merge_fields`` for visits with
server-owned score / status / confirmation, ``server_wins`` for auto-ended duty sessions),
the change feed scope for visits / duty sessions / policy acceptances, and the write path
that is still the loop's job (ops are rejected, never mis-applied)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.geo import point_wkt
from farmerapp.db.session import tenant_scope
from farmerapp.location.models import DutyEndReason, DutySession, PolicyAcceptance
from farmerapp.sync import service as sync_service
from farmerapp.sync.models import SYNC_ENTITIES, SYNC_EXCLUDED_ENTITIES
from farmerapp.sync.schemas import SyncOpIn
from farmerapp.sync.service import (
    CONFLICT_RULES,
    SERVER_OWNED_FIELDS,
    Strategy,
    merge_payload,
    server_owned_fields,
)
from farmerapp.visits.models import GeofenceResult, Visit, VisitPurpose
from tests.farmers.write_fixtures import WriteCtx
from tests.sync.conftest import op, sync

T0 = datetime(2026, 9, 18, 4, 30, tzinfo=UTC)


def test_rules_cover_every_synced_entity() -> None:
    assert set(CONFLICT_RULES) == set(SYNC_ENTITIES)
    assert CONFLICT_RULES["visit"] == Strategy.MERGE_FIELDS
    assert CONFLICT_RULES["duty_session"] == Strategy.MERGE_FIELDS
    assert CONFLICT_RULES["visit_photo"] == Strategy.SERVER_WINS
    assert CONFLICT_RULES["policy_acceptance"] == Strategy.SERVER_WINS
    assert "location_point" in SYNC_EXCLUDED_ENTITIES and "location_point" not in CONFLICT_RULES


def test_visit_server_owned_fields() -> None:
    owned = SERVER_OWNED_FIELDS["visit"]
    assert {"score", "score_components", "status", "confirmation_channel", "confirmed_at"} <= owned
    assert {"geofence_result", "override_approved_by", "duration_s"} <= owned
    assert not {"notes", "crop_stage", "purpose", "checkout_at"} & owned


def test_merge_payload_drops_server_owned_visit_fields() -> None:
    row = Visit(status="verified", score=88)
    payload = {"notes": "new notes", "crop_stage": "fruiting", "score": 100, "status": "verified"}
    assert merge_payload("visit", row, payload) == {"notes": "new notes", "crop_stage": "fruiting"}


def test_duty_session_end_is_server_owned_once_auto_ended() -> None:
    manual = DutySession(end_at=T0, end_reason=DutyEndReason.MANUAL)
    auto = DutySession(end_at=T0, end_reason=DutyEndReason.AUTO_TIME)
    idle = DutySession(end_at=T0, end_reason=DutyEndReason.AUTO_IDLE)
    open_session = DutySession()
    assert server_owned_fields("duty_session", open_session) == SERVER_OWNED_FIELDS["duty_session"]
    assert not {"end_at", "end_reason"} & server_owned_fields("duty_session", manual)
    assert {"end_at", "end_reason"} <= server_owned_fields("duty_session", auto)
    assert {"end_at", "end_reason"} <= server_owned_fields("duty_session", idle)
    payload: dict[str, Any] = {
        "end_at": (T0 + timedelta(hours=1)).isoformat(),
        "end_reason": "manual",
        "km": 3,
    }
    assert "km" in SERVER_OWNED_FIELDS["duty_session"]  # computed by track processing (VV-006)
    assert merge_payload("duty_session", auto, payload) == {}
    assert merge_payload("duty_session", manual, payload) == {
        "end_at": payload["end_at"],
        "end_reason": "manual",
    }


def test_merge_fields_never_loses_a_conflict() -> None:
    visit = Visit(version=5, updated_at=T0)
    stale = SyncOpIn(
        op_id=uuid.uuid4(),
        entity="visit",
        action="update",
        entity_id=uuid.uuid4(),
        base_version=1,
        payload={"notes": "x"},
        client_ts=T0 - timedelta(days=1),
    )
    assert sync_service._loses_conflict(stale, visit) is False  # merge, client-owned fields win
    stale_farmer = stale.model_copy(update={"entity": "farmer"})
    farmer_row = Visit(version=5, updated_at=T0)  # any row with version/updated_at
    assert sync_service._loses_conflict(stale_farmer, farmer_row) is True


async def test_m2_ops_validate_but_are_rejected_until_the_write_path_lands(
    client: AsyncClient, ctx: WriteCtx
) -> None:
    # duty_session / policy_acceptance / location_batch writes landed with FA-010 (tests/duty,
    # tests/location/test_batch.py, tests/policies); a duty session is never deleted by a device.
    ops = [
        op("visit", "create", {"purpose": "advisory"}),
        op("visit_photo", "create", {"blob_uri": "gs://x/y"}),
        op("visit", "update", {"notes": "x"}, base_version=1),
        op("duty_session", "delete", {}, base_version=1),
    ]
    body = await sync(client, ctx, ops)
    assert [r["status"] for r in body["results"]] == ["rejected"] * 4
    assert {r["error"]["code"] for r in body["results"]} == {"unsupported_action"}
    assert all(r["error"]["status"] == 422 for r in body["results"])


async def test_change_feed_reports_own_visits_duty_sessions_and_acceptances(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    officer = ctx.officer
    other = ctx.other_officer
    first = await sync(client, ctx, [])
    cursor = first["cursor"]
    async with tenant_scope(db_session, ctx.tenant_id):
        farmer_id = await db_session.scalar(
            select(Visit.farmer_id).where(Visit.officer_id == officer.id).limit(1)
        )
        assert farmer_id is not None
        mine = Visit(
            tenant_id=ctx.tenant_id,
            officer_id=officer.id,
            farmer_id=farmer_id,
            purpose=VisitPurpose.SCOUTING,
            checkin_at=T0,
            checkin_point=point_wkt(79.55, 18.02),
            geofence_result=GeofenceResult.INSIDE,
        )
        theirs = Visit(
            tenant_id=ctx.tenant_id,
            officer_id=other.id,
            farmer_id=farmer_id,
            purpose=VisitPurpose.SCOUTING,
            checkin_at=T0,
            checkin_point=point_wkt(79.55, 18.02),
            geofence_result=GeofenceResult.INSIDE,
        )
        duty = DutySession(
            tenant_id=ctx.tenant_id, officer_id=officer.id, start_at=T0, policy_version="2026-09-v1"
        )
        acceptance = PolicyAcceptance(
            tenant_id=ctx.tenant_id, user_id=officer.id, version="2026-09-v1", accepted_at=T0
        )
        db_session.add_all([mine, theirs, duty, acceptance])
        await db_session.flush()
    body = await sync(client, ctx, [], cursor=cursor)
    changes = {(c["entity"], c["entity_id"]): c for c in body["changes"]}
    assert ("visit", str(mine.id)) in changes
    assert ("visit", str(theirs.id)) not in changes  # another officer's visit
    assert ("duty_session", str(duty.id)) in changes
    assert ("policy_acceptance", str(acceptance.id)) in changes
    visit_change = changes[("visit", str(mine.id))]
    assert visit_change["action"] == "create" and visit_change["data"]["purpose"] == "scouting"
    assert visit_change["data"]["status"] == "open"
    duty_change = changes[("duty_session", str(duty.id))]
    assert (
        duty_change["data"]["end_at"] is None
        and duty_change["data"]["policy_version"] == "2026-09-v1"
    )
    assert (
        changes[("policy_acceptance", str(acceptance.id))]["data"]["policy_key"]
        == "location_policy"
    )
    # The other officer sees theirs and not mine.
    body = await sync(client, ctx, [], cursor=cursor, headers=ctx.other_headers)
    ids = {(c["entity"], c["entity_id"]) for c in body["changes"]}
    assert ("visit", str(theirs.id)) in ids and ("visit", str(mine.id)) not in ids
    assert ("duty_session", str(duty.id)) not in ids
    assert ("policy_acceptance", str(acceptance.id)) not in ids
