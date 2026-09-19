"""``/v1/corpus`` — WC-007 corpus manager (SPEC 2.6: agronomist read / write; owner and
director read).

Problems and images move ``draft -> reviewed -> approved -> retired``; approving (one entry
via ``/transition`` or a set via ``POST /v1/corpus/approvals``) records who / when and bumps
the corpus version. Only approved problems with approved images are served (``knn.nearest``).
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Annotated

from fastapi import APIRouter, Query, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.diagnosis import corpus
from farmerapp.diagnosis.models import CorpusImage, CorpusProblem, CorpusSource, CorpusStatus
from farmerapp.diagnosis.router import get_diagnosis_services
from farmerapp.diagnosis.schemas import (
    CorpusApprovalIn,
    CorpusImageCreate,
    CorpusImageOut,
    CorpusImagePage,
    CorpusProblemCreate,
    CorpusProblemOut,
    CorpusProblemPage,
    CorpusProblemUpdate,
    CorpusTransitionIn,
    CorpusVersionOut,
    CorpusVersionsOut,
)

READ_ROLES = (Role.AGRONOMIST, Role.OWNER, Role.DIRECTOR)
WRITE_ROLES = (Role.AGRONOMIST,)

router = APIRouter(prefix="/corpus", tags=["corpus"])


async def _problem_out(session: AsyncSession, problem: CorpusProblem) -> CorpusProblemOut:
    counts = await corpus.image_counts(session, [problem.id])
    codes = await corpus.pest_codes(session, [problem.pest_or_disease_id])
    return CorpusProblemOut.from_row(
        problem,
        pest_code=codes.get(problem.pest_or_disease_id),
        image_counts=counts.get(problem.id, {}),
    )


@router.get(
    "/problems",
    operation_id="listCorpusProblems",
    summary="Corpus problems with image counts by status (WC-007)",
    response_model=CorpusProblemPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_problems(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    page: Page,
    crop_id: Annotated[uuid.UUID | None, Query()] = None,
    status: Annotated[list[CorpusStatus] | None, Query()] = None,
    source: Annotated[CorpusSource | None, Query()] = None,
) -> CorpusProblemPage:
    stmt = select(CorpusProblem).where(
        CorpusProblem.tenant_id == actor.tenant_id, CorpusProblem.deleted_at.is_(None)
    )
    if crop_id is not None:
        stmt = stmt.where(CorpusProblem.crop_id == crop_id)
    if status:
        stmt = stmt.where(CorpusProblem.status.in_([s.value for s in status]))
    if source is not None:
        stmt = stmt.where(CorpusProblem.source == source.value)
    keyset = page.after(CorpusProblem.created_at, CorpusProblem.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (
            await session.execute(
                stmt.order_by(CorpusProblem.created_at, CorpusProblem.id).limit(page.fetch)
            )
        )
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    counts = await corpus.image_counts(session, [p.id for p in items])
    codes = await corpus.pest_codes(session, [p.pest_or_disease_id for p in items])
    return CorpusProblemPage(
        items=[
            CorpusProblemOut.from_row(
                p, pest_code=codes.get(p.pest_or_disease_id), image_counts=counts.get(p.id, {})
            )
            for p in items
        ],
        next_cursor=cursor,
        corpus_version=await corpus.current_version(session, actor.tenant_id),
    )


@router.post(
    "/problems",
    operation_id="createCorpusProblem",
    summary="New corpus problem (draft) for a crop x pest / disease",
    status_code=201,
    response_model=CorpusProblemOut,
    responses=problem_responses((409, "corpus_problem_exists"), (422, "corpus_problem_invalid")),
)
async def create_problem(
    body: CorpusProblemCreate,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> CorpusProblemOut:
    problem = await corpus.create_problem(session, actor, body)
    return await _problem_out(session, problem)


@router.get(
    "/problems/{id}",
    operation_id="getCorpusProblem",
    summary="A corpus problem",
    response_model=CorpusProblemOut,
    responses=problem_responses((404, "not_found")),
)
async def get_problem(
    id: uuid.UUID, actor: Annotated[User, require_roles(*READ_ROLES)], session: DbSession
) -> CorpusProblemOut:
    return await _problem_out(session, await corpus.get_problem(session, actor.tenant_id, id))


@router.patch(
    "/problems/{id}",
    operation_id="updateCorpusProblem",
    summary="Edit a draft / reviewed corpus problem (approved entries are immutable)",
    response_model=CorpusProblemOut,
    responses=problem_responses((404, "not_found"), (409, "corpus_entry_locked")),
)
async def update_problem(
    id: uuid.UUID,
    body: CorpusProblemUpdate,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> CorpusProblemOut:
    problem = await corpus.get_problem(session, actor.tenant_id, id, for_update=True)
    return await _problem_out(session, await corpus.update_problem(session, problem, body))


@router.post(
    "/problems/{id}/transition",
    operation_id="transitionCorpusProblem",
    summary="Move a corpus problem through draft -> reviewed -> approved -> retired",
    response_model=CorpusProblemOut,
    responses=problem_responses((404, "not_found"), (409, "invalid_transition")),
)
async def transition_problem(
    id: uuid.UUID,
    body: CorpusTransitionIn,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> CorpusProblemOut:
    problem = await corpus.get_problem(session, actor.tenant_id, id, for_update=True)
    await corpus.transition_problem(
        session, actor, problem, body.to, now=services.clock.now(), note=body.note
    )
    return await _problem_out(session, problem)


@router.get(
    "/problems/{id}/images",
    operation_id="listCorpusImages",
    summary="Images of a corpus problem",
    response_model=CorpusImagePage,
    responses=problem_responses((404, "not_found"), (400, "invalid_cursor")),
)
async def list_images(
    id: uuid.UUID,
    request: Request,
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    auth: Services,
    page: Page,
    status: Annotated[list[CorpusStatus] | None, Query()] = None,
) -> CorpusImagePage:
    now = auth.clock.now()
    problem = await corpus.get_problem(session, actor.tenant_id, id)
    stmt = select(CorpusImage).where(
        CorpusImage.problem_id == problem.id, CorpusImage.deleted_at.is_(None)
    )
    if status:
        stmt = stmt.where(CorpusImage.status.in_([s.value for s in status]))
    keyset = page.after(CorpusImage.created_at, CorpusImage.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (
            await session.execute(
                stmt.order_by(CorpusImage.created_at, CorpusImage.id).limit(page.fetch)
            )
        )
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    services = get_diagnosis_services(request)
    ttl = timedelta(seconds=services.settings.signed_url_ttl_seconds)
    out: list[CorpusImageOut] = []
    for image in items:
        url: str | None = None
        try:
            url = (await services.blobs.signed_url(image.blob_uri, ttl=ttl, now=now)).url
        except (ValueError, LookupError):
            url = None
        out.append(CorpusImageOut.from_row(image).model_copy(update={"signed_url": url}))
    return CorpusImagePage(items=out, next_cursor=cursor)


@router.post(
    "/problems/{id}/images",
    operation_id="addCorpusImage",
    summary="Add an uploaded image to a problem; the server computes its embedding",
    status_code=201,
    response_model=CorpusImageOut,
    responses=problem_responses(
        (404, "not_found"),
        (409, "corpus_image_exists"),
        (409, "corpus_entry_locked"),
        (422, "diagnosis_image_missing"),
        (503, "encoder_unavailable"),
    ),
)
async def add_image(
    id: uuid.UUID,
    body: CorpusImageCreate,
    request: Request,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> CorpusImageOut:
    services = get_diagnosis_services(request)
    problem = await corpus.get_problem(session, actor.tenant_id, id)
    image = await corpus.add_image(
        session, actor, problem, body, encoder=services.encoder, blobs=services.blobs
    )
    return CorpusImageOut.from_row(image)


@router.post(
    "/images/{id}/transition",
    operation_id="transitionCorpusImage",
    summary="Move a corpus image through draft -> reviewed -> approved -> retired",
    response_model=CorpusImageOut,
    responses=problem_responses((404, "not_found"), (409, "invalid_transition")),
)
async def transition_image(
    id: uuid.UUID,
    body: CorpusTransitionIn,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> CorpusImageOut:
    image = await corpus.get_image(session, actor.tenant_id, id, for_update=True)
    await corpus.transition_image(
        session, actor, image, body.to, now=services.clock.now(), note=body.note
    )
    return CorpusImageOut.from_row(image)


@router.post(
    "/approvals",
    operation_id="approveCorpusSet",
    summary="Approve reviewed problems and images together: one corpus version bump",
    status_code=201,
    response_model=CorpusVersionOut,
    responses=problem_responses(
        (404, "not_found"), (409, "invalid_transition"), (422, "corpus_problem_invalid")
    ),
)
async def approve_set(
    body: CorpusApprovalIn,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> CorpusVersionOut:
    version = await corpus.approve_set(
        session,
        actor,
        problem_ids=body.problem_ids,
        image_ids=body.image_ids,
        note=body.note,
        now=services.clock.now(),
    )
    return CorpusVersionOut.from_row(version)


@router.get(
    "/versions",
    operation_id="listCorpusVersions",
    summary="Corpus versions (DX-005), newest first",
    response_model=CorpusVersionsOut,
)
async def list_versions(
    actor: Annotated[User, require_roles(*READ_ROLES)], session: DbSession
) -> CorpusVersionsOut:
    rows = await corpus.versions(session, actor.tenant_id)
    return CorpusVersionsOut(
        current=rows[0].version if rows else 0,
        items=[CorpusVersionOut.from_row(r) for r in rows],
    )


__all__ = ["READ_ROLES", "WRITE_ROLES", "router"]
