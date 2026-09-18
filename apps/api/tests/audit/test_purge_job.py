"""``purge-audit-logs``: NF-012 retention (1 year minimum) as a dry run only, for now."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from typer.testing import CliRunner

from farmerapp.db import audit
from farmerapp.db.session import set_tenant
from farmerapp.jobs import purge_audit_logs as purge_mod
from farmerapp.jobs.cli import cli

NOW = datetime(2026, 9, 17, 9, 0, tzinfo=UTC)


async def test_dry_run_counts_rows_older_than_retention_without_deleting(
    db_session: AsyncSession,
) -> None:
    tenant_id = uuid.uuid4()
    await set_tenant(db_session, tenant_id)
    for age_days in (1, 399, 401, 900):
        row = audit.record(
            db_session,
            action="x.create",
            entity="x",
            entity_id=uuid.uuid4(),
            tenant_id=tenant_id,
        )
        row.created_at = NOW - timedelta(days=age_days)
    await db_session.flush()

    report = await purge_mod.purge_audit_logs(db_session, tenant_id=tenant_id, now=NOW)
    assert report.tenant_id == tenant_id
    assert report.older_than_days == purge_mod.DEFAULT_RETENTION_DAYS == 400
    assert report.cutoff == NOW - timedelta(days=400)
    assert report.rows == 2
    assert report.dry_run is True
    assert await db_session.scalar(text("SELECT count(*) FROM audit_log")) == 4

    shorter = await purge_mod.purge_audit_logs(
        db_session, tenant_id=tenant_id, older_than_days=365, now=NOW
    )
    assert shorter.rows == 3


async def test_retention_below_one_year_is_refused(db_session: AsyncSession) -> None:
    """NF-012: audit logs are kept one year minimum; a shorter purge window is a bug."""
    with pytest.raises(ValueError, match="365"):
        await purge_mod.purge_audit_logs(db_session, tenant_id=uuid.uuid4(), older_than_days=30)


def test_cli_reports_dry_run(monkeypatch: pytest.MonkeyPatch) -> None:
    tenant_id = uuid.UUID(int=7)

    async def fake_run(
        tenant_ids: list[uuid.UUID], older_than_days: int
    ) -> list[purge_mod.PurgeReport]:
        assert tenant_ids == [tenant_id] and older_than_days == 400
        return [
            purge_mod.PurgeReport(
                tenant_id=tenant_id,
                older_than_days=older_than_days,
                cutoff=NOW - timedelta(days=older_than_days),
                rows=12,
            )
        ]

    monkeypatch.setattr(purge_mod, "run_purge", fake_run)
    result = CliRunner().invoke(cli, ["purge-audit-logs", "--tenant-id", str(tenant_id)])
    assert result.exit_code == 0, result.output
    assert (
        "dry-run" in result.output
        and "rows=12" in result.output
        and str(tenant_id) in result.output
    )


def test_cli_lists_the_job() -> None:
    result = CliRunner().invoke(cli, [])
    assert "purge-audit-logs" in result.output
