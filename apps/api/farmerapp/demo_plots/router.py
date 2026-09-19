"""``/v1/demo-plots`` — FA-026 demo plots (writes: the field officer who runs the demo;
reads: the officer, cluster head (own cluster), owner, director, tenant admin, auditor, and
the agronomist for every demo)."""

from __future__ import annotations

import uuid
from typing import Annotated, Literal

from fastapi import APIRouter, Query, Request

from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.demo_plots import service
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
from farmerapp.uploads.blobstore import BlobStore

router = APIRouter(prefix="/demo-plots", tags=["demo-plots"])

WRITE_ROLES = (Role.FIELD_OFFICER,)
READ_ROLES = (
    Role.FIELD_OFFICER,
    Role.CLUSTER_HEAD,
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.AGRONOMIST,
)
_WRITE_PROBLEMS = ((404, "not_found"), (409, "demo_plot_transition_invalid"))


def _blobs(request: Request) -> BlobStore:
    blobs: BlobStore = request.app.state.blobs
    return blobs


@router.post(
    "",
    operation_id="createDemoPlot",
    summary="Register a demo plot on a farmer's crop plot (vs farmer practice or a plot)",
    status_code=201,
    response_model=DemoPlotOut,
    responses=problem_responses(
        (404, "not_found"), (422, "demo_plot_invalid"), (422, "idempotency_key_reuse")
    ),
)
@idempotent(status_code=201)
async def create_demo_plot(
    request: Request,
    body: DemoPlotCreate,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> DemoPlotOut:
    row, _ = await service.create_demo(session, actor, body, now=services.clock.now())
    return DemoPlotOut.from_row(row)


@router.get(
    "",
    operation_id="listDemoPlots",
    summary="Demo plots the caller may see, oldest first (cursor)",
    response_model=DemoPlotPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_demo_plots(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    page: Page,
    status: Annotated[Literal["created", "active", "harvested", "reported"] | None, Query()] = None,
    farmer_id: Annotated[uuid.UUID | None, Query()] = None,
) -> DemoPlotPage:
    return await service.list_demos(session, actor, page, status=status, farmer_id=farmer_id)


@router.get(
    "/{id}",
    operation_id="getDemoPlot",
    summary="A demo plot with its stage observations",
    response_model=DemoPlotDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_demo_plot(
    id: uuid.UUID, actor: Annotated[User, require_roles(*READ_ROLES)], session: DbSession
) -> DemoPlotDetailOut:
    return await service.detail(session, await service.visible_demo(session, actor, id))


@router.post(
    "/{id}/observations",
    operation_id="addDemoObservation",
    summary="Record a stage observation with photos (completed demo_plot uploads)",
    status_code=201,
    response_model=ObservationOut,
    responses=problem_responses(*_WRITE_PROBLEMS, (422, "invalid_blob")),
)
@idempotent(status_code=201)
async def add_observation(
    request: Request,
    id: uuid.UUID,
    body: ObservationIn,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> ObservationOut:
    demo = await service.own_demo(session, actor, id)
    row, _ = await service.add_observation(session, actor, demo, body, blobs=_blobs(request))
    return ObservationOut.from_row(row)


@router.post(
    "/{id}/transition",
    operation_id="transitionDemoPlot",
    summary="Activate the demo (treatment applied) or mark it reported",
    response_model=DemoPlotOut,
    responses=problem_responses(*_WRITE_PROBLEMS),
)
async def transition_demo_plot(
    id: uuid.UUID,
    body: DemoTransitionIn,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> DemoPlotOut:
    demo = await service.own_demo(session, actor, id)
    return DemoPlotOut.from_row(
        await service.transition(session, demo, body, now=services.clock.now())
    )


@router.post(
    "/{id}/yield",
    operation_id="recordDemoYield",
    summary="Enter the harvest: demo vs farmer-practice yield (kg per acre)",
    response_model=DemoPlotOut,
    responses=problem_responses(*_WRITE_PROBLEMS),
)
async def record_yield(
    id: uuid.UUID,
    body: YieldIn,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> DemoPlotOut:
    demo = await service.own_demo(session, actor, id)
    return DemoPlotOut.from_row(
        await service.record_yield(session, demo, body, now=services.clock.now())
    )


__all__ = ["router"]
