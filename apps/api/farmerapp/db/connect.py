"""How the api, worker, jobs and Alembic reach Postgres (SEC-011).

Two modes, chosen by ``DB_IAM_AUTH``:

* **URL** (default; local, CI, docker compose): the password-bearing ``DATABASE_URL`` (app
  role) and ``MIGRATION_DATABASE_URL`` (owner / migrate role), exactly as before.
* **Cloud SQL IAM** (``DB_IAM_AUTH=true``; every Cloud Run service and job): the Cloud SQL
  Python Connector opens each connection to ``DB_INSTANCE_CONNECTION_NAME`` over the private
  IP (``DB_IP_TYPE``) with an IAM login token of the runtime service account, as ``DB_USER``
  (the service account email without ``.gserviceaccount.com``) on ``DB_NAME``. No password
  exists anywhere. Which Postgres role that is follows from the identity: the api / worker /
  jobs service accounts are members of ``farmerapp_app``, only the ``migrate`` job's service
  account is a member of ``farmerapp_migrate`` (grants: docs/deploy/configuration.md).

The connector is created lazily on the first connection, inside the running event loop (it
binds to that loop), with the ``lazy`` refresh strategy that Cloud Run's CPU throttling needs.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import Any
from urllib.parse import quote

from sqlalchemy import pool
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

from farmerapp.settings import Settings

#: ``async () -> Connector``; tests inject a fake.
ConnectorFactory = Callable[..., Awaitable[Any]]

_IP_TYPES = {"private": "PRIVATE", "public": "PRIMARY", "psc": "PSC"}


async def _default_connector_factory(**kwargs: Any) -> Any:  # pragma: no cover - needs GCP
    from google.cloud.sql.connector import create_async_connector

    return await create_async_connector(**kwargs)


class CloudSqlConnect:
    """``async_creator`` for SQLAlchemy: one IAM-authenticated asyncpg connection per call."""

    def __init__(
        self,
        *,
        instance_connection_name: str,
        user: str,
        database: str,
        ip_type: str = "private",
        connector_factory: ConnectorFactory | None = None,
    ) -> None:
        self.instance_connection_name = instance_connection_name
        self.user = user
        self.database = database
        self.ip_type = _IP_TYPES[ip_type]
        self._factory = connector_factory or _default_connector_factory
        self._connector: Any = None

    async def __call__(self) -> Any:
        if self._connector is None:
            self._connector = await self._factory(
                ip_type=self.ip_type, enable_iam_auth=True, refresh_strategy="lazy"
            )
        return await self._connector.connect_async(
            self.instance_connection_name, "asyncpg", user=self.user, db=self.database
        )

    async def close(self) -> None:
        if self._connector is not None:
            await self._connector.close_async()
            self._connector = None


def _iam_url(settings: Settings) -> str:
    """Informational URL of an IAM engine (no host, no password): the connector connects."""
    return f"postgresql+asyncpg://{quote(settings.db_user or '', safe='')}@/{settings.db_name}"


def iam_connect(
    settings: Settings, connector_factory: ConnectorFactory | None = None
) -> CloudSqlConnect:
    if not settings.db_instance_connection_name or not settings.db_user:
        raise ValueError(
            "DB_IAM_AUTH=true needs DB_INSTANCE_CONNECTION_NAME (project:region:instance) and "
            "DB_USER (the service account email without .gserviceaccount.com)"
        )
    return CloudSqlConnect(
        instance_connection_name=settings.db_instance_connection_name,
        user=settings.db_user,
        database=settings.db_name,
        ip_type=settings.db_ip_type,
        connector_factory=connector_factory,
    )


def create_engine(
    settings: Settings,
    *,
    migrate: bool = False,
    connector_factory: ConnectorFactory | None = None,
    **kwargs: Any,
) -> AsyncEngine:
    """The runtime engine (``migrate=False``) or Alembic's (``migrate=True``, no pool).

    URL mode is unchanged from before: ``DATABASE_URL`` / ``MIGRATION_DATABASE_URL``. In IAM
    mode both use the process's own identity (``DB_USER``); the migrate job runs as its own
    service account, so SEC-011's role split holds through IAM rather than through two URLs.
    """
    if migrate:
        kwargs.setdefault("poolclass", pool.NullPool)
    if not settings.db_iam_auth:
        url = settings.migration_database_url if migrate else settings.database_url
        return create_async_engine(url, **kwargs)
    return create_async_engine(
        _iam_url(settings), async_creator=iam_connect(settings, connector_factory), **kwargs
    )


__all__ = ["CloudSqlConnect", "ConnectorFactory", "create_engine", "iam_connect"]
