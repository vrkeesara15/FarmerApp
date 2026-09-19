"""FA-007 routes: the in-app inbox (``/v1/notifications``) and push-token registration
(``/v1/devices/me/push-token``). Every role has an inbox and may register its devices; a
caller only ever reads or marks their own notifications (another user's id is a 404)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query, Request

from farmerapp.api.errors import problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.notifications import service
from farmerapp.notifications.schemas import (
    NotificationOut,
    NotificationPage,
    PushTokenIn,
    PushTokenOut,
    PushTokenRemovedOut,
    PushTokenRemoveIn,
    ReadAllOut,
)

router = APIRouter(prefix="/notifications", tags=["notifications"])
device_router = APIRouter(prefix="/devices", tags=["notifications"])

ALL_ROLES = tuple(Role)


@router.get(
    "",
    operation_id="listNotifications",
    summary="The caller's inbox, newest first (cursor), with the unread count",
    response_model=NotificationPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_notifications(
    actor: Annotated[User, require_roles(*ALL_ROLES)],
    session: DbSession,
    page: Page,
    unread_only: Annotated[bool, Query(description="Only unread notifications.")] = False,
) -> NotificationPage:
    return await service.inbox(session, actor, page, unread_only=unread_only)


@router.post(
    "/read-all",
    operation_id="readAllNotifications",
    summary="Mark every unread notification of the caller as read",
    response_model=ReadAllOut,
)
async def read_all(
    actor: Annotated[User, require_roles(*ALL_ROLES)], session: DbSession, services: Services
) -> ReadAllOut:
    return await service.mark_all_read(session, actor, now=services.clock.now())


@router.post(
    "/{id}/read",
    operation_id="readNotification",
    summary="Mark one of the caller's notifications as read (idempotent)",
    response_model=NotificationOut,
    responses=problem_responses((404, "not_found")),
)
async def read_one(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*ALL_ROLES)],
    session: DbSession,
    services: Services,
) -> NotificationOut:
    return await service.mark_read(session, actor, id, now=services.clock.now())


@device_router.post(
    "/me/push-token",
    operation_id="registerPushToken",
    summary="Register (or refresh) this device's FCM token for push notifications",
    response_model=PushTokenOut,
)
async def register_push_token(
    request: Request,
    body: PushTokenIn,
    actor: Annotated[User, require_roles(*ALL_ROLES)],
    session: DbSession,
    services: Services,
) -> PushTokenOut:
    device_id = getattr(request.state, "device_id", None) or request.headers.get("X-Device-Id")
    return await service.register_token(
        session, actor, body, device_id=device_id, now=services.clock.now()
    )


@device_router.post(
    "/me/push-token/remove",
    operation_id="removePushToken",
    summary="Stop pushing to this token (logout)",
    response_model=PushTokenRemovedOut,
)
async def remove_push_token(
    body: PushTokenRemoveIn,
    actor: Annotated[User, require_roles(*ALL_ROLES)],
    session: DbSession,
    services: Services,
) -> PushTokenRemovedOut:
    removed = await service.unregister_token(session, actor, body.token, now=services.clock.now())
    return PushTokenRemovedOut(removed=removed)


__all__ = ["device_router", "router"]
