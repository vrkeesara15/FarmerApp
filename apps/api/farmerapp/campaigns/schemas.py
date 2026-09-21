"""WC-008 / AN-008 request and response models (console C80-C82)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

from farmerapp.campaigns.models import Campaign, CampaignChannel, CampaignRecipient
from farmerapp.campaigns.segments import Segment
from farmerapp.pii.fields import mask_phone
from farmerapp.tenants.settings import SUPPORTED_LANGUAGES

MessageText = Annotated[str, StringConstraints(min_length=1, max_length=1000)]


def _check_messages(value: dict[str, str] | None) -> dict[str, str] | None:
    if value is None:
        return value
    if not value:
        raise ValueError("at least one language is required")
    unknown = sorted(set(value) - set(SUPPORTED_LANGUAGES))
    if unknown:
        raise ValueError(f"unsupported languages: {', '.join(unknown)}")
    return value


class SegmentCountIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    segment: Segment


class SegmentCountOut(BaseModel):
    count: int = Field(description="Farmers the campaign would reach (consented only).")
    excluded_no_consent: int = Field(
        description="Farmers matching every criterion but without current marketing consent."
    )


class CampaignIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: Annotated[str, StringConstraints(min_length=1, max_length=120, strip_whitespace=True)]
    channel: CampaignChannel
    segment: Segment = Field(default_factory=Segment)
    saved_segment_id: uuid.UUID | None = Field(
        default=None,
        description="AN-004: copy the definition of this saved segment instead of `segment`.",
    )
    messages: dict[str, MessageText] = Field(
        description="Message text per language code (`te`, `kn`, `hi`, `mr`, `en`)."
    )
    template_key: Annotated[str, StringConstraints(max_length=64)] | None = Field(
        default=None,
        description="Key into the tenant's `campaigns.dlt_templates` (SMS) or "
        "`campaigns.whatsapp_templates` (WhatsApp).",
    )
    attribution_days: int | None = Field(default=None, ge=1, le=90)
    holdout_pct: int | None = Field(default=None, ge=0, le=50)
    notes: Annotated[str, StringConstraints(max_length=2000)] | None = None

    _messages = field_validator("messages")(_check_messages)


class CampaignPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: Annotated[str, StringConstraints(min_length=1, max_length=120)] | None = None
    channel: CampaignChannel | None = None
    segment: Segment | None = None
    messages: dict[str, MessageText] | None = None
    template_key: Annotated[str, StringConstraints(max_length=64)] | None = None
    attribution_days: int | None = Field(default=None, ge=1, le=90)
    holdout_pct: int | None = Field(default=None, ge=0, le=50)
    notes: Annotated[str, StringConstraints(max_length=2000)] | None = None

    _messages = field_validator("messages")(_check_messages)


class ScheduleIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    send_at: datetime | None = Field(default=None, description="UTC; default now.")


class CampaignOut(BaseModel):
    id: uuid.UUID
    name: str
    channel: str
    status: str
    segment: dict[str, object]
    messages: dict[str, str]
    template_key: str | None
    scheduled_at: datetime | None
    started_at: datetime | None
    finished_at: datetime | None
    attribution_days: int
    holdout_pct: int
    audience_size: int | None
    created_by: uuid.UUID | None
    created_at: datetime
    notes: str | None

    @classmethod
    def from_row(cls, c: Campaign) -> CampaignOut:
        return cls(
            id=c.id,
            name=c.name,
            channel=c.channel,
            status=c.status,
            segment=dict(c.segment or {}),
            messages={str(k): str(v) for k, v in (c.messages or {}).items()},
            template_key=c.template_key,
            scheduled_at=c.scheduled_at,
            started_at=c.started_at,
            finished_at=c.finished_at,
            attribution_days=c.attribution_days,
            holdout_pct=c.holdout_pct,
            audience_size=c.audience_size,
            created_by=c.created_by,
            created_at=c.created_at,
            notes=c.notes,
        )


class CampaignPage(BaseModel):
    items: list[CampaignOut]
    next_cursor: str | None = None


class RecipientOut(BaseModel):
    id: uuid.UUID
    farmer_id: uuid.UUID
    farmer_name: str | None
    phone_masked: str | None
    arm: str
    language: str
    status: str
    skip_reason: str | None
    dlt_template_id: str | None
    sent_at: datetime | None
    delivered_at: datetime | None
    opened_at: datetime | None
    error: str | None

    @classmethod
    def from_row(cls, r: CampaignRecipient, name: str | None, phone: str | None) -> RecipientOut:
        return cls(
            id=r.id,
            farmer_id=r.farmer_id,
            farmer_name=name,
            phone_masked=mask_phone(phone) if phone else None,
            arm=r.arm,
            language=r.language,
            status=r.status,
            skip_reason=r.skip_reason,
            dlt_template_id=r.dlt_template_id,
            sent_at=r.sent_at,
            delivered_at=r.delivered_at,
            opened_at=r.opened_at,
            error=r.error,
        )


class RecipientPage(BaseModel):
    items: list[RecipientOut]
    next_cursor: str | None = None
    counts: dict[str, int] = Field(description="Recipients per delivery status.")


class ArmOut(BaseModel):
    size: int
    converted_farmers: int
    conversion_rate: float | None
    orders: int
    revenue_paise: int
    own_brand_revenue_paise: int
    own_brand_share: float | None


class RoiOut(BaseModel):
    """AN-008 campaign ROI (console C82)."""

    campaign_id: uuid.UUID
    name: str
    channel: str
    status: str
    started_at: datetime | None
    attribution_days: int
    audience: int = Field(description="Target recipients (holdout excluded).")
    sent: int = Field(description="Accepted by the provider / written as a push notification.")
    delivered: int
    failed: int
    skipped: int
    opened: int | None = Field(description="Opened pushes; null where the channel cannot tell.")
    orders: int
    converted_farmers: int
    conversion_rate: float | None
    revenue_paise: int
    own_brand_revenue_paise: int
    own_brand_share: float | None
    holdout: ArmOut | None
    own_brand_lift: float | None = Field(
        description="Target own-brand share minus holdout share (null without a holdout)."
    )
    conversion_lift: float | None


__all__ = [
    "ArmOut",
    "CampaignIn",
    "CampaignOut",
    "CampaignPage",
    "CampaignPatch",
    "RecipientOut",
    "RecipientPage",
    "RoiOut",
    "ScheduleIn",
    "SegmentCountIn",
    "SegmentCountOut",
]
