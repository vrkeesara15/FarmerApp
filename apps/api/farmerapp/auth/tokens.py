"""JWT access tokens and rotating refresh tokens (SEC-020).

Access: HS256 JWT, 15 min, claims ``sub`` (user id), ``tid`` (tenant), ``role``, ``typ=access``,
``jti``. Expiry is checked against the injected clock (PyJWT's own clock checks are disabled
so tests can drive time). TODO: RS256 + JWKS once another service needs to verify tokens.

Refresh: 48 random bytes, stored as SHA-256; one *family* per login. Every refresh rotates the
token (old one revoked, ``replaced_by`` set). Presenting a revoked token means the family has
leaked (or a client replayed): the whole family is revoked and the caller gets 401
``refresh_reused``. Tokens issued to a mobile client are bound to its ``device_id``.
"""

from __future__ import annotations

import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import TYPE_CHECKING, Any

import jwt
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import UnauthenticatedError
from farmerapp.auth.errors import (
    RefreshDeviceMismatchError,
    RefreshExpiredError,
    RefreshInvalidError,
    RefreshReusedError,
    TokenExpiredError,
    UserDisabledError,
)
from farmerapp.auth.models import RefreshToken, User, UserStatus
from farmerapp.db.session import set_bypass_rls, set_tenant
from farmerapp.logging import get_logger

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


def hash_refresh(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


class TokenService:
    def __init__(self, services: AuthServices) -> None:
        self._s = services

    # ------------------------------------------------------------------ access
    def issue_access_token(self, user: User, now: datetime) -> str:
        settings = self._s.settings
        claims = {
            "iss": settings.jwt_issuer,
            "sub": str(user.id),
            "tid": str(user.tenant_id),
            "role": user.role,
            "typ": "access",
            "iat": int(now.timestamp()),
            "exp": int(now.timestamp()) + settings.access_token_ttl_seconds,
            "jti": uuid.uuid4().hex,
        }
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
            )
        except (KeyError, ValueError) as exc:
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
            access_token=self.issue_access_token(user, now),
            refresh_token=raw,
            expires_in=settings.access_token_ttl_seconds,
            user=user,
        )

    async def _revoke_family(
        self, session: AsyncSession, family_id: uuid.UUID, now: datetime
    ) -> None:
        await session.execute(
            update(RefreshToken)
            .where(RefreshToken.family_id == family_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=now)
        )

    async def rotate(
        self, session: AsyncSession, raw: str, *, device_id: str | None
    ) -> IssuedTokens:
        now = self._s.clock.now()
        await set_bypass_rls(session)
        row = (
            await session.execute(
                select(RefreshToken).where(RefreshToken.token_hash == hash_refresh(raw))
            )
        ).scalar_one_or_none()
        if row is None:
            raise RefreshInvalidError("Unknown refresh token.")
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

        await set_tenant(session, row.tenant_id)
        user = await session.get(User, row.user_id)
        if user is None or user.deleted_at is not None:
            raise RefreshInvalidError("Unknown user.")
        if user.status != UserStatus.ACTIVE:
            await self._revoke_family(session, row.family_id, now)
            await session.commit()
            raise UserDisabledError("This account is disabled.")

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
        row.replaced_by = new_row.id
        await session.flush()
        log.info("refresh_rotated", family_id=str(row.family_id), user_id=str(user.id))
        return issued

    async def revoke(self, session: AsyncSession, raw: str) -> None:
        now = self._s.clock.now()
        await set_bypass_rls(session)
        row = (
            await session.execute(
                select(RefreshToken).where(RefreshToken.token_hash == hash_refresh(raw))
            )
        ).scalar_one_or_none()
        if row is None:
            return
        await self._revoke_family(session, row.family_id, now)
        log.info("logout", family_id=str(row.family_id), user_id=str(row.user_id))
