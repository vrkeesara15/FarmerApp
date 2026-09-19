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


@cli.command("store-day-watch")
def store_day_watch(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    day: str | None = typer.Option(
        None, "--date", help="Business date (YYYY-MM-DD, IST); default today."
    ),
) -> None:
    """OPS-007: on a working day (tenant calendar, Mon-Sat minus holidays), after 22:00 IST,
    notify the store manager and cluster head of every store with zero sales or a day not
    closed by the deadline (once per store, day and kind). Daily at 22:15 IST."""
    from datetime import date

    from farmerapp.ops.store_watch import run_store_day_watch

    _setup()
    when = date.fromisoformat(day) if day else None
    for r in asyncio.run(run_store_day_watch(_tenants(tenant), day=when)):
        state = (
            "checked"
            if r.working_day and r.checked
            else ("not a working day" if not r.working_day else "before the deadline")
        )
        typer.echo(
            f"store-day-watch: tenant={r.tenant_id} date={r.day} {state} stores={r.stores} "
            f"alerts={len(r.alerts)}"
        )
        for a in r.alerts:
            typer.echo(f"  {a.store_code} {a.kind.value} notified={len(a.notified)}")


@cli.command("pii-backfill")
def pii_backfill(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    batch_size: int = typer.Option(500, min=1, help="Rows per batch (one transaction each)."),
    clear_plaintext: bool = typer.Option(
        False, "--clear-plaintext", help="NULL the plain columns of rows already encrypted."
    ),
    restore_plaintext: bool = typer.Option(
        False, "--restore-plaintext", help="Rollback aid: decrypt into empty plain columns."
    ),
) -> None:
    """SEC-026 step 2 (after Alembic 0025): encrypt user / farmer phones and farmer landmarks
    written before, with their searchable hash. Idempotent and resumable (docs/runbooks/
    pii-encryption.md)."""
    from farmerapp.pii.backfill import Mode, run_backfill

    _setup()
    if clear_plaintext and restore_plaintext:
        raise typer.BadParameter("choose one of --clear-plaintext / --restore-plaintext")
    mode: Mode = "clear" if clear_plaintext else "restore" if restore_plaintext else "encrypt"
    for r in asyncio.run(run_backfill(_tenants(tenant), mode=mode, batch_size=batch_size)):
        typer.echo(
            f"pii-backfill ({r.mode}): tenant={r.tenant_id} changed={r.changed} "
            f"remaining={r.remaining}"
        )
        for name, t in r.tables.items():
            typer.echo(
                f"  {name} scanned={t.scanned} changed={t.changed} conflicts={t.conflicts} "
                f"remaining={t.remaining}"
            )


@cli.command("reconcile-payments")
def reconcile_payments(
    tenant_id: list[uuid.UUID] = typer.Option(  # noqa: B008
        ..., "--tenant-id", help="Tenant(s) to reconcile (repeatable)."
    ),
    day: str | None = typer.Option(
        None, "--date", help="Business date (YYYY-MM-DD, IST); default yesterday."
    ),
) -> None:
    """OPS-008: compare the provider's settlements of a day with our paid UPI / link payments
    and report mismatches (dry run: nothing changes; accountants are notified). Daily."""
    from datetime import UTC, date, datetime, timedelta

    from farmerapp.payments.config import IST
    from farmerapp.payments.reconcile import run_reconcile
    from farmerapp.payments.service import build_provider

    _setup()
    when = (
        date.fromisoformat(day)
        if day
        else (datetime.now(UTC).astimezone(IST) - timedelta(days=1)).date()
    )
    reports = asyncio.run(run_reconcile(tenant_id, when, build_provider(get_settings())))
    for r in reports:
        typer.echo(
            f"reconcile-payments (dry-run): tenant={r.tenant_id} date={r.day} "
            f"settlements={r.settlements} paid={r.paid_payments} matched={r.matched} "
            f"mismatches={len(r.mismatches)} notified={r.notified} flag={r.flag_id}"
        )
        for m in r.mismatches:
            typer.echo(
                f"  {m.kind} ref={m.provider_ref} payment={m.payment_id} "
                f"ours={m.ours_paise} theirs={m.theirs_paise}"
            )


def _tenants(values: list[str]) -> list[uuid.UUID]:
    from farmerapp.rules.jobs import UnknownTenantError, resolve_tenant

    try:
        return [resolve_tenant(v) for v in values]
    except UnknownTenantError as exc:
        raise typer.BadParameter(str(exc), param_hint="--tenant") from exc


@cli.command("run-rules")
def run_rules(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    mode: str = typer.Option("batch", help="Runner: batch (nightly 02:00 IST) or inline."),
    rule: list[str] = typer.Option(  # noqa: B008
        [], "--rule", help="Only these rule ids (repeatable; default: every enabled rule)."
    ),
) -> None:
    """VA-001 / SPEC 6.1: run the validation rules of one mode over each tenant and raise
    flags. Idempotent (dedupe key): re-running never duplicates an open flag."""
    from farmerapp.rules.jobs import run_rules_job
    from farmerapp.rules.schema import Mode

    _setup()
    try:
        runner = Mode(mode)
    except ValueError as exc:
        raise typer.BadParameter(f"unknown mode {mode!r}", param_hint="--mode") from exc
    if runner == Mode.EVENT:
        raise typer.BadParameter("event rules run on their topics", param_hint="--mode")
    reports = asyncio.run(run_rules_job(_tenants(tenant), mode=runner, rule_ids=rule or None))
    for r in reports:
        typer.echo(
            f"run-rules ({r.mode.value}): tenant={r.tenant_id} rules={len(r.rules_run)} "
            f"findings={sum(r.findings.values())} raised={r.total_raised} failed={len(r.failed)}"
        )
        for rule_id in r.rules_run:
            typer.echo(f"  {rule_id} findings={r.findings[rule_id]} raised={r.raised[rule_id]}")
        for rule_id in r.failed:
            typer.echo(f"  {rule_id} FAILED")


@cli.command("validate-rules")
def validate_rules_command(
    rules_dir: str | None = typer.Option(
        None, "--rules-dir", help="Rule directory (default: RULES_DIR or the monorepo rules/)."
    ),
) -> None:
    """VA-001 / VA-007 (CI, `make check-api`): every rules/*.yaml validates, matches a Python
    implementation, and ships a positive and a negative fixture. Exit 1 on any problem."""
    from farmerapp.rules.loader import (
        RuleConfigError,
        check_fixtures,
        check_registry,
        load_rules,
    )
    from farmerapp.rules.loader import rules_dir as default_rules_dir
    from farmerapp.rules.registry import implementations

    _setup()
    try:
        rule_set = load_rules(rules_dir or default_rules_dir())
    except RuleConfigError as exc:
        typer.echo(f"validate-rules: {exc}", err=True)
        raise typer.Exit(1) from exc
    implemented = implementations()
    problems = check_registry(rule_set, implemented) + check_fixtures(rule_set, implemented)
    for problem in problems:
        typer.echo(f"validate-rules: {problem}", err=True)
    if problems:
        raise typer.Exit(1)
    typer.echo(f"validate-rules: {len(rule_set.rules)} rules OK ({', '.join(rule_set.rules)})")


@cli.command("backfill-farm-photo-phash")
def backfill_farm_photo_phash(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    batch_size: int = typer.Option(200, min=1, help="Photos read per page."),
    run_rules: bool = typer.Option(
        True, "--run-rules/--no-run-rules", help="Run VA-F08 on the farms that got a hash."
    ),
) -> None:
    """VA-F08: compute ``farm_photo.phash`` for farm photos stored before Alembic 0023 (read
    from the blob store), then run VA-F08 on their farms. Idempotent: only photos without a
    hash are read; missing / undecodable blobs stay NULL and are reported."""
    from farmerapp.farmers.photo_hash import backfill_farm_photo_phash as backfill
    from farmerapp.uploads.blobstore import build_blob_store

    _setup()
    blobs = build_blob_store(get_settings())
    reports = asyncio.run(
        backfill(_tenants(tenant), blobs=blobs, batch_size=batch_size, run_rules=run_rules)
    )
    for r in reports:
        typer.echo(
            f"backfill-farm-photo-phash: tenant={r.tenant_id} scanned={r.scanned} "
            f"hashed={r.hashed} unhashable={r.unhashable} farms_checked={r.farms_checked} "
            f"flags_raised={r.flags_raised}"
        )


@cli.command("flags-sla-escalation")
def flags_sla_escalation(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
) -> None:
    """OPS-010: move every unresolved flag past its SLA one level up (store manager ->
    cluster head -> auditor -> owner) and notify the new owner. Run hourly."""
    from farmerapp.rules.jobs import run_sla_escalation

    _setup()
    for r in asyncio.run(run_sla_escalation(_tenants(tenant))):
        typer.echo(f"flags-sla-escalation: tenant={r.tenant_id} escalated={len(r.escalations)}")
        for e in r.escalations:
            typer.echo(f"  flag={e.flag_id} rule={e.rule_id} -> {e.to_role} {e.to_owner_id}")


@cli.command("diagnosis-queue-age")
def diagnosis_queue_age(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    day: str | None = typer.Option(
        None, "--date", help="IST day of the LLM fallback rate (YYYY-MM-DD); default today."
    ),
) -> None:
    """OPS-009 / DX-006: alert agronomists once per diagnosis waiting > 18 h for review,
    re-deliver stale queued diagnoses, log the day's LLM fallback rate and alert above 40 %.
    Hourly."""
    from datetime import date

    from farmerapp.diagnosis.services import worker_services
    from farmerapp.ops.diagnosis_watch import run_diagnosis_watch

    _setup()
    when = date.fromisoformat(day) if day else None
    reports = asyncio.run(
        run_diagnosis_watch(_tenants(tenant), day=when, services=worker_services())
    )
    for r in reports:
        typer.echo(
            f"diagnosis-queue-age: tenant={r.tenant_id} queue={r.queue} overdue={r.overdue} "
            f"newly_alerted={len(r.alerted)} redelivered={len(r.redelivered)} "
            f"day={r.day} answered={r.answered} llm_rate={r.llm_rate} alert={r.llm_alert}"
        )


def main() -> None:
    cli(prog_name="python -m farmerapp.jobs")
