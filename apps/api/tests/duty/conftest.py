"""Fixtures for the FA-010 / FA-011 / VV-007 tests: a fake clock on a fixed day (three days
after the seed's day, so nothing collides with the seeded tracks), the partitions for that
window, and an officer with tokens minted *after* the clock is set."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.models import User, UserRole
from farmerapp.db.geo import offset
from farmerapp.db.models import Tenant
from farmerapp.location import partitions
from farmerapp.location.models import LocationPoint
from farmerapp.policies.location_policy import policy_for
from farmerapp.tenants.settings import DEFAULT_LOCATION_POLICY_VERSION
from tests.authz.conftest import Bearer, World, bearer, world  # noqa: F401  (fixtures)
from tests.farmers.write_fixtures import WriteCtx, ctx  # noqa: F401  (fixture)

IST = timedelta(hours=5, minutes=30)
DAY = date(2026, 9, 21)  # Monday, three days after SEED_TODAY
T_NOW = datetime(2026, 9, 21, 4, 30, tzinfo=UTC)  # 10:00 IST
BASE_LON, BASE_LAT = 79.55, 18.02
DEVICE = "device-duty-1"
APP_VERSION = "0.2.0"


def ist(hour: int, minute: int = 0, *, day: date = DAY) -> datetime:
    """An IST wall-clock time on ``day`` as an aware UTC datetime."""
    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=UTC) - IST


@pytest.fixture
async def clock(app: FastAPI, db_session: AsyncSession) -> FakeClock:
    """The app's clock at ``T_NOW``; partitions exist for the day before to the day after."""
    fake = FakeClock(T_NOW)
    app.state.auth.clock = fake
    await partitions.ensure_partitions(
        db_session, from_day=DAY - timedelta(days=2), to_day=DAY + timedelta(days=2)
    )
    return fake


@dataclass
class DutyCtx:
    world: World
    ctx: WriteCtx
    clock: FakeClock
    mint: Bearer  # tokens are minted per request: tests advance the clock past the 15-min TTL
    officer: User
    other_officer: User
    cluster_head: User
    store_manager: User

    @property
    def headers(self) -> dict[str, str]:
        return self.mint(self.officer)

    @property
    def other_headers(self) -> dict[str, str]:
        return self.mint(self.other_officer)

    @property
    def head_headers(self) -> dict[str, str]:
        return self.mint(self.cluster_head)

    @property
    def manager_headers(self) -> dict[str, str]:
        return self.mint(self.store_manager)

    @property
    def tenant(self) -> Tenant:
        return self.world.a.tenant

    @property
    def tenant_id(self) -> uuid.UUID:
        return self.world.a.tenant.id

    @property
    def now(self) -> datetime:
        return self.clock.now()

    def policy_body(self, version: str | None = None) -> dict[str, Any]:
        policy = policy_for(version or DEFAULT_LOCATION_POLICY_VERSION)
        return {
            "version": policy.version,
            "text_hash": policy.text_hash,
            "device_id": DEVICE,
            "app_version": APP_VERSION,
        }

    def start_body(self, **extra: Any) -> dict[str, Any]:
        body: dict[str, Any] = {
            "device_id": DEVICE,
            "app_version": APP_VERSION,
            "policy_version": DEFAULT_LOCATION_POLICY_VERSION,
            "start_at": (self.now - timedelta(hours=1)).isoformat(),
            "start_point": {"lat": BASE_LAT, "lon": BASE_LON, "accuracy_m": 12.0},
            "integrity": {"is_mock": False, "is_rooted": False, "clock_drift_s": 3},
        }
        body.update(extra)
        return body

    def end_body(self, **extra: Any) -> dict[str, Any]:
        body: dict[str, Any] = {
            "end_at": self.now.isoformat(),
            "end_point": {"lat": BASE_LAT, "lon": BASE_LON, "accuracy_m": 9.0},
            "end_reason": "manual",
        }
        body.update(extra)
        return body

    def batch_body(
        self, duty_session_id: uuid.UUID | str, points: list[dict[str, Any]], **extra: Any
    ) -> dict[str, Any]:
        body: dict[str, Any] = {
            "duty_session_id": str(duty_session_id),
            "device_id": DEVICE,
            "sent_at": self.now.isoformat(),
            "points": points,
        }
        body.update(extra)
        return body


def point(
    ts: datetime, *, east_m: float = 0.0, north_m: float = 0.0, **extra: Any
) -> dict[str, Any]:
    lon, lat = offset(BASE_LON, BASE_LAT, east_m, north_m)
    body: dict[str, Any] = {
        "ts": ts.isoformat(),
        "lat": lat,
        "lon": lon,
        "accuracy_m": 8.0,
        "speed_mps": 1.5,
        "bearing": 90.0,
        "battery_pct": 77,
        "is_mock": False,
        "is_rooted": False,
        "provider": "fused",
    }
    body.update(extra)
    return body


async def point_count(session: AsyncSession, officer_id: uuid.UUID) -> int:
    count = await session.scalar(
        select(func.count())
        .select_from(LocationPoint)
        .where(LocationPoint.officer_id == officer_id)
    )
    return int(count or 0)


async def set_tenant_settings(session: AsyncSession, tenant: Tenant, **changes: Any) -> None:
    tenant.settings = {**tenant.settings, **changes}
    await session.flush()


async def accept_policy(
    client: AsyncClient, dctx: DutyCtx, headers: dict[str, str] | None = None
) -> dict[str, Any]:
    resp = await client.get("/v1/policies/location", headers=headers or dctx.headers)
    assert resp.status_code == 200, resp.text
    policy = resp.json()
    resp = await client.post(
        "/v1/policies/location/accept",
        json={
            "version": policy["version"],
            "text_hash": policy["text_hash"],
            "device_id": DEVICE,
            "app_version": APP_VERSION,
        },
        headers=headers or dctx.headers,
    )
    assert resp.status_code == 201, resp.text
    body: dict[str, Any] = resp.json()
    return body


async def start_duty(
    client: AsyncClient, dctx: DutyCtx, headers: dict[str, str] | None = None, **extra: Any
) -> dict[str, Any]:
    resp = await client.post(
        "/v1/duty/start", json=dctx.start_body(**extra), headers=headers or dctx.headers
    )
    assert resp.status_code == 201, resp.text
    body: dict[str, Any] = resp.json()
    return body


@pytest.fixture
async def dctx(
    world: World,  # noqa: F811
    ctx: WriteCtx,  # noqa: F811
    bearer: Bearer,  # noqa: F811
    clock: FakeClock,
) -> DutyCtx:
    """The role officer with the current policy accepted at ``T_NOW`` (tokens minted after
    the clock is set, so they are valid on the fake day)."""
    head = world.a.user(UserRole.CLUSTER_HEAD)
    manager = world.a.user(UserRole.STORE_MANAGER)
    return DutyCtx(
        world=world,
        ctx=ctx,
        clock=clock,
        mint=bearer,
        officer=ctx.officer,
        other_officer=ctx.other_officer,
        cluster_head=head,
        store_manager=manager,
    )


@pytest.fixture
async def accepted(client: AsyncClient, dctx: DutyCtx) -> DutyCtx:
    await accept_policy(client, dctx)
    return dctx
