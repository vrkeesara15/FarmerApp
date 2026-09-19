"""WC-011: create users, change roles / status / assignment, guard rails, audit."""

from __future__ import annotations

import uuid

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.db.geo import point_wkt
from farmerapp.db.models import Tenant
from farmerapp.tenants.models import Store
from tests.admin.conftest import Mint, audit_rows, problem


async def test_create_user(
    client: AsyncClient,
    tenant: Tenant,
    tenant_admin: User,
    admin_headers: Mint,
    db_session: AsyncSession,
) -> None:
    tenant.settings = {**tenant.settings, "default_language": "te"}
    await db_session.flush()
    resp = await client.post(
        "/v1/users",
        json={"phone": "98765 43210", "name": "Lakshmi", "role": "field_officer"},
        headers=admin_headers(tenant_admin),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["phone"] == "+919876543210" and body["role"] == "field_officer"
    assert body["language"] == "te" and body["status"] == "active"
    created = await db_session.get(User, uuid.UUID(body["id"]))
    assert created is not None and created.tenant_id == tenant.id

    rows = [
        r for r in await audit_rows(db_session, action="user.create") if r.entity_id == created.id
    ]
    assert len(rows) == 1
    assert rows[0].actor_id == tenant_admin.id
    assert rows[0].after is not None and rows[0].after["phone"] != "+919876543210"  # masked

    # the phone is taken now
    resp = await client.post(
        "/v1/users",
        json={"phone": "+919876543210", "name": "Again", "role": "agronomist"},
        headers=admin_headers(tenant_admin),
    )
    problem(resp, 409, "phone_taken")


async def test_create_user_with_store_and_explicit_language(
    client: AsyncClient, tenant: Tenant, owner: User, admin_headers: Mint, db_session: AsyncSession
) -> None:
    store = Store(
        tenant_id=tenant.id,
        code="WGL",
        name="Warangal",
        district="Warangal",
        location=point_wkt(79.5, 18.0),
    )
    db_session.add(store)
    await db_session.flush()
    resp = await client.post(
        "/v1/users",
        json={
            "phone": "+919876500001",
            "name": "Store Lead",
            "role": "store_manager",
            "store_id": str(store.id),
            "language": "hi",
        },
        headers=admin_headers(owner),
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["store_id"] == str(store.id) and resp.json()["language"] == "hi"

    for field in ("store_id", "cluster_id"):
        resp = await client.post(
            "/v1/users",
            json={
                "phone": "+919876500002",
                "name": "X",
                "role": "cluster_head",
                field: str(uuid.uuid4()),
            },
            headers=admin_headers(owner),
        )
        assert problem(resp, 422, "invalid_assignment")["field"] == field


async def test_farmers_are_not_created_here(
    client: AsyncClient, owner: User, admin_headers: Mint
) -> None:
    resp = await client.post(
        "/v1/users",
        json={"phone": "+919876500003", "name": "Farmer", "role": "farmer"},
        headers=admin_headers(owner),
    )
    assert resp.status_code == 422


async def test_only_an_owner_grants_the_owner_role(
    client: AsyncClient,
    owner: User,
    director: User,
    tenant_admin: User,
    officer: User,
    admin_headers: Mint,
) -> None:
    body = {"phone": "+919876500004", "name": "Co-owner", "role": "owner"}
    for actor in (director, tenant_admin):
        problem(
            await client.post("/v1/users", json=body, headers=admin_headers(actor)),
            403,
            "role_not_grantable",
        )
        resp = await client.patch(
            f"/v1/users/{officer.id}", json={"role": "owner"}, headers=admin_headers(actor)
        )
        problem(resp, 403, "role_not_grantable")
        resp = await client.patch(
            f"/v1/users/{owner.id}", json={"status": "disabled"}, headers=admin_headers(actor)
        )
        problem(resp, 403, "role_not_grantable")
        resp = await client.post(f"/v1/users/{owner.id}/deactivate", headers=admin_headers(actor))
        problem(resp, 403, "role_not_grantable")
    resp = await client.post("/v1/users", json=body, headers=admin_headers(owner))
    assert resp.status_code == 201, resp.text


async def test_nobody_changes_their_own_role_or_status(
    client: AsyncClient, owner: User, tenant_admin: User, admin_headers: Mint
) -> None:
    for actor, change in ((tenant_admin, {"role": "owner"}), (owner, {"status": "disabled"})):
        resp = await client.patch(
            f"/v1/users/{actor.id}", json=change, headers=admin_headers(actor)
        )
        problem(resp, 403, "cannot_modify_self")
    resp = await client.post(f"/v1/users/{owner.id}/deactivate", headers=admin_headers(owner))
    problem(resp, 403, "cannot_modify_self")


async def test_role_change_takes_effect_on_the_next_request(
    client: AsyncClient,
    officer: User,
    owner: User,
    admin_headers: Mint,
    bearer: Mint,
    db_session: AsyncSession,
) -> None:
    before = bearer(officer)
    assert (await client.get("/v1/users", headers=before)).status_code == 403
    resp = await client.patch(
        f"/v1/users/{officer.id}", json={"role": "auditor"}, headers=admin_headers(owner)
    )
    assert resp.status_code == 200, resp.text
    # roles are read from the user row, not the token claim
    assert (await client.get("/v1/users", headers=before)).status_code == 200
    row = (await audit_rows(db_session, action="user.update"))[-1]
    assert row.before == {"id": str(officer.id), "role": "field_officer"}
    assert row.after == {"id": str(officer.id), "role": "auditor"}


async def test_reenabling_keeps_old_tokens_dead(
    client: AsyncClient, officer: User, owner: User, admin_headers: Mint, bearer: Mint
) -> None:
    old = bearer(officer)
    for status in ("disabled", "active"):
        resp = await client.patch(
            f"/v1/users/{officer.id}", json={"status": status}, headers=admin_headers(owner)
        )
        assert resp.status_code == 200, resp.text
    problem(await client.get("/v1/me", headers=old), 401, "session_revoked")


async def test_cross_tenant_user_is_not_found(
    client: AsyncClient, owner: User, admin_headers: Mint, db_session: AsyncSession
) -> None:
    from farmerapp.db.session import set_tenant

    other = Tenant(id=uuid.uuid4(), name="Other", slug="other-admin")
    await set_tenant(db_session, other.id)
    db_session.add(other)
    await db_session.flush()
    stranger = User(tenant_id=other.id, phone="+919111111111", name="S", role="field_officer")
    db_session.add(stranger)
    await db_session.flush()
    await set_tenant(db_session, owner.tenant_id)
    resp = await client.post(f"/v1/users/{stranger.id}/force-logout", headers=admin_headers(owner))
    problem(resp, 404, "not_found")
    assert (await db_session.execute(select(User.id).where(User.id == stranger.id))).first() is None
