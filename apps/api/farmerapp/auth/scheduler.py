"""Delayed task scheduling seam.

Dev/tests: ``InProcessScheduler`` keeps due tasks in memory, driven by an injectable clock and
``run_due`` (the API lifespan ticks it every second in local runs).

Prod: ``PubSubScheduler`` will publish a ``notify.send`` message (SPEC 9.2) carrying the task
name, payload and ``run_at``; the worker handler re-enqueues until due (Pub/Sub has no native
delay; Cloud Tasks is the alternative). TODO(OPS-004, SLO "OTP delivery 98% within 30 s"
in SPEC 12.1): implement + alert on the age of undelivered checks.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Protocol

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import Clock
from farmerapp.logging import get_logger

TaskHandler = Callable[[AsyncSession, dict[str, Any]], Awaitable[None]]

log = get_logger("farmerapp.auth.scheduler")


class Scheduler(Protocol):
    def register(self, task: str, handler: TaskHandler) -> None: ...

    def schedule(self, task: str, run_at: datetime, payload: dict[str, Any]) -> None: ...


@dataclass(order=True)
class ScheduledTask:
    run_at: datetime
    seq: int
    task: str = field(compare=False)
    payload: dict[str, Any] = field(compare=False, default_factory=dict)


class InProcessScheduler:
    def __init__(self, clock: Clock) -> None:
        self._clock = clock
        self._handlers: dict[str, TaskHandler] = {}
        self._queue: list[ScheduledTask] = []
        self._seq = 0

    def register(self, task: str, handler: TaskHandler) -> None:
        self._handlers[task] = handler

    def schedule(self, task: str, run_at: datetime, payload: dict[str, Any]) -> None:
        if task not in self._handlers:
            raise KeyError(f"unknown task {task!r}")
        self._seq += 1
        self._queue.append(ScheduledTask(run_at, self._seq, task, payload))
        self._queue.sort()

    @property
    def pending(self) -> list[ScheduledTask]:
        return list(self._queue)

    def has_due(self) -> bool:
        return bool(self._queue) and self._queue[0].run_at <= self._clock.now()

    async def run_due(self, session: AsyncSession) -> int:
        """Run every task whose ``run_at`` has passed. Returns the number executed."""
        now = self._clock.now()
        ran = 0
        while self._queue and self._queue[0].run_at <= now:
            item = self._queue.pop(0)
            ran += 1
            try:
                await self._handlers[item.task](session, item.payload)
            except Exception:
                log.exception("scheduled_task_failed", task=item.task)
        return ran


class PubSubScheduler:
    """Production seam (not implemented yet, see module docstring)."""

    def __init__(self, topic: str) -> None:
        self.topic = topic
        self._handlers: dict[str, TaskHandler] = {}

    def register(self, task: str, handler: TaskHandler) -> None:
        self._handlers[task] = handler

    def schedule(self, task: str, run_at: datetime, payload: dict[str, Any]) -> None:
        raise NotImplementedError(
            f"publish {task} to {self.topic} with run_at={run_at.isoformat()} (TODO OPS-004)"
        )
