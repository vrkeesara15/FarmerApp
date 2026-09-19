"""FA-007 inbox and push-token payloads."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

from farmerapp.notifications.models import Notification, PushToken


class NotificationOut(BaseModel):
    id: uuid.UUID
    tenant_id: uuid.UUID
    user_id: uuid.UUID
    kind: str
    title_key: str = Field(description="i18n key of the title (the app resolves it).")
    body_key: str = Field(description="i18n key of the body.")
    data: dict[str, Any] = Field(description="Ids for the deep link (see `route`).")
    route: str = Field(description="Where the app opens this notification (FA-007 deep link).")
    created_at: datetime
    read_at: datetime | None
    delivery_status: str = Field(
        description="pending | delivered | failed | no_device | skipped (push only; the "
        "inbox lists every row whatever its push outcome)."
    )
    delivered_at: datetime | None

    @classmethod
    def from_row(cls, row: Notification) -> NotificationOut:
        from farmerapp.notifications.delivery import deep_link

        return cls(
            id=row.id,
            tenant_id=row.tenant_id,
            user_id=row.user_id,
            kind=row.kind,
            title_key=row.title_key,
            body_key=row.body_key,
            data=dict(row.data or {}),
            route=deep_link(row)["route"],
            created_at=row.created_at,
            read_at=row.read_at,
            delivery_status=row.delivery_status,
            delivered_at=row.delivered_at,
        )


class NotificationPage(BaseModel):
    items: list[NotificationOut]
    next_cursor: str | None = None
    unread: int = Field(description="Unread notifications of the caller (badge).")


class ReadAllOut(BaseModel):
    marked: int


class PushTokenIn(BaseModel):
    token: str = Field(min_length=16, max_length=4096, description="FCM registration token.")
    platform: Literal["android", "ios", "web"] = "android"
    device_id: str | None = Field(
        default=None,
        max_length=128,
        description="The app's device id (defaults to the device bound to the access token).",
    )
    app_version: str | None = Field(default=None, max_length=32)


class PushTokenRemoveIn(BaseModel):
    token: str = Field(min_length=16, max_length=4096)


class PushTokenOut(BaseModel):
    id: uuid.UUID
    platform: str
    device_id: str | None
    token_suffix: str = Field(description="Last 6 characters (the token is never echoed).")
    last_registered_at: datetime
    active: bool

    @classmethod
    def from_row(cls, row: PushToken) -> PushTokenOut:
        return cls(
            id=row.id,
            platform=row.platform,
            device_id=row.device_id,
            token_suffix=row.token[-6:],
            last_registered_at=row.last_registered_at,
            active=row.disabled_at is None,
        )


class PushTokenRemovedOut(BaseModel):
    removed: int


__all__ = [
    "NotificationOut",
    "NotificationPage",
    "PushTokenIn",
    "PushTokenOut",
    "PushTokenRemoveIn",
    "PushTokenRemovedOut",
    "ReadAllOut",
]
