from __future__ import annotations

from typer.testing import CliRunner

from farmerapp.jobs.cli import cli

runner = CliRunner()


def test_hello() -> None:
    result = runner.invoke(cli, ["hello", "--name", "farmer"])
    assert result.exit_code == 0
    assert "hello, farmer" in result.output


def test_seed_stub() -> None:
    result = runner.invoke(cli, ["seed"])
    assert result.exit_code == 0
    assert "seed: nothing yet" in result.output


def test_no_args_shows_help() -> None:
    result = runner.invoke(cli, [])
    assert "hello" in result.output and "seed" in result.output
