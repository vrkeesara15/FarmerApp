"""``notification`` — the minimal in-app inbox row (FA-007 groundwork; migration 0008).

Written by the server when something needs the user's attention: VV-007 auto end of duty
(``kind = duty_auto_ended`` to the officer, so the app can prompt) and OPS-006 sync silence
(``kind = officer_sync_silence`` to the cluster head). ``title_key`` / ``body_key`` are i18n
keys the apps resolve (strings never live in the database); ``data`` carries the ids the
app needs to deep-link. FA-007 adds FCM delivery and the inbox endpoints on top of this
table; ``read_at`` is reserved for it.

Not audited (``__audit__ = False``): a notification is derived from an audited change
(the duty session end), not a mutation of user data.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, TenantRow


class NotificationKind(StrEnum):
    DUTY_AUTO_ENDED = "duty_auto_ended"  # VV-007
    OFFICER_SYNC_SILENCE = "officer_sync_silence"  # OPS-006
    FLAG_ASSIGNED = "flag_assigned"  # VA-003: a validation flag is yours (owner / watcher)
    FLAG_ESCALATED = "flag_escalated"  # OPS-010 / SPEC 6.1: a flag moved up to you


class Notification(Base, TenantRow):
    __tablename__ = "notification"
    __table_args__ = (
        CheckConstraint(
            "char_length(kind) > 0 AND char_length(title_key) > 0 AND char_length(body_key) > 0",
            name="keys",
        ),
        Index(
            "ix_notification_tenant_user_created",
            "tenant_id",
            "user_id",
            "created_at",
            postgresql_ops={"created_at": "DESC"},
        ),
    )
    __audit__ = False

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="CASCADE"), nullable=False
    )
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    title_key: Mapped[str] = mapped_column(String(64), nullable=False)
    body_key: Mapped[str] = mapped_column(String(64), nullable=False)
    data: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


__all__ = ["Notification", "NotificationKind"]
