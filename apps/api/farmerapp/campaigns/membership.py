"""VA-F09 ``SegmentMembershipPort`` adapter: which farmers are in a campaign segment.

VA-F09 ("consent missing or withdrawn but farmer in a campaign segment", batch, high) lives
in the rules package and reads campaign audiences only through a port; this module is the
real adapter over ``campaign`` / ``campaign_recipient``. The parent wires an instance
(``CAMPAIGN_SEGMENT_MEMBERSHIP``) into the rule's port.

A farmer is **in a segment** while they are a recipient of a live campaign (``scheduled`` /
``sending``, or ``sent`` within ``recent_days``) in the target arm and not yet skipped. The
send job already skips such a farmer (``skip_reason = consent_withdrawn``), so VA-F09 is the
belt-and-braces signal that a frozen audience outlived a withdrawal (or that a recipient row
was written without consent at all).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.campaigns.models import (
    Campaign,
    CampaignRecipient,
    CampaignStatus,
    RecipientArm,
    RecipientStatus,
)
from farmerapp.campaigns.segments import has_marketing_consent

RECENT_DAYS = 30
_LIVE = (CampaignStatus.SCHEDULED.value, CampaignStatus.SENDING.value)
_MEMBER = (
    RecipientStatus.PENDING.value,
    RecipientStatus.SENT.value,
    RecipientStatus.DELIVERED.value,
)


@dataclass(frozen=True)
class SegmentMembership:
    farmer_id: uuid.UUID
    campaign_id: uuid.UUID
    campaign_name: str
    campaign_status: str
    recipient_status: str


class CampaignSegmentMembership:
    """Implements the rules package's ``SegmentMembershipPort``."""

    def __init__(self, recent_days: int = RECENT_DAYS) -> None:
        self.recent_days = recent_days

    async def memberships(
        self,
        session: AsyncSession,
        tenant_id: uuid.UUID,
        *,
        farmer_ids: list[uuid.UUID] | None = None,
        now: datetime | None = None,
    ) -> list[SegmentMembership]:
        since = (now or datetime.now().astimezone()) - timedelta(days=self.recent_days)
        stmt = (
            select(
                CampaignRecipient.farmer_id,
                Campaign.id,
                Campaign.name,
                Campaign.status,
                CampaignRecipient.status,
            )
            .join(Campaign, Campaign.id == CampaignRecipient.campaign_id)
            .where(
                CampaignRecipient.tenant_id == tenant_id,
                Campaign.tenant_id == tenant_id,
                Campaign.deleted_at.is_(None),
                CampaignRecipient.arm == RecipientArm.TARGET.value,
                CampaignRecipient.status.in_(_MEMBER),
                or_(
                    Campaign.status.in_(_LIVE),
                    (Campaign.status == CampaignStatus.SENT.value)
                    & (Campaign.finished_at >= since),
                ),
            )
            .order_by(CampaignRecipient.farmer_id, Campaign.id)
        )
        if farmer_ids is not None:
            stmt = stmt.where(CampaignRecipient.farmer_id.in_(farmer_ids))
        rows = await session.execute(stmt)
        return [SegmentMembership(*row) for row in rows.tuples()]

    async def farmers_in_segments(
        self, session: AsyncSession, tenant_id: uuid.UUID, *, now: datetime | None = None
    ) -> set[uuid.UUID]:
        return {m.farmer_id for m in await self.memberships(session, tenant_id, now=now)}

    async def members_without_consent(
        self, session: AsyncSession, tenant_id: uuid.UUID, *, now: datetime | None = None
    ) -> list[SegmentMembership]:
        """The VA-F09 findings: segment members whose latest marketing consent is not a grant
        (withdrawn, or never recorded)."""
        members = await self.memberships(session, tenant_id, now=now)
        consented = await has_marketing_consent(
            session, tenant_id, list({m.farmer_id for m in members})
        )
        return [m for m in members if m.farmer_id not in consented]


#: The instance the parent registers as the VA-F09 ``SegmentMembershipPort``.
CAMPAIGN_SEGMENT_MEMBERSHIP = CampaignSegmentMembership()

__all__ = [
    "CAMPAIGN_SEGMENT_MEMBERSHIP",
    "CampaignSegmentMembership",
    "SegmentMembership",
]
