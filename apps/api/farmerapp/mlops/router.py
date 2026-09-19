"""Diagnosis ML operations routes (M7: DX-011, DX-012, AN-007).

* ``GET /v1/diagnoses/quality`` — AN-007 summary (tenant-wide roles, agronomist).
* ``GET /v1/diagnoses/evaluations`` / ``/{id}`` — DX-011 nightly runs (same roles).
* ``GET /v1/models/on-device/current`` — the newest approved on-device model with a signed
  download URL (every signed-in role: both apps download it).
* ``GET /v1/models/releases`` / ``/{id}`` — DX-012 releases (agronomist, owner, director,
  tenant admin).
* ``POST /v1/models/releases/{id}/decision`` — approve / reject a candidate, retire an
  approved release (agronomist, owner; step-up; audited).

Registered **before** ``/v1/diagnoses/{id}`` so ``quality`` / ``evaluations`` are not read as
diagnosis ids.
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Annotated

from fastapi import APIRouter, Query, Request
from sqlalchemy import case, select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.stepup import STEP_UP_OPENAPI, StepUp
from farmerapp.mlops import quality, releases
from farmerapp.mlops.models import EvaluationRun, ModelRelease, ReleaseKind, ReleaseStatus
from farmerapp.mlops.schemas import (
    EvaluationListOut,
    EvaluationRunOut,
    EvaluationSummaryOut,
    ModelReleaseListOut,
    ModelReleaseOut,
    OnDeviceModelOut,
    QualityOut,
    ReleaseDecisionIn,
)
from farmerapp.uploads.blobstore import BlobStore

router = APIRouter(tags=["diagnosis-ops"])

QUALITY_ROLES = (Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN, Role.AUDITOR, Role.AGRONOMIST)
RELEASE_READ_ROLES = (Role.AGRONOMIST, Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN)
RELEASE_DECIDE_ROLES = (Role.AGRONOMIST, Role.OWNER)

_DECISIONS = {
    "approve": ReleaseStatus.APPROVED,
    "reject": ReleaseStatus.REJECTED,
    "retire": ReleaseStatus.RETIRED,
}


@router.get(
    "/diagnoses/quality",
    operation_id="getDiagnosisQuality",
    summary="AN-007: corpus share, escalation rate, review SLA, top unknowns, latest evaluation",
    response_model=QualityOut,
)
async def diagnosis_quality(
    actor: Annotated[User, require_roles(*QUALITY_ROLES)],
    session: DbSession,
    services: Services,
    days: Annotated[int, Query(ge=1, le=365)] = 30,
) -> QualityOut:
    return await quality.quality_summary(
        session, actor.tenant_id, now=services.clock.now(), days=days
    )


@router.get(
    "/diagnoses/evaluations",
    operation_id="listDiagnosisEvaluations",
    summary="DX-011: nightly evaluation runs, newest first",
    response_model=EvaluationListOut,
)
async def list_evaluations(
    actor: Annotated[User, require_roles(*QUALITY_ROLES)],
    session: DbSession,
    limit: Annotated[int, Query(ge=1, le=200)] = 30,
) -> EvaluationListOut:
    runs = await quality.evaluation_runs(session, actor.tenant_id, limit=limit)
    return EvaluationListOut(items=[EvaluationSummaryOut.from_row(r) for r in runs])


@router.get(
    "/diagnoses/evaluations/{id}",
    operation_id="getDiagnosisEvaluation",
    summary="DX-011: one evaluation run with metrics per crop and per problem",
    response_model=EvaluationRunOut,
    responses=problem_responses((404, "not_found")),
)
async def get_evaluation(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*QUALITY_ROLES)],
    session: DbSession,
) -> EvaluationRunOut:
    row = await session.get(EvaluationRun, id)
    if row is None or row.tenant_id != actor.tenant_id or row.deleted_at is not None:
        raise NotFoundError("Evaluation run not found.")
    return EvaluationRunOut.from_row(row)


# --------------------------------------------------------------------------- DX-012
def _blobs(request: Request) -> BlobStore:
    store: BlobStore = request.app.state.blobs
    return store


@router.get(
    "/models/on-device/current",
    operation_id="getCurrentOnDeviceModel",
    summary="DX-012: the approved on-device model to download (signed URL, sha256)",
    response_model=OnDeviceModelOut,
    responses=problem_responses((404, "no_approved_model")),
)
async def current_on_device_model(
    request: Request,
    actor: Annotated[User, require_roles(*Role)],
    session: DbSession,
    services: Services,
) -> OnDeviceModelOut:
    row = await releases.current_release(session, actor.tenant_id, ReleaseKind.ON_DEVICE)
    now = services.clock.now()
    signed = await _blobs(request).signed_url(
        row.artifact_uri,
        ttl=timedelta(seconds=services.settings.signed_url_ttl_seconds),
        now=now,
    )
    meta = row.model_metadata or {}
    return OnDeviceModelOut(
        release_id=row.id,
        model_name=row.model_name,
        model_version=row.model_version,
        sha256=row.sha256,
        size_bytes=row.size_bytes,
        url=signed.url,
        url_expires_at=signed.expires_at,
        labels=meta.get("labels"),
        thresholds=meta.get("thresholds"),
        input=meta.get("input"),
        output=meta.get("output"),
        approved_at=row.decided_at,
    )


@router.get(
    "/models/releases",
    operation_id="listModelReleases",
    summary="DX-012: on-device model releases (candidates first, then newest)",
    response_model=ModelReleaseListOut,
)
async def list_releases(
    actor: Annotated[User, require_roles(*RELEASE_READ_ROLES)],
    session: DbSession,
    status: Annotated[ReleaseStatus | None, Query()] = None,
) -> ModelReleaseListOut:
    stmt = select(ModelRelease).where(
        ModelRelease.tenant_id == actor.tenant_id, ModelRelease.deleted_at.is_(None)
    )
    if status is not None:
        stmt = stmt.where(ModelRelease.status == status.value)
    rows = await session.scalars(
        stmt.order_by(
            case((ModelRelease.status == ReleaseStatus.CANDIDATE.value, 0), else_=1),
            ModelRelease.created_at.desc(),
            ModelRelease.id,
        ).limit(100)
    )
    return ModelReleaseListOut(items=[ModelReleaseOut.from_row(r) for r in rows])


@router.get(
    "/models/releases/{id}",
    operation_id="getModelRelease",
    summary="DX-012: one release with its metadata and evaluation numbers",
    response_model=ModelReleaseOut,
    responses=problem_responses((404, "not_found")),
)
async def get_release(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*RELEASE_READ_ROLES)],
    session: DbSession,
) -> ModelReleaseOut:
    return ModelReleaseOut.from_row(await releases.visible_release(session, actor, id))


@router.post(
    "/models/releases/{id}/decision",
    operation_id="decideModelRelease",
    summary="DX-012 approval gate: approve / reject a candidate, retire a release (step-up)",
    response_model=ModelReleaseOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses(
        (401, "step_up_required"),
        (404, "not_found"),
        (409, "invalid_transition"),
        (409, "evaluation_missing"),
    ),
)
async def decide_release(
    id: uuid.UUID,
    body: ReleaseDecisionIn,
    actor: Annotated[User, require_roles(*RELEASE_DECIDE_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> ModelReleaseOut:
    row = await releases.visible_release(session, actor, id)
    row = await releases.decide(
        session,
        actor,
        row,
        to=_DECISIONS[body.decision],
        note=body.note,
        now=services.clock.now(),
    )
    return ModelReleaseOut.from_row(row)


__all__ = ["QUALITY_ROLES", "RELEASE_DECIDE_ROLES", "RELEASE_READ_ROLES", "router"]
