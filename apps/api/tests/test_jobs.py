from __future__ import annotations

import uuid

import pytest
from typer.testing import CliRunner

from farmerapp.jobs.cli import cli

runner = CliRunner()


def test_hello() -> None:
    result = runner.invoke(cli, ["hello", "--name", "farmer"])
    assert result.exit_code == 0
    assert "hello, farmer" in result.output


def test_seed_command_reports_summary(monkeypatch: pytest.MonkeyPatch) -> None:
    """The CLI wraps ``seed_demo``; the DB path is covered in tests/auth/test_seed.py."""
    from farmerapp.jobs import seed as seed_mod

    async def fake_run() -> seed_mod.SeedResult:
        return seed_mod.SeedResult(tenant_id=uuid.UUID(int=1), tenant_slug="fcc", users_created=6)

    monkeypatch.setattr(seed_mod, "run_seed", fake_run)
    result = runner.invoke(cli, ["seed"])
    assert result.exit_code == 0, result.output
    assert "fcc" in result.output and "users_created=6" in result.output


def test_no_args_shows_help() -> None:
    result = runner.invoke(cli, [])
    assert "hello" in result.output and "seed" in result.output
