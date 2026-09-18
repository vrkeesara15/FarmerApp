"""The ``auto-end-duty`` and ``officer-sync-silence`` job commands (VV-007, OPS-006) wrap
the per-tenant runners; the database paths are covered in ``test_auto_end.py``."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
from typer.testing import CliRunner

from farmerapp.duty import auto_end as duty_jobs
from farmerapp.jobs.cli import cli

runner = CliRunner()
TENANT = uuid.UUID(int=7)
T = datetime(2026, 9, 21, 14, 30, tzinfo=UTC)


def test_auto_end_duty_command(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[list[uuid.UUID]] = []

    async def fake_run(
        tenant_ids: list[uuid.UUID], *, now: datetime | None = None
    ) -> list[duty_jobs.AutoEndResult]:
        calls.append(tenant_ids)
        return [duty_jobs.AutoEndResult(TENANT, uuid.UUID(int=1), uuid.UUID(int=2), "auto_time", T)]

    monkeypatch.setattr(duty_jobs, "run_auto_end", fake_run)
    result = runner.invoke(cli, ["auto-end-duty", "--tenant-id", str(TENANT)])
    assert result.exit_code == 0, result.output
    assert "auto-end-duty: tenants=1 ended=1" in result.output
    assert "auto_time at 2026-09-21T14:30:00+00:00" in result.output
    assert calls == [[TENANT]]
    assert runner.invoke(cli, ["auto-end-duty"]).exit_code != 0  # --tenant-id is required


def test_officer_sync_silence_command(monkeypatch: pytest.MonkeyPatch) -> None:
    async def fake_run(
        tenant_ids: list[uuid.UUID], *, now: datetime | None = None
    ) -> list[duty_jobs.SilenceResult]:
        return [
            duty_jobs.SilenceResult(
                TENANT, uuid.UUID(int=1), uuid.UUID(int=2), T, [uuid.UUID(int=3)]
            )
        ]

    monkeypatch.setattr(duty_jobs, "run_sync_silence", fake_run)
    result = runner.invoke(
        cli,
        ["officer-sync-silence", "--tenant-id", str(TENANT), "--tenant-id", str(uuid.UUID(int=8))],
    )
    assert result.exit_code == 0, result.output
    assert "officer-sync-silence: tenants=2 silent=1" in result.output
    assert "notified=1" in result.output


def test_help_lists_the_duty_jobs() -> None:
    output = runner.invoke(cli, []).output
    assert "auto-end-duty" in output and "officer-sync-silence" in output
