"""Typer CLI. Each job is a subcommand; Cloud Run Jobs invoke one per execution."""

from __future__ import annotations

import asyncio
import time
import uuid

import typer

from farmerapp.duty import auto_end as duty_jobs
from farmerapp.jobs import purge_audit_logs as purge_mod
from farmerapp.jobs import purge_expired as expired_mod
from farmerapp.jobs import seed as seed_mod
from farmerapp.location import partitions
from farmerapp.location.models import LOCATION_RETENTION_DAYS
from farmerapp.logging import configure_logging, get_logger
from farmerapp.settings import get_settings

cli = typer.Typer(help="FarmerApp batch jobs.", no_args_is_help=True, add_completion=False)


def _setup() -> None:
    settings = get_settings()
    configure_logging(level=settings.log_level, json_logs=settings.log_json, service="jobs")


@cli.command()
def hello(name: str = typer.Option("world", help="Who to greet.")) -> None:
    """No-op job used to verify the jobs image and scheduler wiring."""
    _setup()
    get_logger("farmerapp.jobs.hello").info("hello", name=name)
    typer.echo(f"hello, {name}")


@cli.command()
def seed(
    small: bool = typer.Option(False, help="Seed the small profile (test fixture size)."),
) -> None:
    """Upsert the demo tenants "Future Crop Care" (fcc) and "Green Fields" (gfl): users (one
    per role), clusters, stores, officers, villages, farmers, farms, crop plots and consent
    records (SPEC 10.5). Idempotent: running it twice yields the same counts.
    """
    _setup()
    started = time.perf_counter()
    result = asyncio.run(seed_mod.run_seed(seed_mod.SMALL if small else seed_mod.FULL))
    elapsed = time.perf_counter() - started
    get_logger("farmerapp.jobs.seed").info(
        "seed_done",
        tenant=result.tenant_slug,
        users_created=result.users_created,
        created=dict(result.created),
        totals=dict(result.totals),
        seconds=round(elapsed, 2),
    )
    typer.echo(
        f"seed: tenant={result.tenant_slug} ({result.tenant_id}) "
        f"users_created={result.users_created} in {elapsed:.1f}s"
    )
    for table in seed_mod.SEEDED_TABLES:
        typer.echo(f"  {table:<15} created={result.created[table]:<5} total={result.totals[table]}")


@cli.command("purge-audit-logs")
def purge_audit_logs(
    tenant_id: list[uuid.UUID] = typer.Option(  # noqa: B008
        ..., "--tenant-id", help="Tenant(s) to report on (repeatable)."
    ),
    older_than_days: int = typer.Option(
        purge_mod.DEFAULT_RETENTION_DAYS,
        help="Retention window in days (NF-012: audit logs are kept one year minimum).",
    ),
) -> None:
    """Report audit rows older than the retention window (dry run; nothing is deleted).

    The real purge (archive, then delete as the migrate role) lands with OPS / NF-012.
    """
    _setup()
    reports = asyncio.run(purge_mod.run_purge(tenant_id, older_than_days))
    for report in reports:
        typer.echo(
            f"purge-audit-logs (dry-run): tenant={report.tenant_id} "
            f"older_than_days={report.older_than_days} cutoff={report.cutoff.isoformat()} "
            f"rows={report.rows}"
        )


@cli.command("purge-expired")
def purge_expired(
    tenant_id: list[uuid.UUID] = typer.Option(  # noqa: B008
        ..., "--tenant-id", help="Tenant(s) to purge (repeatable)."
    ),
) -> None:
    """Delete expired pending uploads (with staged chunks) and expired Idempotency-Key rows
    (NF-003). Safe to run every 15 minutes."""
    _setup()
    for report in asyncio.run(expired_mod.run_purge_expired(tenant_id)):
        typer.echo(
            f"purge-expired: tenant={report.tenant_id} upload_sessions={report.upload_sessions} "
            f"upload_chunks={report.upload_chunks} idempotency_keys={report.idempotency_keys}"
        )


@cli.command("ensure-partitions")
def ensure_partitions(
    days_ahead: int = typer.Option(
        partitions.DEFAULT_DAYS_AHEAD, help="Create location_point partitions up to today + N."
    ),
) -> None:
    """Create the missing daily partitions of ``location_point`` (yesterday .. today + N).
    Run daily (Cloud Scheduler); idempotent."""
    _setup()
    created = asyncio.run(partitions.run_ensure_partitions(days_ahead))
    typer.echo(f"ensure-partitions: days_ahead={days_ahead} created={len(created)}")
    for name in created:
        typer.echo(f"  {name}")


@cli.command("purge-location-points")
def purge_location_points(
    retention_days: int = typer.Option(
        LOCATION_RETENTION_DAYS,
        help="Days of raw points to keep (SPEC 2.6: 180 minimum; the function refuses less).",
    ),
    apply: bool = typer.Option(
        False, "--apply", help="Aggregate into location_daily_agg and drop the partitions."
    ),
) -> None:
    """Report (default) or apply the SPEC 2.6 retention: partitions older than the window
    are folded into ``location_daily_agg`` (km, points, first / last ts per officer and
    day) and dropped."""
    _setup()
    report = asyncio.run(partitions.run_purge(retention_days=retention_days, apply=apply))
    mode = "apply" if apply else "dry-run"
    typer.echo(
        f"purge-location-points ({mode}): retention_days={retention_days} "
        f"partitions={len(report)} points={sum(r.points for r in report)}"
    )
    for row in report:
        state = "dropped" if row.dropped else "kept"
        typer.echo(
            f"  {row.partition} day={row.day} points={row.points} "
            f"officer_days={row.officer_days} {state}"
        )


@cli.command("auto-end-duty")
def auto_end_duty(
    tenant_id: list[uuid.UUID] = typer.Option(  # noqa: B008
        ..., "--tenant-id", help="Tenant(s) to process (repeatable)."
    ),
) -> None:
    """VV-007: end open duty sessions past the tenant's auto-end time (IST) or idle at home
    for ``idle_end_minutes``; writes a notification for the officer. Run every 10 minutes."""
    _setup()
    results = asyncio.run(duty_jobs.run_auto_end(tenant_id))
    typer.echo(f"auto-end-duty: tenants={len(tenant_id)} ended={len(results)}")
    for r in results:
        typer.echo(
            f"  tenant={r.tenant_id} session={r.duty_session_id} officer={r.officer_id} "
            f"{r.end_reason} at {r.end_at.isoformat()}"
        )


@cli.command("officer-sync-silence")
def officer_sync_silence(
    tenant_id: list[uuid.UUID] = typer.Option(  # noqa: B008
        ..., "--tenant-id", help="Tenant(s) to process (repeatable)."
    ),
) -> None:
    """OPS-006: notify cluster heads of officers on duty with no location batch for 2 h
    (one notification per session). Run every 30 minutes."""
    _setup()
    results = asyncio.run(duty_jobs.run_sync_silence(tenant_id))
    typer.echo(f"officer-sync-silence: tenants={len(tenant_id)} silent={len(results)}")
    for r in results:
        typer.echo(
            f"  tenant={r.tenant_id} session={r.duty_session_id} officer={r.officer_id} "
            f"last_contact={r.last_contact_at.isoformat()} notified={len(r.notified)}"
        )


def main() -> None:
    cli(prog_name="python -m farmerapp.jobs")
