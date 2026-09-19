"""FA-026 demo plot lifecycle: create -> activate -> stage observations -> yield -> report.

=========================== ================================================================
step                        rule
=========================== ================================================================
create                      the farmer and the crop plot (and the comparison plot) must be
                            within the officer's farmer scope; the plot must be the farmer's
activate (``active``)       from ``created``; ``started_at``
observation                 while ``created`` / ``active`` / ``harvested``; photos are
                            completed uploads of the tenant; the latest stage is kept on
                            the plot and ``last_observed_at`` feeds the FA-018 beat plan
yield (``harvested``)       from ``active`` (or a correction while ``harvested``): demo and
                            farmer-practice yields in kg per acre
report (``reported``)       from ``harvested``; final
=========================== ================================================================

A wrong step is ``409 demo_plot_transition_invalid``. Reads: the officer who runs the demo;
cluster heads, owners, directors, tenant admins and auditors per the field-staff scope; the
agronomist reads every demo (crop data, SPEC 2.6).
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import ColumnElement, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, ConflictError, NotFoundError
from farmerapp.api.pagination import PageRequest
from farmerapp.auth.field_scope import staff_ids
from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.models import Product
from farmerapp.demo_plots.models import DemoObservation, DemoPlot, DemoStatus
from farmerapp.demo_plots.schemas import (
    DemoPlotCreate,
    DemoPlotDetailOut,
    DemoPlotOut,
    DemoPlotPage,
    DemoTransitionIn,
    ObservationIn,
    ObservationOut,
    YieldIn,
)
from farmerapp.farmers import service as farmers
from farmerapp.farmers.models import Farm
from farmerapp.payments.service import validate_blob
from farmerapp.uploads.blobstore import BlobStore


class DemoTransitionInvalidError(ConflictError):
    code = "demo_plot_transition_invalid"


class DemoPlotInvalidError(AppError):
    status = 422
    code = "demo_plot_invalid"


def demo_filters(actor: User) -> list[ColumnElement[bool]]:
    """Which demo plots ``actor`` may read."""
    out: list[ColumnElement[bool]] = [
        DemoPlot.tenant_id == actor.tenant_id,
        DemoPlot.deleted_at.is_(None),
    ]
    if UserRole(actor.role) != UserRole.AGRONOMIST:
        out.append(DemoPlot.officer_id.in_(staff_ids(actor)))
    return out


async def visible_demo(session: AsyncSession, actor: User, demo_id: uuid.UUID) -> DemoPlot:
    row = (
        await session.execute(select(DemoPlot).where(DemoPlot.id == demo_id, *demo_filters(actor)))
    ).scalar_one_or_none()
    if row is None:
        raise NotFoundError("Demo plot not found.")
    return row


async def own_demo(session: AsyncSession, actor: User, demo_id: uuid.UUID) -> DemoPlot:
    """A demo plot the actor runs (writes); anything else is a 404."""
    row = await visible_demo(session, actor, demo_id)
    if row.officer_id != actor.id:
        raise NotFoundError("Demo plot not found.")
    return row


async def create_demo(
    session: AsyncSession, actor: User, body: DemoPlotCreate, *, now: datetime
) -> tuple[DemoPlot, bool]:
    if body.id is not None:
        existing = await session.get(DemoPlot, body.id)
        if existing is not None:
            return await own_demo(session, actor, existing.id), False
    farmer = await farmers.visible_farmer(session, actor, body.farmer_id)
    plot = await farmers.visible_crop_plot(session, actor, body.crop_plot_id)
    farm = await session.get_one(Farm, plot.farm_id)
    if farm.farmer_id != farmer.id:
        raise DemoPlotInvalidError("The crop plot does not belong to the farmer.")
    if body.comparison_crop_plot_id is not None:
        await farmers.visible_crop_plot(session, actor, body.comparison_crop_plot_id)
    if body.product_id is not None:
        product = await session.get(Product, body.product_id)
        if product is None or product.tenant_id != actor.tenant_id:
            raise DemoPlotInvalidError("Unknown product.")
    row = DemoPlot(
        id=body.id or uuid.uuid4(),
        tenant_id=actor.tenant_id,
        officer_id=actor.id,
        farmer_id=farmer.id,
        farm_id=farm.id,
        crop_plot_id=plot.id,
        baseline=body.baseline,
        comparison_crop_plot_id=body.comparison_crop_plot_id,
        product_id=body.product_id,
        treatment=body.treatment,
    )
    session.add(row)
    await session.flush()
    await session.refresh(row)
    return row, True


async def add_observation(
    session: AsyncSession,
    actor: User,
    demo: DemoPlot,
    body: ObservationIn,
    *,
    blobs: BlobStore,
) -> tuple[DemoObservation, bool]:
    if body.id is not None:
        existing = await session.get(DemoObservation, body.id)
        if existing is not None:
            if existing.tenant_id != actor.tenant_id or existing.demo_plot_id != demo.id:
                raise NotFoundError("Observation not found.")
            return existing, False
    if demo.status == DemoStatus.REPORTED:
        raise DemoTransitionInvalidError("The demo is reported; no more observations.")
    for uri in body.photo_uris:
        await validate_blob(uri, actor.tenant_id, blobs)
    row = DemoObservation(
        id=body.id or uuid.uuid4(),
        tenant_id=actor.tenant_id,
        demo_plot_id=demo.id,
        officer_id=actor.id,
        stage=body.stage,
        side=body.side,
        observed_at=body.observed_at,
        note=body.note,
        photo_uris=list(body.photo_uris),
    )
    session.add(row)
    if demo.last_observed_at is None or body.observed_at >= demo.last_observed_at:
        demo.last_observed_at = body.observed_at
        demo.stage = body.stage
    await session.flush()
    await session.refresh(row)
    return row, True


async def transition(
    session: AsyncSession, demo: DemoPlot, body: DemoTransitionIn, *, now: datetime
) -> DemoPlot:
    at = body.at or now
    if body.to == DemoStatus.ACTIVE.value:
        if demo.status == DemoStatus.ACTIVE:
            return demo  # replay
        if demo.status != DemoStatus.CREATED:
            raise DemoTransitionInvalidError(f"A {demo.status} demo cannot be activated.")
        demo.status = DemoStatus.ACTIVE.value
        demo.started_at = at
    else:
        if demo.status == DemoStatus.REPORTED:
            return demo
        if demo.status != DemoStatus.HARVESTED:
            raise DemoTransitionInvalidError("Enter the yield (harvest) before reporting.")
        demo.status = DemoStatus.REPORTED.value
        demo.reported_at = at
    await session.flush()
    await session.refresh(demo)
    return demo


async def record_yield(
    session: AsyncSession, demo: DemoPlot, body: YieldIn, *, now: datetime
) -> DemoPlot:
    if demo.status not in (DemoStatus.ACTIVE, DemoStatus.HARVESTED):
        raise DemoTransitionInvalidError(f"A {demo.status} demo cannot take a yield entry.")
    demo.demo_yield_kg_per_acre = body.demo_yield_kg_per_acre
    demo.practice_yield_kg_per_acre = body.practice_yield_kg_per_acre
    demo.yield_note = body.note
    demo.harvested_at = body.harvested_at or demo.harvested_at or now
    demo.status = DemoStatus.HARVESTED.value
    await session.flush()
    await session.refresh(demo)
    return demo


async def detail(session: AsyncSession, demo: DemoPlot) -> DemoPlotDetailOut:
    rows = (
        (
            await session.execute(
                select(DemoObservation)
                .where(
                    DemoObservation.demo_plot_id == demo.id,
                    DemoObservation.deleted_at.is_(None),
                )
                .order_by(DemoObservation.observed_at, DemoObservation.id)
            )
        )
        .scalars()
        .all()
    )
    return DemoPlotDetailOut(
        **DemoPlotOut.from_row(demo).model_dump(),
        observations=[ObservationOut.from_row(r) for r in rows],
    )


async def list_demos(
    session: AsyncSession,
    actor: User,
    page: PageRequest,
    *,
    status: str | None,
    farmer_id: uuid.UUID | None,
) -> DemoPlotPage:
    stmt = select(DemoPlot).where(*demo_filters(actor))
    if status is not None:
        stmt = stmt.where(DemoPlot.status == status)
    if farmer_id is not None:
        stmt = stmt.where(DemoPlot.farmer_id == farmer_id)
    keyset = page.after(DemoPlot.created_at, DemoPlot.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (await session.execute(stmt.order_by(DemoPlot.created_at, DemoPlot.id).limit(page.fetch)))
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    return DemoPlotPage(items=[DemoPlotOut.from_row(r) for r in items], next_cursor=cursor)


__all__ = [
    "DemoPlotInvalidError",
    "DemoTransitionInvalidError",
    "add_observation",
    "create_demo",
    "demo_filters",
    "detail",
    "list_demos",
    "own_demo",
    "record_yield",
    "transition",
    "visible_demo",
]
