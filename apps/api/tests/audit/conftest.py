"""Audit-trail fixtures (FA-006).

Reuses the SEC-006 ``world`` / ``bearer`` fixtures (two seeded tenants, minted tokens) and
adds fake auth services (clock + providers) so login/logout can be driven without SMS, plus
small helpers to read ``audit_log`` rows back through the app-role session (i.e. under RLS).
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

import pytest
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.deps import AuthServices
from farmerapp.auth.providers import FakeProvider
from farmerapp.auth.scheduler import InProcessScheduler
from farmerapp.db.models import AuditLog
from farmerapp.settings import get_settings
from tests.authz.conftest import bearer, step_up, world  # noqa: F401  (fixtures re-exported)
from tests.rls.conftest import two_tenants  # noqa: F401  (fixture re-exported)

T0 = datetime(2026, 9, 17, 9, 0, tzinfo=UTC)

# Request metadata the tests send and expect back on the audit row.
TRACE = "trace-fa006"
DEVICE = "device-fa006"
USER_AGENT = "FarmerApp-Test/1.0"
CLIENT_IP = "203.0.113.9"
REQUEST_HEADERS = {
    "X-Request-Id": TRACE,
    "X-Device-Id": DEVICE,
    "User-Agent": USER_AGENT,
    "X-Forwarded-For": f"{CLIENT_IP}, 10.0.0.1",
}


@pytest.fixture
def clock() -> FakeClock:
    return FakeClock(T0)


@pytest.fixture
def sms() -> FakeProvider:
    return FakeProvider()


@pytest.fixture
def auth_services(app: FastAPI, clock: FakeClock, sms: FakeProvider) -> AuthServices:
    services = AuthServices(
        settings=get_settings(),
        clock=clock,
        sms=sms,
        whatsapp=sms,
        scheduler=InProcessScheduler(clock),
    )
    app.state.auth = services
    return services


async def audit_rows(
    session: AsyncSession,
    *,
    entity: str | None = None,
    entity_id: uuid.UUID | None = None,
    action: str | None = None,
) -> Sequence[AuditLog]:
    """Audit rows visible to the session's bound tenant, oldest first."""
    stmt = select(AuditLog).order_by(AuditLog.created_at, AuditLog.id)
    if entity is not None:
        stmt = stmt.where(AuditLog.entity == entity)
    if entity_id is not None:
        stmt = stmt.where(AuditLog.entity_id == entity_id)
    if action is not None:
        stmt = stmt.where(AuditLog.action == action)
    return (await session.execute(stmt)).scalars().all()


async def one_audit_row(
    session: AsyncSession, *, action: str, entity_id: uuid.UUID | None = None
) -> AuditLog:
    rows = await audit_rows(session, action=action, entity_id=entity_id)
    assert len(rows) == 1, [(r.action, r.entity_id) for r in rows]
    return rows[0]
