"""WC-008 jobs: ``send-campaigns`` (Cloud Scheduler every minute: throttled sends of due
campaigns, then delivery status refresh)."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

from farmerapp.auth.deps import build_auth_services
from farmerapp.campaigns.service import (
    CampaignSender,
    SendReport,
    refresh_delivery,
    send_due_campaigns,
)
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.settings import get_settings


def default_sender() -> CampaignSender:
    services = build_auth_services(get_settings())
    return CampaignSender(sms=services.sms, whatsapp=services.whatsapp)


async def run_send_campaigns(
    tenant_ids: Sequence[uuid.UUID],
    *,
    now: datetime | None = None,
    sender: CampaignSender | None = None,
) -> list[tuple[SendReport, int]]:
    now = now or datetime.now(UTC)
    sender = sender or default_sender()
    out: list[tuple[SendReport, int]] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                report = await send_due_campaigns(
                    session, tenant_id=tenant_id, now=now, sender=sender
                )
            async with job_session(tenant_id) as session:
                changed = await refresh_delivery(
                    session, tenant_id=tenant_id, now=now, sender=sender
                )
        out.append((report, changed))
    return out


__all__ = ["default_sender", "run_send_campaigns"]
