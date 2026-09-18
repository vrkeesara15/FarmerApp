"""``/v1/farmers`` — read the farmers directory and one farmer's 360 (M1-KICKOFF, WC-003).

Row scope follows SPEC 2.6 through ``farmerapp.auth.scope.farmer_filters``: owner / director
/ auditor / tenant_admin see the tenant, a cluster head their cluster (village -> store ->
cluster), a store manager their store (village -> store), a field officer the farmers they
registered, an agronomist crop data (phone masked, landmark hidden), a farmer their own
record. Registration (FA-012) adds the write endpoints.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import farmer_filters
from farmerapp.farmers.models import ConsentRecord, CropPlot, Farm, Farmer
from farmerapp.farmers.schemas import (
    ConsentRecordOut,
    FarmerDetailOut,
    FarmerOut,
    FarmerPage,
    FarmOut,
)

router = APIRouter(prefix="/farmers", tags=["farmers"])

LIST_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.FIELD_OFFICER,
    Role.AGRONOMIST,
)
READ_ROLES = (*LIST_ROLES, Role.FARMER)

#: Roles that read crop data, not the person (SPEC 2.6 "Read (crop data)").
PII_REDACTED_ROLES = frozenset({UserRole.AGRONOMIST})


def _redact(actor: User) -> bool:
    return UserRole(actor.role) in PII_REDACTED_ROLES


@router.get(
    "",
    operation_id="listFarmers",
    summary="Farmers visible to the caller (tenant, cluster, store or own), oldest first",
    response_model=FarmerPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_farmers(
    actor: Annotated[User, require_roles(*LIST_ROLES)],
    session: DbSession,
    page: Page,
    village_id: Annotated[uuid.UUID | None, Query()] = None,
    registered_by: Annotated[uuid.UUID | None, Query(description="Officer user id.")] = None,
) -> FarmerPage:
    stmt = select(Farmer).where(Farmer.deleted_at.is_(None), *farmer_filters(actor))
    if village_id is not None:
        stmt = stmt.where(Farmer.village_id == village_id)
    if registered_by is not None:
        stmt = stmt.where(Farmer.registered_by == registered_by)
    after = page.after(Farmer.created_at, Farmer.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(Farmer.created_at, Farmer.id).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    redact = _redact(actor)
    return FarmerPage(
        items=[FarmerOut.from_row(f, redact_pii=redact) for f in items], next_cursor=next_cursor
    )


@router.get(
    "/{id}",
    operation_id="getFarmer",
    summary="One farmer with farms, crop plots and consent history",
    response_model=FarmerDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_farmer(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
) -> FarmerDetailOut:
    stmt = select(Farmer).where(
        Farmer.id == id, Farmer.deleted_at.is_(None), *farmer_filters(actor)
    )
    farmer = (await session.execute(stmt)).scalar_one_or_none()
    if farmer is None:
        raise NotFoundError("Farmer not found.")

    farms = (
        (
            await session.execute(
                select(Farm)
                .where(Farm.farmer_id == farmer.id, Farm.deleted_at.is_(None))
                .order_by(Farm.created_at, Farm.id)
            )
        )
        .scalars()
        .all()
    )
    plots_by_farm: dict[uuid.UUID, list[CropPlot]] = {f.id: [] for f in farms}
    if farms:
        plots = (
            (
                await session.execute(
                    select(CropPlot)
                    .where(CropPlot.farm_id.in_(list(plots_by_farm)), CropPlot.deleted_at.is_(None))
                    .order_by(CropPlot.sowing_date, CropPlot.id)
                )
            )
            .scalars()
            .all()
        )
        for plot in plots:
            plots_by_farm[plot.farm_id].append(plot)
    consents = (
        (
            await session.execute(
                select(ConsentRecord)
                .where(ConsentRecord.subject_id == farmer.id)
                .order_by(ConsentRecord.created_at, ConsentRecord.id)
            )
        )
        .scalars()
        .all()
    )
    base = FarmerOut.from_row(farmer, redact_pii=_redact(actor))
    return FarmerDetailOut(
        **base.model_dump(),
        farms=[FarmOut.from_row(f, plots_by_farm[f.id]) for f in farms],
        consents=[ConsentRecordOut.from_row(c) for c in consents],
    )
