"""M7 growth jobs, registered on the jobs CLI (``farmerapp.jobs.cli`` imports this module).

=========================== ================ ==============================================
command                     schedule (IST)   requirement
=========================== ================ ==============================================
``send-campaigns``          every minute     WC-008 throttled sends + delivery status
``close-incentives``        1st, 06:00       WC-009 freeze last month's payouts
``stock-alerts``            daily 01:30      ST-004 low-stock and 60 / 30-day expiry alerts
``accounting-export``       daily 02:30      ST-008 yesterday's Tally / Zoho files per store
``run-report-schedules``    every 15 min     WC-013 scheduled reports by email
``weekly-owner-report``     Monday 08:00     AN-015 one-page owner PDF by email
=========================== ================ ==============================================
"""

from __future__ import annotations

import asyncio
from datetime import date

import typer

from farmerapp.jobs.cli import _setup, _tenants, cli

TenantOption = typer.Option(..., "--tenant", "--tenant-id", help="Tenant id or demo slug.")


@cli.command("send-campaigns")
def send_campaigns(tenant: list[str] = TenantOption) -> None:
    """WC-008: send due campaigns (at most `campaigns.sends_per_run` recipients per tenant and
    run, consent re-checked right before sending), then refresh delivery status."""
    from farmerapp.campaigns.jobs import run_send_campaigns

    _setup()
    for report, changed in asyncio.run(run_send_campaigns(_tenants(tenant))):
        typer.echo(
            f"send-campaigns: tenant={report.tenant_id} campaigns={report.campaigns} "
            f"sent={report.sent} failed={report.failed} skipped={sum(report.skipped.values())} "
            f"finished={len(report.finished)} delivery_updates={changed}"
        )


@cli.command("close-incentives")
def close_incentives(
    tenant: list[str] = TenantOption,
    month: str | None = typer.Option(
        None, "--month", help="Any day of the month to close (YYYY-MM-DD); default last month."
    ),
) -> None:
    """WC-009: freeze every field officer's payout of an ended month with the active rules
    (idempotent: frozen officer-months are never recomputed)."""
    from farmerapp.incentives.jobs import run_close_incentives

    _setup()
    when = date.fromisoformat(month) if month else None
    for r in asyncio.run(run_close_incentives(_tenants(tenant), month=when)):
        typer.echo(
            f"close-incentives: tenant={r.tenant_id} month={r.month} closed={len(r.closed)} "
            f"already_closed={r.already_closed} total_paise={r.total_paise} "
            f"rule_version={r.rule_version}"
        )


@cli.command("stock-alerts")
def stock_alerts(tenant: list[str] = TenantOption) -> None:
    """ST-004: nightly low-stock (below the reorder level) and expiry (60 / 30 days) alerts to
    store managers, deduplicated per SKU until restock and per batch and threshold."""
    from farmerapp.stock.alerts import run_stock_alerts

    _setup()
    for r in asyncio.run(run_stock_alerts(_tenants(tenant))):
        typer.echo(
            f"stock-alerts: tenant={r.tenant_id} day={r.day} low={len(r.low)} "
            f"expiring={len(r.expiring)} notifications={r.notifications} "
            f"deduplicated={r.deduplicated}"
        )


@cli.command("accounting-export")
def accounting_export(
    tenant: list[str] = TenantOption,
    day: str | None = typer.Option(
        None, "--date", help="IST business day (YYYY-MM-DD); default yesterday."
    ),
) -> None:
    """ST-008: per store, the day's Tally CSV + voucher XML and Zoho Books CSV into the exports
    bucket, emailed to `reports.accounting_emails` (once per store and day)."""
    from farmerapp.exports.jobs import run_accounting_export

    _setup()
    when = date.fromisoformat(day) if day else None
    for r in asyncio.run(run_accounting_export(_tenants(tenant), day=when)):
        typer.echo(
            f"accounting-export: tenant={r.tenant_id} date={r.day} stores={len(r.stores)} "
            f"already_sent={r.already_sent} vouchers={r.vouchers}"
        )


@cli.command("run-report-schedules")
def run_report_schedules(tenant: list[str] = TenantOption) -> None:
    """WC-013: run every due scheduled report as its owner and email it."""
    from farmerapp.exports.jobs import run_report_schedules as run

    _setup()
    for r in asyncio.run(run(_tenants(tenant))):
        typer.echo(
            f"run-report-schedules: tenant={r.tenant_id} ran={len(r.ran)} "
            f"failed={len(r.failed)} skipped={r.skipped}"
        )


@cli.command("weekly-owner-report")
def weekly_owner_report(tenant: list[str] = TenantOption) -> None:
    """AN-015: the one-page owner PDF (AN-001 KPIs + top five flags) for last week, emailed to
    `reports.weekly_owner_emails`. Monday 08:00 IST; re-runs send nothing twice."""
    from farmerapp.exports.jobs import run_weekly_owner_report

    _setup()
    for r in asyncio.run(run_weekly_owner_report(_tenants(tenant))):
        typer.echo(f"weekly-owner-report: tenant={r.tenant_id} week={r.week_start} {r.status}")


__all__ = [
    "accounting_export",
    "close_incentives",
    "run_report_schedules",
    "send_campaigns",
    "stock_alerts",
    "weekly_owner_report",
]
