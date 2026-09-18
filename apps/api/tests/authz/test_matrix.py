"""SEC-006: authorisation matrix generated from ``apps/api/openapi.yaml``.

Every operation in the contract carries either ``x-public: true`` or ``x-roles: [...]``
(emitted by ``farmerapp.auth.policy``). For each protected operation this module
parametrises over all ten roles and asserts that allowed roles are *not* rejected on
authorisation grounds (any status except 401/403 — business validity is the job of the
feature's own tests) and denied roles get a ``403 forbidden`` problem. It also proves that a
tenant-A token never reaches tenant-B data, that unknown or disabled users get 401, and that
forbidden calls are logged (FA-002).

Adding a route: give it a policy (or the app refuses to start), regenerate ``openapi.yaml``
and, when the route takes path parameters or a body, add a ``RouteFixture`` below.
"""

from __future__ import annotations

import json
import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pytest
import yaml
from httpx import AsyncClient, Response

from farmerapp.api.errors import PROBLEM_MEDIA_TYPE
from farmerapp.auth.models import User, UserRole, UserStatus
from tests.authz.conftest import ROLES, Bearer, SeededTenant, World

OPENAPI_PATH = Path(__file__).resolve().parents[2] / "openapi.yaml"
METHODS = ("get", "post", "put", "patch", "delete")


@dataclass(frozen=True)
class Operation:
    method: str
    path: str
    public: bool
    roles: frozenset[str]
    self_param: str | None

    @property
    def id(self) -> str:
        return f"{self.method.upper()} {self.path}"

    @property
    def has_path_params(self) -> bool:
        return "{" in self.path


def load_operations() -> list[Operation]:
    spec = yaml.safe_load(OPENAPI_PATH.read_text())
    ops: list[Operation] = []
    for path, item in spec["paths"].items():
        for method in METHODS:
            op = item.get(method)
            if op is None:
                continue
            ops.append(
                Operation(
                    method=method,
                    path=path,
                    public=bool(op.get("x-public", False)),
                    roles=frozenset(op.get("x-roles", ())),
                    self_param=op.get("x-self"),
                )
            )
    return ops


OPERATIONS = load_operations()
PROTECTED = [op for op in OPERATIONS if not op.public]
PUBLIC = [op for op in OPERATIONS if op.public]
WITH_ID = [op for op in PROTECTED if op.has_path_params]


# --------------------------------------------------------------------------- fixtures table
@dataclass(frozen=True)
class Ctx:
    """What a request is made *as* and *about*: the actor and the tenant whose data it targets."""

    actor: User
    target: SeededTenant


@dataclass(frozen=True)
class RouteFixture:
    """Minimal valid request for an operation. Defaults: no path params, no body."""

    path_params: Callable[[Ctx], dict[str, str]] = field(default=lambda _ctx: {})
    body: Callable[[Ctx], dict[str, Any] | None] = field(default=lambda _ctx: None)
    query: dict[str, str] = field(default_factory=dict)


def _target_owner_id(ctx: Ctx) -> dict[str, str]:
    return {"id": str(ctx.target.owner.id)}


ROUTE_FIXTURES: dict[str, RouteFixture] = {
    "GET /v1/users/{id}": RouteFixture(path_params=_target_owner_id),
    "PATCH /v1/users/{id}": RouteFixture(
        path_params=_target_owner_id, body=lambda _ctx: {"name": "Renamed by test"}
    ),
}


def _fixture_for(op: Operation) -> RouteFixture:
    fx = ROUTE_FIXTURES.get(op.id)
    if fx is None:
        if op.has_path_params:
            pytest.fail(f"{op.id} takes path parameters; add a RouteFixture in {__file__}")
        fx = RouteFixture()
    return fx


async def call(
    client: AsyncClient,
    op: Operation,
    ctx: Ctx,
    headers: dict[str, str] | None = None,
    *,
    path_params: dict[str, str] | None = None,
) -> Response:
    fx = _fixture_for(op)
    params = path_params if path_params is not None else fx.path_params(ctx)
    url = op.path.format(**params)
    body = fx.body(ctx)
    return await client.request(
        op.method.upper(), url, params=fx.query or None, json=body, headers=headers or {}
    )


def _assert_forbidden(resp: Response) -> None:
    assert resp.status_code == 403, resp.text
    assert resp.headers["content-type"].startswith(PROBLEM_MEDIA_TYPE)
    body = resp.json()
    assert body["code"] == "forbidden"
    assert body["status"] == 403
    assert "items" not in body


def _assert_not_rejected(resp: Response) -> None:
    assert resp.status_code not in (401, 403), f"{resp.status_code}: {resp.text}"


def _no_tenant_leak(resp: Response, other: SeededTenant) -> None:
    """Nothing of tenant B in the response (a problem ``instance`` only echoes the request path)."""
    text = resp.text
    if resp.headers.get("content-type", "").startswith(PROBLEM_MEDIA_TYPE):
        body = resp.json()
        body.pop("instance", None)
        text = json.dumps(body)
    assert str(other.tenant.id) not in text
    for user in other.users.values():
        assert str(user.id) not in text
        assert user.phone not in text


# --------------------------------------------------------------------------- contract shape
def test_contract_has_operations() -> None:
    assert PROTECTED and PUBLIC, "openapi.yaml must contain protected and public operations"


@pytest.mark.parametrize("op", OPERATIONS, ids=[op.id for op in OPERATIONS])
def test_every_operation_declares_exactly_one_policy(op: Operation) -> None:
    if op.public:
        assert not op.roles, f"{op.id} is public and must not list x-roles"
    else:
        assert op.roles, f"{op.id} has neither x-public nor x-roles"
        assert op.roles <= set(ROLES), f"{op.id} lists unknown roles {op.roles - set(ROLES)}"
    if op.self_param is not None:
        assert not op.public and op.self_param in op.path


# --------------------------------------------------------------------------- role matrix
@pytest.mark.parametrize("role", ROLES)
@pytest.mark.parametrize("op", PROTECTED, ids=[op.id for op in PROTECTED])
async def test_role_matrix(
    client: AsyncClient, world: World, bearer: Bearer, op: Operation, role: str
) -> None:
    actor = world.a.user(role)
    ctx = Ctx(actor=actor, target=world.a)
    resp = await call(client, op, ctx, bearer(actor))
    if role in op.roles:
        _assert_not_rejected(resp)
    else:
        _assert_forbidden(resp)


SELF_OPS = [op for op in PROTECTED if op.self_param]


@pytest.mark.parametrize("role", ROLES)
@pytest.mark.parametrize("op", SELF_OPS, ids=[op.id for op in SELF_OPS])
async def test_self_access_is_allowed_for_every_role(
    client: AsyncClient, world: World, bearer: Bearer, op: Operation, role: str
) -> None:
    """``x-self`` operations: any authenticated user may address their own record."""
    actor = world.a.user(role)
    assert op.self_param is not None
    resp = await call(
        client,
        op,
        Ctx(actor=actor, target=world.a),
        bearer(actor),
        path_params={op.self_param: str(actor.id)},
    )
    assert resp.status_code < 300, resp.text
    assert resp.json()["id"] == str(actor.id)


# --------------------------------------------------------------------------- cross tenant
def _an_allowed_actor(world: World, op: Operation) -> User:
    role = UserRole.OWNER if UserRole.OWNER.value in op.roles else UserRole(sorted(op.roles)[0])
    return world.a.user(role)


@pytest.mark.parametrize("op", WITH_ID, ids=[op.id for op in WITH_ID])
async def test_cross_tenant_id_is_not_found(
    client: AsyncClient, world: World, bearer: Bearer, op: Operation
) -> None:
    """A tenant-A token addressing a tenant-B resource id gets 404 or 403, never data."""
    actor = _an_allowed_actor(world, op)
    resp = await call(client, op, Ctx(actor=actor, target=world.b), bearer(actor))
    assert resp.status_code in (403, 404), resp.text
    _no_tenant_leak(resp, world.b)


LISTS = [op for op in PROTECTED if op.method == "get" and not op.has_path_params]


@pytest.mark.parametrize("op", LISTS, ids=[op.id for op in LISTS])
async def test_collections_never_contain_other_tenants(
    client: AsyncClient, world: World, bearer: Bearer, op: Operation
) -> None:
    actor = _an_allowed_actor(world, op)
    resp = await call(client, op, Ctx(actor=actor, target=world.a), bearer(actor))
    _assert_not_rejected(resp)
    _no_tenant_leak(resp, world.b)
    body = resp.json()
    for item in body.get("items", []):
        assert item.get("tenant_id", str(world.a.tenant.id)) == str(world.a.tenant.id)


# --------------------------------------------------------------------------- authentication
@pytest.mark.parametrize("op", PROTECTED, ids=[op.id for op in PROTECTED])
async def test_protected_operation_without_token(
    client: AsyncClient, world: World, op: Operation
) -> None:
    resp = await call(client, op, Ctx(actor=world.a.owner, target=world.a))
    assert resp.status_code == 401, resp.text
    assert resp.json()["code"] == "unauthenticated"
    assert resp.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize("op", PUBLIC, ids=[op.id for op in PUBLIC])
async def test_public_operation_needs_no_token(
    client: AsyncClient, world: World, op: Operation
) -> None:
    resp = await call(client, op, Ctx(actor=world.a.owner, target=world.a))
    _assert_not_rejected(resp)


async def test_unknown_user_token_is_401(client: AsyncClient, world: World, bearer: Bearer) -> None:
    import uuid

    ghost = User(
        id=uuid.uuid4(),
        tenant_id=world.a.tenant.id,
        phone="+919999999999",
        name="Ghost",
        role=UserRole.OWNER,
    )
    resp = await client.get("/v1/me", headers=bearer(ghost))
    assert resp.status_code == 401
    assert resp.json()["code"] == "unauthenticated"


async def test_disabled_user_token_is_401(
    client: AsyncClient, world: World, bearer: Bearer, db_session: Any
) -> None:
    owner = world.a.owner
    headers = bearer(owner)
    owner.status = UserStatus.DISABLED
    await db_session.flush()
    resp = await client.get("/v1/users", headers=headers)
    assert resp.status_code == 401, resp.text
    assert resp.json()["code"] == "user_disabled"
    assert resp.headers["www-authenticate"] == "Bearer"


# --------------------------------------------------------------------------- logging
async def test_forbidden_call_is_logged_without_pii(
    client: AsyncClient, world: World, bearer: Bearer, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.WARNING, logger="farmerapp.auth.policy")
    officer = world.a.user(UserRole.FIELD_OFFICER)
    resp = await client.get("/v1/users", headers=bearer(officer))
    _assert_forbidden(resp)

    records = [r for r in caplog.records if r.name == "farmerapp.auth.policy"]
    assert len(records) == 1, [r.msg for r in records]
    record = records[0]
    assert record.levelno == logging.WARNING
    event = record.msg if isinstance(record.msg, dict) else {"event": record.getMessage()}
    assert event["event"] == "authz_forbidden"
    assert event["actor_id"] == str(officer.id)
    assert event["role"] == "field_officer"
    assert event["tenant_id"] == str(officer.tenant_id)
    assert event["method"] == "GET"
    assert event["route"] == "/v1/users"
    text = str(record.msg)
    assert officer.phone not in text
    assert officer.name not in text
