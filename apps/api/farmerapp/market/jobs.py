"""FM-012 daily job: pull mandi prices for each tenant's districts and pilot crops.

Cloud Scheduler entry (an infra follow-up, like the other M6/M7 jobs):
``python -m farmerapp.jobs mandi-prices --tenant fcc`` daily at 07:30 IST — after the public
feed has published the previous day's arrivals and before the farmer app's morning open.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.market.provider import MandiPriceProvider, build_provider
from farmerapp.market.service import RefreshReport, refresh_prices
from farmerapp.settings import get_settings
from farmerapp.tenants.settings import get_tenant_settings


async def run_mandi_prices(
    tenant_ids: Sequence[uuid.UUID],
    *,
    now: datetime | None = None,
    provider: MandiPriceProvider | None = None,
) -> list[RefreshReport]:
    now = now or datetime.now(UTC)
    provider = provider or build_provider(get_settings())
    out: list[RefreshReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                mandi = (await get_tenant_settings(session, tenant_id)).mandi
                if not mandi.enabled:
                    continue
                out.append(
                    await refresh_prices(
                        session,
                        tenant_id=tenant_id,
                        provider=provider,
                        settings=mandi,
                        now=now,
                    )
                )
    return out


__all__ = ["run_mandi_prices"]
