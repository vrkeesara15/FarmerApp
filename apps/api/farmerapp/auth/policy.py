"""Declarative route authorisation (FA-002).

Every route declares exactly one policy through its dependencies:

* ``require_roles(Role.OWNER, Role.DIRECTOR)`` — a dependency that authenticates the caller
  (``get_current_user``) and returns the ``User`` when its role is listed. Anything else is a
  ``403 forbidden`` problem, logged at WARNING with actor id, role, tenant and route (never
  phone or name). ``self_param="id"`` additionally lets any authenticated user address their
  own record (the path parameter equals the caller's id).
* ``PUBLIC`` — a marker for routes that need no bearer token (health, OTP login, refresh).

``install_policies(app)`` runs at startup: it refuses to start when a route has no policy
(or has conflicting ones), keeps the registry on ``app.state.policies`` and writes it into
the OpenAPI document as ``x-roles`` / ``x-public`` / ``x-self`` so the SEC-006 matrix
(``tests/authz/test_matrix.py``) is generated from the same source of truth.
"""

from __future__ import annotations

from collections.abc import Callable, Iterator, Mapping
from dataclasses import dataclass
from typing import Annotated, Any

from fastapi import Depends, FastAPI, Request
from fastapi.routing import APIRoute, iter_route_contexts

from farmerapp.api.errors import PROBLEM_MEDIA_TYPE, ForbiddenError
from farmerapp.auth.deps import get_current_user
from farmerapp.auth.models import User
from farmerapp.auth.models import UserRole as Role
from farmerapp.logging import get_logger

log = get_logger("farmerapp.auth.policy")

_POLICY_ATTR = "__farmerapp_policy__"
_OPENAPI_HOOK_ATTR = "__farmerapp_policy_openapi__"

# Problem codes every protected route can answer with, documented once here.
_AUTHN_CODES = ("unauthenticated", "token_expired", "user_disabled")
_AUTHZ_CODES = ("forbidden",)

#: ``(METHOD, full path)`` -> policy, e.g. ``("GET", "/v1/users/{id}")``.
PolicyRegistry = dict[tuple[str, str], "Policy"]


@dataclass(frozen=True)
class Policy:
    """Who may call a route. ``roles`` is empty only for public routes."""

    roles: frozenset[Role]
    public: bool = False
    self_param: str | None = None

    def allows(self, user: User, path_params: Mapping[str, Any]) -> bool:
        if self.public or Role(user.role) in self.roles:
            return True
        if self.self_param is not None and user.id is not None:
            return str(path_params.get(self.self_param)) == str(user.id)
        return False

    def openapi(self) -> dict[str, Any]:
        if self.public:
            return {"x-public": True}
        out: dict[str, Any] = {"x-roles": sorted(r.value for r in self.roles)}
        if self.self_param is not None:
            out["x-self"] = self.self_param
        return out


def _tag(fn: Callable[..., Any], policy: Policy) -> Callable[..., Any]:
    setattr(fn, _POLICY_ATTR, policy)
    return fn


async def _public() -> None:
    return None


PUBLIC_POLICY = Policy(roles=frozenset(), public=True)
_tag(_public, PUBLIC_POLICY)

#: Route marker: ``@router.get("/health", dependencies=[PUBLIC])``.
PUBLIC: Any = Depends(_public)


def iter_api_routes(app: FastAPI) -> Iterator[tuple[str, APIRoute]]:
    """Every ``APIRoute`` of the app with its full path (nested routers flattened)."""
    for ctx in iter_route_contexts(app.routes):
        route = ctx.original_route
        if isinstance(route, APIRoute):
            yield ctx.path or route.path, route


def route_template(request: Request) -> str:
    """The matched route's path template (``/v1/users/{id}``), else the concrete path."""
    endpoint = request.scope.get("endpoint")
    for path, route in iter_api_routes(request.app):
        if route.endpoint is endpoint:
            return path
    return str(request.url.path)


def require_roles(*roles: Role, self_param: str | None = None) -> Any:
    """Dependency: the authenticated ``User`` when their role is allowed, else 403 ``forbidden``.

    Use as ``actor: Annotated[User, require_roles(Role.OWNER)]`` (returns the user) or in a
    route's ``dependencies=[...]`` list.
    """
    if not roles:
        raise ValueError("require_roles needs at least one role (use PUBLIC for open routes)")
    policy = Policy(roles=frozenset(roles), self_param=self_param)

    async def _check(request: Request, user: Annotated[User, Depends(get_current_user)]) -> User:
        if policy.allows(user, request.path_params):
            return user
        log.warning(
            "authz_forbidden",
            actor_id=str(user.id),
            role=user.role,
            tenant_id=str(user.tenant_id),
            method=request.method,
            route=route_template(request),
        )
        raise ForbiddenError("Your role does not allow this action.")

    _tag(_check, policy)
    return Depends(_check)


def policy_of(route: APIRoute) -> Policy | None:
    """The policy declared on a route (top-level dependencies only). ``None`` if missing."""
    found: list[Policy] = []
    for dep in route.dependant.dependencies:
        policy = getattr(dep.call, _POLICY_ATTR, None)
        if isinstance(policy, Policy) and policy not in found:
            found.append(policy)
    if len(found) > 1:
        methods = ",".join(sorted(route.methods or ()))
        raise RuntimeError(f"{methods} {route.path} declares conflicting policies: {found}")
    return found[0] if found else None


def _merge_problem(responses: dict[str, Any], status: int, codes: tuple[str, ...]) -> None:
    entry = responses.setdefault(str(status), {"description": ""})
    entry.setdefault("content", {PROBLEM_MEDIA_TYPE: {}})
    parts = [p for p in str(entry.get("description", "")).split(", ") if p]
    parts.extend(f"`{c}`" for c in codes if f"`{c}`" not in parts)
    entry["description"] = ", ".join(parts)


def annotate_openapi(schema: dict[str, Any], registry: PolicyRegistry) -> dict[str, Any]:
    """Write ``x-roles`` / ``x-public`` / ``x-self`` and the 401/403 problems into operations."""
    paths = schema.get("paths", {})
    for (method, path), policy in registry.items():
        operation = paths.get(path, {}).get(method.lower())
        if operation is None:
            continue  # include_in_schema=False
        operation.update(policy.openapi())
        if not policy.public:
            responses = operation.setdefault("responses", {})
            _merge_problem(responses, 401, _AUTHN_CODES)
            _merge_problem(responses, 403, _AUTHZ_CODES)
    return schema


def _install_openapi_hook(app: FastAPI) -> None:
    if getattr(app.state, _OPENAPI_HOOK_ATTR, False):
        return
    original = app.openapi

    def with_policies() -> dict[str, Any]:
        registry: PolicyRegistry = app.state.policies
        return annotate_openapi(original(), registry)

    app.openapi = with_policies  # type: ignore[method-assign]
    setattr(app.state, _OPENAPI_HOOK_ATTR, True)


def install_policies(app: FastAPI) -> PolicyRegistry:
    """Startup check: every API route has a policy; the contract documents it. Idempotent."""
    registry: PolicyRegistry = {}
    missing: list[str] = []
    for path, route in iter_api_routes(app):
        policy = policy_of(route)
        if policy is None:
            missing.append(f"{','.join(sorted(route.methods or ()))} {path}")
            continue
        for method in route.methods or ():
            registry[(method.upper(), path)] = policy
    if missing:
        raise RuntimeError(
            "Routes without a role policy (add require_roles(...) or PUBLIC): " + "; ".join(missing)
        )
    app.state.policies = registry
    _install_openapi_hook(app)
    return registry


__all__ = [
    "PUBLIC",
    "PUBLIC_POLICY",
    "Policy",
    "PolicyRegistry",
    "Role",
    "annotate_openapi",
    "install_policies",
    "iter_api_routes",
    "policy_of",
    "require_roles",
    "route_template",
]
