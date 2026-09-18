"""The shared test engine survives a dead pooled connection (flake seen in M2 / M3 runs).

A pooled app-role connection is killed server-side between two checkouts, as happens when the
Postgres container is recreated or restarted under a running suite. The next checkout must
get a live connection (``pool_pre_ping``) instead of failing with "connection is closed".
"""

from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine


async def test_dead_pooled_connection_is_replaced_at_checkout(
    app_engine: AsyncEngine, migrate_engine: AsyncEngine
) -> None:
    async with app_engine.connect() as conn:
        pid = await conn.scalar(text("SELECT pg_backend_pid()"))
    # Checked in: the connection idles in the pool. Kill every app-role backend of the test
    # database from the server side (nothing else runs concurrently in the suite).
    async with migrate_engine.connect() as admin:
        killed = await admin.scalar(
            text(
                "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity "
                "WHERE usename = 'farmerapp_app' AND datname = current_database()"
            )
        )
    assert killed >= 1
    async with app_engine.connect() as conn:
        assert await conn.scalar(text("SELECT 1")) == 1
        assert await conn.scalar(text("SELECT pg_backend_pid()")) != pid
