"""``Idempotency-Key`` on POST (SPEC 8.3, NF-003).

A mobile client sends a fresh key with every POST and re-sends the *same* key when it
retries after a lost response. The first execution stores ``(tenant, actor, key)`` together
with a hash of the request body and the JSON response; a retry with the same key and body
replays the stored response (same status, same body) without running the handler again; the
same key with a different body is a ``422 idempotency_key_reuse``. Keys live 24 hours
(``IDEMPOTENCY_TTL_SECONDS``; ``purge-expired`` job) and are private to the actor.

Usage — decorate the endpoint; it must take ``request: Request``, ``session`` and ``actor``
keyword parameters (FastAPI passes everything by keyword)::

    @router.post("", status_code=201, response_model=FarmerDetailOut)
    @idempotent(status_code=201)
    async def create_farmer(request: Request, body: FarmerCreate, actor: ..., session: ...):

Only successful responses are stored: an error is evaluated again on retry (a duplicate
phone stays a 409 either way). Replays are served before the handler runs, so nothing is
written twice and no audit row is produced for the replay.
"""

from __future__ import annotations

import functools
import hashlib
import inspect
import uuid
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from typing import Any, ParamSpec, TypeVar

from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from sqlalchemy import DateTime, Index, Integer, String, UniqueConstraint, Uuid, select
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.api.errors import AppError
from farmerapp.db.base import Base, TenantRow
from farmerapp.settings import get_settings

IDEMPOTENCY_HEADER = "Idempotency-Key"
KEY_MAX_LENGTH = 200

P = ParamSpec("P")
T = TypeVar("T")


class IdempotencyKeyReuseError(AppError):
    status = 422
    code = "idempotency_key_reuse"


class IdempotencyKey(Base, TenantRow):
    """One stored POST response per ``(tenant, actor, key)``."""

    __tablename__ = "idempotency_key"
    __table_args__ = (
        UniqueConstraint("tenant_id", "actor_id", "key"),
        Index("ix_idempotency_key_expires_at", "expires_at"),
    )
    __audit__ = False  # bookkeeping, not data

    actor_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    key: Mapped[str] = mapped_column(String(KEY_MAX_LENGTH), nullable=False)
    request_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    method: Mapped[str] = mapped_column(String(8), nullable=False)
    path: Mapped[str] = mapped_column(String(512), nullable=False)
    status_code: Mapped[int] = mapped_column(Integer, nullable=False)
    response: Mapped[Any] = mapped_column(JSONB, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


def request_hash(method: str, path: str, body: bytes) -> str:
    return hashlib.sha256(b"\n".join([method.encode(), path.encode(), body])).hexdigest()


async def find_key(
    session: AsyncSession, *, tenant_id: uuid.UUID, actor_id: uuid.UUID, key: str, now: datetime
) -> IdempotencyKey | None:
    stmt = select(IdempotencyKey).where(
        IdempotencyKey.tenant_id == tenant_id,
        IdempotencyKey.actor_id == actor_id,
        IdempotencyKey.key == key,
        IdempotencyKey.expires_at > now,
    )
    return (await session.execute(stmt)).scalar_one_or_none()


def idempotent(
    *, status_code: int = 200
) -> Callable[[Callable[P, Awaitable[T]]], Callable[P, Awaitable[T | JSONResponse]]]:
    """Replay a stored response for a repeated ``Idempotency-Key``; store a new success."""

    def decorate(fn: Callable[P, Awaitable[T]]) -> Callable[P, Awaitable[T | JSONResponse]]:
        params = inspect.signature(fn).parameters
        for name in ("request", "session", "actor"):
            if name not in params:
                raise TypeError(f"@idempotent endpoint {fn.__name__} needs a `{name}` parameter")

        @functools.wraps(fn)
        async def wrapper(*args: P.args, **kwargs: P.kwargs) -> T | JSONResponse:
            request: Request = kwargs["request"]  # type: ignore[assignment]
            session: AsyncSession = kwargs["session"]  # type: ignore[assignment]
            actor: Any = kwargs["actor"]
            key = request.headers.get(IDEMPOTENCY_HEADER)
            if not key or len(key) > KEY_MAX_LENGTH:
                return await fn(*args, **kwargs)
            now = datetime.now(UTC)
            digest = request_hash(request.method, request.url.path, await request.body())
            stored = await find_key(
                session, tenant_id=actor.tenant_id, actor_id=actor.id, key=key, now=now
            )
            if stored is not None:
                if stored.request_hash != digest:
                    raise IdempotencyKeyReuseError(
                        "This Idempotency-Key was already used with a different request."
                    )
                return JSONResponse(stored.response, status_code=stored.status_code)
            result = await fn(*args, **kwargs)
            if isinstance(result, JSONResponse):
                return result  # a nested replay; nothing new to store
            ttl = timedelta(seconds=get_settings().idempotency_ttl_seconds)
            session.add(
                IdempotencyKey(
                    tenant_id=actor.tenant_id,
                    actor_id=actor.id,
                    key=key,
                    request_hash=digest,
                    method=request.method,
                    path=request.url.path,
                    status_code=status_code,
                    response=jsonable_encoder(result),
                    expires_at=now + ttl,
                )
            )
            await session.flush()
            return result

        return wrapper

    return decorate


__all__ = [
    "IDEMPOTENCY_HEADER",
    "IdempotencyKey",
    "IdempotencyKeyReuseError",
    "find_key",
    "idempotent",
    "request_hash",
]
