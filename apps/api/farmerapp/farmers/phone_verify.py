"""Farmer phone verification (FA-012, VA-F01) on top of the FA-001 OTP machinery.

The officer's app asks for a code to the *farmer's* phone (``purpose = farmer_register``,
same TTL, attempt lockout and resend limits as login), confirms it and receives a
``phone_verification_token``: an HS256 JWT (``typ = phone_verification``) bound to the
tenant and phone, valid 30 minutes, that ``POST /v1/farmers`` or a sync ``farmer.create``
op presents so the row is created with ``phone_verified = true``. Without it the farmer is
registered unverified (offline capture) and verified later on the record.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

import jwt

from farmerapp.auth.models import OtpPurpose
from farmerapp.farmers.errors import PhoneVerificationInvalidError
from farmerapp.settings import Settings

JWT_TYP = "phone_verification"  # the JWT `typ` label
PURPOSE = OtpPurpose.FARMER_REGISTER


def issue_token(settings: Settings, *, tenant_id: uuid.UUID, phone: str, now: datetime) -> str:
    claims = {
        "iss": settings.jwt_issuer,
        "typ": JWT_TYP,
        "tid": str(tenant_id),
        "phone": phone,
        "iat": int(now.timestamp()),
        "exp": int(now.timestamp()) + settings.phone_verification_ttl_seconds,
        "jti": uuid.uuid4().hex,
    }
    return jwt.encode(claims, settings.jwt_signing_key, algorithm=settings.jwt_algorithm)


def verify_token(
    settings: Settings, token: str, *, tenant_id: uuid.UUID, phone: str, now: datetime
) -> None:
    """Raise ``phone_verification_invalid`` unless ``token`` proves ``phone`` in ``tenant``."""
    try:
        claims: dict[str, Any] = jwt.decode(
            token,
            settings.jwt_signing_key,
            algorithms=[settings.jwt_algorithm],
            issuer=settings.jwt_issuer,
            options={"verify_exp": False, "verify_iat": False, "require": ["exp", "phone"]},
        )
    except jwt.PyJWTError as exc:
        raise PhoneVerificationInvalidError("Invalid phone verification token.") from exc
    if claims.get("typ") != JWT_TYP:
        raise PhoneVerificationInvalidError("Invalid phone verification token.")
    if int(claims["exp"]) <= int(now.timestamp()):
        raise PhoneVerificationInvalidError("Phone verification token expired.")
    if claims.get("tid") != str(tenant_id) or claims.get("phone") != phone:
        raise PhoneVerificationInvalidError("Token does not match this phone.")


__all__ = ["JWT_TYP", "PURPOSE", "issue_token", "verify_token"]
