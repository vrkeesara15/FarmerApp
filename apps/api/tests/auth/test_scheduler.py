"""In-process delayed-task scheduler with an injectable clock (dev/test seam for Pub/Sub)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock, SystemClock
from farmerapp.auth.scheduler import InProcessScheduler, PubSubScheduler


def test_system_clock_is_utc_aware() -> None:
    now = SystemClock().now()
    assert now.tzinfo is not None and abs((now - datetime.now(UTC)).total_seconds()) < 5


def test_fake_clock_advances() -> None:
    c = FakeClock(datetime(2026, 1, 1, tzinfo=UTC))
    c.advance(90)
    assert c.now() == datetime(2026, 1, 1, 0, 1, 30, tzinfo=UTC)
    c.advance(timedelta(hours=1))
    assert c.now().hour == 1


async def test_run_due_executes_in_order_and_once(db_session: AsyncSession) -> None:
    clock = FakeClock(datetime(2026, 1, 1, tzinfo=UTC))
    s = InProcessScheduler(clock)
    seen: list[Any] = []

    async def handler(session: AsyncSession, payload: dict[str, Any]) -> None:
        seen.append(payload["n"])

    s.register("t", handler)
    s.schedule("t", clock.now() + timedelta(seconds=10), {"n": 2})
    s.schedule("t", clock.now() + timedelta(seconds=5), {"n": 1})
    assert await s.run_due(db_session) == 0
    clock.advance(10)
    assert await s.run_due(db_session) == 2
    assert seen == [1, 2]
    assert s.pending == []
    assert await s.run_due(db_session) == 0


async def test_unknown_task_is_rejected() -> None:
    s = InProcessScheduler(FakeClock(datetime(2026, 1, 1, tzinfo=UTC)))
    with pytest.raises(KeyError):
        s.schedule("nope", datetime(2026, 1, 1, tzinfo=UTC), {})


async def test_handler_error_is_logged_not_raised(db_session: AsyncSession) -> None:
    clock = FakeClock(datetime(2026, 1, 1, tzinfo=UTC))
    s = InProcessScheduler(clock)

    async def boom(session: AsyncSession, payload: dict[str, Any]) -> None:
        raise RuntimeError("x")

    s.register("boom", boom)
    s.schedule("boom", clock.now(), {})
    assert await s.run_due(db_session) == 1
    assert s.pending == []


def test_pubsub_scheduler_is_a_documented_seam() -> None:
    s = PubSubScheduler(topic="notify.send")
    with pytest.raises(NotImplementedError):
        s.schedule("check_delivery", datetime(2026, 1, 1, tzinfo=UTC), {})
