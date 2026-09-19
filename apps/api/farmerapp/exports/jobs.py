"""Jobs of the exports package (Cloud Scheduler, times in IST):

=========================== ================ ==============================================
job                         schedule         what
=========================== ================ ==============================================
``run-report-schedules``    every 15 min     WC-013 due ``report_schedule`` rows, emailed
``weekly-owner-report``     Mon 08:00        AN-015 one-page PDF to owners / directors
``accounting-export``       daily 02:30      ST-008 yesterday's Tally CSV / XML + Zoho CSV
                                             per store, stored and emailed to accountants
=========================== ================ ==============================================
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.ports import FlagCountsPort
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.exports import accounting
from farmerapp.exports.cron import IST
from farmerapp.exports.email import Attachment, Email, EmailSender, build_email_sender
from farmerapp.exports.models import ReportKind
from farmerapp.exports.owner_weekly import WeeklyResult, send_weekly_owner_report
from farmerapp.exports.service import (
    ScheduleReport,
    build_exports_store,
    claim_run,
    deliver,
    run_due_schedules,
)
from farmerapp.exports.writers import CSV_MEDIA_TYPE, write_csv
from farmerapp.logging import get_logger
from farmerapp.settings import get_settings
from farmerapp.tenants.models import Store
from farmerapp.tenants.settings import AccountingSettings, get_tenant_settings
from farmerapp.uploads.blobstore import BlobStore

log = get_logger("farmerapp.exports.jobs")

#: Cloud Scheduler entries (time zone Asia/Kolkata) the infra module should create.
SCHEDULES = {
    "run-report-schedules": "*/15 * * * *",
    "weekly-owner-report": "0 8 * * 1",
    "accounting-export": "30 2 * * *",
    "stock-alerts": "30 1 * * *",
    "send-campaigns": "* * * * *",
    "close-incentives": "0 6 1 * *",
}


def _store() -> BlobStore:
    return build_exports_store(get_settings())


def _email() -> EmailSender:
    return build_email_sender(get_settings())


async def run_report_schedules(
    tenant_ids: Sequence[uuid.UUID],
    *,
    now: datetime | None = None,
    store: BlobStore | None = None,
    email: EmailSender | None = None,
) -> list[ScheduleReport]:
    now = now or datetime.now(UTC)
    store = store or _store()
    email = email or _email()
    out: list[ScheduleReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                out.append(
                    await run_due_schedules(
                        session, tenant_id=tenant_id, now=now, store=store, email=email
                    )
                )
    return out


async def run_weekly_owner_report(
    tenant_ids: Sequence[uuid.UUID],
    *,
    now: datetime | None = None,
    flags: FlagCountsPort | None = None,
    store: BlobStore | None = None,
    email: EmailSender | None = None,
) -> list[WeeklyResult]:
    from farmerapp.flags.analytics import FLAG_TABLE_COUNTS

    now = now or datetime.now(UTC)
    store = store or _store()
    email = email or _email()
    out: list[WeeklyResult] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                out.append(
                    await send_weekly_owner_report(
                        session,
                        tenant_id=tenant_id,
                        now=now,
                        flags=flags or FLAG_TABLE_COUNTS,
                        store=store,
                        email=email,
                    )
                )
    return out


# --------------------------------------------------------------------------- ST-008
@dataclass
class AccountingReport:
    tenant_id: uuid.UUID
    day: date
    stores: list[str] = field(default_factory=list)
    already_sent: int = 0
    vouchers: int = 0


def accounting_files(
    data: accounting.AccountingDay, acc: AccountingSettings, company: str
) -> list[Attachment]:
    code = data.store.code
    day = data.day.isoformat()
    tally, _ = write_csv(accounting.TALLY_COLUMNS, accounting.tally_rows(data, acc))
    zoho, _ = write_csv(accounting.ZOHO_COLUMNS, accounting.zoho_rows(data))
    with tally, zoho:
        return [
            Attachment(f"tally-{code}-{day}.csv", tally.read(), CSV_MEDIA_TYPE),
            Attachment(
                f"tally-{code}-{day}.xml",
                accounting.tally_xml(data, acc, company),
                "application/xml",
            ),
            Attachment(f"zoho-{code}-{day}.csv", zoho.read(), CSV_MEDIA_TYPE),
        ]


async def accounting_export(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    day: date,
    store: BlobStore,
    email: EmailSender,
) -> AccountingReport:
    """Per store: the day's three files into the exports bucket and one email to the
    accountants; once per store and day."""
    settings = await get_tenant_settings(session, tenant_id)
    report = AccountingReport(tenant_id=tenant_id, day=day)
    stores = (
        await session.execute(
            select(Store)
            .where(Store.tenant_id == tenant_id, Store.deleted_at.is_(None))
            .order_by(Store.code)
        )
    ).scalars()
    recipients = list(settings.reports.accounting_emails)
    for shop in stores:
        run = await claim_run(
            session,
            tenant_id=tenant_id,
            kind=ReportKind.ACCOUNTING,
            dedupe_key=f"accounting:{shop.id}:{day.isoformat()}",
            period=day.isoformat(),
            store_id=shop.id,
        )
        if run is None:
            report.already_sent += 1
            continue
        data = await accounting.load_day(session, shop, day)
        files = accounting_files(data, settings.accounting, settings.legal_name or shop.name)
        uris = []
        for f in files:
            uris.append(
                await store.put(
                    f"{tenant_id}/accounting/{shop.code}/{day.isoformat()}/{f.filename}",
                    f.content,
                    content_type=f.content_type,
                )
            )
        run.blob_uris = uris
        report.vouchers += len(accounting.vouchers(data, settings.accounting))
        await deliver(
            email,
            run,
            recipients,
            Email(
                to=tuple(recipients),
                subject=f"{shop.code} accounting export {day.strftime('%d-%m-%Y')}",
                text=(
                    f"Sales vouchers {len(data.invoices)}, credit notes {len(data.credit_notes)}, "
                    f"receipts {len(data.receipts)} for {shop.name} on {day.isoformat()}. "
                    "Tally CSV and XML and the Zoho Books CSV are attached."
                ),
                attachments=tuple(files),
            ),
        )
        report.stores.append(shop.code)
    await session.flush()
    log.info(
        "accounting_export",
        tenant_id=str(tenant_id),
        day=day.isoformat(),
        stores=len(report.stores),
        already_sent=report.already_sent,
        vouchers=report.vouchers,
    )
    return report


async def run_accounting_export(
    tenant_ids: Sequence[uuid.UUID],
    *,
    day: date | None = None,
    now: datetime | None = None,
    store: BlobStore | None = None,
    email: EmailSender | None = None,
) -> list[AccountingReport]:
    now = now or datetime.now(UTC)
    day = day or (now.astimezone(IST).date() - timedelta(days=1))
    store = store or _store()
    email = email or _email()
    out: list[AccountingReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                out.append(
                    await accounting_export(
                        session, tenant_id=tenant_id, day=day, store=store, email=email
                    )
                )
    return out


__all__ = [
    "SCHEDULES",
    "AccountingReport",
    "accounting_export",
    "accounting_files",
    "run_accounting_export",
    "run_report_schedules",
    "run_weekly_owner_report",
]
