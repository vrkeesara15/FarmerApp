"""Helpers shared by the FA-012 / FA-013 / FA-025 write tests: an officer of the seeded
tenant with their bearer headers, a village in their store, the crop ids, and payload
builders (square farm polygons of a given size around the village)."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from decimal import Decimal
from typing import Any

import pytest
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.db.geo import ACRE_M2, offset
from farmerapp.db.session import tenant_scope
from farmerapp.tenants.models import Village
from tests.authz.conftest import Bearer, World

# A spot in Hasanparthy mandal (Warangal) far from every seeded farm.
BASE_LON, BASE_LAT = 79.46, 18.12


def square(lon: float, lat: float, acres: float) -> dict[str, Any]:
    """GeoJSON polygon: a square of ``acres`` with its south-west corner at (lon, lat)."""
    side = (acres * ACRE_M2) ** 0.5
    ne = offset(lon, lat, side, side)
    e = offset(lon, lat, side, 0)
    n = offset(lon, lat, 0, side)
    ring = [[lon, lat], [e[0], e[1]], [ne[0], ne[1]], [n[0], n[1]], [lon, lat]]
    return {"type": "Polygon", "coordinates": [ring]}


def bowtie(lon: float, lat: float, acres: float) -> dict[str, Any]:
    """A self-intersecting ring (VA-F03 "no self-intersection")."""
    side = (acres * ACRE_M2) ** 0.5
    ne = offset(lon, lat, side, side)
    e = offset(lon, lat, side, 0)
    n = offset(lon, lat, 0, side)
    ring = [[lon, lat], [ne[0], ne[1]], [e[0], e[1]], [n[0], n[1]], [lon, lat]]
    return {"type": "Polygon", "coordinates": [ring]}


@dataclass(frozen=True)
class WriteCtx:
    world: World
    officer: User
    headers: dict[str, str]
    village_id: uuid.UUID
    crop_ids: list[uuid.UUID]
    other_officer: User
    other_headers: dict[str, str]

    @property
    def tenant_id(self) -> uuid.UUID:
        return self.world.a.tenant.id

    def farm(
        self,
        *,
        acres: float = 1.0,
        declared: float | None = None,
        at: tuple[float, float] = (BASE_LON, BASE_LAT),
        plots: int = 0,
        boundary: dict[str, Any] | bool | None = True,
        **extra: Any,
    ) -> dict[str, Any]:
        body: dict[str, Any] = {
            "name": "Test farm",
            "area_acres": str(Decimal(str(declared if declared is not None else acres))),
            "soil": "black",
            "irrigation": "borewell",
            "ownership": "own",
            "crop_plots": [self.plot(i) for i in range(plots)],
        }
        if boundary is True:
            body["boundary"] = square(at[0], at[1], acres)
        elif boundary is not False:
            body["boundary"] = boundary
        body.update(extra)
        return body

    def plot(self, i: int = 0, **extra: Any) -> dict[str, Any]:
        body: dict[str, Any] = {
            "crop_id": str(self.crop_ids[i % len(self.crop_ids)]),
            "variety": f"V-{i}",
            "season": "kharif",
            "sowing_date": "2026-07-01",
            "stage": "sown",
            "area_acres": "0.5",
        }
        body.update(extra)
        return body

    def farmer(self, phone: str = "+919000199001", **extra: Any) -> dict[str, Any]:
        body: dict[str, Any] = {
            "phone": phone,
            "name": "Ravi Kumar",
            "village_id": str(self.village_id),
            "landmark": "Near the temple",
            "language": "te",
            "land_ownership": "own",
            "farms": [],
            "consents": [{"purpose": "data", "granted": True}],
        }
        body.update(extra)
        return body


@pytest.fixture
async def ctx(app: FastAPI, world: World, bearer: Bearer, db_session: AsyncSession) -> WriteCtx:
    officers = [u for u in world.a.everyone if u.role == UserRole.FIELD_OFFICER]
    officer = world.a.user(UserRole.FIELD_OFFICER)
    other = next(u for u in officers if u.id != officer.id)
    async with tenant_scope(db_session, world.a.tenant.id):
        village = (
            (
                await db_session.execute(
                    select(Village)
                    .where(Village.store_id == officer.store_id)
                    .order_by(Village.name)
                )
            )
            .scalars()
            .first()
        )
        crops = (await db_session.execute(select(Crop.id).order_by(Crop.code))).scalars().all()
    assert village is not None and crops
    return WriteCtx(
        world=world,
        officer=officer,
        headers=bearer(officer),
        village_id=village.id,
        crop_ids=list(crops),
        other_officer=other,
        other_headers=bearer(other),
    )
