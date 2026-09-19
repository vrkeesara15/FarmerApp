"""Campaigns (WC-008, AN-008; migration 0031_growth).

* ``campaign`` — a marketing message to a segment of farmers over one channel (``sms``,
  ``whatsapp`` or ``push``). ``segment`` is the stored segment definition
  (``farmerapp.campaigns.segments.Segment``); ``messages`` the text per language
  (``{"te": "...", "en": "..."}``, the farmer's preferred language first, then the tenant
  default, then English); ``template_key`` names the DLT / WhatsApp template in the tenant
  settings (``campaigns.dlt_templates`` / ``campaigns.whatsapp_templates``). ``status``:
  ``draft`` -> ``scheduled`` (audience frozen into ``campaign_recipient``) -> ``sending`` ->
  ``sent``; ``cancelled`` from draft / scheduled. ``holdout_pct`` of the consented audience is
  kept back as a control group (AN-008 own-brand lift); ``attribution_days`` is the
  conversion window (an order by a recipient within N days of the send).
* ``campaign_recipient`` — one farmer of a scheduled campaign: ``arm`` ``target`` or
  ``holdout``, the language used, the per-recipient delivery ``status`` (``pending`` ->
  ``sent`` -> ``delivered`` / ``failed``; ``skipped`` with a ``skip_reason`` such as
  ``consent_withdrawn`` when the send-time consent re-check fails; holdout rows stay
  ``holdout``), the provider reference, the DLT template id used, the notification row of a
  push and when it was opened. Not audited (``__audit__ = False``): delivery bookkeeping
  derived from the audited campaign.
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
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import sql_in
from farmerapp.db.base import Base, BaseColumns


class CampaignChannel(StrEnum):
    SMS = "sms"
    WHATSAPP = "whatsapp"
    PUSH = "push"


class CampaignStatus(StrEnum):
    DRAFT = "draft"
    SCHEDULED = "scheduled"
    SENDING = "sending"
    SENT = "sent"
    CANCELLED = "cancelled"


class RecipientArm(StrEnum):
    TARGET = "target"
    HOLDOUT = "holdout"


class RecipientStatus(StrEnum):
    PENDING = "pending"
    SENT = "sent"
    DELIVERED = "delivered"
    FAILED = "failed"
    SKIPPED = "skipped"
    HOLDOUT = "holdout"


class SkipReason(StrEnum):
    CONSENT_WITHDRAWN = "consent_withdrawn"  # WC-008: re-checked at send time
    NO_APP = "no_app"  # push to a farmer without the farmer app login
    FARMER_DELETED = "farmer_deleted"
    CAMPAIGN_CANCELLED = "campaign_cancelled"


class Campaign(Base, BaseColumns):
    __tablename__ = "campaign"
    __table_args__ = (
        CheckConstraint(f"channel IN ({sql_in(CampaignChannel)})", name="channel"),
        CheckConstraint(f"status IN ({sql_in(CampaignStatus)})", name="status"),
        CheckConstraint("holdout_pct >= 0 AND holdout_pct <= 50", name="holdout_pct"),
        CheckConstraint("attribution_days >= 1 AND attribution_days <= 90", name="attribution"),
        CheckConstraint("char_length(name) > 0", name="name"),
        Index("ix_campaign_tenant_status", "tenant_id", "status", "scheduled_at"),
    )

    name: Mapped[str] = mapped_column(String(120), nullable=False)
    channel: Mapped[str] = mapped_column(String(16), nullable=False)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, default=CampaignStatus.DRAFT.value
    )
    segment: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    messages: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    template_key: Mapped[str | None] = mapped_column(String(64), nullable=True)
    scheduled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    attribution_days: Mapped[int] = mapped_column(Integer, nullable=False, default=14)
    holdout_pct: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    audience_size: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)


class CampaignRecipient(Base, BaseColumns):
    __tablename__ = "campaign_recipient"
    __table_args__ = (
        UniqueConstraint("tenant_id", "campaign_id", "farmer_id"),
        CheckConstraint(f"arm IN ({sql_in(RecipientArm)})", name="arm"),
        CheckConstraint(f"status IN ({sql_in(RecipientStatus)})", name="status"),
        CheckConstraint(
            f"skip_reason IS NULL OR skip_reason IN ({sql_in(SkipReason)})", name="skip_reason"
        ),
        Index("ix_campaign_recipient_campaign_status", "tenant_id", "campaign_id", "status"),
        Index("ix_campaign_recipient_farmer", "tenant_id", "farmer_id", "sent_at"),
    )
    __audit__ = False  # delivery bookkeeping of an audited campaign

    campaign_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("campaign.id", ondelete="CASCADE"), nullable=False
    )
    farmer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farmer.id", ondelete="CASCADE"), nullable=False
    )
    arm: Mapped[str] = mapped_column(String(8), nullable=False, default=RecipientArm.TARGET.value)
    language: Mapped[str] = mapped_column(String(8), nullable=False)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, default=RecipientStatus.PENDING.value
    )
    skip_reason: Mapped[str | None] = mapped_column(String(32), nullable=True)
    provider_ref: Mapped[str | None] = mapped_column(String(64), nullable=True)
    dlt_template_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    notification_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    opened_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    error: Mapped[str | None] = mapped_column(String(200), nullable=True)


__all__ = [
    "Campaign",
    "CampaignChannel",
    "CampaignRecipient",
    "CampaignStatus",
    "RecipientArm",
    "RecipientStatus",
    "SkipReason",
]
