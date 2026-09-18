"""Typer CLI. Each job is a subcommand; Cloud Run Jobs invoke one per execution."""

from __future__ import annotations

import asyncio
import time
import uuid

import typer

from farmerapp.jobs import purge_audit_logs as purge_mod
from farmerapp.jobs import seed as seed_mod
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


def main() -> None:
    cli(prog_name="python -m farmerapp.jobs")
