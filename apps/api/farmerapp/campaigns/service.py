"""WC-008 campaign lifecycle: draft, schedule (freeze the consented audience), send with
throttling and a send-time consent re-check, delivery status, and the AN-008 ROI.

Channels:

* ``sms`` — the tenant's DLT template id for ``campaign.template_key``
  (``TenantSettings.campaigns.dlt_templates``; TRAI requires a registered template for
  promotional SMS, so scheduling without one is ``422 dlt_template_missing``) through the
  auth SMS provider adapter (``SmsProvider``; a provider that implements
  ``send_sms_template(to, body, template_id)`` receives the template id);
* ``whatsapp`` — the WhatsApp Business template name for the key
  (``campaigns.whatsapp_templates``; ``422 whatsapp_template_missing``) through
  ``WhatsAppProvider.send_whatsapp`` with the message as the ``text`` parameter;
* ``push`` — a ``notification`` row (kind ``campaign_message``) for the farmer's app login;
  delivery to the device is the notifications package's job (FCM). A farmer without the app
  is skipped (``no_app``); ``read_at`` on the row is the "opened" signal.

Messages are per language: the farmer's ``language`` if the campaign has it, else the
tenant's default language, else English, else the first language given.
"""

from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any, Protocol

from sqlalchemy import and_, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from farmerapp.api.errors import AppError, NotFoundError
from farmerapp.auth.models import User
from farmerapp.auth.providers import DeliveryStatus, ProviderError, SmsProvider, WhatsAppProvider
from farmerapp.campaigns.models import (
    Campaign,
    CampaignChannel,
    CampaignRecipient,
    CampaignStatus,
    RecipientArm,
    RecipientStatus,
    SkipReason,
)
from farmerapp.campaigns.segments import (
    PURCHASE_STATUSES,
    Segment,
    SegmentContext,
    has_marketing_consent,
    segment_query,
)
from farmerapp.catalog.models import Product, Sku
from farmerapp.farmers.models import Farmer
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification
from farmerapp.orders.models import Order, OrderLine
from farmerapp.tenants.settings import TenantSettings, get_tenant_settings

log = get_logger("farmerapp.campaigns")

#: ``notification.kind`` of a push campaign message (the text travels in ``data.text``).
CAMPAIGN_NOTIFICATION_KIND = "campaign_message"
EDITABLE = frozenset({CampaignStatus.DRAFT})
CANCELLABLE = frozenset({CampaignStatus.DRAFT, CampaignStatus.SCHEDULED})
ACTIVE = (CampaignStatus.SCHEDULED.value, CampaignStatus.SENDING.value)
SENT_STATUSES = (RecipientStatus.SENT.value, RecipientStatus.DELIVERED.value)


class CampaignStateError(AppError):
    status = 409
    code = "invalid_campaign_state"


class EmptySegmentError(AppError):
    status = 422
    code = "empty_segment"


class TemplateMissingError(AppError):
    status = 422
    code = "dlt_template_missing"


# --------------------------------------------------------------------------- ports
class TemplateSmsProvider(Protocol):
    async def send_sms_template(self, to: str, body: str, template_id: str) -> str: ...


@dataclass
class CampaignSender:
    """The provider adapters a send uses (from ``AuthServices`` or ``build_auth_services``)."""

    sms: SmsProvider
    whatsapp: WhatsAppProvider


# --------------------------------------------------------------------------- helpers
def pick_language(messages: dict[str, Any], preferred: str | None, settings: TenantSettings) -> str:
    for lang in (preferred, settings.default_language, "en"):
        if lang and lang in messages:
            return lang
    return next(iter(messages))


def in_holdout(campaign_id: uuid.UUID, farmer_id: uuid.UUID, pct: int) -> bool:
    """Deterministic control-group split (the same farmer always lands in the same arm)."""
    if pct <= 0:
        return False
    digest = hashlib.sha256(f"{campaign_id}:{farmer_id}".encode()).digest()
    return int.from_bytes(digest[:4], "big") % 100 < pct


def template_for(campaign: Campaign, settings: TenantSettings) -> str | None:
    """The DLT template id (SMS) / WhatsApp template name for the campaign, or raise."""
    channel = CampaignChannel(campaign.channel)
    if channel == CampaignChannel.PUSH:
        return None
    key = campaign.template_key or ""
    if channel == CampaignChannel.SMS:
        template = settings.campaigns.dlt_templates.get(key)
        if not template:
            raise TemplateMissingError(
                "No DLT template id is configured for this template key "
                "(settings: campaigns.dlt_templates).",
                extra={"template_key": key or None},
            )
        return template
    template = settings.campaigns.whatsapp_templates.get(key)
    if not template:
        raise TemplateMissingError(
            "No WhatsApp template is configured for this template key "
            "(settings: campaigns.whatsapp_templates).",
            code="whatsapp_template_missing",
            extra={"template_key": key or None},
        )
    return template


async def get_campaign(
    session: AsyncSession, tenant_id: uuid.UUID, campaign_id: uuid.UUID, *, lock: bool = False
) -> Campaign:
    stmt = select(Campaign).where(
        Campaign.id == campaign_id, Campaign.tenant_id == tenant_id, Campaign.deleted_at.is_(None)
    )
    if lock:
        stmt = stmt.with_for_update()
    campaign = (await session.execute(stmt)).scalar_one_or_none()
    if campaign is None:
        raise NotFoundError("Campaign not found.")
    return campaign


# --------------------------------------------------------------------------- lifecycle
async def create_campaign(
    session: AsyncSession,
    actor: User,
    *,
    name: str,
    channel: CampaignChannel,
    segment: Segment,
    messages: dict[str, str],
    template_key: str | None,
    attribution_days: int | None,
    holdout_pct: int | None,
    notes: str | None,
) -> Campaign:
    settings = await get_tenant_settings(session, actor.tenant_id)
    campaign = Campaign(
        tenant_id=actor.tenant_id,
        name=name,
        channel=channel.value,
        status=CampaignStatus.DRAFT.value,
        segment=segment.model_dump(mode="json", exclude_defaults=True),
        messages=dict(messages),
        template_key=template_key,
        attribution_days=attribution_days or settings.campaigns.attribution_days,
        holdout_pct=settings.campaigns.holdout_pct if holdout_pct is None else holdout_pct,
        created_by=actor.id,
        notes=notes,
    )
    session.add(campaign)
    await session.flush()
    return campaign


def update_campaign(campaign: Campaign, changes: dict[str, Any]) -> Campaign:
    if CampaignStatus(campaign.status) not in EDITABLE:
        raise CampaignStateError("Only a draft campaign can be edited.")
    for key, value in changes.items():
        if key == "segment" and value is not None:
            value = Segment.model_validate(value).model_dump(mode="json", exclude_defaults=True)
        if key == "channel" and value is not None:
            value = CampaignChannel(value).value
        setattr(campaign, key, value)
    return campaign


async def schedule_campaign(
    session: AsyncSession, campaign: Campaign, *, send_at: datetime | None, now: datetime
) -> Campaign:
    """Freeze the consented audience into ``campaign_recipient`` and schedule the send."""
    if CampaignStatus(campaign.status) != CampaignStatus.DRAFT:
        raise CampaignStateError("Only a draft campaign can be scheduled.")
    settings = await get_tenant_settings(session, campaign.tenant_id)
    template = template_for(campaign, settings)
    segment = Segment.model_validate(campaign.segment)
    ctx = SegmentContext(tenant_id=campaign.tenant_id, now=now)
    audience = select(Farmer.id, Farmer.language).where(
        Farmer.id.in_(segment_query(segment, ctx)), Farmer.tenant_id == campaign.tenant_id
    )
    rows = (await session.execute(audience.order_by(Farmer.id))).tuples().all()
    if not rows:
        raise EmptySegmentError("No consented farmer matches this segment.")
    targets = 0
    for farmer_id, language in rows:
        holdout = in_holdout(campaign.id, farmer_id, campaign.holdout_pct)
        targets += 0 if holdout else 1
        session.add(
            CampaignRecipient(
                tenant_id=campaign.tenant_id,
                campaign_id=campaign.id,
                farmer_id=farmer_id,
                arm=(RecipientArm.HOLDOUT if holdout else RecipientArm.TARGET).value,
                language=pick_language(campaign.messages, language, settings),
                status=(RecipientStatus.HOLDOUT if holdout else RecipientStatus.PENDING).value,
                dlt_template_id=template if campaign.channel == CampaignChannel.SMS else None,
            )
        )
    if targets == 0:
        raise EmptySegmentError("Every matching farmer fell into the holdout group.")
    campaign.status = CampaignStatus.SCHEDULED.value
    campaign.scheduled_at = send_at or now
    campaign.audience_size = targets
    await session.flush()
    return campaign


async def cancel_campaign(session: AsyncSession, campaign: Campaign) -> Campaign:
    if CampaignStatus(campaign.status) not in CANCELLABLE:
        raise CampaignStateError("Only a draft or scheduled campaign can be cancelled.")
    campaign.status = CampaignStatus.CANCELLED.value
    await session.execute(
        update(CampaignRecipient)
        .where(
            CampaignRecipient.tenant_id == campaign.tenant_id,
            CampaignRecipient.campaign_id == campaign.id,
            CampaignRecipient.status == RecipientStatus.PENDING.value,
        )
        .values(status=RecipientStatus.SKIPPED.value, skip_reason=SkipReason.CAMPAIGN_CANCELLED)
    )
    await session.flush()
    return campaign


# --------------------------------------------------------------------------- send job
@dataclass
class SendReport:
    tenant_id: uuid.UUID
    campaigns: int = 0
    sent: int = 0
    failed: int = 0
    skipped: dict[str, int] = field(default_factory=dict)
    finished: list[uuid.UUID] = field(default_factory=list)


async def _send_one(
    sender: CampaignSender,
    campaign: Campaign,
    recipient: CampaignRecipient,
    farmer: Farmer,
    text: str,
    template: str | None,
) -> str:
    channel = CampaignChannel(campaign.channel)
    if channel == CampaignChannel.SMS:
        if template and hasattr(sender.sms, "send_sms_template"):
            templated: TemplateSmsProvider = sender.sms  # type: ignore[assignment]
            return await templated.send_sms_template(farmer.phone, text, template)
        return await sender.sms.send_sms(farmer.phone, text)
    return await sender.whatsapp.send_whatsapp(
        farmer.phone, template or "", {"text": text, "campaign_id": str(campaign.id)}
    )


async def send_due_campaigns(
    session: AsyncSession, *, tenant_id: uuid.UUID, now: datetime, sender: CampaignSender
) -> SendReport:
    """One throttled pass: at most ``campaigns.sends_per_run`` recipients over every due
    campaign of the tenant. Consent is re-checked for each batch right before sending."""
    settings = await get_tenant_settings(session, tenant_id)
    budget = settings.campaigns.sends_per_run
    report = SendReport(tenant_id=tenant_id)
    due = (
        (
            await session.execute(
                select(Campaign)
                .where(
                    Campaign.tenant_id == tenant_id,
                    Campaign.deleted_at.is_(None),
                    Campaign.status.in_(ACTIVE),
                    Campaign.scheduled_at <= now,
                )
                .order_by(Campaign.scheduled_at, Campaign.id)
                .with_for_update(skip_locked=True)
            )
        )
        .scalars()
        .all()
    )
    for campaign in due:
        if budget <= 0:
            break
        report.campaigns += 1
        if campaign.status == CampaignStatus.SCHEDULED:
            campaign.status = CampaignStatus.SENDING.value
            campaign.started_at = now
        template = template_for(campaign, settings)
        batch = (
            (
                await session.execute(
                    select(CampaignRecipient)
                    .where(
                        CampaignRecipient.tenant_id == tenant_id,
                        CampaignRecipient.campaign_id == campaign.id,
                        CampaignRecipient.status == RecipientStatus.PENDING.value,
                    )
                    .order_by(CampaignRecipient.id)
                    .limit(budget)
                    .with_for_update(skip_locked=True)
                )
            )
            .scalars()
            .all()
        )
        budget -= len(batch)
        farmers = {
            f.id: f
            for f in (
                await session.execute(
                    select(Farmer).where(
                        Farmer.tenant_id == tenant_id,
                        Farmer.id.in_([r.farmer_id for r in batch]),
                    )
                )
            ).scalars()
        }
        consented = await has_marketing_consent(session, tenant_id, list(farmers))
        for recipient in batch:
            farmer = farmers.get(recipient.farmer_id)
            reason: SkipReason | None = None
            if farmer is None or farmer.deleted_at is not None:
                reason = SkipReason.FARMER_DELETED
            elif recipient.farmer_id not in consented:
                reason = SkipReason.CONSENT_WITHDRAWN
            elif campaign.channel == CampaignChannel.PUSH and farmer.user_id is None:
                reason = SkipReason.NO_APP
            if reason is not None or farmer is None:
                recipient.status = RecipientStatus.SKIPPED.value
                recipient.skip_reason = (reason or SkipReason.FARMER_DELETED).value
                key = recipient.skip_reason
                report.skipped[key] = report.skipped.get(key, 0) + 1
                continue
            text = str(campaign.messages.get(recipient.language) or "")
            if campaign.channel == CampaignChannel.PUSH:
                if farmer.user_id is None:  # pragma: no cover - skipped as no_app above
                    continue
                note = Notification(
                    tenant_id=tenant_id,
                    user_id=farmer.user_id,
                    kind=CAMPAIGN_NOTIFICATION_KIND,
                    title_key=f"notification.{CAMPAIGN_NOTIFICATION_KIND}.title",
                    body_key=f"notification.{CAMPAIGN_NOTIFICATION_KIND}.body",
                    data={
                        "campaign_id": str(campaign.id),
                        "campaign_name": campaign.name,
                        "language": recipient.language,
                        "text": text,
                    },
                )
                session.add(note)
                await session.flush()
                recipient.notification_id = note.id
                recipient.status = RecipientStatus.SENT.value
                recipient.sent_at = now
                report.sent += 1
                continue
            try:
                recipient.provider_ref = await _send_one(
                    sender, campaign, recipient, farmer, text, template
                )
            except ProviderError as exc:
                recipient.status = RecipientStatus.FAILED.value
                recipient.error = str(exc)[:200]
                report.failed += 1
                continue
            recipient.status = RecipientStatus.SENT.value
            recipient.sent_at = now
            report.sent += 1
        await session.flush()
        remaining = await session.scalar(
            select(func.count())
            .select_from(CampaignRecipient)
            .where(
                CampaignRecipient.tenant_id == tenant_id,
                CampaignRecipient.campaign_id == campaign.id,
                CampaignRecipient.status == RecipientStatus.PENDING.value,
            )
        )
        if not remaining:
            campaign.status = CampaignStatus.SENT.value
            campaign.finished_at = now
            report.finished.append(campaign.id)
    await session.flush()
    log.info(
        "campaign_sends",
        tenant_id=str(tenant_id),
        campaigns=report.campaigns,
        sent=report.sent,
        failed=report.failed,
        skipped=sum(report.skipped.values()),
    )
    return report


async def refresh_delivery(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    now: datetime,
    sender: CampaignSender,
    max_age: timedelta = timedelta(days=3),
) -> int:
    """Poll SMS delivery status for recent sends; mark opened pushes (``read_at``)."""
    changed = 0
    rows = (
        await session.execute(
            select(CampaignRecipient, Campaign.channel)
            .join(Campaign, Campaign.id == CampaignRecipient.campaign_id)
            .where(
                CampaignRecipient.tenant_id == tenant_id,
                CampaignRecipient.status == RecipientStatus.SENT.value,
                CampaignRecipient.sent_at >= now - max_age,
            )
        )
    ).tuples()
    pushes: dict[uuid.UUID, CampaignRecipient] = {}
    for recipient, channel in rows:
        if channel == CampaignChannel.PUSH:
            if recipient.notification_id is not None:
                pushes[recipient.notification_id] = recipient
            continue
        if channel != CampaignChannel.SMS or not recipient.provider_ref:
            continue
        status = await sender.sms.delivery_status(recipient.provider_ref)
        if status == DeliveryStatus.DELIVERED:
            recipient.status = RecipientStatus.DELIVERED.value
            recipient.delivered_at = now
            changed += 1
        elif status == DeliveryStatus.FAILED:
            recipient.status = RecipientStatus.FAILED.value
            changed += 1
    if pushes:
        read = await session.execute(
            select(Notification.id, Notification.read_at).where(
                Notification.tenant_id == tenant_id,
                Notification.id.in_(list(pushes)),
                Notification.read_at.is_not(None),
            )
        )
        for note_id, read_at in read.tuples():
            recipient = pushes[note_id]
            recipient.status = RecipientStatus.DELIVERED.value
            recipient.delivered_at = recipient.delivered_at or read_at
            recipient.opened_at = read_at
            changed += 1
    await session.flush()
    return changed


# --------------------------------------------------------------------------- AN-008 ROI
@dataclass(frozen=True)
class ArmOutcome:
    size: int
    converted_farmers: int
    orders: int
    revenue_paise: int
    own_brand_paise: int
    lines_paise: int

    @property
    def conversion_rate(self) -> float | None:
        return round(self.converted_farmers / self.size, 4) if self.size else None

    @property
    def own_brand_share(self) -> float | None:
        return round(self.own_brand_paise / self.lines_paise, 4) if self.lines_paise else None


async def _arm_outcome(
    session: AsyncSession, campaign: Campaign, arm: RecipientArm, window_start: datetime | None
) -> ArmOutcome:
    """Orders attributed to the campaign for one arm.

    Target: an order by a recipient placed after that recipient's send and within
    ``attribution_days`` of it, unless a later campaign reached the farmer before the order
    (last touch wins). Holdout: orders in the same window measured from the campaign start.
    """
    tid = campaign.tenant_id
    days = timedelta(days=campaign.attribution_days)
    r = CampaignRecipient
    base = [r.tenant_id == tid, r.campaign_id == campaign.id, r.arm == arm.value]
    if arm == RecipientArm.TARGET:
        base.append(r.status.in_(SENT_STATUSES))
        size = await session.scalar(select(func.count()).select_from(r).where(*base))
        if window_start is None:
            return ArmOutcome(int(size or 0), 0, 0, 0, 0, 0)
        later = aliased(CampaignRecipient)
        start_col = r.sent_at
        last_touch = ~(
            select(later.id)
            .where(
                later.tenant_id == tid,
                later.farmer_id == r.farmer_id,
                later.campaign_id != campaign.id,
                later.status.in_(SENT_STATUSES),
                later.sent_at > r.sent_at,
                later.sent_at < Order.placed_at,
            )
            .exists()
        )
        order_filter = and_(
            Order.placed_at > start_col, Order.placed_at <= start_col + days, last_touch
        )
    else:
        size = await session.scalar(select(func.count()).select_from(r).where(*base))
        if window_start is None:
            return ArmOutcome(int(size or 0), 0, 0, 0, 0, 0)
        order_filter = and_(Order.placed_at > window_start, Order.placed_at <= window_start + days)
    orders = (
        select(Order.id, Order.farmer_id, Order.total_paise)
        .join(r, and_(r.farmer_id == Order.farmer_id, *base))
        .where(
            Order.tenant_id == tid,
            Order.deleted_at.is_(None),
            Order.status.in_(PURCHASE_STATUSES),
            order_filter,
        )
        .subquery()
    )
    totals = (
        await session.execute(
            select(
                func.count(orders.c.id),
                func.count(func.distinct(orders.c.farmer_id)),
                func.coalesce(func.sum(orders.c.total_paise), 0),
            )
        )
    ).one()
    lines = (
        await session.execute(
            select(
                func.coalesce(func.sum(OrderLine.line_total_paise), 0),
                func.coalesce(
                    func.sum(OrderLine.line_total_paise).filter(Product.own_brand.is_(True)), 0
                ),
            )
            .join(Sku, Sku.id == OrderLine.sku_id)
            .join(Product, Product.id == Sku.product_id)
            .where(OrderLine.order_id.in_(select(orders.c.id)), OrderLine.deleted_at.is_(None))
        )
    ).one()
    return ArmOutcome(
        size=int(size or 0),
        converted_farmers=int(totals[1] or 0),
        orders=int(totals[0] or 0),
        revenue_paise=int(totals[2] or 0),
        own_brand_paise=int(lines[1] or 0),
        lines_paise=int(lines[0] or 0),
    )


@dataclass(frozen=True)
class Roi:
    campaign: Campaign
    counts: dict[str, int]
    opened: int | None
    target: ArmOutcome
    holdout: ArmOutcome | None

    @property
    def own_brand_lift(self) -> float | None:
        if self.holdout is None:
            return None
        t, h = self.target.own_brand_share, self.holdout.own_brand_share
        return round(t - h, 4) if t is not None and h is not None else None

    @property
    def conversion_lift(self) -> float | None:
        if self.holdout is None:
            return None
        t, h = self.target.conversion_rate, self.holdout.conversion_rate
        return round(t - h, 4) if t is not None and h is not None else None


async def campaign_roi(session: AsyncSession, campaign: Campaign) -> Roi:
    rows = await session.execute(
        select(CampaignRecipient.status, func.count(), func.count(CampaignRecipient.opened_at))
        .where(
            CampaignRecipient.tenant_id == campaign.tenant_id,
            CampaignRecipient.campaign_id == campaign.id,
        )
        .group_by(CampaignRecipient.status)
    )
    counts = {s.value: 0 for s in RecipientStatus}
    opened = 0
    for status, n, o in rows.tuples():
        counts[str(status)] = int(n)
        opened += int(o)
    start = campaign.started_at
    target = await _arm_outcome(session, campaign, RecipientArm.TARGET, start)
    holdout = (
        await _arm_outcome(session, campaign, RecipientArm.HOLDOUT, start)
        if counts[RecipientStatus.HOLDOUT.value]
        else None
    )
    return Roi(
        campaign=campaign,
        counts=counts,
        opened=opened if campaign.channel == CampaignChannel.PUSH else None,
        target=target,
        holdout=holdout,
    )


__all__ = [
    "CAMPAIGN_NOTIFICATION_KIND",
    "CampaignSender",
    "CampaignStateError",
    "EmptySegmentError",
    "Roi",
    "SendReport",
    "TemplateMissingError",
    "campaign_roi",
    "cancel_campaign",
    "create_campaign",
    "get_campaign",
    "in_holdout",
    "pick_language",
    "refresh_delivery",
    "schedule_campaign",
    "send_due_campaigns",
    "update_campaign",
]
