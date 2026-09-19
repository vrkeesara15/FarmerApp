"""M7 farmer P1 fixtures: the SMALL world, the demo farmer login with its farmer record and
a crop plot, and helpers to write confirmed diagnoses for the outbreak rule."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date, datetime

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.diagnosis.models import CorpusProblem, CorpusStatus, Diagnosis
from farmerapp.farmers.models import CropPlot, Farm, Farmer
from tests.authz.conftest import Bearer, World, bearer, step_up  # noqa: F401
from tests.authz.conftest import world as world  # fixture re-exported


@dataclass(frozen=True)
class FarmerLogin:
    user: User
    farmer: Farmer
    farm: Farm
    plot: CropPlot
    crop: Crop
    district: str


async def farmer_login(session: AsyncSession, world: World) -> FarmerLogin:
    from farmerapp.tenants.models import Village

    user = world.a.user(UserRole.FARMER)
    farmer = (await session.execute(select(Farmer).where(Farmer.user_id == user.id))).scalar_one()
    farm = (
        (
            await session.execute(
                select(Farm).where(Farm.farmer_id == farmer.id).order_by(Farm.created_at, Farm.id)
            )
        )
        .scalars()
        .first()
    )
    assert farm is not None
    plot = (
        (
            await session.execute(
                select(CropPlot).where(CropPlot.farm_id == farm.id).order_by(CropPlot.id)
            )
        )
        .scalars()
        .first()
    )
    assert plot is not None
    crop = await session.get_one(Crop, plot.crop_id)
    district = await session.scalar(select(Village.district).where(Village.id == farmer.village_id))
    assert district is not None
    return FarmerLogin(user, farmer, farm, plot, crop, district)


@pytest.fixture
async def login(db_session: AsyncSession, world: World) -> FarmerLogin:
    return await farmer_login(db_session, world)


async def approved_problem(session: AsyncSession, tenant_id: uuid.UUID) -> CorpusProblem:
    problem = (
        (
            await session.execute(
                select(CorpusProblem)
                .where(
                    CorpusProblem.tenant_id == tenant_id,
                    CorpusProblem.status == CorpusStatus.APPROVED.value,
                )
                .order_by(CorpusProblem.id)
            )
        )
        .scalars()
        .first()
    )
    assert problem is not None, "the SMALL seed has an approved corpus"
    return problem


async def confirmed_case(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    farmer: Farmer,
    problem: CorpusProblem,
    district: str,
    at: datetime,
    status: str = "confirmed",
) -> Diagnosis:
    row = Diagnosis(
        tenant_id=tenant_id,
        subject="farmer",
        farmer_id=farmer.id,
        images=[],
        crop_id=problem.crop_id,
        district=district,
        status=status,
        source="agronomist" if status in ("confirmed", "corrected") else "corpus",
        confidence="high",
        model_versions={},
        final_problem_id=problem.id,
        created_at=at,
        reviewed_at=at if status in ("confirmed", "corrected") else None,
    )
    session.add(row)
    await session.flush()
    return row


def monday(day: date) -> date:
    from datetime import timedelta

    return day - timedelta(days=day.weekday())
