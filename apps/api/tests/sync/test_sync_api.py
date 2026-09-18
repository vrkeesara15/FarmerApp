"""``POST /v1/sync`` (FA-025 / NF-003): outbox operations applied in order with ``op_id``
idempotency, per-entity conflict rules (last-writer-wins for farmer / farm / crop plot),
problem-style rejections, and the scoped changes feed with an advancing cursor."""

from __future__ import annotations

import base64
import uuid
from datetime import timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import ConsentRecord, Farm, Farmer
from farmerapp.sync import service as sync_service
from farmerapp.sync.models import SyncChange, SyncOp
from tests.farmers.write_fixtures import BASE_LAT, BASE_LON, WriteCtx, bowtie
from tests.sync.conftest import DEVICE, T_CLIENT, op, sync


def _seq(cursor: str | None) -> int:
    assert cursor is not None
    return int(base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)).decode())


# ------------------------------------------------------------------ apply
async def test_registration_via_sync_op(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    fid = uuid.uuid4()
    payload = ctx.farmer(farms=[ctx.farm(plots=1)])
    body = await sync(client, ctx, [op("farmer", "create", payload, entity_id=fid)])
    result = body["results"][0]
    assert result["status"] == "applied" and result["entity_id"] == str(fid)
    assert result["version"] == 1 and result["error"] is None
    server = result["server"]
    assert server["id"] == str(fid) and server["phone"] == payload["phone"]
    assert server["phone_verified"] is False and server["warnings"] == []
    assert len(server["farms"]) == 1 and len(server["farms"][0]["crop_plots"]) == 1
    assert [c["purpose"] for c in server["consents"]] == ["data"]
    async with tenant_scope(db_session, ctx.tenant_id):
        row = await db_session.get_one(Farmer, fid)
        assert row.registered_by == ctx.officer.id
        assert (
            await db_session.scalar(select(ConsentRecord).where(ConsentRecord.subject_id == fid))
        ) is not None
        stored = (
            await db_session.execute(
                select(SyncOp).where(SyncOp.op_id == uuid.UUID(body["results"][0]["op_id"]))
            )
        ).scalar_one()
        assert stored.device_id == DEVICE and stored.actor_id == ctx.officer.id
        assert stored.result["status"] == "applied"
    # The changes feed carries the new farmer, its farm, plot and consent record.
    assert {(c["entity"], c["action"]) for c in body["changes"]} >= {
        ("farmer", "create"),
        ("farm", "create"),
        ("crop_plot", "create"),
        ("consent_record", "create"),
    }
    assert body["cursor"] and body["has_more"] is False


async def test_duplicate_phone_is_rejected_not_aborting_the_batch(
    client: AsyncClient, ctx: WriteCtx
) -> None:
    seeded = ctx.world.a.farmer
    ops = [
        op("farmer", "create", ctx.farmer(phone=seeded.phone)),
        op("farmer", "create", ctx.farmer(phone="+919000199201")),
    ]
    body = await sync(client, ctx, ops)
    first, second = body["results"]
    assert first["status"] == "rejected" and first["version"] is None and first["server"] is None
    assert first["error"]["code"] == "farmer_phone_exists" and first["error"]["status"] == 409
    assert first["error"]["detail"]
    assert second["status"] == "applied"


async def test_validation_failures_are_rejected_with_details(
    client: AsyncClient, ctx: WriteCtx
) -> None:
    ops = [
        op("farmer", "create", ctx.farmer(phone="12345")),
        op(
            "farmer", "create", ctx.farmer(farms=[ctx.farm(boundary=bowtie(BASE_LON, BASE_LAT, 1))])
        ),
        op("farmer", "create", ctx.farmer(phone="+919000199202", village_id=str(uuid.uuid4()))),
        op("khata", "create", {}),
        op("consent_record", "update", {"granted": False}, base_version=1),
    ]
    resp = await client.post(
        "/v1/sync", json={"device_id": DEVICE, "cursor": None, "ops": ops}, headers=ctx.headers
    )
    assert resp.status_code == 422  # unknown entity fails request validation
    ops.pop(3)
    body = await sync(client, ctx, ops)
    codes = [r["error"]["code"] for r in body["results"]]
    assert codes == ["validation_error", "farm_boundary_invalid", "not_found", "unsupported_action"]
    assert body["results"][0]["error"]["errors"][0]["loc"] == ["phone"]
    assert all(r["status"] == "rejected" for r in body["results"])


async def test_replayed_op_id_is_duplicate_with_identical_result(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    fid, oid = uuid.uuid4(), uuid.uuid4()
    create = op("farmer", "create", ctx.farmer(), entity_id=fid, op_id=oid)
    first = await sync(client, ctx, [create])
    again = await sync(
        client, ctx, [create, op("farmer", "create", ctx.farmer(phone="+919000199203"))]
    )
    replay = again["results"][0]
    assert replay["status"] == "duplicate"
    original = first["results"][0]
    for key in ("op_id", "entity_id", "version", "error", "server"):
        assert replay[key] == original[key], key
    assert again["results"][1]["status"] == "applied"
    async with tenant_scope(db_session, ctx.tenant_id):
        rows = (
            await db_session.execute(select(Farmer).where(Farmer.phone == "+919000199001"))
        ).all()
        assert len(rows) == 1
    # A rejected result replays as duplicate too, still carrying the original error.
    dup = op("farmer", "create", ctx.farmer(), op_id=uuid.uuid4())
    body = await sync(client, ctx, [dup])
    assert body["results"][0]["status"] == "rejected"
    body = await sync(client, ctx, [dup])
    assert body["results"][0]["status"] == "duplicate"
    assert body["results"][0]["error"]["code"] == "farmer_phone_exists"


async def test_last_writer_wins_on_farmer_name(client: AsyncClient, ctx: WriteCtx) -> None:
    fid = uuid.uuid4()
    await sync(client, ctx, [op("farmer", "create", ctx.farmer(), entity_id=fid)])
    # Server-side edit through REST bumps the version to 2.
    resp = await client.patch(
        f"/v1/farmers/{fid}", json={"name": "Server Name"}, headers=ctx.headers
    )
    assert resp.status_code == 200 and resp.json()["version"] == 2
    server_updated_at = resp.json()["updated_at"]

    # Stale client (base_version 1) with an OLDER client_ts loses: conflict, server state returned.
    older = op(
        "farmer", "update", {"name": "Old Phone Edit"}, entity_id=fid, base_version=1,
        client_ts=T_CLIENT - timedelta(days=1),
    )  # fmt: skip
    body = await sync(client, ctx, [older])
    result = body["results"][0]
    assert result["status"] == "conflict" and result["version"] == 2
    assert result["server"]["name"] == "Server Name"
    assert result["server"]["updated_at"] == server_updated_at

    # Stale client with a NEWER client_ts wins (last writer).
    from datetime import UTC, datetime

    newer = op(
        "farmer", "update", {"name": "Newer Phone Edit"}, entity_id=fid, base_version=1,
        client_ts=datetime.now(UTC) + timedelta(minutes=1),
    )  # fmt: skip
    body = await sync(client, ctx, [newer])
    result = body["results"][0]
    assert result["status"] == "applied" and result["version"] == 3
    assert result["server"]["name"] == "Newer Phone Edit"

    # Matching base_version applies without looking at the clock.
    exact = op("farmer", "update", {"landmark": "Well"}, entity_id=fid, base_version=3)
    body = await sync(client, ctx, [exact])
    assert body["results"][0]["status"] == "applied" and body["results"][0]["version"] == 4
    resp = await client.get(f"/v1/farmers/{fid}", headers=ctx.headers)
    assert resp.json()["name"] == "Newer Phone Edit" and resp.json()["landmark"] == "Well"


async def test_conflict_rule_table() -> None:
    rules = sync_service.CONFLICT_RULES
    assert rules["farmer"] == rules["farm"] == rules["crop_plot"] == "last_writer_wins"
    assert rules["consent_record"] == "server_wins"  # append-only: never updated
    assert sync_service.Strategy.SERVER_WINS.value == "server_wins"  # reserved: khata, payments
    assert set(sync_service.Strategy) == {"server_wins", "last_writer_wins", "merge_fields"}


async def test_farm_and_plot_ops_and_soft_delete(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    fid, farm_id, plot_id = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    ops = [
        op("farmer", "create", ctx.farmer(), entity_id=fid),
        op("farm", "create", {**ctx.farm(), "farmer_id": str(fid)}, entity_id=farm_id),
        op("crop_plot", "create", {**ctx.plot(), "farm_id": str(farm_id)}, entity_id=plot_id),
        op("farm", "update", {"name": "Edited"}, entity_id=farm_id, base_version=1),
        op("crop_plot", "delete", {}, entity_id=plot_id, base_version=1),
        op(
            "consent_record",
            "create",
            {"farmer_id": str(fid), "purpose": "marketing", "granted": True},
        ),
    ]
    body = await sync(client, ctx, ops)
    statuses = [r["status"] for r in body["results"]]
    assert statuses == ["applied"] * 6, body["results"]
    assert body["results"][3]["version"] == 2 and body["results"][3]["server"]["name"] == "Edited"
    assert body["results"][4]["version"] == 2 and body["results"][4]["server"]["deleted_at"]
    assert body["results"][5]["server"]["purpose"] == "marketing"
    async with tenant_scope(db_session, ctx.tenant_id):
        farm = await db_session.get_one(Farm, farm_id)
        assert farm.name == "Edited" and farm.deleted_at is None
    deletes = [c for c in body["changes"] if c["action"] == "delete"]
    assert (
        deletes and deletes[0]["entity"] == "crop_plot" and deletes[0]["entity_id"] == str(plot_id)
    )
    assert set(deletes[0]["data"]) == {"id", "deleted_at"}
    # A farm update after the delete of its plot: ordering + missing entity handling.
    body = await sync(
        client,
        ctx,
        [op("crop_plot", "update", {"stage": "sown"}, entity_id=plot_id, base_version=2)],
    )
    assert (
        body["results"][0]["status"] == "rejected"
        and body["results"][0]["error"]["code"] == "not_found"
    )
    body = await sync(
        client, ctx, [op("farm", "delete", {}, entity_id=uuid.uuid4(), base_version=1)]
    )
    assert (
        body["results"][0]["status"] == "rejected"
        and body["results"][0]["error"]["code"] == "not_found"
    )


async def test_create_of_existing_entity_id_is_a_conflict(
    client: AsyncClient, ctx: WriteCtx
) -> None:
    fid = uuid.uuid4()
    await sync(client, ctx, [op("farmer", "create", ctx.farmer(), entity_id=fid)])
    body = await sync(
        client, ctx, [op("farmer", "create", ctx.farmer(phone="+919000199204"), entity_id=fid)]
    )
    assert body["results"][0]["status"] == "conflict" and body["results"][0]["server"]["id"] == str(
        fid
    )


async def test_farmer_role_may_only_update_own_record(
    client: AsyncClient, ctx: WriteCtx, bearer: Any
) -> None:
    from farmerapp.auth.models import UserRole

    farmer_user = ctx.world.a.user(UserRole.FARMER)
    own = next(f for f in ctx.world.a.farmers if f.user_id == farmer_user.id)
    other = next(f for f in ctx.world.a.farmers if f.user_id is None)
    ops = [
        op("farmer", "update", {"landmark": "Mine"}, entity_id=own.id, base_version=own.version),
        op(
            "farmer",
            "update",
            {"landmark": "Not mine"},
            entity_id=other.id,
            base_version=other.version,
        ),
        op("farmer", "create", ctx.farmer(phone="+919000199205")),
    ]
    body = await sync(client, ctx, ops, headers=bearer(farmer_user))
    assert [r["status"] for r in body["results"]] == ["applied", "rejected", "rejected"]
    assert body["results"][1]["error"]["code"] == "not_found"
    assert body["results"][2]["error"]["code"] == "forbidden"
    assert all(c["entity_id"] != str(other.id) for c in body["changes"])


async def test_batch_limits_and_idempotency_key(client: AsyncClient, ctx: WriteCtx) -> None:
    too_many = [op("farmer", "create", ctx.farmer()) for _ in range(201)]
    resp = await client.post(
        "/v1/sync", json={"device_id": DEVICE, "cursor": None, "ops": too_many}, headers=ctx.headers
    )
    assert resp.status_code == 422
    key = {"Idempotency-Key": "batch-" + uuid.uuid4().hex}
    ops = [op("farmer", "create", ctx.farmer())]
    first = await sync(client, ctx, ops, headers={**ctx.headers, **key})
    second = await sync(client, ctx, ops, headers={**ctx.headers, **key})
    assert second == first  # replayed as a whole, results still say "applied"


# ------------------------------------------------------------------ changes feed
async def test_changes_feed_is_scoped_and_cursor_advances(
    client: AsyncClient, ctx: WriteCtx
) -> None:
    initial = await sync(client, ctx, [])
    start = initial["cursor"]
    # The seed wrote through the same flush hook: the officer's own farmers are already there.
    own = {str(f.id) for f in ctx.world.a.farmers if f.registered_by == ctx.officer.id}
    seeded = {c["entity_id"] for c in initial["changes"] if c["entity"] == "farmer"}
    assert seeded == own and initial["has_more"] is False

    mine = uuid.uuid4()
    await sync(
        client, ctx, [op("farmer", "create", ctx.farmer(farms=[ctx.farm()]), entity_id=mine)]
    )
    theirs = uuid.uuid4()
    other_ctx_ops = [op("farmer", "create", ctx.farmer(phone="+919000199206"), entity_id=theirs)]
    resp = await client.post(
        "/v1/sync",
        json={"device_id": "device-2", "cursor": None, "ops": other_ctx_ops},
        headers=ctx.other_headers,
    )
    assert resp.status_code == 200 and resp.json()["results"][0]["status"] == "applied"

    body = await sync(client, ctx, [], cursor=start)
    ids = {c["entity_id"] for c in body["changes"]}
    assert str(mine) in ids and str(theirs) not in ids
    farmer_change = next(c for c in body["changes"] if c["entity"] == "farmer")
    assert farmer_change["action"] == "create" and farmer_change["version"] == 1
    assert farmer_change["data"]["name"] == "Ravi Kumar" and farmer_change["seq"] > 0
    farm_change = next(c for c in body["changes"] if c["entity"] == "farm")
    assert farm_change["data"]["boundary"]["type"] == "Polygon"
    assert _seq(body["cursor"]) > _seq(start)
    assert all(c["seq"] <= _seq(body["cursor"]) for c in body["changes"])

    # From the new cursor: nothing new; the other officer sees only theirs.
    again = await sync(client, ctx, [], cursor=body["cursor"])
    assert again["changes"] == [] and again["cursor"] == body["cursor"]
    resp = await client.post(
        "/v1/sync",
        json={"device_id": "device-2", "cursor": start, "ops": []},
        headers=ctx.other_headers,
    )
    other_ids = {c["entity_id"] for c in resp.json()["changes"]}
    assert str(theirs) in other_ids and str(mine) not in other_ids

    # An update collapses to one change with the latest state; the version reflects it.
    resp = await client.patch(f"/v1/farmers/{mine}", json={"name": "Renamed"}, headers=ctx.headers)
    assert resp.status_code == 200
    body = await sync(client, ctx, [], cursor=start)
    farmer_changes = [c for c in body["changes"] if c["entity_id"] == str(mine)]
    assert len(farmer_changes) == 1
    assert farmer_changes[0]["action"] == "update" and farmer_changes[0]["version"] == 2
    assert farmer_changes[0]["data"]["name"] == "Renamed"


async def test_changes_feed_is_capped_with_has_more(
    client: AsyncClient, ctx: WriteCtx, monkeypatch: pytest.MonkeyPatch
) -> None:
    start = (await sync(client, ctx, []))["cursor"]  # past the seed's changes
    monkeypatch.setattr(sync_service, "MAX_CHANGES", 3)
    ops = [
        op("farmer", "create", ctx.farmer(phone=f"+91900019930{i}", consents=[])) for i in range(5)
    ]
    await sync(client, ctx, ops)
    page = await sync(client, ctx, [], cursor=start)
    assert len(page["changes"]) == 3 and page["has_more"] is True
    rest = await sync(client, ctx, [], cursor=page["cursor"])
    assert len(rest["changes"]) == 2 and rest["has_more"] is False
    seen = [c["entity_id"] for c in page["changes"] + rest["changes"]]
    assert len(seen) == len(set(seen)) == 5


async def test_bad_cursor_is_400(client: AsyncClient, ctx: WriteCtx) -> None:
    resp = await client.post(
        "/v1/sync", json={"device_id": DEVICE, "cursor": "junk!", "ops": []}, headers=ctx.headers
    )
    assert resp.status_code == 400 and resp.json()["code"] == "invalid_cursor"


async def test_sync_change_rows_are_appended_by_every_write_path(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    """The change log is written by the flush listener, so REST writes feed it too."""
    resp = await client.post(
        "/v1/farmers", json=ctx.farmer(farms=[ctx.farm(plots=1)]), headers=ctx.headers
    )
    assert resp.status_code == 201
    fid = uuid.UUID(resp.json()["id"])
    async with tenant_scope(db_session, ctx.tenant_id):
        rows = (
            (
                await db_session.execute(
                    select(SyncChange)
                    .where(SyncChange.tenant_id == ctx.tenant_id)
                    .order_by(SyncChange.seq)
                )
            )
            .scalars()
            .all()
        )
    by_entity = {(r.entity, r.entity_id): r for r in rows}
    assert ("farmer", fid) in by_entity and by_entity[("farmer", fid)].action == "create"
    assert (
        by_entity[("farmer", fid)].version == 1
        and by_entity[("farmer", fid)].actor_id == ctx.officer.id
    )
    assert {e for e, _ in by_entity} >= {"farmer", "farm", "crop_plot", "consent_record"}
