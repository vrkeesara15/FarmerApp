"""AN-015 weekly owner email: a one-page PDF of the AN-001 owner-home KPIs and the top five
open validation flags, delivered **every Monday at 08:00 IST** to the tenant's owner / director
addresses (``TenantSettings.reports.weekly_owner_emails``).

* Schedule: Cloud Scheduler runs ``python -m farmerapp.jobs weekly-owner-report`` with
  ``WEEKLY_OWNER_CRON`` (``0 8 * * 1``, time zone Asia/Kolkata). The report week is the
  Monday-Sunday week that ended before the latest Monday 08:00 IST at or before ``now``, so a
  late or repeated run still reports the right week; a ``report_run`` per tenant and week
  (``weekly_owner:<monday>``) makes every re-run a no-op.
* KPIs: ``analytics.owner_home.owner_home`` over that week with a tenant-wide scope (as the
  tenant's first active owner, else director) and the flags port — exactly the AN-001 numbers.
* Flags: the five most severe unresolved flags (high, medium, low; oldest first).
* The PDF (fpdf2, core fonts; non-Latin-1 characters are replaced) is also stored in the
  exports bucket.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta

from fpdf import FPDF
from fpdf.enums import XPos, YPos
from sqlalchemy import case, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.filters import AnalyticsFilters, resolve_scope
from farmerapp.analytics.owner_home import owner_home
from farmerapp.analytics.ports import FlagCountsPort
from farmerapp.analytics.schemas import KpiOut
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db.models.tenant import Tenant
from farmerapp.exports.cron import IST, WEEKLY_MONDAY_0800, next_fire
from farmerapp.exports.email import Attachment, Email, EmailSender
from farmerapp.exports.models import ReportKind, ReportRun
from farmerapp.exports.service import claim_run, deliver
from farmerapp.flags.models import UNRESOLVED, Flag
from farmerapp.invoices.pdf import inr
from farmerapp.logging import get_logger
from farmerapp.tenants.settings import get_tenant_settings
from farmerapp.uploads.blobstore import BlobStore

log = get_logger("farmerapp.exports.owner_weekly")

WEEKLY_OWNER_CRON = WEEKLY_MONDAY_0800
TOP_FLAGS = 5
KPI_LABELS = {
    "revenue": "Revenue",
    "own_brand_share": "Own-brand share",
    "credit_outstanding": "Credit outstanding",
    "credit_overdue": "Credit overdue",
    "verified_visits": "Verified visits",
    "active_farmers": "Active farmers (60 days)",
    "open_flags": "Open validation flags",
}


def report_week(now: datetime) -> tuple[date, date]:
    """``(monday, sunday)`` of the week the report covers at ``now``."""
    local = now.astimezone(IST)
    monday = local.date() - timedelta(days=local.weekday())
    if local < datetime.combine(monday, time(8, 0), tzinfo=IST):
        monday -= timedelta(days=7)
    start = monday - timedelta(days=7)
    return start, start + timedelta(days=6)


def next_delivery(after: datetime) -> datetime:
    """The next Monday 08:00 IST (UTC) after ``after``."""
    return next_fire(WEEKLY_OWNER_CRON, after)


@dataclass(frozen=True)
class FlagLine:
    rule_id: str
    severity: str
    title: str
    opened_at: datetime


@dataclass(frozen=True)
class WeeklyReport:
    tenant_name: str
    week_start: date
    week_end: date
    kpis: list[KpiOut]
    flags: list[FlagLine]


def format_kpi(kpi: KpiOut, value: float | None) -> str:
    if value is None:
        return "-"
    if kpi.unit == "paise":
        return f"Rs {inr(round(value))}"
    if kpi.unit == "ratio":
        return f"{value * 100:.1f}%"
    return f"{round(value):,}"


async def _viewer(session: AsyncSession, tenant_id: uuid.UUID) -> User | None:
    for role in (UserRole.OWNER, UserRole.DIRECTOR):
        user = await session.scalar(
            select(User)
            .where(
                User.tenant_id == tenant_id,
                User.role == role.value,
                User.status == UserStatus.ACTIVE.value,
                User.deleted_at.is_(None),
            )
            .order_by(User.created_at, User.id)
            .limit(1)
        )
        if user is not None:
            return user
    return None


async def top_flags(
    session: AsyncSession, tenant_id: uuid.UUID, limit: int = TOP_FLAGS
) -> list[FlagLine]:
    rank = case({"high": 0, "medium": 1, "low": 2}, value=Flag.severity, else_=3)
    rows = await session.execute(
        select(Flag.rule_id, Flag.severity, Flag.title, Flag.created_at)
        .where(
            Flag.tenant_id == tenant_id,
            Flag.deleted_at.is_(None),
            Flag.status.in_([s.value for s in UNRESOLVED]),
        )
        .order_by(rank, Flag.created_at, Flag.id)
        .limit(limit)
    )
    return [FlagLine(*row) for row in rows.tuples()]


async def build_report(
    session: AsyncSession, tenant_id: uuid.UUID, now: datetime, flags: FlagCountsPort
) -> WeeklyReport | None:
    viewer = await _viewer(session, tenant_id)
    tenant = await session.get(Tenant, tenant_id)
    if viewer is None or tenant is None:
        return None
    start, end = report_week(now)
    scope = await resolve_scope(session, viewer, AnalyticsFilters(from_=start, to=end))
    home = await owner_home(session, scope, flags)
    return WeeklyReport(
        tenant_name=tenant.name,
        week_start=start,
        week_end=end,
        kpis=list(home.kpis),
        flags=await top_flags(session, tenant_id),
    )


def _latin1(text: str) -> str:
    return text.encode("latin-1", "replace").decode("latin-1")


def render_pdf(report: WeeklyReport, generated_at: datetime) -> bytes:
    pdf = FPDF(orientation="P", unit="mm", format="A4")
    pdf.set_auto_page_break(auto=False)
    pdf.set_title(_latin1(f"Weekly owner report {report.week_start.isoformat()}"))
    pdf.add_page()

    def text(value: str, *, size: float = 10, bold: bool = False, h: float = 6) -> None:
        pdf.set_font("Helvetica", "B" if bold else "", size)
        pdf.cell(0, h, _latin1(value), new_x=XPos.LMARGIN, new_y=YPos.NEXT)

    week = f"{report.week_start.strftime('%d %b %Y')} - {report.week_end.strftime('%d %b %Y')}"
    text(f"{report.tenant_name}: weekly owner report", size=15, bold=True, h=9)
    text(f"Week {week} (IST)", size=10)
    local = generated_at.astimezone(IST)
    text(f"Generated {local.strftime('%d %b %Y %H:%M')} IST", size=8)
    pdf.ln(3)
    text("Key figures", size=12, bold=True, h=8)
    widths = (70, 40, 40, 40)
    pdf.set_font("Helvetica", "B", 9)
    for w, head in zip(widths, ("KPI", "This week", "Target", "Last year"), strict=True):
        pdf.cell(w, 7, head, border=1)
    pdf.ln(7)
    pdf.set_font("Helvetica", "", 9)
    for kpi in report.kpis:
        cells = (
            KPI_LABELS.get(kpi.key, kpi.key),
            format_kpi(kpi, kpi.value),
            format_kpi(kpi, kpi.target),
            format_kpi(kpi, kpi.last_year),
        )
        for w, cell in zip(widths, cells, strict=True):
            pdf.cell(w, 7, _latin1(cell), border=1)
        pdf.ln(7)
    pdf.ln(4)
    text(f"Top {TOP_FLAGS} open validation flags", size=12, bold=True, h=8)
    if not report.flags:
        text("No open flags.", size=9)
    for i, flag in enumerate(report.flags, start=1):
        age = max((generated_at - flag.opened_at).days, 0)
        pdf.set_font("Helvetica", "", 9)
        pdf.multi_cell(
            0,
            5,
            _latin1(
                f"{i}. [{flag.severity.upper()}] {flag.rule_id}: {flag.title} (open {age} days)"
            ),
            new_x=XPos.LMARGIN,
            new_y=YPos.NEXT,
        )
    pdf.set_y(-20)
    text("Figures as on the owner home (AN-001); flags from the validation inbox.", size=7)
    return bytes(pdf.output())


@dataclass
class WeeklyResult:
    tenant_id: uuid.UUID
    week_start: date | None
    status: str  # sent | failed | no_recipients | already_sent | no_viewer


async def send_weekly_owner_report(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    now: datetime,
    flags: FlagCountsPort,
    store: BlobStore,
    email: EmailSender,
) -> WeeklyResult:
    start, end = report_week(now)
    if await _viewer(session, tenant_id) is None:
        log.warning("weekly_owner_report_no_viewer", tenant_id=str(tenant_id))
        return WeeklyResult(tenant_id, start, "no_viewer")
    run: ReportRun | None = await claim_run(
        session,
        tenant_id=tenant_id,
        kind=ReportKind.WEEKLY_OWNER,
        dedupe_key=f"weekly_owner:{start.isoformat()}",
        period=f"{start.isoformat()}..{end.isoformat()}",
    )
    if run is None:
        return WeeklyResult(tenant_id, start, "already_sent")
    report = await build_report(session, tenant_id, now, flags)
    if report is None:
        run.status = "failed"
        run.error = "no active owner or director"
        return WeeklyResult(tenant_id, start, "no_viewer")
    pdf = render_pdf(report, now)
    filename = f"owner-weekly-{start.isoformat()}.pdf"
    uri = await store.put(
        f"{tenant_id}/reports/weekly_owner/{start.isoformat()}.pdf",
        pdf,
        content_type="application/pdf",
    )
    run.blob_uris = [uri]
    settings = await get_tenant_settings(session, tenant_id)
    recipients = list(settings.reports.weekly_owner_emails)
    await deliver(
        email,
        run,
        recipients,
        Email(
            to=tuple(recipients),
            subject=f"{report.tenant_name}: weekly report {start.strftime('%d %b')} - "
            f"{end.strftime('%d %b %Y')}",
            text="The weekly owner report (key figures and the top open flags) is attached.",
            attachments=(Attachment(filename, pdf, "application/pdf"),),
        ),
    )
    await session.flush()
    log.info(
        "weekly_owner_report",
        tenant_id=str(tenant_id),
        week_start=start.isoformat(),
        status=run.status,
        recipients=run.recipients,
    )
    return WeeklyResult(tenant_id, start, run.status)


def utcnow() -> datetime:
    return datetime.now(UTC)


__all__ = [
    "KPI_LABELS",
    "WEEKLY_OWNER_CRON",
    "WeeklyReport",
    "build_report",
    "next_delivery",
    "render_pdf",
    "report_week",
    "send_weekly_owner_report",
    "top_flags",
]
