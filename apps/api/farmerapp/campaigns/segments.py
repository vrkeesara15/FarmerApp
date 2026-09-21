"""WC-008 segment builder: which farmers a campaign may reach.

A ``Segment`` is a conjunction of optional criteria over the farmer's crops (a live crop
plot of one of ``crop_ids``, optionally at one of ``stages``), place (``districts`` of the
village, ``store_ids``), holding size (``min_acres`` / ``max_acres`` over the live farms), purchase
history (fulfilled / open orders within
``purchase_within_days`` with at least ``min_spend_paise`` in that window; or **no**
purchase within ``no_purchase_within_days``), the last visit (a visit within
``visited_within_days``; or none within ``not_visited_within_days``) and app usage
(``app_user``: has / has not the farmer-app login; ``app_active_within_days``: a session
within N days).

**Only farmers with current marketing consent are selectable** (FM-002 / NF-013): the latest
``consent_record`` of ``(farmer, marketing)`` must be a grant. The consent filter is part of
every audience query (``segment_query``) and cannot be switched off; ``count_segment`` also
reports how many farmers matched everything but consent (``excluded_no_consent``) so the
console can explain the difference. The send job re-checks consent per recipient
(``has_marketing_consent``) right before sending.
"""

from __future__ import annotations

import uuid
from collections.abc import Collection
from dataclasses import dataclass
from datetime import datetime, timedelta

from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import ColumnElement, Select, and_, exists, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from farmerapp.auth.models import RefreshToken
from farmerapp.farmers.models import (
    ConsentPurpose,
    ConsentRecord,
    ConsentSubject,
    CropPlot,
    CropStage,
    Farm,
    Farmer,
)
from farmerapp.orders.models import Order, OrderStatus
from farmerapp.tenants.models import Village
from farmerapp.visits.models import Visit

#: Orders that count as a purchase: placed and not cancelled (draft = never placed).
PURCHASE_STATUSES = tuple(
    s.value for s in OrderStatus if s not in (OrderStatus.DRAFT, OrderStatus.CANCELLED)
)


class Segment(BaseModel):
    """The stored segment definition (``campaign.segment``). Every field is optional."""

    model_config = ConfigDict(extra="forbid")

    crop_ids: list[uuid.UUID] = Field(default_factory=list, max_length=50)
    min_acres: float | None = Field(
        default=None, ge=0, le=10_000, description="Total live farm area of the farmer, acres."
    )
    max_acres: float | None = Field(default=None, ge=0, le=10_000)
    stages: list[CropStage] = Field(
        default_factory=list, description="Crop stage of a plot (with `crop_ids`: of that crop)."
    )
    districts: list[str] = Field(default_factory=list, max_length=50)
    store_ids: list[uuid.UUID] = Field(default_factory=list, max_length=100)
    purchase_within_days: int | None = Field(default=None, ge=1, le=730)
    min_spend_paise: int | None = Field(
        default=None, ge=0, description="Spend within `purchase_within_days` (default 365)."
    )
    no_purchase_within_days: int | None = Field(default=None, ge=1, le=730)
    visited_within_days: int | None = Field(default=None, ge=1, le=365)
    not_visited_within_days: int | None = Field(default=None, ge=1, le=365)
    app_user: bool | None = Field(default=None, description="Has the farmer-app login.")
    app_active_within_days: int | None = Field(default=None, ge=1, le=365)
    languages: list[str] = Field(default_factory=list, max_length=5)

    @model_validator(mode="after")
    def _consistent(self) -> Segment:
        if self.purchase_within_days and self.no_purchase_within_days:
            raise ValueError("purchase_within_days and no_purchase_within_days exclude each other")
        if self.visited_within_days and self.not_visited_within_days:
            raise ValueError("visited_within_days and not_visited_within_days exclude each other")
        if (
            self.min_acres is not None
            and self.max_acres is not None
            and self.min_acres > self.max_acres
        ):
            raise ValueError("min_acres must not exceed max_acres")
        return self


def latest_consent(tenant_id: uuid.UUID) -> Select[tuple[uuid.UUID, datetime | None]]:
    """The newest marketing consent row per farmer: ``(subject_id, granted_at)``."""
    return (
        select(ConsentRecord.subject_id, ConsentRecord.granted_at)
        .where(
            ConsentRecord.tenant_id == tenant_id,
            ConsentRecord.subject_type == ConsentSubject.FARMER.value,
            ConsentRecord.purpose == ConsentPurpose.MARKETING.value,
        )
        .order_by(
            ConsentRecord.subject_id, ConsentRecord.created_at.desc(), ConsentRecord.id.desc()
        )
        .distinct(ConsentRecord.subject_id)
    )


def consented_farmer_ids(tenant_id: uuid.UUID) -> Select[tuple[uuid.UUID]]:
    """Farmers whose latest marketing consent record is a grant."""
    latest = latest_consent(tenant_id).subquery()
    return select(latest.c.subject_id).where(latest.c.granted_at.is_not(None))


async def has_marketing_consent(
    session: AsyncSession, tenant_id: uuid.UUID, farmer_ids: Collection[uuid.UUID]
) -> set[uuid.UUID]:
    """Of ``farmer_ids``, those with current marketing consent (send-time re-check)."""
    if not farmer_ids:
        return set()
    latest = latest_consent(tenant_id).where(ConsentRecord.subject_id.in_(list(farmer_ids)))
    rows = await session.execute(latest)
    return {subject for subject, granted in rows.tuples() if granted is not None}


@dataclass(frozen=True)
class SegmentContext:
    tenant_id: uuid.UUID
    now: datetime


def _criteria(segment: Segment, ctx: SegmentContext) -> list[ColumnElement[bool]]:
    t = ctx.tenant_id
    out: list[ColumnElement[bool]] = [Farmer.tenant_id == t, Farmer.deleted_at.is_(None)]
    if segment.crop_ids or segment.stages:
        plot = and_(
            Farm.farmer_id == Farmer.id,
            Farm.deleted_at.is_(None),
            CropPlot.farm_id == Farm.id,
            CropPlot.deleted_at.is_(None),
        )
        conds = [plot]
        if segment.crop_ids:
            conds.append(CropPlot.crop_id.in_(segment.crop_ids))
        if segment.stages:
            conds.append(CropPlot.stage.in_([s.value for s in segment.stages]))
        out.append(exists().where(*conds))
    if segment.districts or segment.store_ids:
        village = select(Village.id).where(Village.tenant_id == t)
        if segment.districts:
            village = village.where(
                func.lower(Village.district).in_([d.lower() for d in segment.districts])
            )
        if segment.store_ids:
            village = village.where(Village.store_id.in_(segment.store_ids))
        out.append(Farmer.village_id.in_(village))
    if segment.languages:
        out.append(Farmer.language.in_(segment.languages))
    if segment.min_acres is not None or segment.max_acres is not None:
        acres = (
            select(func.coalesce(func.sum(Farm.area_acres), 0))
            .where(Farm.tenant_id == t, Farm.farmer_id == Farmer.id, Farm.deleted_at.is_(None))
            .correlate(Farmer)
            .scalar_subquery()
        )
        if segment.min_acres is not None:
            out.append(acres >= segment.min_acres)
        if segment.max_acres is not None:
            out.append(acres <= segment.max_acres)
    bought = and_(
        Order.tenant_id == t,
        Order.farmer_id == Farmer.id,
        Order.deleted_at.is_(None),
        Order.status.in_(PURCHASE_STATUSES),
    )
    if segment.purchase_within_days is not None or segment.min_spend_paise is not None:
        days = segment.purchase_within_days or 365
        since = ctx.now - timedelta(days=days)
        window = and_(bought, Order.placed_at >= since)
        if segment.min_spend_paise:
            spend = (
                select(func.coalesce(func.sum(Order.total_paise), 0))
                .where(window)
                .scalar_subquery()
            )
            out.append(spend >= segment.min_spend_paise)
        else:
            out.append(exists().where(window))
    if segment.no_purchase_within_days is not None:
        since = ctx.now - timedelta(days=segment.no_purchase_within_days)
        out.append(~exists().where(bought, Order.placed_at >= since))
    visit = and_(Visit.tenant_id == t, Visit.farmer_id == Farmer.id, Visit.deleted_at.is_(None))
    if segment.visited_within_days is not None:
        since = ctx.now - timedelta(days=segment.visited_within_days)
        out.append(exists().where(visit, Visit.checkin_at >= since))
    if segment.not_visited_within_days is not None:
        since = ctx.now - timedelta(days=segment.not_visited_within_days)
        out.append(~exists().where(visit, Visit.checkin_at >= since))
    if segment.app_user is not None:
        out.append(Farmer.user_id.is_not(None) if segment.app_user else Farmer.user_id.is_(None))
    if segment.app_active_within_days is not None:
        since = ctx.now - timedelta(days=segment.app_active_within_days)
        token = aliased(RefreshToken)
        out.append(
            exists().where(
                token.tenant_id == t, token.user_id == Farmer.user_id, token.created_at >= since
            )
        )
    return out


def segment_query(
    segment: Segment, ctx: SegmentContext, *, consent: bool = True
) -> Select[tuple[uuid.UUID]]:
    """Farmer ids of the segment. ``consent=False`` exists only for the VA-F09 check and the
    ``excluded_no_consent`` figure; an audience is always built with consent."""
    stmt = select(Farmer.id).where(*_criteria(segment, ctx))
    if consent:
        stmt = stmt.where(Farmer.id.in_(consented_farmer_ids(ctx.tenant_id)))
    return stmt


@dataclass(frozen=True)
class SegmentCount:
    count: int
    excluded_no_consent: int


async def count_segment(
    session: AsyncSession, segment: Segment, ctx: SegmentContext
) -> SegmentCount:
    consented = await session.scalar(
        select(func.count()).select_from(segment_query(segment, ctx).subquery())
    )
    everyone = await session.scalar(
        select(func.count()).select_from(segment_query(segment, ctx, consent=False).subquery())
    )
    total = int(everyone or 0)
    count = int(consented or 0)
    return SegmentCount(count=count, excluded_no_consent=max(total - count, 0))


__all__ = [
    "PURCHASE_STATUSES",
    "Segment",
    "SegmentContext",
    "SegmentCount",
    "consented_farmer_ids",
    "count_segment",
    "has_marketing_consent",
    "latest_consent",
    "segment_query",
]
