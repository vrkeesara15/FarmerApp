"""``/v1/campaigns`` — WC-008 campaigns and the AN-008 ROI (console C80-C82).

Roles: owners, directors and tenant admins build, schedule and cancel campaigns; auditors
read them. Farmers are only ever selected with current marketing consent (see
``campaigns.segments``); sending happens in the ``send-campaigns`` job.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query, Request, status
from sqlalchemy import func, select

from farmerapp.analytics import segments as analytics_segments
from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.campaigns import service
from farmerapp.campaigns.models import (
    Campaign,
    CampaignRecipient,
    CampaignStatus,
    RecipientStatus,
)
from farmerapp.campaigns.schemas import (
    ArmOut,
    CampaignIn,
    CampaignOut,
    CampaignPage,
    CampaignPatch,
    RecipientOut,
    RecipientPage,
    RoiOut,
    ScheduleIn,
    SegmentCountIn,
    SegmentCountOut,
)
from farmerapp.campaigns.segments import Segment, SegmentContext, count_segment
from farmerapp.farmers.models import Farmer

router = APIRouter(prefix="/campaigns", tags=["campaigns"])

WRITE_ROLES = (Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN)
READ_ROLES = (*WRITE_ROLES, Role.AUDITOR)
_STATE = ((404, "not_found"), (409, "invalid_campaign_state"))


@router.post(
    "/segment-count",
    operation_id="countCampaignSegment",
    summary="Live count of the consented farmers a segment selects (WC-008)",
    response_model=SegmentCountOut,
)
async def segment_count(
    body: SegmentCountIn,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> SegmentCountOut:
    ctx = SegmentContext(tenant_id=actor.tenant_id, now=services.clock.now())
    result = await count_segment(session, body.segment, ctx)
    return SegmentCountOut(count=result.count, excluded_no_consent=result.excluded_no_consent)


@router.get(
    "",
    operation_id="listCampaigns",
    summary="Campaigns of the tenant, newest first",
    response_model=CampaignPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_campaigns(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    page: Page,
    status_: Annotated[CampaignStatus | None, Query(alias="status")] = None,
) -> CampaignPage:
    stmt = select(Campaign).where(
        Campaign.tenant_id == actor.tenant_id, Campaign.deleted_at.is_(None)
    )
    if status_ is not None:
        stmt = stmt.where(Campaign.status == status_.value)
    keyset = page.before(Campaign.created_at, Campaign.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (
            await session.execute(
                stmt.order_by(Campaign.created_at.desc(), Campaign.id.desc()).limit(page.fetch)
            )
        )
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    return CampaignPage(items=[CampaignOut.from_row(c) for c in items], next_cursor=cursor)


@router.post(
    "",
    operation_id="createCampaign",
    summary="Create a draft campaign (segment, channel, messages per language)",
    status_code=status.HTTP_201_CREATED,
    response_model=CampaignOut,
    responses=problem_responses((404, "not_found"), (422, "idempotency_key_reuse")),
)
@idempotent(status_code=status.HTTP_201_CREATED)
async def create_campaign(
    request: Request,
    body: CampaignIn,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> CampaignOut:
    segment = body.segment
    if body.saved_segment_id is not None:
        # AN-004: the campaign takes a copy, so editing the saved segment later never
        # rewrites what this campaign was sent to.
        saved = await analytics_segments.get_saved(session, actor.tenant_id, body.saved_segment_id)
        segment = Segment.model_validate(saved.definition or {})
    campaign = await service.create_campaign(
        session,
        actor,
        name=body.name,
        channel=body.channel,
        segment=segment,
        messages=dict(body.messages),
        template_key=body.template_key,
        attribution_days=body.attribution_days,
        holdout_pct=body.holdout_pct,
        notes=body.notes,
    )
    return CampaignOut.from_row(campaign)


@router.get(
    "/{id}",
    operation_id="getCampaign",
    summary="One campaign",
    response_model=CampaignOut,
    responses=problem_responses((404, "not_found")),
)
async def get_campaign(
    id: uuid.UUID, actor: Annotated[User, require_roles(*READ_ROLES)], session: DbSession
) -> CampaignOut:
    return CampaignOut.from_row(await service.get_campaign(session, actor.tenant_id, id))


@router.patch(
    "/{id}",
    operation_id="updateCampaign",
    summary="Edit a draft campaign",
    response_model=CampaignOut,
    responses=problem_responses(*_STATE),
)
async def update_campaign(
    id: uuid.UUID,
    body: CampaignPatch,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> CampaignOut:
    campaign = await service.get_campaign(session, actor.tenant_id, id, lock=True)
    service.update_campaign(campaign, body.model_dump(mode="json", exclude_unset=True))
    await session.flush()
    return CampaignOut.from_row(campaign)


@router.post(
    "/{id}/schedule",
    operation_id="scheduleCampaign",
    summary="Freeze the consented audience (holdout split) and schedule the send",
    response_model=CampaignOut,
    responses=problem_responses(
        *_STATE,
        (422, "empty_segment"),
        (422, "dlt_template_missing"),
        (422, "whatsapp_template_missing"),
    ),
)
async def schedule_campaign(
    id: uuid.UUID,
    body: ScheduleIn,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> CampaignOut:
    campaign = await service.get_campaign(session, actor.tenant_id, id, lock=True)
    await service.schedule_campaign(
        session, campaign, send_at=body.send_at, now=services.clock.now()
    )
    return CampaignOut.from_row(campaign)


@router.post(
    "/{id}/cancel",
    operation_id="cancelCampaign",
    summary="Cancel a draft or scheduled campaign (pending recipients are skipped)",
    response_model=CampaignOut,
    responses=problem_responses(*_STATE),
)
async def cancel_campaign(
    id: uuid.UUID, actor: Annotated[User, require_roles(*WRITE_ROLES)], session: DbSession
) -> CampaignOut:
    campaign = await service.get_campaign(session, actor.tenant_id, id, lock=True)
    await service.cancel_campaign(session, campaign)
    return CampaignOut.from_row(campaign)


@router.get(
    "/{id}/recipients",
    operation_id="listCampaignRecipients",
    summary="Per-recipient delivery status of a campaign (masked phones)",
    response_model=RecipientPage,
    responses=problem_responses((400, "invalid_cursor"), (404, "not_found")),
)
async def list_recipients(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    page: Page,
    status_: Annotated[RecipientStatus | None, Query(alias="status")] = None,
) -> RecipientPage:
    campaign = await service.get_campaign(session, actor.tenant_id, id)
    base = [
        CampaignRecipient.tenant_id == actor.tenant_id,
        CampaignRecipient.campaign_id == campaign.id,
    ]
    stmt = select(CampaignRecipient, Farmer).join(Farmer, Farmer.id == CampaignRecipient.farmer_id)
    stmt = stmt.where(*base)
    if status_ is not None:
        stmt = stmt.where(CampaignRecipient.status == status_.value)
    after = page.after(CampaignRecipient.created_at, CampaignRecipient.id)
    if after is not None:
        stmt = stmt.where(after)
    rows = (
        (
            await session.execute(
                stmt.order_by(CampaignRecipient.created_at, CampaignRecipient.id).limit(page.fetch)
            )
        )
        .tuples()
        .all()
    )
    recipients = [r for r, _ in rows]
    farmers = {r.id: f for r, f in rows}
    items, cursor = page.slice(recipients)
    counts = {
        str(k): int(v)
        for k, v in (
            await session.execute(
                select(CampaignRecipient.status, func.count())
                .where(*base)
                .group_by(CampaignRecipient.status)
            )
        ).tuples()
    }
    return RecipientPage(
        items=[RecipientOut.from_row(r, farmers[r.id].name, farmers[r.id].phone) for r in items],
        next_cursor=cursor,
        counts=counts,
    )


@router.get(
    "/{id}/roi",
    operation_id="getCampaignRoi",
    summary="AN-008 campaign ROI: sent, delivered, opened, orders, revenue, own-brand lift",
    response_model=RoiOut,
    responses=problem_responses((404, "not_found")),
)
async def campaign_roi(
    id: uuid.UUID, actor: Annotated[User, require_roles(*READ_ROLES)], session: DbSession
) -> RoiOut:
    campaign = await service.get_campaign(session, actor.tenant_id, id)
    roi = await service.campaign_roi(session, campaign)
    c = roi.counts
    t = roi.target
    holdout = (
        ArmOut(
            size=roi.holdout.size,
            converted_farmers=roi.holdout.converted_farmers,
            conversion_rate=roi.holdout.conversion_rate,
            orders=roi.holdout.orders,
            revenue_paise=roi.holdout.revenue_paise,
            own_brand_revenue_paise=roi.holdout.own_brand_paise,
            own_brand_share=roi.holdout.own_brand_share,
        )
        if roi.holdout is not None
        else None
    )
    return RoiOut(
        campaign_id=campaign.id,
        name=campaign.name,
        channel=campaign.channel,
        status=campaign.status,
        started_at=campaign.started_at,
        attribution_days=campaign.attribution_days,
        audience=campaign.audience_size or 0,
        sent=c["sent"] + c["delivered"],
        delivered=c["delivered"],
        failed=c["failed"],
        skipped=c["skipped"],
        opened=roi.opened,
        orders=t.orders,
        converted_farmers=t.converted_farmers,
        conversion_rate=t.conversion_rate,
        revenue_paise=t.revenue_paise,
        own_brand_revenue_paise=t.own_brand_paise,
        own_brand_share=t.own_brand_share,
        holdout=holdout,
        own_brand_lift=roi.own_brand_lift,
        conversion_lift=roi.conversion_lift,
    )


__all__ = ["READ_ROLES", "WRITE_ROLES", "router"]
