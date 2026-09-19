"""``notification`` — the minimal in-app inbox row (FA-007 groundwork; migration 0008).

Written by the server when something needs the user's attention: VV-007 auto end of duty
(``kind = duty_auto_ended`` to the officer, so the app can prompt) and OPS-006 sync silence
(``kind = officer_sync_silence`` to the cluster head). ``title_key`` / ``body_key`` are i18n
keys the apps resolve (strings never live in the database); ``data`` carries the ids the
app needs to deep-link. FA-007 (M7, migration 0030) adds push delivery
(``delivery_status`` / ``attempts`` / ``next_attempt_at`` / ``delivered_at`` / ``last_error``,
``farmerapp.notifications.delivery``), the inbox endpoints (``read_at`` is the read receipt)
and ``push_token``; notifications are a sync entity (``farmerapp.notifications.feed``).

Not audited (``__audit__ = False``): a notification is derived from an audited change
(the duty session end), not a mutation of user data.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns, TenantRow


class NotificationKind(StrEnum):
    DUTY_AUTO_ENDED = "duty_auto_ended"  # VV-007
    OFFICER_SYNC_SILENCE = "officer_sync_silence"  # OPS-006
    FLAG_ASSIGNED = "flag_assigned"  # VA-003: a validation flag is yours (owner / watcher)
    FLAG_ESCALATED = "flag_escalated"  # OPS-010 / SPEC 6.1: a flag moved up to you
    STORE_ZERO_SALES = "store_zero_sales"  # OPS-007: no sale on a working day
    STORE_DAY_NOT_CLOSED = "store_day_not_closed"  # OPS-007: not closed by 22:00 IST
    PAYMENT_RECONCILIATION = "payment_reconciliation"  # OPS-008: finance ticket
    DIAGNOSIS_READY = "diagnosis_ready"  # FM-005: a result (answer / provisional) is in
    DIAGNOSIS_REVIEWED = "diagnosis_reviewed"  # WC-006: the agronomist confirmed / corrected
    DIAGNOSIS_QUEUE_AGED = "diagnosis_queue_aged"  # OPS-009 / DX-006: provisional > 18 h
    DIAGNOSIS_LLM_RATE = "diagnosis_llm_rate"  # OPS-009: LLM fallback > 40 % in a day
    #: FM-006: a farmer / officer asked an expert about an answered case (to agronomists)
    DIAGNOSIS_EXPERT_REQUESTED = "diagnosis_expert_requested"
    DATA_REQUEST_RECEIVED = "data_request_received"  # FM-015 / NF-013: a ticket to handle
    # M7 (FA-007 deep links and the field P1 features).
    VISIT_CONFIRMATION_REQUESTED = "visit_confirm_request"  # FA-016 app_push -> farmer app
    CREDIT_APPROVAL_DECIDED = "credit_approval_decided"  # ST-007: to the officer who asked
    TRAVEL_CLAIM_SUBMITTED = "travel_claim_submitted"  # FA-023: to the cluster head
    TRAVEL_CLAIM_DECIDED = "travel_claim_decided"  # FA-023: to the officer
    BEAT_PLAN_READY = "beat_plan_ready"  # FA-018: the 06:00 plan is ready
    # M7 farmer P1 (crop calendar, outbreaks, diagnosis ML operations).
    CROP_TASK_REMINDER = "crop_task_reminder"  # FM-007: a crop calendar task is due
    OUTBREAK_ALERT = "outbreak_alert"  # DX-013 / FM-009: pest / disease cluster in a district
    DIAGNOSIS_EVAL_DROP = "diagnosis_eval_drop"  # DX-011: top-1 accuracy fell > 5 points
    MODEL_RELEASE_CANDIDATE = "model_release_candidate"  # DX-012: a model awaits approval


class DeliveryStatus(StrEnum):
    """FA-007 push delivery state of a notification row (the inbox shows every row)."""

    PENDING = "pending"  # not pushed yet (or waiting for a retry: ``next_attempt_at``)
    DELIVERED = "delivered"  # FCM accepted it for at least one active device
    FAILED = "failed"  # every attempt failed (``last_error``); still in the inbox
    NO_DEVICE = "no_device"  # the user has no active push token; inbox only
    SKIPPED = "skipped"  # written before FA-007 delivery existed (migration 0030)


class PushPlatform(StrEnum):
    ANDROID = "android"
    IOS = "ios"
    WEB = "web"


class Notification(Base, TenantRow):
    __tablename__ = "notification"
    __table_args__ = (
        CheckConstraint(
            "char_length(kind) > 0 AND char_length(title_key) > 0 AND char_length(body_key) > 0",
            name="keys",
        ),
        CheckConstraint(
            "delivery_status IN ('pending', 'delivered', 'failed', 'no_device', 'skipped')",
            name="delivery_status",
        ),
        Index(
            "ix_notification_pending",
            "tenant_id",
            "next_attempt_at",
            postgresql_where=text("delivery_status = 'pending'"),
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
    # FA-007 push delivery (migration 0030; rows written before it are ``skipped``).
    delivery_status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default=DeliveryStatus.PENDING.value,
        server_default=text("'pending'"),
    )
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    next_attempt_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_error: Mapped[str | None] = mapped_column(String(200), nullable=True)


class PushToken(Base, BaseColumns):
    """FA-007: an FCM registration token of one of the user's devices.

    ``POST /v1/devices/me/push-token`` upserts it (one row per token and tenant: a token that
    moves to another account follows the new user). Delivery uses the user's tokens that are
    not disabled and whose device (``device_id``, when the token was bound to one) is not
    ``lost`` / ``revoked`` (SEC-025). A token FCM reports ``UNREGISTERED`` is disabled.
    Bookkeeping, like ``upload_session``: not audited, never in the sync feed; the token is
    never logged (only its last 6 characters).
    """

    __tablename__ = "push_token"
    __table_args__ = (
        UniqueConstraint("tenant_id", "token"),
        CheckConstraint("platform IN ('android', 'ios', 'web')", name="platform"),
        CheckConstraint("char_length(token) >= 16", name="token"),
        Index("ix_push_token_user_id", "tenant_id", "user_id"),
    )
    __audit__ = False

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user.id", ondelete="CASCADE"), nullable=False
    )
    token: Mapped[str] = mapped_column(String(4096), nullable=False)
    platform: Mapped[str] = mapped_column(String(8), nullable=False)
    device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(32), nullable=True)
    last_registered_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    disabled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    disabled_reason: Mapped[str | None] = mapped_column(String(32), nullable=True)


__all__ = ["DeliveryStatus", "Notification", "NotificationKind", "PushPlatform", "PushToken"]
