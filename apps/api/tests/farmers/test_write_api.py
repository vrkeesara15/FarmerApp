"""FA-012 / FA-013 write endpoints: registration with nested farms, crop plots and consent,
duplicate phone -> 409, inline VA-F01 / VA-F03 checks, idempotency keys, scope-based 404s,
PATCH / soft DELETE of farms and crop plots, consent grants and withdrawals."""

from __future__ import annotations

import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.models import AuditLog, Tenant
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import ConsentRecord, CropPlot, Farm, Farmer
from tests.authz.conftest import Bearer
from tests.farmers.write_fixtures import BASE_LAT, BASE_LON, WriteCtx, bowtie, square


async def _create(client: AsyncClient, ctx: WriteCtx, body: dict[str, Any], **kw: Any) -> Any:
    resp = await client.post("/v1/farmers", json=body, headers={**ctx.headers, **kw})
    assert resp.status_code == 201, resp.text
    return resp.json()


# ------------------------------------------------------------------ registration (FA-012)
async def test_register_farmer_creates_row_and_consent(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    body = await _create(client, ctx, ctx.farmer())
    assert body["phone"] == "+919000199001" and body["phone_last4"] == "9001"
    assert body["name"] == "Ravi Kumar" and body["village_id"] == str(ctx.village_id)
    assert body["registered_by"] == str(ctx.officer.id) and body["source"] == "officer"
    assert body["phone_verified"] is False  # offline registration, no OTP token
    assert body["version"] == 1 and body["warnings"] == [] and body["farms"] == []
    assert [c["purpose"] for c in body["consents"]] == ["data"]
    consent = body["consents"][0]
    assert consent["granted_at"] and consent["channel"] == "officer"
    assert consent["version"] == "2026-09-v1" and consent["recorded_by"] == str(ctx.officer.id)

    async with tenant_scope(db_session, ctx.tenant_id):
        row = await db_session.get_one(Farmer, uuid.UUID(body["id"]))
        assert row.phone == "+919000199001" and row.registered_by == ctx.officer.id
        records = (
            (
                await db_session.execute(
                    select(ConsentRecord).where(ConsentRecord.subject_id == row.id)
                )
            )
            .scalars()
            .all()
        )
        assert len(records) == 1 and records[0].purpose == "data" and records[0].granted
        audit = (
            (
                await db_session.execute(
                    select(AuditLog.action)
                    .where(AuditLog.entity_id == row.id)
                    .order_by(AuditLog.created_at)
                )
            )
            .scalars()
            .all()
        )
        assert audit == ["farmer.create"]

    resp = await client.get(f"/v1/farmers/{body['id']}", headers=ctx.headers)
    assert resp.status_code == 200 and resp.json()["phone_verified"] is False


async def test_phone_is_normalised_and_validated(client: AsyncClient, ctx: WriteCtx) -> None:
    body = await _create(client, ctx, ctx.farmer(phone="98765 43210"))
    assert body["phone"] == "+919876543210"
    for bad in ("12345", "+911234567890", "+1 555 0100"):
        resp = await client.post("/v1/farmers", json=ctx.farmer(phone=bad), headers=ctx.headers)
        assert resp.status_code == 422 and resp.json()["code"] == "validation_error", bad


async def test_duplicate_phone_is_409(client: AsyncClient, ctx: WriteCtx) -> None:
    await _create(client, ctx, ctx.farmer())
    resp = await client.post("/v1/farmers", json=ctx.farmer(name="Other"), headers=ctx.headers)
    assert resp.status_code == 409, resp.text
    assert resp.json()["code"] == "farmer_phone_exists"
    # A seeded farmer's phone (registered by another officer) is a duplicate as well.
    seeded = ctx.world.a.farmer
    resp = await client.post(
        "/v1/farmers", json=ctx.farmer(phone=seeded.phone), headers=ctx.headers
    )
    assert resp.status_code == 409 and resp.json()["code"] == "farmer_phone_exists"


async def test_staff_phone_is_rejected(client: AsyncClient, ctx: WriteCtx) -> None:
    """VA-F01: a staff phone cannot be registered as a farmer."""
    resp = await client.post(
        "/v1/farmers", json=ctx.farmer(phone=ctx.other_officer.phone), headers=ctx.headers
    )
    assert resp.status_code == 422 and resp.json()["code"] == "farmer_phone_is_staff"


async def test_unknown_village_is_404(client: AsyncClient, ctx: WriteCtx) -> None:
    resp = await client.post(
        "/v1/farmers", json=ctx.farmer(village_id=str(uuid.uuid4())), headers=ctx.headers
    )
    assert resp.status_code == 404 and resp.json()["code"] == "not_found"
    other = ctx.world.b.farmer.village_id  # another tenant's village
    resp = await client.post(
        "/v1/farmers", json=ctx.farmer(village_id=str(other)), headers=ctx.headers
    )
    assert resp.status_code == 404


async def test_consent_version_comes_from_tenant_settings(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    async with tenant_scope(db_session, ctx.tenant_id):
        tenant = await db_session.get_one(Tenant, ctx.tenant_id)
        tenant.settings = {**tenant.settings, "consent_version": "2026-10-v2"}
        await db_session.flush()
    body = await _create(
        client,
        ctx,
        ctx.farmer(
            consents=[
                {"purpose": "data", "granted": True},
                {"purpose": "marketing", "granted": True, "language": "te"},
            ]
        ),
    )
    assert {c["version"] for c in body["consents"]} == {"2026-10-v2"}
    assert body["consent_marketing"] is True and body["consent_version"] == "2026-10-v2"


# ------------------------------------------------------------------ FA-013
async def test_farmer_with_two_farms_and_three_plots_in_one_post(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    farms = [
        ctx.farm(acres=1.0, plots=2, name="Home field"),
        ctx.farm(acres=2.0, plots=1, name="River field", at=(BASE_LON + 0.01, BASE_LAT)),
    ]
    body = await _create(client, ctx, ctx.farmer(farms=farms))
    assert [f["name"] for f in body["farms"]] == ["Home field", "River field"]
    assert [len(f["crop_plots"]) for f in body["farms"]] == [2, 1]
    assert body["warnings"] == []
    home = body["farms"][0]
    assert home["boundary"]["type"] == "Polygon" and home["centroid"]["lat"] > 18
    assert abs(float(home["area_acres_computed"]) - 1.0) < 0.05
    assert (
        home["crop_plots"][0]["variety"] == "V-0" and home["crop_plots"][0]["farm_id"] == home["id"]
    )
    async with tenant_scope(db_session, ctx.tenant_id):
        farm_ids = (
            (
                await db_session.execute(
                    select(Farm.id).where(Farm.farmer_id == uuid.UUID(body["id"]))
                )
            )
            .scalars()
            .all()
        )
        assert len(farm_ids) == 2
        plots = (
            (await db_session.execute(select(CropPlot).where(CropPlot.farm_id.in_(farm_ids))))
            .scalars()
            .all()
        )
        assert len(plots) == 3


async def test_client_generated_ids_are_honoured(client: AsyncClient, ctx: WriteCtx) -> None:
    fid, farm_id, plot_id = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    farm = ctx.farm(plots=0, id=str(farm_id), crop_plots=[ctx.plot(0, id=str(plot_id))])
    body = await _create(client, ctx, ctx.farmer(id=str(fid), farms=[farm]))
    assert body["id"] == str(fid)
    assert body["farms"][0]["id"] == str(farm_id)
    assert body["farms"][0]["crop_plots"][0]["id"] == str(plot_id)


# ------------------------------------------------------------------ VA-F03 inline checks
async def test_self_intersecting_polygon_is_422(client: AsyncClient, ctx: WriteCtx) -> None:
    farm = ctx.farm(boundary=bowtie(BASE_LON, BASE_LAT, 1.0))
    resp = await client.post("/v1/farmers", json=ctx.farmer(farms=[farm]), headers=ctx.headers)
    assert resp.status_code == 422, resp.text
    assert resp.json()["code"] == "farm_boundary_invalid"
    assert "Self-intersection" in resp.json()["detail"]


async def test_malformed_geojson_is_422(client: AsyncClient, ctx: WriteCtx) -> None:
    cases: list[dict[str, Any]] = [
        {"type": "Point", "coordinates": [BASE_LON, BASE_LAT]},
        {"type": "Polygon", "coordinates": [[[BASE_LON, BASE_LAT], [BASE_LON, BASE_LAT + 0.001]]]},
        {"type": "Polygon", "coordinates": [[[200, 18], [201, 18], [201, 19], [200, 18]]]},
    ]
    for boundary in cases:
        farm = ctx.farm(boundary=boundary)
        resp = await client.post("/v1/farmers", json=ctx.farmer(farms=[farm]), headers=ctx.headers)
        assert resp.status_code == 422, resp.text
        assert resp.json()["code"] in ("validation_error", "farm_boundary_invalid")


async def test_area_mismatch_is_a_warning_not_a_rejection(
    client: AsyncClient, ctx: WriteCtx
) -> None:
    farm = ctx.farm(acres=1.0, declared=2.0)  # measured 1 acre, declared 2 (+100 %)
    body = await _create(client, ctx, ctx.farmer(farms=[farm]))
    assert body["warnings"] == ["area_mismatch"]
    assert body["farms"][0]["warnings"] == ["area_mismatch"]
    farm = ctx.farm(acres=1.0, declared=1.2, at=(BASE_LON + 0.02, BASE_LAT))  # +20 %: fine
    body = await _create(client, ctx, ctx.farmer(phone="+919000199002", farms=[farm]))
    assert body["warnings"] == [] and body["farms"][0]["warnings"] == []


async def test_overlap_with_another_farmers_farm_is_a_warning(
    client: AsyncClient, ctx: WriteCtx
) -> None:
    await _create(client, ctx, ctx.farmer(farms=[ctx.farm(acres=1.0)]))
    # Second farmer, same square shifted by a third of a side: ~44 % overlap.
    side = (4046.8564224) ** 0.5
    from farmerapp.db.geo import offset

    lon, lat = offset(BASE_LON, BASE_LAT, side / 3, 0)
    body = await _create(
        client, ctx, ctx.farmer(phone="+919000199002", farms=[ctx.farm(acres=1.0, at=(lon, lat))])
    )
    assert body["warnings"] == ["farm_overlap"]
    # Own farms never trigger it: a third farmer far away, then a second farm on the same spot.
    far = (BASE_LON + 0.05, BASE_LAT)
    third = await _create(
        client, ctx, ctx.farmer(phone="+919000199003", farms=[ctx.farm(acres=1.0, at=far)])
    )
    assert third["warnings"] == []
    resp = await client.post(
        f"/v1/farmers/{third['id']}/farms", json=ctx.farm(acres=1.0, at=far), headers=ctx.headers
    )
    assert resp.status_code == 201 and resp.json()["warnings"] == []


# ------------------------------------------------------------------ idempotency keys
async def test_idempotency_key_replays_the_original_response(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    payload = ctx.farmer(farms=[ctx.farm(plots=1)])
    key = {"Idempotency-Key": "reg-" + uuid.uuid4().hex}
    first = await client.post("/v1/farmers", json=payload, headers={**ctx.headers, **key})
    assert first.status_code == 201, first.text
    second = await client.post("/v1/farmers", json=payload, headers={**ctx.headers, **key})
    assert second.status_code == 201 and second.json() == first.json()
    async with tenant_scope(db_session, ctx.tenant_id):
        n = await db_session.scalar(
            select(Farmer.id).where(Farmer.phone == payload["phone"]).limit(2)
        )
        rows = (
            await db_session.execute(select(Farmer).where(Farmer.phone == payload["phone"]))
        ).all()
    assert n is not None and len(rows) == 1
    # Same key, different body -> 422 idempotency_key_reuse.
    resp = await client.post(
        "/v1/farmers", json=ctx.farmer(name="Changed"), headers={**ctx.headers, **key}
    )
    assert resp.status_code == 422 and resp.json()["code"] == "idempotency_key_reuse"
    # Another actor may use the same key: it is scoped by tenant + actor.
    resp = await client.post(
        "/v1/farmers",
        json=ctx.farmer(phone="+919000199003"),
        headers={**ctx.other_headers, **key},
    )
    assert resp.status_code == 201


async def test_idempotency_key_does_not_cache_errors(client: AsyncClient, ctx: WriteCtx) -> None:
    key = {"Idempotency-Key": "dup-" + uuid.uuid4().hex}
    await _create(client, ctx, ctx.farmer())
    resp = await client.post("/v1/farmers", json=ctx.farmer(), headers={**ctx.headers, **key})
    assert resp.status_code == 409
    resp = await client.post("/v1/farmers", json=ctx.farmer(), headers={**ctx.headers, **key})
    assert resp.status_code == 409  # evaluated again, not replayed


# ------------------------------------------------------------------ updates and scope
async def test_patch_farmer_and_scope_404(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    body = await _create(client, ctx, ctx.farmer())
    fid = body["id"]
    resp = await client.patch(
        f"/v1/farmers/{fid}", json={"name": "Ravi K", "landmark": None}, headers=ctx.headers
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["name"] == "Ravi K" and resp.json()["landmark"] is None
    assert resp.json()["version"] == 2
    # Another officer does not see this farmer: 404 on read and write.
    resp = await client.patch(f"/v1/farmers/{fid}", json={"name": "X"}, headers=ctx.other_headers)
    assert resp.status_code == 404 and resp.json()["code"] == "not_found"
    resp = await client.post(f"/v1/farmers/{fid}/farms", json=ctx.farm(), headers=ctx.other_headers)
    assert resp.status_code == 404
    resp = await client.post(
        f"/v1/farmers/{fid}/consents",
        json={"purpose": "marketing", "granted": True},
        headers=ctx.other_headers,
    )
    assert resp.status_code == 404
    # The phone cannot be changed through PATCH (re-verification would be needed).
    resp = await client.patch(
        f"/v1/farmers/{fid}", json={"phone": "+919000199009"}, headers=ctx.headers
    )
    assert resp.status_code == 422
    # Version check: a stale version is a 409 conflict.
    resp = await client.patch(
        f"/v1/farmers/{fid}", json={"name": "Stale", "version": 1}, headers=ctx.headers
    )
    assert resp.status_code == 409 and resp.json()["code"] == "version_conflict"


async def test_farm_and_crop_plot_lifecycle(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    farmer = await _create(client, ctx, ctx.farmer())
    fid = farmer["id"]
    resp = await client.post(
        f"/v1/farmers/{fid}/farms", json=ctx.farm(plots=1), headers=ctx.headers
    )
    assert resp.status_code == 201, resp.text
    farm = resp.json()
    assert farm["farmer_id"] == fid and len(farm["crop_plots"]) == 1 and farm["warnings"] == []

    resp = await client.patch(
        f"/v1/farms/{farm['id']}", json={"name": "Renamed", "soil": "red"}, headers=ctx.headers
    )
    assert resp.status_code == 200 and resp.json()["name"] == "Renamed"
    assert resp.json()["soil"] == "red" and resp.json()["version"] == 2
    resp = await client.patch(
        f"/v1/farms/{farm['id']}",
        json={"boundary": bowtie(BASE_LON, BASE_LAT, 1.0)},
        headers=ctx.headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "farm_boundary_invalid"
    resp = await client.patch(
        f"/v1/farms/{farm['id']}",
        json={"boundary": square(BASE_LON, BASE_LAT, 1.0), "area_acres": "3.0"},
        headers=ctx.headers,
    )
    assert resp.status_code == 200 and resp.json()["warnings"] == ["area_mismatch"]

    resp = await client.post(
        f"/v1/farms/{farm['id']}/crop-plots", json=ctx.plot(1, season="rabi"), headers=ctx.headers
    )
    assert resp.status_code == 201, resp.text
    plot = resp.json()
    assert plot["season"] == "rabi" and plot["farm_id"] == farm["id"]
    resp = await client.patch(
        f"/v1/crop-plots/{plot['id']}", json={"stage": "vegetative"}, headers=ctx.headers
    )
    assert resp.status_code == 200 and resp.json()["stage"] == "vegetative"
    resp = await client.post(
        f"/v1/farms/{farm['id']}/crop-plots",
        json=ctx.plot(0, crop_id=str(uuid.uuid4())),
        headers=ctx.headers,
    )
    assert resp.status_code == 404  # unknown crop
    resp = await client.post(
        f"/v1/farms/{farm['id']}/crop-plots",
        json=ctx.plot(0, season="monsoon"),
        headers=ctx.headers,
    )
    assert resp.status_code == 422

    # Soft deletes: hidden from the 360, row kept with deleted_at.
    resp = await client.delete(f"/v1/crop-plots/{plot['id']}", headers=ctx.headers)
    assert resp.status_code == 204
    resp = await client.delete(f"/v1/crop-plots/{plot['id']}", headers=ctx.headers)
    assert resp.status_code == 404
    resp = await client.delete(f"/v1/farms/{farm['id']}", headers=ctx.other_headers)
    assert resp.status_code == 404
    resp = await client.delete(f"/v1/farms/{farm['id']}", headers=ctx.headers)
    assert resp.status_code == 204
    resp = await client.get(f"/v1/farmers/{fid}", headers=ctx.headers)
    assert resp.status_code == 200 and resp.json()["farms"] == []
    async with tenant_scope(db_session, ctx.tenant_id):
        row = await db_session.get_one(Farm, uuid.UUID(farm["id"]))
        assert row.deleted_at is not None
        plot_row = await db_session.get_one(CropPlot, uuid.UUID(plot["id"]))
        assert plot_row.deleted_at is not None
    resp = await client.patch(f"/v1/farms/{farm['id']}", json={"name": "Gone"}, headers=ctx.headers)
    assert resp.status_code == 404


async def test_consent_grant_and_withdrawal_are_appended(
    client: AsyncClient, ctx: WriteCtx
) -> None:
    farmer = await _create(client, ctx, ctx.farmer())
    fid = farmer["id"]
    resp = await client.post(
        f"/v1/farmers/{fid}/consents",
        json={"purpose": "marketing", "granted": True},
        headers=ctx.headers,
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["purpose"] == "marketing" and resp.json()["granted_at"]
    resp = await client.post(
        f"/v1/farmers/{fid}/consents",
        json={"purpose": "marketing", "granted": False},
        headers=ctx.headers,
    )
    assert resp.status_code == 201 and resp.json()["withdrawn_at"]
    resp = await client.get(f"/v1/farmers/{fid}", headers=ctx.headers)
    body = resp.json()
    assert [(c["purpose"], c["granted_at"] is not None) for c in body["consents"]] == [
        ("data", True),
        ("marketing", True),
        ("marketing", False),
    ]
    assert body["consent_marketing"] is False


async def test_tenant_admin_and_store_manager_can_register(
    client: AsyncClient, ctx: WriteCtx, bearer: Bearer
) -> None:
    for role, phone in (
        (UserRole.TENANT_ADMIN, "+919000199004"),
        (UserRole.STORE_MANAGER, "+919000199005"),
    ):
        actor = ctx.world.a.user(role)
        resp = await client.post("/v1/farmers", json=ctx.farmer(phone=phone), headers=bearer(actor))
        assert resp.status_code == 201, resp.text
        assert resp.json()["registered_by"] == str(actor.id)
