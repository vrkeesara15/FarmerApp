"""FA-007 in-app inbox, push-token registration and the ``notify`` helper.

* ``notify(...)`` — add a ``notification`` row (``pending``) for one user; the ``notify.send``
  worker / ``deliver-notifications`` sweeper pushes it. Keys follow the convention
  ``notification.<kind>.title`` / ``notification.<kind>.body``.
* Inbox — a user only ever sees their own rows (``user_id`` = the caller; RLS pins the
  tenant): newest first with a keyset cursor, ``read`` / ``read-all`` set ``read_at`` (a sync
  feed change, ``farmerapp.notifications.feed``).
* ``register_token`` — upsert by ``(tenant, token)``; a token seen for another user moves to
  the caller (a shared phone after a re-login) and is re-enabled.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from functools import lru_cache
from typing import Any

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError
from farmerapp.api.pagination import PageRequest
from farmerapp.auth.models import User
from farmerapp.notifications.models import Notification, PushToken
from farmerapp.notifications.push import PushSender, build_push_sender
from farmerapp.notifications.schemas import (
    NotificationOut,
    NotificationPage,
    PushTokenIn,
    PushTokenOut,
    ReadAllOut,
)
from farmerapp.settings import get_settings


def title_key(kind: str) -> str:
    return f"notification.{kind}.title"


def body_key(kind: str) -> str:
    return f"notification.{kind}.body"


def notify(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    user_id: uuid.UUID,
    kind: str,
    data: dict[str, Any] | None = None,
    body: str | None = None,
) -> Notification:
    """Queue one inbox row (+ push) for ``user_id``; ``body`` overrides the body key."""
    row = Notification(
        id=uuid.uuid4(),
        tenant_id=tenant_id,
        user_id=user_id,
        kind=kind,
        title_key=title_key(kind),
        body_key=body or body_key(kind),
        data={k: (str(v) if isinstance(v, uuid.UUID) else v) for k, v in (data or {}).items()},
    )
    session.add(row)
    return row


async def inbox(
    session: AsyncSession, actor: User, page: PageRequest, *, unread_only: bool = False
) -> NotificationPage:
    stmt = select(Notification).where(
        Notification.tenant_id == actor.tenant_id, Notification.user_id == actor.id
    )
    if unread_only:
        stmt = stmt.where(Notification.read_at.is_(None))
    keyset = page.before(Notification.created_at, Notification.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (
            await session.execute(
                stmt.order_by(Notification.created_at.desc(), Notification.id.desc()).limit(
                    page.fetch
                )
            )
        )
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    unread = await session.scalar(
        select(func.count()).where(
            Notification.tenant_id == actor.tenant_id,
            Notification.user_id == actor.id,
            Notification.read_at.is_(None),
        )
    )
    return NotificationPage(
        items=[NotificationOut.from_row(r) for r in items],
        next_cursor=cursor,
        unread=int(unread or 0),
    )


async def own_notification(
    session: AsyncSession, actor: User, notification_id: uuid.UUID
) -> Notification:
    row = await session.get(Notification, notification_id)
    if row is None or row.tenant_id != actor.tenant_id or row.user_id != actor.id:
        raise NotFoundError("Notification not found.")
    return row


async def mark_read(
    session: AsyncSession, actor: User, notification_id: uuid.UUID, *, now: datetime
) -> NotificationOut:
    row = await own_notification(session, actor, notification_id)
    if row.read_at is None:
        row.read_at = now
        await session.flush()
    return NotificationOut.from_row(row)


async def mark_all_read(session: AsyncSession, actor: User, *, now: datetime) -> ReadAllOut:
    rows = (
        (
            await session.execute(
                select(Notification).where(
                    Notification.tenant_id == actor.tenant_id,
                    Notification.user_id == actor.id,
                    Notification.read_at.is_(None),
                )
            )
        )
        .scalars()
        .all()
    )
    for row in rows:  # ORM updates: each read receipt is a sync feed change
        row.read_at = now
    await session.flush()
    return ReadAllOut(marked=len(rows))


async def register_token(
    session: AsyncSession,
    actor: User,
    body: PushTokenIn,
    *,
    device_id: str | None,
    now: datetime,
) -> PushTokenOut:
    row = (
        await session.execute(
            select(PushToken).where(
                PushToken.tenant_id == actor.tenant_id, PushToken.token == body.token
            )
        )
    ).scalar_one_or_none()
    device = device_id or body.device_id
    if row is None:
        row = PushToken(
            tenant_id=actor.tenant_id,
            user_id=actor.id,
            token=body.token,
            platform=body.platform,
            device_id=device,
            app_version=body.app_version,
            last_registered_at=now,
        )
        session.add(row)
    else:
        row.user_id = actor.id
        row.platform = body.platform
        row.device_id = device or row.device_id
        row.app_version = body.app_version or row.app_version
        row.last_registered_at = now
        row.disabled_at = None
        row.disabled_reason = None
        row.deleted_at = None
    await session.flush()
    await session.refresh(row)
    return PushTokenOut.from_row(row)


async def unregister_token(session: AsyncSession, actor: User, token: str, *, now: datetime) -> int:
    """Logout: stop pushing to this token (only the caller's own)."""
    result = await session.execute(
        update(PushToken)
        .where(
            PushToken.tenant_id == actor.tenant_id,
            PushToken.user_id == actor.id,
            PushToken.token == token,
            PushToken.disabled_at.is_(None),
        )
        .values(disabled_at=now, disabled_reason="logout")
    )
    return int(getattr(result, "rowcount", 0) or 0)


@lru_cache(maxsize=1)
def worker_push_sender() -> PushSender:
    """The worker / job process's sender (``PUSH_PROVIDER``)."""
    settings = get_settings()
    return build_push_sender(settings.push_provider, settings.fcm_project or settings.gcp_project)


__all__ = [
    "body_key",
    "inbox",
    "mark_all_read",
    "mark_read",
    "notify",
    "own_notification",
    "register_token",
    "title_key",
    "unregister_token",
    "worker_push_sender",
]
