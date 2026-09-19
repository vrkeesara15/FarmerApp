"""Engine construction (farmerapp.db.connect): URL mode is unchanged for local / CI, IAM mode
goes through the Cloud SQL Python Connector (SEC-011). No database or GCP needed."""

from __future__ import annotations

from typing import Any

import pytest
from sqlalchemy.pool import NullPool

from farmerapp.db.connect import CloudSqlConnect, create_engine, iam_connect
from farmerapp.settings import Settings

APP_URL = "postgresql+asyncpg://farmerapp_app:pw@localhost:5432/farmerapp"
MIGRATE_URL = "postgresql+asyncpg://farmerapp:pw@localhost:5432/farmerapp"
IAM: dict[str, Any] = {
    "db_iam_auth": True,
    "db_instance_connection_name": "farmerapp-dev:asia-south1:farmerapp-dev",
    "db_user": "farmerapp-api@farmerapp-dev.iam",
    "db_name": "farmerapp",
}


def _settings(**values: Any) -> Settings:
    return Settings.model_validate(
        {"database_url": APP_URL, "migration_database_url": MIGRATE_URL, **values}
    )


class FakeConnector:
    def __init__(self) -> None:
        self.calls: list[tuple[Any, ...]] = []
        self.closed = False

    async def connect_async(self, instance: str, driver: str, **kwargs: Any) -> str:
        self.calls.append((instance, driver, kwargs))
        return f"conn-{len(self.calls)}"

    async def close_async(self) -> None:
        self.closed = True


class Factory:
    def __init__(self) -> None:
        self.created: list[dict[str, Any]] = []
        self.connector = FakeConnector()

    async def __call__(self, **kwargs: Any) -> FakeConnector:
        self.created.append(kwargs)
        return self.connector


async def test_url_mode_is_unchanged() -> None:
    settings = _settings()
    assert settings.db_iam_auth is False
    app = create_engine(settings, pool_size=3)
    migrate = create_engine(settings, migrate=True)
    try:
        assert app.url.render_as_string(hide_password=False) == APP_URL
        assert migrate.url.render_as_string(hide_password=False) == MIGRATE_URL
        assert isinstance(migrate.pool, NullPool)
        assert app.pool.size() == 3  # type: ignore[attr-defined]
    finally:
        await app.dispose()
        await migrate.dispose()


async def test_iam_mode_connects_through_the_connector_as_db_user() -> None:
    factory = Factory()
    settings = _settings(**IAM)
    creator = iam_connect(settings, factory)
    assert await creator() == "conn-1"
    assert await creator() == "conn-2"
    # One connector per process (created in the running loop), lazy refresh for Cloud Run.
    assert factory.created == [
        {"ip_type": "PRIVATE", "enable_iam_auth": True, "refresh_strategy": "lazy"}
    ]
    instance, driver, kwargs = factory.connector.calls[0]
    assert instance == "farmerapp-dev:asia-south1:farmerapp-dev"
    assert driver == "asyncpg"
    assert kwargs == {"user": "farmerapp-api@farmerapp-dev.iam", "db": "farmerapp"}
    await creator.close()
    assert factory.connector.closed
    await creator.close()  # idempotent


async def test_iam_engine_ignores_the_password_urls() -> None:
    engine = create_engine(_settings(**IAM), connector_factory=Factory())
    migrate = create_engine(_settings(**IAM), migrate=True, connector_factory=Factory())
    try:
        # No host, no password: the connector opens the connection.
        assert engine.url.render_as_string(hide_password=False) == (
            "postgresql+asyncpg://farmerapp-api%40farmerapp-dev.iam@/farmerapp"
        )
        assert isinstance(migrate.pool, NullPool)
    finally:
        await engine.dispose()
        await migrate.dispose()


async def test_iam_engine_checkout_uses_the_connector() -> None:
    """SQLAlchemy calls the async creator for a new pooled connection."""
    factory = Factory()
    engine = create_engine(_settings(**IAM), connector_factory=factory)
    try:
        with pytest.raises(Exception):  # noqa: B017 - the fake returns a str, not a connection
            async with engine.connect():
                pass
        assert factory.connector.calls and factory.connector.calls[0][1] == "asyncpg"
    finally:
        await engine.dispose()


@pytest.mark.parametrize(
    ("ip_type", "expected"), [("private", "PRIVATE"), ("public", "PRIMARY"), ("psc", "PSC")]
)
def test_ip_type_maps_to_the_connector_enum(ip_type: str, expected: str) -> None:
    assert iam_connect(_settings(**IAM, db_ip_type=ip_type)).ip_type == expected


def test_iam_mode_needs_the_instance_and_the_user() -> None:
    with pytest.raises(ValueError, match="DB_INSTANCE_CONNECTION_NAME"):
        iam_connect(_settings(db_iam_auth=True, db_user="u"))
    with pytest.raises(ValueError, match="DB_USER"):
        iam_connect(_settings(db_iam_auth=True, db_instance_connection_name="p:r:i", db_user=""))
    assert isinstance(iam_connect(_settings(**IAM)), CloudSqlConnect)
