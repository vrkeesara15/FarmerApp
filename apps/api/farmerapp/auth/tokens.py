"""JWT access tokens and rotating refresh tokens (SEC-020).

Access: HS256 JWT, 15 min, claims ``sub`` (user id), ``tid`` (tenant), ``role``, ``typ=access``,
``jti``. Expiry is checked against the injected clock (PyJWT's own clock checks are disabled
so tests can drive time). TODO: RS256 + JWKS once another service needs to verify tokens.

Refresh: 48 random bytes, stored as SHA-256; one *family* per login. Every refresh rotates the
token (old one revoked, ``replaced_by`` set). Presenting a revoked token means the family has
leaked (or a client replayed): the whole family is revoked and the caller gets 401
``refresh_reused``. Tokens issued to a mobile client are bound to its ``device_id``, and so
are their access tokens (``did`` claim) so a lost device can be cut off on its own (SEC-025).

A token revoked by an admin action (``revoked_reason``) is not reuse: refresh answers 401
``session_revoked`` (forced logout, device unbound) or ``device_wipe_required`` (account
disabled, device lost) instead (WC-011, SEC-025).
"""

from __future__ import annotations

import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import TYPE_CHECKING, Any

import jwt
from sqlalchemy import select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import UnauthenticatedError
from farmerapp.auth.devices import DeviceMeta, check_refresh
from farmerapp.auth.errors import (
    DeviceWipeRequiredError,
    RefreshDeviceMismatchError,
    RefreshExpiredError,
    RefreshInvalidError,
    RefreshReusedError,
    SessionRevokedError,
    TokenExpiredError,
    UserDisabledError,
)
from farmerapp.auth.models import RefreshToken, RevokeReason, User, UserStatus
from farmerapp.db.session import set_tenant
from farmerapp.logging import get_logger

_ADMIN_WIPE = frozenset({RevokeReason.USER_DISABLED.value, RevokeReason.DEVICE_LOST.value})
_ADMIN_REVOKE = frozenset({RevokeReason.FORCE_LOGOUT.value, RevokeReason.DEVICE_REVOKED.value})

if TYPE_CHECKING:
    from farmerapp.auth.deps import AuthServices

log = get_logger("farmerapp.auth.tokens")


@dataclass(frozen=True)
class IssuedTokens:
    access_token: str
    refresh_token: str
    expires_in: int
    user: User


@dataclass(frozen=True)
class AccessClaims:
    user_id: uuid.UUID
    tenant_id: uuid.UUID
    role: str
    jti: str
    issued_at: int = 0
    device_id: str | None = None


def hash_refresh(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


_FIND_REFRESH = text("SELECT token_id, tenant_id FROM auth_find_refresh_token(:h)")


async def find_refresh_token(session: AsyncSession, raw: str) -> RefreshToken | None:
    """Locate a refresh token before any tenant is bound: the ``SECURITY DEFINER`` lookup
    (migration 0003) yields ids only; the row itself is read under the tenant's RLS."""
    row = (await session.execute(_FIND_REFRESH, {"h": hash_refresh(raw)})).first()
    if row is None:
        return None
    await set_tenant(session, row.tenant_id)
    return await session.get(RefreshToken, row.token_id)


class TokenService:
    def __init__(self, services: AuthServices) -> None:
        self._s = services

    # ------------------------------------------------------------------ access
    def issue_access_token(self, user: User, now: datetime, *, device_id: str | None = None) -> str:
        settings = self._s.settings
        claims: dict[str, Any] = {
            "iss": settings.jwt_issuer,
            "sub": str(user.id),
            "tid": str(user.tenant_id),
            "role": user.role,
            "typ": "access",
            "iat": int(now.timestamp()),
            "exp": int(now.timestamp()) + settings.access_token_ttl_seconds,
            "jti": uuid.uuid4().hex,
        }
        if device_id:
            claims["did"] = device_id
        return jwt.encode(claims, settings.jwt_signing_key, algorithm=settings.jwt_algorithm)

    def decode_access_token(self, token: str, now: datetime) -> AccessClaims:
        settings = self._s.settings
        try:
            claims: dict[str, Any] = jwt.decode(
                token,
                settings.jwt_signing_key,
                algorithms=[settings.jwt_algorithm],
                issuer=settings.jwt_issuer,
                options={"verify_exp": False, "verify_iat": False, "require": ["sub", "exp"]},
            )
        except jwt.PyJWTError as exc:
            raise UnauthenticatedError("Invalid token.") from exc
        if claims.get("typ") != "access":
            raise UnauthenticatedError("Invalid token type.")
        if int(claims["exp"]) <= int(now.timestamp()):
            raise TokenExpiredError("Access token expired.")
        try:
            return AccessClaims(
                user_id=uuid.UUID(str(claims["sub"])),
                tenant_id=uuid.UUID(str(claims["tid"])),
                role=str(claims.get("role", "")),
                jti=str(claims.get("jti", "")),
                issued_at=int(claims.get("iat", 0)),
                device_id=str(claims["did"]) if claims.get("did") else None,
            )
        except (KeyError, ValueError, TypeError) as exc:
            raise UnauthenticatedError("Invalid token claims.") from exc

    # ------------------------------------------------------------------ refresh
    async def issue_for_login(
        self,
        session: AsyncSession,
        user: User,
        *,
        device_id: str | None,
        device_name: str | None,
    ) -> IssuedTokens:
        now = self._s.clock.now()
        return await self._issue(
            session,
            user,
            family_id=uuid.uuid4(),
            device_id=device_id,
            device_name=device_name,
            now=now,
        )

    async def _issue(
        self,
        session: AsyncSession,
        user: User,
        *,
        family_id: uuid.UUID,
        device_id: str | None,
        device_name: str | None,
        now: datetime,
    ) -> IssuedTokens:
        settings = self._s.settings
        raw = secrets.token_urlsafe(48)
        row = RefreshToken(
            id=uuid.uuid4(),
            tenant_id=user.tenant_id,
            created_at=now,
            user_id=user.id,
            family_id=family_id,
            token_hash=hash_refresh(raw),
            device_id=device_id,
            device_name=device_name,
            expires_at=now + timedelta(seconds=settings.refresh_token_ttl_seconds),
        )
        session.add(row)
        await session.flush()
        return IssuedTokens(
            access_token=self.issue_access_token(user, now, device_id=device_id),
            refresh_token=raw,
            expires_in=settings.access_token_ttl_seconds,
            user=user,
        )

    async def _revoke_family(
        self,
        session: AsyncSession,
        family_id: uuid.UUID,
        now: datetime,
        reason: RevokeReason = RevokeReason.REUSE,
    ) -> None:
        await session.execute(
            update(RefreshToken)
            .where(RefreshToken.family_id == family_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=now, revoked_reason=reason.value)
            .execution_options(synchronize_session="fetch")
        )

    async def rotate(
        self,
        session: AsyncSession,
        raw: str,
        *,
        device_id: str | None,
        meta: DeviceMeta | None = None,
    ) -> IssuedTokens:
        now = self._s.clock.now()
        row = await find_refresh_token(session, raw)
        if row is None:
            raise RefreshInvalidError("Unknown refresh token.")
        if row.revoked_at is not None and row.revoked_reason in _ADMIN_WIPE:
            if row.device_id is not None:
                raise DeviceWipeRequiredError("This device must be wiped.")
            raise UserDisabledError("This account is disabled.")
        if row.revoked_at is not None and row.revoked_reason in _ADMIN_REVOKE:
            raise SessionRevokedError("You were signed out by an administrator.")
        if row.revoked_at is not None:
            await self._revoke_family(session, row.family_id, now)
            await session.commit()
            log.warning(
                "refresh_reuse_detected", family_id=str(row.family_id), user_id=str(row.user_id)
            )
            raise RefreshReusedError("Refresh token reuse detected; session revoked.")
        if row.expires_at <= now:
            raise RefreshExpiredError("Refresh token expired.")
        if row.device_id is not None and row.device_id != device_id:
            log.warning("refresh_device_mismatch", family_id=str(row.family_id))
            raise RefreshDeviceMismatchError("Refresh token is bound to another device.")

        user = await session.get(User, row.user_id)
        if user is None or user.deleted_at is not None:
            raise RefreshInvalidError("Unknown user.")
        if user.status != UserStatus.ACTIVE:
            await self._revoke_family(session, row.family_id, now, RevokeReason.USER_DISABLED)
            await session.commit()
            if row.device_id is not None:
                raise DeviceWipeRequiredError("This account is disabled.")
            raise UserDisabledError("This account is disabled.")
        if row.device_id is not None:
            await check_refresh(session, user, row.device_id, meta or DeviceMeta(), now)

        issued = await self._issue(
            session,
            user,
            family_id=row.family_id,
            device_id=row.device_id,
            device_name=row.device_name,
            now=now,
        )
        new_row = (
            await session.execute(
                select(RefreshToken).where(
                    RefreshToken.token_hash == hash_refresh(issued.refresh_token)
                )
            )
        ).scalar_one()
        row.revoked_at = now
        row.revoked_reason = RevokeReason.ROTATED
        row.replaced_by = new_row.id
        await session.flush()
        log.info("refresh_rotated", family_id=str(row.family_id), user_id=str(user.id))
        return issued

    async def revoke(self, session: AsyncSession, raw: str) -> RefreshToken | None:
        """Revoke the token's family; returns the presented row (``None`` if unknown)."""
        now = self._s.clock.now()
        row = await find_refresh_token(session, raw)
        if row is None:
            return None
        await self._revoke_family(session, row.family_id, now, RevokeReason.LOGOUT)
        log.info("logout", family_id=str(row.family_id), user_id=str(row.user_id))
        return row
