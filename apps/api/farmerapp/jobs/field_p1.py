"""M7 field P1 scheduled jobs (one ``job_session`` per tenant, the system as audit actor).

============================ ================================ ================================
command                      schedule (Cloud Scheduler, IST)  does
============================ ================================ ================================
``deliver-notifications``    every minute                     FA-007 push the due ``pending``
                                                              notifications (the sweeper next
                                                              to the ``notify.send`` worker)
``process-tracks``           every 30 min                     VV-006 (re-)process ended duty
                                                              sessions with the configured
                                                              road snapper (last 3 days)
``generate-beat-plans``      daily 06:00                      FA-018 today's plan for every
                                                              active field officer
============================ ================================ ================================

The Cloud Scheduler entries are infra work (human-applied in stg / prd); see
docs/prs/M7-field-p1-api.md.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, date, datetime, timedelta

from farmerapp.analytics.filters import today_ist
from farmerapp.beat.service import GenerateReport, generate_for_tenant
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.duty.processing import ProcessReport, process_tracks
from farmerapp.duty.roads import RoadSnapper, build_snapper
from farmerapp.notifications.delivery import DeliveryReport, deliver_pending
from farmerapp.notifications.push import PushSender
from farmerapp.settings import get_settings

PROCESS_LOOKBACK = timedelta(days=3)


async def run_deliver_notifications(
    tenant_ids: Sequence[uuid.UUID],
    *,
    sender: PushSender | None = None,
    now: datetime | None = None,
) -> list[tuple[uuid.UUID, DeliveryReport]]:
    from farmerapp.notifications.service import worker_push_sender

    settings = get_settings()
    sender = sender or worker_push_sender()
    out: list[tuple[uuid.UUID, DeliveryReport]] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                report = await deliver_pending(
                    session,
                    sender,
                    tenant_id=tenant_id,
                    now=now,
                    max_attempts=settings.notify_max_attempts,
                )
        out.append((tenant_id, report))
    return out


async def run_process_tracks(
    tenant_ids: Sequence[uuid.UUID],
    *,
    snapper: RoadSnapper | None = None,
    now: datetime | None = None,
) -> list[ProcessReport]:
    settings = get_settings()
    snapper = snapper or build_snapper(settings.road_snapper, settings.google_maps_api_key)
    now = now or datetime.now(UTC)
    reports: list[ProcessReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(
                    await process_tracks(
                        session,
                        tenant_id=tenant_id,
                        snapper=snapper,
                        since=now - PROCESS_LOOKBACK,
                        now=now,
                    )
                )
    return reports


async def run_generate_beat_plans(
    tenant_ids: Sequence[uuid.UUID], *, day: date | None = None, now: datetime | None = None
) -> list[GenerateReport]:
    now = now or datetime.now(UTC)
    day = day or today_ist(now)
    reports: list[GenerateReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(await generate_for_tenant(session, tenant_id, day, now=now))
    return reports


__all__ = ["run_deliver_notifications", "run_generate_beat_plans", "run_process_tracks"]
