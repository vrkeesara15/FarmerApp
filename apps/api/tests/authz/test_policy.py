"""FA-002 policy registry: every route declares a policy; the contract documents it."""

from __future__ import annotations

from typing import Annotated

import pytest
from fastapi import FastAPI
from fastapi.routing import APIRoute

from farmerapp.auth.models import User
from farmerapp.auth.policy import (
    PUBLIC,
    Policy,
    Role,
    install_policies,
    iter_api_routes,
    policy_of,
    require_roles,
)


def test_role_enum_has_the_ten_fa002_roles() -> None:
    assert [r.value for r in Role] == [
        "owner",
        "director",
        "cluster_head",
        "auditor",
        "store_manager",
        "accountant",
        "field_officer",
        "agronomist",
        "tenant_admin",
        "farmer",
    ]


def test_require_roles_needs_at_least_one_role() -> None:
    with pytest.raises(ValueError, match="at least one role"):
        require_roles()


def _sample_app() -> FastAPI:
    app = FastAPI()

    @app.get("/v1/open", dependencies=[PUBLIC])
    async def open_route() -> dict[str, str]:
        return {"ok": "open"}

    @app.get("/v1/closed")
    async def closed_route(
        actor: Annotated[User, require_roles(Role.OWNER, Role.DIRECTOR)],
    ) -> dict[str, str]:
        return {"ok": actor.role}

    @app.patch("/v1/things/{id}", responses={403: {"description": "`thing_locked`"}})
    async def thing_route(
        id: str, actor: Annotated[User, require_roles(Role.OWNER, self_param="id")]
    ) -> dict[str, str]:
        return {"ok": id}

    return app


def _route(app: FastAPI, path: str) -> APIRoute:
    for full_path, route in iter_api_routes(app):
        if full_path == path:
            return route
    raise AssertionError(path)


def test_policy_of_reads_the_route_dependency() -> None:
    app = _sample_app()
    assert policy_of(_route(app, "/v1/open")) == Policy(roles=frozenset(), public=True)
    closed = policy_of(_route(app, "/v1/closed"))
    assert closed == Policy(roles=frozenset({Role.OWNER, Role.DIRECTOR}))
    thing = policy_of(_route(app, "/v1/things/{id}"))
    assert thing is not None and thing.self_param == "id"


def test_install_policies_annotates_openapi() -> None:
    app = _sample_app()
    registry = install_policies(app)
    assert set(registry) == {
        ("GET", "/v1/open"),
        ("GET", "/v1/closed"),
        ("PATCH", "/v1/things/{id}"),
    }
    install_policies(app)  # idempotent: no duplicated response codes or hooks

    schema = app.openapi()
    open_op = schema["paths"]["/v1/open"]["get"]
    assert open_op["x-public"] is True
    assert "x-roles" not in open_op and "403" not in open_op["responses"]

    closed_op = schema["paths"]["/v1/closed"]["get"]
    assert closed_op["x-roles"] == ["director", "owner"]
    assert "x-public" not in closed_op and "x-self" not in closed_op
    assert "`forbidden`" in closed_op["responses"]["403"]["description"]
    assert closed_op["responses"]["403"]["description"].count("`forbidden`") == 1
    assert "`unauthenticated`" in closed_op["responses"]["401"]["description"]
    assert "`user_disabled`" in closed_op["responses"]["401"]["description"]

    thing_op = schema["paths"]["/v1/things/{id}"]["patch"]
    assert thing_op["x-roles"] == ["owner"] and thing_op["x-self"] == "id"
    # existing 403 documentation is kept and extended, not replaced
    assert "`thing_locked`" in thing_op["responses"]["403"]["description"]
    assert "`forbidden`" in thing_op["responses"]["403"]["description"]


def test_route_without_policy_fails_startup() -> None:
    app = FastAPI()

    @app.get("/v1/things")
    async def things() -> None:
        return None

    @app.post("/v1/other", dependencies=[PUBLIC])
    async def other() -> None:
        return None

    with pytest.raises(RuntimeError, match=r"GET /v1/things") as excinfo:
        install_policies(app)
    assert "/v1/other" not in str(excinfo.value)


def test_conflicting_policies_are_rejected() -> None:
    app = FastAPI()

    @app.get("/v1/confused", dependencies=[PUBLIC, require_roles(Role.OWNER)])
    async def confused() -> None:
        return None

    with pytest.raises(RuntimeError, match="conflicting"):
        install_policies(app)


def test_policy_allows() -> None:
    owner = User(role=Role.OWNER)
    officer = User(role=Role.FIELD_OFFICER, id=None)
    policy = Policy(roles=frozenset({Role.OWNER}), self_param="id")
    assert policy.allows(owner, {})
    assert not policy.allows(officer, {"id": "other"})
    import uuid

    officer.id = uuid.uuid4()
    assert policy.allows(officer, {"id": str(officer.id)})
    assert not Policy(roles=frozenset({Role.OWNER})).allows(officer, {"id": str(officer.id)})


def test_real_app_has_a_policy_on_every_route(app: FastAPI) -> None:
    routes = list(iter_api_routes(app))
    assert len(routes) >= 6  # health, 4 auth, me, users...
    missing = [f"{sorted(r.methods or ())} {path}" for path, r in routes if policy_of(r) is None]
    assert missing == []
    assert set(app.state.policies) == {(m, path) for path, r in routes for m in (r.methods or ())}
