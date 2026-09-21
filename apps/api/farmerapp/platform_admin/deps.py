"""The guard on every WC-014 route: ``platform_admin``, and in the platform tenant.

Two conditions, not one. The role alone would be enough for FastAPI, but a role is a string
in a row that tenant administration itself can write, so the dependency also insists the
caller lives in the platform tenant — a tenant admin who contrived to set
``role = 'platform_admin'`` on one of their own users still gets 403, because their tenant is
not the platform tenant. ``tests/platform/test_authz.py`` proves both halves.

The dependency tags itself with the route policy (``x-roles: [platform_admin]``) so
``install_policies`` and the SEC-006 matrix see it like any other route, and adds
``x-platform: true`` to the operation so the matrix knows to skip its cross-tenant assertions:
these routes are cross-tenant *by design*, and that is the one exception in the contract.
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import Depends, Request

from farmerapp.api.errors import ForbiddenError
from farmerapp.auth.deps import get_current_user
from farmerapp.auth.models import User
from farmerapp.auth.policy import Policy, Role, route_template, tag_policy
from farmerapp.logging import get_logger
from farmerapp.platform_admin.models import PLATFORM_TENANT_ID

log = get_logger("farmerapp.platform_admin.authz")

PLATFORM_POLICY = Policy(roles=frozenset({Role.PLATFORM_ADMIN}))

#: ``openapi_extra`` for every platform route (see the module docstring).
PLATFORM_OPENAPI: dict[str, Any] = {"x-platform": True}


async def _platform_admin(
    request: Request, user: Annotated[User, Depends(get_current_user)]
) -> User:
    if Role(user.role) is Role.PLATFORM_ADMIN and user.tenant_id == PLATFORM_TENANT_ID:
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


tag_policy(_platform_admin, PLATFORM_POLICY)

#: ``actor: PlatformAdmin`` on a route.
PlatformAdmin = Annotated[User, Depends(_platform_admin)]

__all__ = ["PLATFORM_OPENAPI", "PLATFORM_POLICY", "PlatformAdmin"]
