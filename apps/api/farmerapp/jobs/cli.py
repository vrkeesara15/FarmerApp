"""Typer CLI. Each job is a subcommand; Cloud Run Jobs invoke one per execution."""

from __future__ import annotations

import asyncio
import time
import uuid
from typing import Any

import typer

from farmerapp import retention
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
    # Rule ports the jobs process needs: the nightly `run-rules` batch reads WC-008 campaign
    # audiences (VA-F09) and FA-023 travel claims (VA-E07) through them.
    from farmerapp.campaigns import membership as campaign_membership
    from farmerapp.travel import rules_port as travel_rules_port

    campaign_membership.register()
    travel_rules_port.register()


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


@cli.command("retention-sweep")
def retention_sweep(
    tenant_id: list[uuid.UUID] = typer.Option(  # noqa: B008
        ..., "--tenant-id", help="Tenant(s) to sweep (repeatable)."
    ),
    retention_class: list[str] = typer.Option(  # noqa: B008
        [], "--class", help="Only these classes (see --help for the list)."
    ),
    apply: bool = typer.Option(
        False, "--apply", help="Actually delete. Without it nothing is deleted (NF-012)."
    ),
) -> None:
    """NF-012: report every retention class and, with --apply, purge what the runtime role may.

    Dry run by default. Financial records (8 years) are a floor and are never deleted here;
    audit logs and location points name the job that owns their purge.
    """
    _setup()
    reports = asyncio.run(
        retention.run_sweep(tenant_id, apply=apply, classes=tuple(retention_class))
    )
    for report in reports:
        mode = "apply" if report.applied else "dry-run"
        typer.echo(f"retention-sweep ({mode}): tenant={report.tenant_id}")
        for entry in report.classes:
            suffix = f" -> {entry.deferred_to}" if entry.deferred_to else ""
            typer.echo(
                f"  {entry.name:<18} {entry.action:<8} {entry.days:>5}d "
                f"due={entry.due:<7} deleted={entry.deleted}{suffix}"
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


@cli.command("flags-summarise")
def flags_summarise(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    max_age_days: int = typer.Option(7, min=1, help="Only flags raised in the last N days."),
    limit: int = typer.Option(200, min=1, help="At most this many flags per tenant and run."),
) -> None:
    """VA-004: the review agent summarises every recent flag that has no summary yet (flags
    raised on the API path). Needs FLAG_SUMMARY_LLM (off: nothing happens). Every 10 min."""
    from farmerapp.flags.review_agent import summarise_pending

    _setup()
    for r in asyncio.run(
        summarise_pending(_tenants(tenant), max_age_days=max_age_days, limit=limit)
    ):
        typer.echo(
            f"flags-summarise: tenant={r.tenant_id} done={r.done} other={r.other} "
            f"deferred={r.deferred}"
        )


@cli.command("rules-quality-report")
def rules_quality_report(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
) -> None:
    """VA-006: the weekly rule-quality report (precision per rule, last week and four weeks)
    to the tenant admins; rules under 30 % precision over four weeks are auto-disabled
    pending review (audited). Weekly, Monday 03:00 IST."""
    from farmerapp.flags.precision import run_quality_reports

    _setup()
    for r in asyncio.run(run_quality_reports(_tenants(tenant))):
        typer.echo(
            f"rules-quality-report: tenant={r.tenant_id} rules={len(r.rules)} "
            f"auto_disabled={','.join(r.auto_disabled) or '-'} notified={len(r.notified)}"
        )
        for q in r.rules:
            p = q.four_weeks.precision
            typer.echo(
                f"  {q.rule_id} enabled={q.enabled} 4w_resolved={q.four_weeks.resolved} "
                f"4w_precision={'-' if p is None else f'{p:.0%}'}"
            )


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


@cli.command("deliver-notifications")
def deliver_notifications(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
) -> None:
    """FA-007: push the due pending notifications to the users' active devices (retries back
    off per row; PUSH_PROVIDER). Every minute, next to the notify.send worker."""
    from farmerapp.jobs.field_p1 import run_deliver_notifications

    _setup()
    for tenant_id, r in asyncio.run(run_deliver_notifications(_tenants(tenant))):
        typer.echo(
            f"deliver-notifications: tenant={tenant_id} delivered={r.delivered} "
            f"no_device={r.no_device} retrying={r.retrying} failed={r.failed}"
        )


@cli.command("process-tracks")
def process_tracks_command(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
) -> None:
    """VV-006: (re-)process duty sessions ended in the last 3 days with the configured road
    snapper (ROAD_SNAPPER; km, stops, gaps). Every 30 minutes."""
    from farmerapp.jobs.field_p1 import run_process_tracks

    _setup()
    for r in asyncio.run(run_process_tracks(_tenants(tenant))):
        typer.echo(
            f"process-tracks: tenant={r.tenant_id} processed={r.processed} source={r.km_source}"
        )


@cli.command("generate-beat-plans")
def generate_beat_plans(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    day: str | None = typer.Option(None, "--date", help="IST day (YYYY-MM-DD); default today."),
) -> None:
    """FA-018: today's beat plan for every active field officer (existing plans are kept).
    Daily at 06:00 IST."""
    from datetime import date

    from farmerapp.jobs.field_p1 import run_generate_beat_plans

    _setup()
    when = date.fromisoformat(day) if day else None
    for r in asyncio.run(run_generate_beat_plans(_tenants(tenant), day=when)):
        typer.echo(
            f"generate-beat-plans: tenant={r.tenant_id} date={r.day} officers={r.officers} "
            f"generated={r.generated}"
        )


# --------------------------------------------------------------------------- M7 farmer P1
@cli.command("calendar-reminders")
def calendar_reminders(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
) -> None:
    """FM-007: generate missing / stale crop calendars and write today's task reminders
    (notification rows) for farmers with an app login, outside the tenant's quiet hours.
    Daily 07:00 IST."""
    from farmerapp.advisory.calendar import run_calendar_reminders

    _setup()
    for r in asyncio.run(run_calendar_reminders(_tenants(tenant))):
        typer.echo(
            f"calendar-reminders: tenant={r.tenant_id} day={r.day} state={r.state} "
            f"plots={r.plots_checked} generated={r.tasks_generated} "
            f"reminded={len(r.reminded)} no_login={r.no_login}"
        )


@cli.command("outbreak-detection")
def outbreak_detection(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    weeks_back: int = typer.Option(1, min=0, max=8, help="Also re-evaluate N weeks before."),
) -> None:
    """DX-013 / FM-009: cluster confirmed diagnoses by district, crop, problem and ISO week;
    raise outbreak alerts where the tenant rule fires and notify farmers growing the crop in
    the district, officers and agronomists (once per alert). Daily 06:30 IST."""
    from farmerapp.advisory.outbreaks import run_outbreak_detection

    _setup()
    for r in asyncio.run(run_outbreak_detection(_tenants(tenant), weeks_back=weeks_back)):
        typer.echo(
            f"outbreak-detection: tenant={r.tenant_id} weeks={[w.isoformat() for w in r.weeks]} "
            f"cells={r.cells} fired={len(r.fired)} new_alerts={len(r.created)} "
            f"notified_farmers={r.notified_farmers} notified_staff={r.notified_staff}"
        )
        for c in r.fired:
            typer.echo(
                f"  {c.district} crop={c.crop_id} problem={c.problem_id} week={c.week_start} "
                f"cases={c.cases} prior_mean={c.prior_mean}"
            )


@cli.command("diagnosis-evaluate")
def diagnosis_evaluate(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    manifest: str | None = typer.Option(
        None, help="Manifest key in CORPUS_BUCKET or gs:// URI (default DIAGNOSIS_EVAL_MANIFEST)."
    ),
    llm: str = typer.Option(
        "off", help="LLM fallback during the run: off (default), fake, or configured."
    ),
) -> None:
    """DX-011: evaluate the diagnosis pipeline on the held-out, agronomist-labelled manifest
    (rolled back: nothing written but the run), record an evaluation_run with metrics per
    crop and problem, and alert when top-1 accuracy drops by more than 5 points. Nightly."""
    from farmerapp.diagnosis.services import build_diagnosis_services
    from farmerapp.mlops.evaluation import run_nightly_evaluation

    _setup()
    if llm not in ("off", "fake", "configured"):
        raise typer.BadParameter("off | fake | configured", param_hint="--llm")
    settings = get_settings()
    if llm != "configured":
        settings = settings.model_copy(update={"diagnosis_llm": llm})
    services = build_diagnosis_services(settings)
    runs = asyncio.run(
        run_nightly_evaluation(_tenants(tenant), services=services, manifest=manifest)
    )
    failed = False
    for r in runs:
        failed |= r.status != "ok"
        typer.echo(
            f"diagnosis-evaluate: tenant={r.tenant_id} status={r.status} cases={r.cases} "
            f"top1={r.top1_accuracy} corpus_share={r.corpus_answer_share} "
            f"escalation={r.escalation_rate} delta_points={r.top1_delta_points} "
            f"alerted={r.alerted}"
        )
    if failed:
        raise typer.Exit(1)


@cli.command("export-training-set")
def export_training_set(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    include_public: bool = typer.Option(
        False, "--include-public", help="Also export the public bootstrap images."
    ),
) -> None:
    """DX-012: export the approved corpus field images as a training manifest (ml/ondevice
    format) into the corpus bucket for the monthly on-device fine-tune. Weekly."""
    from farmerapp.mlops.evaluation import corpus_blob_store
    from farmerapp.mlops.training_export import run_export

    _setup()
    sources = ("internal", "public") if include_public else ("internal",)
    blobs = corpus_blob_store(get_settings())
    for r in asyncio.run(run_export(_tenants(tenant), blobs=blobs, sources=sources)):
        typer.echo(
            f"export-training-set: tenant={r.tenant_id} images={r.images} "
            f"per_crop={r.per_crop} per_split={r.per_split} manifest={r.manifest_uri}"
        )


@cli.command("register-model-candidate")
def register_model_candidate(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    artifact_uri: str = typer.Option(..., help="gs:// URI of the candidate .tflite."),
    metadata_uri: str = typer.Option(..., help="gs:// URI of its metadata.json."),
    training_manifest_uri: str | None = typer.Option(None, help="Training manifest used."),
    pipeline_run: str | None = typer.Option(None, help="Vertex AI pipeline run name."),
) -> None:
    """DX-012: record a fine-tuned on-device model as a release candidate (sha256 from the
    bytes) and notify the approvers. The last step of the retraining pipeline; manual."""
    from farmerapp.mlops.evaluation import corpus_blob_store
    from farmerapp.mlops.releases import run_register_candidate

    _setup()
    results = asyncio.run(
        run_register_candidate(
            _tenants(tenant),
            blobs=corpus_blob_store(get_settings()),
            artifact_uri=artifact_uri,
            metadata_uri=metadata_uri,
            training_manifest_uri=training_manifest_uri,
            pipeline_run=pipeline_run,
        )
    )
    for tenant_id, row, created in results:
        typer.echo(
            f"register-model-candidate: tenant={tenant_id} release={row.id} "
            f"version={row.model_version} status={row.status} created={created}"
        )


@cli.command("reembed-corpus")
def reembed_corpus(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    encoder_name: str = typer.Option(..., help="New encoder name (the embed service's)."),
    encoder_version: str = typer.Option(..., help="New encoder version."),
    batch_size: int = typer.Option(32, min=1, max=256, help="Images per embed call."),
    max_images: int | None = typer.Option(None, min=1, help="Stop after N (resumable)."),
    embed_url: str | None = typer.Option(
        None, help="Base URL of the new embed service (default DIAGNOSIS_EMBED_URL)."
    ),
) -> None:
    """DX-012: embed every live corpus image with a new encoder into corpus_embedding
    (staging; resumable). Nothing changes for diagnoses until activate-encoder. Manual."""
    from farmerapp.diagnosis.encoder import build_encoder
    from farmerapp.mlops.reembed import run_reembed
    from farmerapp.uploads.blobstore import build_blob_store

    _setup()
    settings = get_settings().model_copy(
        update={
            "diagnosis_encoder_name": encoder_name,
            "diagnosis_encoder_version": encoder_version,
            **({"diagnosis_embed_url": embed_url} if embed_url else {}),
        }
    )
    encoder = build_encoder(settings)
    if encoder.info.name != encoder_name or encoder.info.version != encoder_version:
        raise typer.BadParameter(
            f"the configured encoder answers as {encoder.info.label}", param_hint="--encoder-name"
        )
    reports = asyncio.run(
        run_reembed(
            _tenants(tenant),
            encoder=encoder,
            blobs=build_blob_store(settings),
            batch_size=batch_size,
            max_images=max_images,
        )
    )
    for r in reports:
        typer.echo(
            f"reembed-corpus: tenant={r.tenant_id} encoder={r.encoder} embedded={r.embedded} "
            f"remaining={r.remaining} missing_blobs={len(r.missing_blobs or [])}"
        )


@cli.command("activate-encoder")
def activate_encoder(
    tenant: list[str] = typer.Option(  # noqa: B008
        ..., "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable)."
    ),
    encoder_name: str = typer.Option(..., help="Encoder to activate."),
    encoder_version: str = typer.Option(..., help="Its version."),
    note: str | None = typer.Option(None, help="Why (kept on the activation row)."),
) -> None:
    """DX-012: flip the tenant's corpus to a fully staged encoder in one transaction (the
    previous vectors are kept for rollback; audited). Human-run after the threshold retune."""
    from farmerapp.diagnosis.encoder import EncoderInfo
    from farmerapp.mlops.reembed import run_activate

    _setup()
    info = EncoderInfo(name=encoder_name, version=encoder_version)
    for r in asyncio.run(run_activate(_tenants(tenant), encoder=info, note=note)):
        typer.echo(
            f"activate-encoder: tenant={r.tenant_id} encoder={r.encoder} images={r.images} "
            f"previous={r.previous}"
        )


# --------------------------------------------------------------------------- M8 WC-014
@cli.command("usage-recount")
def usage_recount(
    tenant: list[str] = typer.Option(  # noqa: B008
        [], "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable). Default: all."
    ),
) -> None:
    """WC-014: recompute the usage counters from the source tables, one tenant at a time.

    The counters are maintained incrementally on the creation paths; this job exists to
    backfill a tenant that predates them and to prove they have not drifted. It is the only
    place that runs ``count(*)`` over a tenant's farmers or photos, which is why it is a job
    and not a request.
    """
    from farmerapp.platform_admin.jobs import run_recount

    _setup()
    for report in asyncio.run(_recount(tenant)):
        typer.echo(f"usage-recount: tenant={report.tenant_id} counts={report.counts}")
    _ = run_recount


async def _recount(tenant: list[str]) -> list[Any]:
    from farmerapp.platform_admin.jobs import all_tenant_ids, run_recount

    ids = _tenants(tenant) if tenant else [tid async for tid, _slug in all_tenant_ids()]
    return await run_recount(ids)


@cli.command("billing-statements")
def billing_statements(
    tenant: list[str] = typer.Option(  # noqa: B008
        [], "--tenant", "--tenant-id", help="Tenant id or demo slug (repeatable). Default: all."
    ),
    period: str | None = typer.Option(None, help="Billing month YYYY-MM (default: this month)."),
) -> None:
    """WC-014: generate each tenant's monthly usage statement (counts and overage).

    Charging is a documented port, not an implementation: nothing here talks to a payment
    provider (see docs/prs/M8-tenant-admin.md, "Payment port").
    """
    _setup()
    for report in asyncio.run(_statements(tenant, period)):
        typer.echo(
            f"billing-statements: tenant={report.tenant_id} period={report.period} "
            f"total_paise={report.total_paise} overage_paise={report.overage_paise}"
        )


async def _statements(tenant: list[str], period: str | None) -> list[Any]:
    from farmerapp.platform_admin.jobs import all_tenant_ids, run_statements

    ids = _tenants(tenant) if tenant else [tid async for tid, _slug in all_tenant_ids()]
    return await run_statements(ids, period=period)


# M7 growth jobs (WC-008, WC-009, WC-013, AN-015, ST-004, ST-008) register themselves on `cli`.
from farmerapp.jobs import growth as _growth  # noqa: E402, F401


def main() -> None:
    cli(prog_name="python -m farmerapp.jobs")
