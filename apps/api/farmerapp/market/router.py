"""FM-012 mandi price routes.

* ``GET /v1/me/mandi-prices`` — the farmer's own crops (farmer app, F44a next to My crops).
* ``GET /v1/farmers/{id}/mandi-prices`` — the officer variant: the same answer for one of
  their farmers, so an officer can quote a price during a visit (agent app).

Both return, per crop, the rows of the **latest date we hold**, nearest market first, each
with ``price_date`` and ``source_name`` — FM-012's acceptance criterion — plus
``indicative_note_key`` so both apps show the "indicative only" line in the farmer's language.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import select

from farmerapp.advisory.calendar import own_farmer
from farmerapp.api.errors import problem_responses
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.farmers import service as farmers
from farmerapp.farmers.models import Farmer
from farmerapp.market import service
from farmerapp.market.schemas import CropPricesOut, MandiPricesOut, MandiQuoteOut
from farmerapp.tenants.models import Village

router = APIRouter(tags=["market"])

#: Staff who may see a farmer's prices: the same scope as the crop calendar (SPEC 2.6).
STAFF_ROLES = (
    Role.FIELD_OFFICER,
    Role.STORE_MANAGER,
    Role.CLUSTER_HEAD,
    Role.TENANT_ADMIN,
    Role.OWNER,
    Role.DIRECTOR,
    Role.AUDITOR,
    Role.AGRONOMIST,
)
FARMER_DATA_ROLES = (*STAFF_ROLES, Role.FARMER)

MAX_MARKETS = 10


async def _out(session: DbSession, farmer: Farmer, limit_per_crop: int) -> MandiPricesOut:
    district = await session.scalar(select(Village.district).where(Village.id == farmer.village_id))
    groups = await service.prices_for_farmer(session, farmer, limit_per_crop=limit_per_crop)
    dates = [g.price_date for g in groups if g.price_date is not None]
    return MandiPricesOut(
        farmer_id=farmer.id,
        district=district,
        as_of=max(dates) if dates else None,
        crops=[
            CropPricesOut(
                crop_id=g.crop_id,
                crop_code=g.crop_code,
                crop_name=g.crop_name,
                crop_names={"en": g.crop_name, **g.crop_names},
                price_date=g.price_date,
                source_name=g.source_name,
                source_url=g.source_url,
                quotes=[MandiQuoteOut.model_validate(row) for row in g.rows],
            )
            for g in groups
        ],
    )


@router.get(
    "/me/mandi-prices",
    operation_id="getMyMandiPrices",
    summary="FM-012: mandi prices for the farmer's own crops, with the date and the source",
    response_model=MandiPricesOut,
    responses=problem_responses((404, "not_found")),
)
async def my_mandi_prices(
    actor: Annotated[User, require_roles(Role.FARMER)],
    session: DbSession,
    markets: Annotated[int, Query(ge=1, le=MAX_MARKETS)] = 5,
) -> MandiPricesOut:
    return await _out(session, await own_farmer(session, actor), markets)


@router.get(
    "/farmers/{id}/mandi-prices",
    operation_id="getFarmerMandiPrices",
    summary="FM-012: mandi prices for one farmer's crops (staff in scope, or the farmer)",
    response_model=MandiPricesOut,
    responses=problem_responses((404, "not_found")),
)
async def farmer_mandi_prices(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*FARMER_DATA_ROLES)],
    session: DbSession,
    markets: Annotated[int, Query(ge=1, le=MAX_MARKETS)] = 5,
) -> MandiPricesOut:
    farmer = await farmers.visible_farmer(session, actor, id)
    return await _out(session, farmer, markets)


__all__ = ["router"]
