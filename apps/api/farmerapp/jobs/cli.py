"""Typer CLI. Each job is a subcommand; Cloud Run Jobs invoke one per execution."""

from __future__ import annotations

import typer

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
def seed() -> None:
    """Load the demo tenant (5 stores, 5 officers, 200 farmers). Stub until M1-KICKOFF."""
    _setup()
    get_logger("farmerapp.jobs.seed").info("seed: nothing yet")
    typer.echo("seed: nothing yet")


def main() -> None:
    cli(prog_name="python -m farmerapp.jobs")
