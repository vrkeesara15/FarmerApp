"""Fixtures for the M2 tests: the seeded world (``SMALL`` profile) plus the officers, duty
sessions and visits of tenant A grouped per officer, all loaded under the tenant's scope."""

from __future__ import annotations

import uuid
from dataclasses import dataclass

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.db.session import set_tenant, tenant_scope
from farmerapp.location.models import DutySession
from farmerapp.tenants.models import Store
from farmerapp.visits.models import Visit
from tests.authz.conftest import Bearer, World, bearer, world  # noqa: F401  (fixtures re-exported)
from tests.farmers.conftest import graph  # noqa: F401  (fixture re-exported)
from tests.farmers.write_fixtures import ctx  # noqa: F401  (fixture re-exported)

_ = Bearer  # re-exported type

M2_TABLES = (
    "duty_session",
    "location_point",
    "location_daily_agg",
    "policy_acceptance",
    "visit",
    "visit_photo",
    "visit_confirmation",
)


@dataclass(frozen=True)
class M2World:
    world: World
    officers: tuple[User, ...]  # tenant A field officers, by phone
    stores: dict[uuid.UUID, Store]
    visits: dict[uuid.UUID, list[Visit]]  # officer id -> visits (check-in order)
    sessions: dict[uuid.UUID, list[DutySession]]  # officer id -> duty sessions

    @property
    def officer(self) -> User:
        """The role officer (``+919000000004``, store WGL, North Telangana)."""
        return self.world.a.user(UserRole.FIELD_OFFICER)

    def officer_in_cluster(self, cluster_id: uuid.UUID | None, *, same: bool) -> User:
        for officer in self.officers:
            if (officer.cluster_id == cluster_id) is same:
                return officer
        raise AssertionError("no such officer")

    def all_visits(self) -> list[Visit]:
        return [v for visits in self.visits.values() for v in visits]


@pytest.fixture
async def m2(world: World, db_session: AsyncSession) -> M2World:  # noqa: F811
    tid = world.a.tenant.id
    async with tenant_scope(db_session, tid):
        officers = tuple(
            (
                await db_session.execute(
                    select(User).where(User.role == UserRole.FIELD_OFFICER).order_by(User.phone)
                )
            )
            .scalars()
            .all()
        )
        stores = {s.id: s for s in (await db_session.execute(select(Store))).scalars()}
        visits: dict[uuid.UUID, list[Visit]] = {o.id: [] for o in officers}
        for visit in (
            await db_session.execute(select(Visit).order_by(Visit.checkin_at, Visit.id))
        ).scalars():
            visits[visit.officer_id].append(visit)
        sessions: dict[uuid.UUID, list[DutySession]] = {o.id: [] for o in officers}
        for session in (
            await db_session.execute(select(DutySession).order_by(DutySession.start_at))
        ).scalars():
            sessions[session.officer_id].append(session)
    await set_tenant(db_session, tid)
    return M2World(world=world, officers=officers, stores=stores, visits=visits, sessions=sessions)
