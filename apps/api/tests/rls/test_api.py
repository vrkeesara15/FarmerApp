"""API-level proof (FA-003): a tenant-A token never reaches tenant-B data."""

from __future__ import annotations

import json
import uuid
from typing import Any

import jwt
from httpx import AsyncClient, Response
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.settings import get_settings
from tests.authz.conftest import Bearer, World


def _no_leak(resp: Response, world: World) -> None:
    """Nothing of tenant B in the response (a problem ``instance`` only echoes the path)."""
    payload = resp.json()
    if isinstance(payload, dict):
        payload.pop("instance", None)
    body = json.dumps(payload)
    for user in world.b.users.values():
        assert str(user.id) not in body and user.phone not in body and user.name not in body
    assert str(world.b.tenant.id) not in body


async def test_get_other_tenant_user_is_404(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    resp = await client.get(f"/v1/users/{world.b.owner.id}", headers=bearer(world.a.owner))
    assert resp.status_code == 404 and resp.json()["code"] == "not_found"
    _no_leak(resp, world)


async def test_patch_other_tenant_user_is_404_and_unchanged(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    resp = await client.patch(
        f"/v1/users/{world.b.owner.id}",
        json={"name": "Pwned", "role": "farmer", "status": "disabled"},
        headers=bearer(world.a.owner),
    )
    assert resp.status_code == 404
    _no_leak(resp, world)
    # Read back as tenant B (through the API, hence through RLS): nothing changed.
    resp = await client.get(f"/v1/users/{world.b.owner.id}", headers=bearer(world.b.owner))
    assert resp.status_code == 200
    assert resp.json()["name"] == world.b.owner.name and resp.json()["role"] == "owner"


async def test_list_never_includes_other_tenant(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    for tenant, other in ((world.a, world.b), (world.b, world.a)):
        resp = await client.get("/v1/users", params={"limit": "200"}, headers=bearer(tenant.owner))
        assert resp.status_code == 200
        body: dict[str, Any] = resp.json()
        ids = {item["id"] for item in body["items"]}
        assert ids == {str(u.id) for u in tenant.everyone}
        assert not ids & {str(u.id) for u in other.everyone}
        assert {item["tenant_id"] for item in body["items"]} == {str(tenant.tenant.id)}


async def test_request_binds_the_tokens_tenant_on_the_session(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    """After a request as A, an unfiltered ORM query on the request session only sees A."""
    resp = await client.get("/v1/me", headers=bearer(world.a.owner))
    assert resp.status_code == 200
    bound = await db_session.scalar(text("SELECT current_setting('app.tenant_id', true)"))
    assert bound == str(world.a.tenant.id)
    users = (await db_session.execute(select(User))).scalars().all()
    assert {u.tenant_id for u in users} == {world.a.tenant.id}


def _forged(user: User, *, tid: uuid.UUID, sub: uuid.UUID | None = None) -> dict[str, str]:
    """A correctly signed token whose tenant claim does not match the user's tenant."""
    settings = get_settings()
    claims = {
        "iss": settings.jwt_issuer,
        "sub": str(sub or user.id),
        "tid": str(tid),
        "role": user.role,
        "typ": "access",
        "iat": 1_000_000_000,
        "exp": 4_000_000_000,
        "jti": uuid.uuid4().hex,
    }
    token = jwt.encode(claims, settings.jwt_signing_key, algorithm=settings.jwt_algorithm)
    return {"Authorization": f"Bearer {token}"}


async def test_token_with_mismatched_tenant_claim_is_401(client: AsyncClient, world: World) -> None:
    """A tenant-B ``tid`` on a tenant-A user id: RLS hides the user, so the caller is nobody."""
    headers = _forged(world.a.owner, tid=world.b.tenant.id)
    for path in ("/v1/me", "/v1/users", f"/v1/users/{world.b.owner.id}"):
        resp = await client.get(path, headers=headers)
        assert resp.status_code == 401, path
        assert resp.json()["code"] == "unauthenticated"
        _no_leak(resp, world)


async def test_token_with_unknown_tenant_claim_is_401(client: AsyncClient, world: World) -> None:
    resp = await client.get("/v1/me", headers=_forged(world.a.owner, tid=uuid.uuid4()))
    assert resp.status_code == 401


async def test_token_naming_a_tenant_b_user_with_tenant_a_claim_is_401(
    client: AsyncClient, world: World
) -> None:
    headers = _forged(world.b.owner, tid=world.a.tenant.id, sub=world.b.owner.id)
    resp = await client.get("/v1/me", headers=headers)
    assert resp.status_code == 401
    _no_leak(resp, world)
