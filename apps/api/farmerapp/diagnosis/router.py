"""``/v1/diagnoses`` — crop doctor requests, results, the agronomist queue (SPEC 3).

* ``POST /v1/diagnoses`` — farmer (self), field officer (own farmers).
* ``GET /v1/diagnoses``, ``GET /v1/diagnoses/{id}`` — farmer, field officer, cluster head,
  store manager (their scope), agronomist, owner, director, tenant admin, auditor.
* ``GET /v1/diagnoses/review-queue`` — agronomist, owner.
* ``POST /v1/diagnoses/{id}/ask-expert`` — the farmer it is about, the officer who asked.
* ``POST /v1/diagnoses/{id}/review`` — agronomist.
* ``GET /v1/diagnoses/thresholds`` (agronomist, owner, director) / ``PUT`` (agronomist).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Query, Request
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import Role, require_roles
from farmerapp.diagnosis import service
from farmerapp.diagnosis.decision import (
    DEFAULT_AGREEMENT,
    DEFAULT_MIN_SIMILARITY,
    DEFAULT_T1,
)
from farmerapp.diagnosis.models import Confidence, Diagnosis, DiagnosisStatus
from farmerapp.diagnosis.schemas import (
    AskExpertIn,
    DiagnosisCreate,
    DiagnosisDetailOut,
    DiagnosisOut,
    DiagnosisPage,
    DiagnosisPhotoOut,
    DiagnosisReviewOut,
    ReviewIn,
    ReviewQueueCounts,
    ReviewQueueItem,
    ReviewQueuePage,
    ThresholdIn,
    ThresholdOut,
    ThresholdsOut,
)
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.diagnosis.thresholds import set_thresholds, threshold_history
from farmerapp.uploads.blobstore import BlobStore

#: DX-006: a provisional result older than this is overdue (OPS-009 alert).
QUEUE_ALERT_HOURS = 18

CREATE_ROLES = (Role.FARMER, Role.FIELD_OFFICER)
READ_ROLES = (
    Role.FARMER,
    Role.FIELD_OFFICER,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.AGRONOMIST,
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
)
QUEUE_ROLES = (Role.AGRONOMIST, Role.OWNER)
THRESHOLD_READ_ROLES = (Role.AGRONOMIST, Role.OWNER, Role.DIRECTOR)

router = APIRouter(prefix="/diagnoses", tags=["diagnosis"])


def get_diagnosis_services(request: Request) -> DiagnosisServices:
    services: DiagnosisServices = request.app.state.diagnosis
    return services


async def _signed(
    blobs: BlobStore, photos: list[DiagnosisPhotoOut], now: datetime, ttl_s: int
) -> list[DiagnosisPhotoOut]:
    out: list[DiagnosisPhotoOut] = []
    for photo in photos:
        url: str | None = None
        try:
            url = (
                await blobs.signed_url(photo.blob_uri, ttl=timedelta(seconds=ttl_s), now=now)
            ).url
        except (ValueError, LookupError):
            url = None
        out.append(photo.model_copy(update={"signed_url": url}))
    return out


async def _detail(
    session: AsyncSession,
    actor: User,
    row: Diagnosis,
    *,
    services: DiagnosisServices,
    now: datetime,
) -> DiagnosisDetailOut:
    """Provenance (scores, reviews) only for reviewer roles; everyone gets signed photos."""
    base = DiagnosisOut.from_row(row)
    photos = await _signed(
        services.blobs, base.images, now, services.settings.signed_url_ttl_seconds
    )
    if UserRole(actor.role) not in service.REVIEWER_ROLES:
        return DiagnosisDetailOut(**{**base.model_dump(), "images": photos})
    reviews = await service.reviews_of(session, row.id)
    return DiagnosisDetailOut(
        **{**base.model_dump(), "images": photos},
        scores=row.scores,
        reviews=[DiagnosisReviewOut.from_row(r) for r in reviews],
        reviewed_by=row.reviewed_by,
        llm_used=row.llm_used,
        on_device=row.on_device,
        expert_requested_by=row.expert_requested_by,
        expert_note=row.expert_note,
    )


@router.post(
    "",
    operation_id="createDiagnosis",
    summary="Ask the crop doctor: queue a diagnosis for 1-3 uploaded photos (FM-004, FA-019)",
    status_code=202,
    response_model=DiagnosisOut,
    responses=problem_responses(
        (404, "not_found"),
        (422, "diagnosis_image_missing"),
        (422, "diagnosis_invalid"),
        (422, "idempotency_key_reuse"),
    ),
)
@idempotent(status_code=202)
async def create_diagnosis(
    body: DiagnosisCreate,
    request: Request,
    actor: Annotated[User, require_roles(*CREATE_ROLES)],
    session: DbSession,
    services: Services,
) -> DiagnosisOut:
    diagnosis_services = get_diagnosis_services(request)
    row, _created = await service.create_diagnosis(
        session, actor, body, services=diagnosis_services, now=services.clock.now()
    )
    return DiagnosisOut.from_row(row)


@router.get(
    "",
    operation_id="listDiagnoses",
    summary="Diagnoses visible to the caller, newest first (history, FM-005)",
    response_model=DiagnosisPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_diagnoses(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    page: Page,
    farmer_id: Annotated[uuid.UUID | None, Query()] = None,
    status: Annotated[list[DiagnosisStatus] | None, Query()] = None,
) -> DiagnosisPage:
    stmt = select(Diagnosis).where(*service.diagnosis_filters(actor))
    if farmer_id is not None:
        stmt = stmt.where(Diagnosis.farmer_id == farmer_id)
    if status:
        stmt = stmt.where(Diagnosis.status.in_([s.value for s in status]))
    keyset = page.before(Diagnosis.created_at, Diagnosis.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (
            await session.execute(
                stmt.order_by(Diagnosis.created_at.desc(), Diagnosis.id.desc()).limit(page.fetch)
            )
        )
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    return DiagnosisPage(items=[DiagnosisOut.from_row(r) for r in items], next_cursor=cursor)


@router.get(
    "/review-queue",
    operation_id="diagnosisReviewQueue",
    summary="Agronomist queue: provisional, out-of-scope and flagged diagnoses (WC-006)",
    response_model=ReviewQueuePage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def review_queue(
    request: Request,
    actor: Annotated[User, require_roles(*QUEUE_ROLES)],
    session: DbSession,
    services: Services,
    page: Page,
    crop_id: Annotated[uuid.UUID | None, Query()] = None,
    confidence: Annotated[list[Confidence] | None, Query()] = None,
    min_age_hours: Annotated[float | None, Query(ge=0, description="Older than N hours")] = None,
    flagged: Annotated[bool | None, Query()] = None,
) -> ReviewQueuePage:
    now = services.clock.now()
    filters = service.queue_filters(actor)
    if crop_id is not None:
        filters.append(Diagnosis.crop_id == crop_id)
    if confidence:
        filters.append(Diagnosis.confidence.in_([c.value for c in confidence]))
    if min_age_hours is not None:
        filters.append(Diagnosis.created_at <= now - timedelta(hours=min_age_hours))
    if flagged is not None:
        filters.append(Diagnosis.flagged.is_(flagged))
    # Oldest first: the SLA is about age (DX-006).
    stmt = select(Diagnosis).where(*filters)
    keyset = page.after(Diagnosis.created_at, Diagnosis.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (await session.execute(stmt.order_by(Diagnosis.created_at, Diagnosis.id).limit(page.fetch)))
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    diagnosis_services = get_diagnosis_services(request)
    overdue_before = now - timedelta(hours=QUEUE_ALERT_HOURS)
    out: list[ReviewQueueItem] = []
    for row in items:
        detail = await _detail(session, actor, row, services=diagnosis_services, now=now)
        age = (now - row.created_at).total_seconds() / 3600
        out.append(
            ReviewQueueItem(
                **detail.model_dump(),
                age_hours=round(age, 2),
                overdue=row.created_at <= overdue_before,
            )
        )
    by_confidence: dict[str, int] = {}
    for confidence_value, count in (
        await session.execute(
            select(Diagnosis.confidence, func.count())
            .where(*filters)
            .group_by(Diagnosis.confidence)
        )
    ).tuples():
        key = str(confidence_value) if confidence_value else "none"
        by_confidence[key] = by_confidence.get(key, 0) + int(count)
    overdue = await session.scalar(
        select(func.count())
        .select_from(Diagnosis)
        .where(*filters, Diagnosis.created_at <= overdue_before)
    )
    return ReviewQueuePage(
        items=out,
        next_cursor=cursor,
        counts=ReviewQueueCounts(
            total=sum(by_confidence.values()),
            overdue=int(overdue or 0),
            by_confidence=by_confidence,
        ),
    )


@router.get(
    "/thresholds",
    operation_id="getDiagnosisThresholds",
    summary="DX-003 decision thresholds per crop with their versions",
    response_model=ThresholdsOut,
)
async def get_thresholds(
    actor: Annotated[User, require_roles(*THRESHOLD_READ_ROLES)], session: DbSession
) -> ThresholdsOut:
    rows = await threshold_history(session, actor.tenant_id)
    return ThresholdsOut(
        defaults={
            "t1": DEFAULT_T1,
            "agreement": DEFAULT_AGREEMENT,
            "min_similarity": DEFAULT_MIN_SIMILARITY,
        },
        items=[ThresholdOut.from_row(r) for r in rows],
    )


@router.put(
    "/thresholds",
    operation_id="setDiagnosisThresholds",
    summary="Set the DX-003 thresholds of a crop (or the default): a new config version",
    response_model=ThresholdOut,
    responses=problem_responses((422, "validation_error")),
)
async def put_thresholds(
    body: ThresholdIn,
    actor: Annotated[User, require_roles(Role.AGRONOMIST)],
    session: DbSession,
) -> ThresholdOut:
    from farmerapp.api.errors import AppError
    from farmerapp.catalog.crops import Crop

    if body.min_similarity > body.t1:
        raise AppError("min_similarity must not exceed t1.", status=422, code="validation_error")
    if body.crop_id is not None:
        crop = await session.get(Crop, body.crop_id)
        if crop is None or crop.tenant_id != actor.tenant_id:
            raise AppError("Unknown crop.", status=422, code="validation_error")
    row = await set_thresholds(
        session,
        actor,
        crop_id=body.crop_id,
        t1=body.t1,
        agreement=body.agreement,
        min_similarity=body.min_similarity,
        note=body.note,
    )
    return ThresholdOut.from_row(row)


@router.get(
    "/{id}",
    operation_id="getDiagnosis",
    summary="A diagnosis and its result (poll after POST; also in the sync feed)",
    response_model=DiagnosisDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_diagnosis(
    id: uuid.UUID,
    request: Request,
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    services: Services,
) -> DiagnosisDetailOut:
    row = await service.visible_diagnosis(session, actor, id)
    return await _detail(
        session, actor, row, services=get_diagnosis_services(request), now=services.clock.now()
    )


@router.post(
    "/{id}/ask-expert",
    operation_id="askExpertDiagnosis",
    summary="Ask an expert: put an answered case in the agronomist queue (FM-006, no re-upload)",
    response_model=DiagnosisDetailOut,
    responses=problem_responses((404, "not_found"), (409, "diagnosis_already_reviewed")),
)
async def ask_expert(
    id: uuid.UUID,
    request: Request,
    actor: Annotated[User, require_roles(*CREATE_ROLES)],
    session: DbSession,
    services: Services,
    body: AskExpertIn | None = None,
) -> DiagnosisDetailOut:
    """The farmer the case is about, or the field officer who asked for it. The same photos
    go to the agronomist queue as a ``flagged`` case and the agronomists are notified
    (``diagnosis_expert_requested``). Idempotent: repeating it changes nothing."""
    diagnosis_services = get_diagnosis_services(request)
    row = await service.visible_diagnosis(session, actor, id, for_update=True)
    now = services.clock.now()
    await service.ask_expert(session, actor, row, note=body.note if body else None, now=now)
    return await _detail(session, actor, row, services=diagnosis_services, now=now)


@router.post(
    "/{id}/review",
    operation_id="reviewDiagnosis",
    summary="Agronomist confirms or corrects a diagnosis, optionally adding it to the corpus",
    response_model=DiagnosisDetailOut,
    responses=problem_responses(
        (404, "not_found"), (409, "diagnosis_not_reviewable"), (422, "review_invalid")
    ),
)
async def review_diagnosis(
    id: uuid.UUID,
    body: ReviewIn,
    request: Request,
    actor: Annotated[User, require_roles(Role.AGRONOMIST)],
    session: DbSession,
    services: Services,
) -> DiagnosisDetailOut:
    diagnosis_services = get_diagnosis_services(request)
    row = await service.visible_diagnosis(session, actor, id, for_update=True)
    now = services.clock.now()
    await service.review(session, actor, row, body, services=diagnosis_services, now=now)
    return await _detail(session, actor, row, services=diagnosis_services, now=now)


__all__ = ["CREATE_ROLES", "QUEUE_ALERT_HOURS", "READ_ROLES", "get_diagnosis_services", "router"]
