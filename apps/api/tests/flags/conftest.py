"""Flag test fixtures: a fixture world with flags raised by the real engine.

``flagged`` seeds the VA-F06 positive fixture (two high severity employee flags: ``officer``
burst, ``officer2`` shared device) and the VA-F03 positive fixture (four medium farmer-data
flags) into one tenant, as the golden fixtures do.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.flags.models import Flag
from farmerapp.flags.service import raise_flag
from farmerapp.rules.loader import DEFAULT_RULES_DIR, load_rules
from farmerapp.rules.registry import Evidence, Finding, record
from farmerapp.rules.schema import Mode, Subject
from tests.authz.conftest import bearer  # noqa: F401  (fixture re-exported)
from tests.rules.harness import DEFAULT_NOW, BaseWorld, base_world, load_fixture, run_fixture

RULES = load_rules(DEFAULT_RULES_DIR)


@dataclass
class Flagged:
    world: BaseWorld
    flags: list[Flag]

    def about(self, ref: str) -> list[Flag]:
        return [f for f in self.flags if f.subject_id == self.world.refs[ref]]

    def one(self, ref: str) -> Flag:
        found = self.about(ref)
        assert found, ref
        return found[0]


@pytest.fixture
async def flagged(db_session: AsyncSession) -> Flagged:
    world = await base_world(db_session)
    for rule_id in ("VA-F06", "VA-F03"):
        await run_fixture(
            db_session, rule_id, load_fixture(rule_id, "positive"), rule_set=RULES, world=world
        )
    flags = (
        (
            await db_session.execute(
                select(Flag).where(Flag.tenant_id == world.tenant_id).order_by(Flag.created_at)
            )
        )
        .scalars()
        .all()
    )
    assert len(flags) == 6
    return Flagged(world=world, flags=list(flags))


async def make_flag(
    session: AsyncSession,
    world: BaseWorld,
    subject_ref: str,
    *,
    rule_id: str = "VA-F06",
    subject: Subject = Subject.EMPLOYEE,
    key: str | None = None,
    now: datetime = DEFAULT_NOW,
    photos: list[str] | None = None,
) -> Flag:
    subject_id = world.refs[subject_ref]
    flag = await raise_flag(
        session,
        tenant_id=world.tenant_id,
        rule=RULES.get(rule_id),
        finding=Finding(
            subject_type=subject,
            subject_id=subject_id,
            key=key or uuid.uuid4().hex,
            title="Test flag",
            evidence=Evidence(
                records=[record("user" if subject == Subject.EMPLOYEE else "farmer", subject_id)],
                photos=photos or [],
            ),
        ),
        mode=Mode.BATCH,
        now=now,
    )
    assert flag is not None
    return flag
