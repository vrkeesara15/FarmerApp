"""Typer CLI. Each job is a subcommand; Cloud Run Jobs invoke one per execution."""

from __future__ import annotations

import asyncio

import typer

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
def seed() -> None:
    """Upsert the demo tenant "Future Crop Care" (fcc) and its test users (one per role).

    M1-KICKOFF adds stores, officers and farmers. Idempotent.
    """
    _setup()
    result = asyncio.run(seed_mod.run_seed())
    get_logger("farmerapp.jobs.seed").info(
        "seed_done", tenant=result.tenant_slug, users_created=result.users_created
    )
    typer.echo(
        f"seed: tenant={result.tenant_slug} ({result.tenant_id}) "
        f"users_created={result.users_created}"
    )


def main() -> None:
    cli(prog_name="python -m farmerapp.jobs")
