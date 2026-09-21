"""FM-013 fixtures: two farmer logins of the same tenant (a referrer and an invited farmer)."""

from __future__ import annotations

from dataclasses import dataclass

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.farmers.models import Farmer
from tests.advisory.conftest import FarmerLogin, farmer_login
from tests.advisory.conftest import login as login
from tests.authz.conftest import Bearer, World, bearer, step_up  # noqa: F401
from tests.authz.conftest import world as world


@dataclass(frozen=True)
class Pair:
    """The farmer who refers (with a login) and another farmer of the same tenant."""

    referrer: FarmerLogin
    invited: Farmer


@pytest.fixture
async def pair(db_session: AsyncSession, world: World) -> Pair:
    referrer = await farmer_login(db_session, world)
    other = (
        await db_session.scalars(
            select(Farmer)
            .where(
                Farmer.tenant_id == world.a.tenant.id,
                Farmer.id != referrer.farmer.id,
                Farmer.deleted_at.is_(None),
            )
            .order_by(Farmer.created_at)
            .limit(1)
        )
    ).first()
    assert other is not None, "the SMALL seed has more than one farmer"
    return Pair(referrer=referrer, invited=other)
