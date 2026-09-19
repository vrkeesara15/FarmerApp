"""SEC-028 re-authentication before admin actions ("step-up").

Role and status changes, user creation, forced logout, device binding and lost reports,
settings changes and exports need a fresh OTP on top of the session:

1. ``POST /v1/auth/step-up/send`` sends a code to the caller's own phone (OTP purpose
   ``step_up``; the FA-001 machinery: hashed, 5 min, lockout, resend limits).
2. ``POST /v1/auth/step-up`` with the code returns a **step-up token** valid for
   ``step_up_token_ttl_seconds`` (5 min): an HS256 JWT with ``typ=step_up`` bound to the
   user and tenant. It is never accepted as an access token (and vice versa).
3. The client sends it as ``X-Step-Up-Token`` with the protected request. Without a valid one
   the route answers 401 ``step_up_required`` (after the role check, so other roles still get
   403 ``forbidden``). The token may be reused for further admin actions until it expires.

Protected operations carry ``x-step-up: true`` in the OpenAPI contract.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated, Any

import jwt
from fastapi import Depends, Request

from farmerapp.auth.deps import AuthServices, get_auth_services, get_current_user
from farmerapp.auth.errors import StepUpRequiredError
from farmerapp.auth.models import User
from farmerapp.settings import Settings

STEP_UP_HEADER = "X-Step-Up-Token"
STEP_UP_TYPE = "step_up"
#: ``openapi_extra`` for protected routes (the console reads it to prompt for the OTP).
STEP_UP_OPENAPI: dict[str, Any] = {"x-step-up": True}


def issue_step_up_token(settings: Settings, user: User, now: datetime) -> str:
    claims = {
        "iss": settings.jwt_issuer,
        "sub": str(user.id),
        "tid": str(user.tenant_id),
        "typ": STEP_UP_TYPE,
        "iat": int(now.timestamp()),
        "exp": int(now.timestamp()) + settings.step_up_token_ttl_seconds,
        "jti": uuid.uuid4().hex,
    }
    return jwt.encode(claims, settings.jwt_signing_key, algorithm=settings.jwt_algorithm)


def verify_step_up_token(settings: Settings, token: str, user: User, now: datetime) -> bool:
    try:
        claims: dict[str, Any] = jwt.decode(
            token,
            settings.jwt_signing_key,
            algorithms=[settings.jwt_algorithm],
            issuer=settings.jwt_issuer,
            options={"verify_exp": False, "verify_iat": False, "require": ["sub", "exp", "tid"]},
        )
    except jwt.PyJWTError:
        return False
    exp = claims.get("exp")
    return (
        claims.get("typ") == STEP_UP_TYPE
        and claims.get("sub") == str(user.id)
        and claims.get("tid") == str(user.tenant_id)
        and isinstance(exp, int)
        and exp > int(now.timestamp())
    )


def check_step_up(request: Request, services: AuthServices, user: User) -> None:
    """Raise 401 ``step_up_required`` unless the request carries a valid step-up token."""
    token = request.headers.get(STEP_UP_HEADER, "").strip()
    if not token or not verify_step_up_token(services.settings, token, user, services.clock.now()):
        raise StepUpRequiredError(
            "Confirm it is you: enter the code sent to your phone.",
            extra={"step_up_url": "/v1/auth/step-up/send"},
        )


async def _require_step_up(
    request: Request,
    services: Annotated[AuthServices, Depends(get_auth_services)],
    user: Annotated[User, Depends(get_current_user)],
) -> None:
    check_step_up(request, services, user)


#: Route parameter: ``_step_up: StepUp`` declared *after* the ``require_roles`` actor.
StepUp = Annotated[None, Depends(_require_step_up)]

__all__ = [
    "STEP_UP_HEADER",
    "STEP_UP_OPENAPI",
    "StepUp",
    "check_step_up",
    "issue_step_up_token",
    "verify_step_up_token",
]
