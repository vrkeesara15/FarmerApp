"""Diagnosis requests, scope, delivery and the agronomist review (FM-004, FA-019, WC-006).

* ``create_diagnosis`` — ``POST /v1/diagnoses`` and the sync op ``diagnosis`` create: a
  farmer asks for themself, a field officer for one of their own farmers. The photos must be
  completed uploads of the tenant (1-3; the device queues the op until its uploads are
  done); the server keeps its own sha256 of each. District comes from the farmer's village,
  season / stage from the crop plot (else the IST month). The row is ``queued`` and
  ``diagnosis.requested`` is published (``DIAGNOSIS_DELIVERY=pubsub``) or the pipeline runs
  in the request (``inline``, local / dev). A replayed id returns the existing row.
* ``diagnosis_filters`` — farmer: own; field officer: own farmers (or what they asked);
  cluster head / store manager: their cluster / store's farmers; agronomist, owner,
  director, tenant admin, auditor: the tenant (SPEC 2.6 "Farmer profile" row: the agronomist
  reads crop data).
* ``ask_expert`` — FM-006 on an answered case: flagged into the agronomist queue with the
  same photos (no second diagnosis), agronomists notified (``diagnosis_expert_requested``).
* ``review`` — WC-006: confirm / correct / not diagnosable, the farmer's result is rebuilt
  (status ``confirmed`` / ``corrected``, source ``agronomist``, ``can_buy`` now true), the
  farmer and officer are notified (``diagnosis_reviewed``), ``add_to_corpus`` copies the
  photos into the corpus as ``reviewed`` images (still needing approval, WC-007), and the
  action is appended to ``diagnosis_review``.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy import ColumnElement, and_, false, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import ForbiddenError, NotFoundError
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.auth.scope import farmer_filters
from farmerapp.catalog.crops import Crop
from farmerapp.diagnosis.corpus import add_image, get_problem, read_tenant_blob
from farmerapp.diagnosis.errors import (
    DiagnosisAlreadyReviewedError,
    DiagnosisInvalidError,
    DiagnosisNotReviewableError,
    ReviewInvalidError,
)
from farmerapp.diagnosis.llm import LlmTemporaryError
from farmerapp.diagnosis.models import (
    REVIEWABLE,
    Confidence,
    CorpusStatus,
    Diagnosis,
    DiagnosisReview,
    DiagnosisSource,
    DiagnosisStatus,
    DiagnosisSubject,
    ReviewAction,
)
from farmerapp.diagnosis.pipeline import (
    PipelineTemporaryError,
    build_result,
    notify,
    process,
    result_for_problem,
    write_llm_logs,
)
from farmerapp.diagnosis.schemas import CorpusImageCreate, DiagnosisCreate, ReviewIn
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.farmers.models import CropPlot, Farm, Farmer, Season
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.payments.publisher import PublishError
from farmerapp.tenants.models import Village
from farmerapp.worker.topics import Topic

log = get_logger("farmerapp.diagnosis")

#: Roles that see provenance (scores, reviews) in the detail view.
REVIEWER_ROLES = frozenset(
    {
        UserRole.AGRONOMIST,
        UserRole.OWNER,
        UserRole.DIRECTOR,
        UserRole.TENANT_ADMIN,
        UserRole.AUDITOR,
    }
)


def season_for(day: date) -> str:
    """Indian cropping season of a calendar day (kharif Jun-Oct, rabi Nov-Mar, zaid Apr-May)."""
    if 6 <= day.month <= 10:
        return Season.KHARIF.value
    if day.month in (4, 5):
        return Season.ZAID.value
    return Season.RABI.value


# --------------------------------------------------------------------------- scope
def diagnosis_filters(actor: User) -> list[ColumnElement[bool]]:
    visible = select(Farmer.id).where(*farmer_filters(actor))
    base: list[ColumnElement[bool]] = [
        Diagnosis.tenant_id == actor.tenant_id,
        Diagnosis.deleted_at.is_(None),
    ]
    role = UserRole(actor.role)
    if role == UserRole.ACCOUNTANT:
        return [*base, false()]
    if role == UserRole.FIELD_OFFICER:
        return [*base, or_(Diagnosis.farmer_id.in_(visible), Diagnosis.requested_by == actor.id)]
    return [*base, Diagnosis.farmer_id.in_(visible)]


async def visible_diagnosis(
    session: AsyncSession, actor: User, diagnosis_id: uuid.UUID, *, for_update: bool = False
) -> Diagnosis:
    stmt = select(Diagnosis).where(Diagnosis.id == diagnosis_id, *diagnosis_filters(actor))
    if for_update:
        stmt = stmt.with_for_update()
    row = (await session.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise NotFoundError("Diagnosis not found.")
    return row


# --------------------------------------------------------------------------- create
async def crop_id_for_code(session: AsyncSession, tenant_id: uuid.UUID, code: str) -> uuid.UUID:
    """The tenant's crop with this code (``paddy``); 422 ``diagnosis_invalid`` otherwise."""
    crop_id = await session.scalar(
        select(Crop.id).where(
            Crop.tenant_id == tenant_id,
            Crop.code == code.strip().lower(),
            Crop.deleted_at.is_(None),
        )
    )
    if crop_id is None:
        raise DiagnosisInvalidError(
            f"Unknown crop code {code!r}.", extra={"errors": [{"loc": ["crop_code"]}]}
        )
    return crop_id


async def _farmer_for(session: AsyncSession, actor: User, farmer_id: uuid.UUID | None) -> Farmer:
    role = UserRole(actor.role)
    stmt = select(Farmer).where(Farmer.deleted_at.is_(None))
    if role == UserRole.FARMER:
        stmt = stmt.where(Farmer.tenant_id == actor.tenant_id, Farmer.user_id == actor.id)
        if farmer_id is not None:
            stmt = stmt.where(Farmer.id == farmer_id)
    else:
        if farmer_id is None:
            raise DiagnosisInvalidError(
                "farmer_id is required.", extra={"errors": [{"loc": ["farmer_id"]}]}
            )
        stmt = stmt.where(Farmer.id == farmer_id, *farmer_filters(actor))
    farmer = (await session.execute(stmt.limit(1))).scalar_one_or_none()
    if farmer is None:
        raise NotFoundError("Farmer not found.")
    return farmer


async def _plot_for(
    session: AsyncSession, farmer: Farmer, plot_id: uuid.UUID | None
) -> CropPlot | None:
    if plot_id is None:
        return None
    plot = (
        await session.execute(
            select(CropPlot)
            .join(Farm, Farm.id == CropPlot.farm_id)
            .where(
                CropPlot.id == plot_id,
                CropPlot.deleted_at.is_(None),
                Farm.farmer_id == farmer.id,
            )
        )
    ).scalar_one_or_none()
    if plot is None:
        raise DiagnosisInvalidError(
            "The crop plot is not one of the farmer's.",
            extra={"errors": [{"loc": ["crop_plot_id"]}]},
        )
    return plot


async def create_diagnosis(
    session: AsyncSession,
    actor: User,
    body: DiagnosisCreate,
    *,
    services: DiagnosisServices,
    now: datetime | None = None,
    deliver: bool = True,
) -> tuple[Diagnosis, bool]:
    """``(diagnosis, created)``; a replayed id returns the existing row (``created`` False)."""
    now = now or datetime.now(UTC)
    if UserRole(actor.role) not in (UserRole.FARMER, UserRole.FIELD_OFFICER):
        raise ForbiddenError("Only farmers and field officers request diagnoses.")
    if body.id is not None:
        existing = await session.get(Diagnosis, body.id)
        if existing is not None:
            return await visible_diagnosis(session, actor, body.id), False
    farmer = await _farmer_for(session, actor, body.farmer_id)
    plot = await _plot_for(session, farmer, body.crop_plot_id)
    crop_id: uuid.UUID | None = None
    if isinstance(body.crop_id, uuid.UUID):
        crop = await session.get(Crop, body.crop_id)
        if crop is None or crop.tenant_id != actor.tenant_id:
            raise DiagnosisInvalidError("Unknown crop.", extra={"errors": [{"loc": ["crop_id"]}]})
        crop_id = crop.id
    elif body.crop_code is not None:
        crop_id = await crop_id_for_code(session, actor.tenant_id, body.crop_code)
    elif plot is not None:
        crop_id = plot.crop_id
    photos: list[dict[str, Any]] = []
    for photo in body.images:
        _data, digest = await read_tenant_blob(
            services.blobs, actor.tenant_id, photo.blob_uri, sha256=photo.sha256
        )
        photos.append(
            {
                "blob_uri": photo.blob_uri,
                "sha256": digest,
                "quality": photo.quality.model_dump(exclude_none=True) if photo.quality else None,
            }
        )
    district = await session.scalar(select(Village.district).where(Village.id == farmer.village_id))
    captured = body.captured_at or now
    diagnosis = Diagnosis(
        id=body.id or uuid.uuid4(),
        tenant_id=actor.tenant_id,
        subject=(
            DiagnosisSubject.FARMER.value
            if UserRole(actor.role) == UserRole.FARMER
            else DiagnosisSubject.OFFICER.value
        ),
        farmer_id=farmer.id,
        crop_plot_id=plot.id if plot else None,
        requested_by=actor.id,
        images=photos,
        crop_id=crop_id,
        crop_detected_on_device=body.crop_guess.model_dump() if body.crop_guess else None,
        district=district,
        season=plot.season if plot is not None else season_for(captured.date()),
        crop_stage=body.crop_stage or (plot.stage if plot is not None else None),
        language=farmer.language or "en",
        status=DiagnosisStatus.QUEUED.value,
        model_versions={
            "encoder": services.encoder.info.label,
            "on_device": (body.on_device.model_version if body.on_device else body.on_device_model),
            "llm": None,
        },
        on_device=body.on_device.model_dump(exclude_none=True) if body.on_device else None,
        flagged=body.ask_expert,
        captured_at=body.captured_at,
    )
    session.add(diagnosis)
    await session.flush()
    log.info(
        "diagnosis_requested",
        tenant_id=str(actor.tenant_id),
        diagnosis_id=str(diagnosis.id),
        subject=diagnosis.subject,
        photos=len(photos),
        crop_known=crop_id is not None,
    )
    if deliver:
        await deliver_diagnosis(session, services, diagnosis, now=now)
    await session.refresh(diagnosis)  # server-side timestamps for the response
    return diagnosis, True


async def deliver_diagnosis(
    session: AsyncSession, services: DiagnosisServices, diagnosis: Diagnosis, *, now: datetime
) -> None:
    """``diagnosis.requested`` to the worker, or the pipeline right here (inline). A failure
    leaves the row ``queued``; ``diagnosis-queue-age`` re-delivers stale queued rows."""
    if services.publisher is not None:
        try:
            await services.publisher.publish(
                Topic.DIAGNOSIS_REQUESTED,
                {"tenant_id": str(diagnosis.tenant_id), "diagnosis_id": str(diagnosis.id)},
            )
        except PublishError:
            log.warning("diagnosis_publish_failed", diagnosis_id=str(diagnosis.id))
        return
    try:
        async with session.begin_nested():
            await process(session, services, diagnosis, now=now)
    except LlmTemporaryError as exc:
        await session.refresh(diagnosis)
        await write_llm_logs(session, diagnosis.tenant_id, diagnosis.id, exc.calls, now=now)
        log.warning("diagnosis_inline_deferred", diagnosis_id=str(diagnosis.id), cause="llm")
    except PipelineTemporaryError:
        await session.refresh(diagnosis)
        log.warning("diagnosis_inline_deferred", diagnosis_id=str(diagnosis.id), cause="encoder")


# --------------------------------------------------------------------------- review
async def review(
    session: AsyncSession,
    actor: User,
    diagnosis: Diagnosis,
    body: ReviewIn,
    *,
    services: DiagnosisServices,
    now: datetime | None = None,
) -> DiagnosisReview:
    now = now or datetime.now(UTC)
    if DiagnosisStatus(diagnosis.status) == DiagnosisStatus.QUEUED:
        raise DiagnosisNotReviewableError("The diagnosis has not been processed yet.")
    before_status, before_problem = diagnosis.status, diagnosis.final_problem_id
    corpus_image_ids: list[uuid.UUID] = []
    problem = None
    if body.action == ReviewAction.NOT_DIAGNOSABLE:
        if body.add_to_corpus:
            raise ReviewInvalidError("A case that cannot be diagnosed cannot join the corpus.")
        diagnosis.status = DiagnosisStatus.OUT_OF_SCOPE.value
        diagnosis.final_problem_id = None
        diagnosis.source = DiagnosisSource.AGRONOMIST.value
        diagnosis.confidence = None
        diagnosis.out_of_scope_reason = diagnosis.out_of_scope_reason or "expert_not_diagnosable"
        diagnosis.result = build_result(
            status=DiagnosisStatus.OUT_OF_SCOPE,
            confidence=None,
            problem=None,
            treatments=None,
            out_of_scope_reason=diagnosis.out_of_scope_reason,
        )
    else:
        if body.action == ReviewAction.CORRECT:
            if body.problem_id is None:
                raise ReviewInvalidError(
                    "problem_id is required to correct.",
                    extra={"errors": [{"loc": ["problem_id"]}]},
                )
            problem_id = body.problem_id
        else:
            if body.problem_id is not None and body.problem_id != diagnosis.final_problem_id:
                raise ReviewInvalidError("To change the label, use action `correct`.")
            if diagnosis.final_problem_id is None:
                raise ReviewInvalidError(
                    "There is no label to confirm; use `correct` or `not_diagnosable`."
                )
            problem_id = diagnosis.final_problem_id
        problem = await get_problem(session, actor.tenant_id, problem_id)
        if problem.status == CorpusStatus.RETIRED.value:
            raise ReviewInvalidError("The corpus problem is retired.")
        if diagnosis.crop_id is not None and problem.crop_id != diagnosis.crop_id:
            raise ReviewInvalidError("The problem belongs to another crop.")
        corrected = body.action == ReviewAction.CORRECT and problem.id != before_problem
        status = DiagnosisStatus.CORRECTED if corrected else DiagnosisStatus.CONFIRMED
        diagnosis.crop_id = problem.crop_id
        diagnosis.result = await result_for_problem(
            session,
            diagnosis,
            problem,
            status=status,
            confidence=Confidence.HIGH,
            today=now.date(),
        )
        diagnosis.status = status.value
        diagnosis.final_problem_id = problem.id
        diagnosis.source = DiagnosisSource.AGRONOMIST.value
        diagnosis.confidence = Confidence.HIGH.value
        diagnosis.out_of_scope_reason = None
        if body.add_to_corpus:
            for photo in diagnosis.images or []:
                image = await add_image(
                    session,
                    actor,
                    problem,
                    CorpusImageCreate(
                        blob_uri=photo["blob_uri"],
                        stage=diagnosis.crop_stage,
                        region=diagnosis.district,
                        season=diagnosis.season,
                    ),
                    encoder=services.encoder,
                    blobs=services.blobs,
                    status=CorpusStatus.REVIEWED,
                    from_diagnosis_id=diagnosis.id,
                )
                corpus_image_ids.append(image.id)
    diagnosis.reviewed_by = actor.id
    diagnosis.reviewed_at = now
    diagnosis.flagged = False
    row = DiagnosisReview(
        tenant_id=actor.tenant_id,
        diagnosis_id=diagnosis.id,
        actor_id=actor.id,
        action=body.action.value,
        from_status=before_status,
        to_status=diagnosis.status,
        from_problem_id=before_problem,
        to_problem_id=diagnosis.final_problem_id,
        note=body.note,
        add_to_corpus=body.add_to_corpus,
        corpus_image_ids=corpus_image_ids,
    )
    session.add(row)
    await notify(session, diagnosis, NotificationKind.DIAGNOSIS_REVIEWED, now=now)
    await session.flush()
    await session.refresh(diagnosis)
    await session.refresh(row)
    log.info(
        "diagnosis_reviewed",
        tenant_id=str(actor.tenant_id),
        diagnosis_id=str(diagnosis.id),
        action=body.action.value,
        from_status=before_status,
        to_status=diagnosis.status,
        corrected=diagnosis.status == DiagnosisStatus.CORRECTED.value,
        added_images=len(corpus_image_ids),
        age_hours=round((now - diagnosis.created_at).total_seconds() / 3600, 2),
    )
    return row


# --------------------------------------------------------------------------- ask expert
async def _expert_recipients(session: AsyncSession, tenant_id: uuid.UUID) -> list[uuid.UUID]:
    """Active agronomists of the tenant (owners when there is none, as OPS-009 does)."""
    for role in (UserRole.AGRONOMIST, UserRole.OWNER):
        rows = await session.execute(
            select(User.id)
            .where(
                User.tenant_id == tenant_id,
                User.role == role.value,
                User.status == UserStatus.ACTIVE.value,
                User.deleted_at.is_(None),
            )
            .order_by(User.id)
        )
        found = list(rows.scalars())
        if found:
            return found
    return []


async def ask_expert(
    session: AsyncSession,
    actor: User,
    diagnosis: Diagnosis,
    *,
    note: str | None,
    now: datetime | None = None,
) -> bool:
    """FM-006 "Ask an expert" on a case the caller owns: the farmer it is about, or the
    field officer who asked for it. The same photos go to the agronomist queue as a
    ``flagged`` case (no second diagnosis). Idempotent: an already flagged case is left
    alone (``False``); a case the agronomist already reviewed is 409."""
    now = now or datetime.now(UTC)
    role = UserRole(actor.role)
    if role == UserRole.FIELD_OFFICER and diagnosis.requested_by != actor.id:
        raise ForbiddenError("Only the field officer who asked for this diagnosis can escalate it.")
    if role not in (UserRole.FARMER, UserRole.FIELD_OFFICER):
        raise ForbiddenError("Only farmers and field officers ask an expert.")
    if diagnosis.reviewed_at is not None:
        raise DiagnosisAlreadyReviewedError("An agronomist has already answered this case.")
    if diagnosis.flagged:
        return False
    diagnosis.flagged = True
    diagnosis.expert_requested_at = now
    diagnosis.expert_requested_by = actor.id
    diagnosis.expert_note = note
    kind = NotificationKind.DIAGNOSIS_EXPERT_REQUESTED
    for user_id in await _expert_recipients(session, diagnosis.tenant_id):
        session.add(
            Notification(
                tenant_id=diagnosis.tenant_id,
                user_id=user_id,
                kind=kind.value,
                title_key=f"notification.{kind.value}.title",
                body_key=f"notification.{kind.value}.body",
                data={
                    "diagnosis_id": str(diagnosis.id),
                    "status": diagnosis.status,
                    "farmer_id": str(diagnosis.farmer_id),
                },
            )
        )
    await session.flush()
    await session.refresh(diagnosis)
    log.info(
        "diagnosis_expert_requested",
        tenant_id=str(actor.tenant_id),
        diagnosis_id=str(diagnosis.id),
        status=diagnosis.status,
        source=diagnosis.source,
        by_role=role.value,
        has_note=note is not None,
    )
    return True


def queue_filters(actor: User) -> list[ColumnElement[bool]]:
    """WC-006 queue: unreviewed provisional / out-of-scope diagnoses, or flagged ones."""
    return [
        *diagnosis_filters(actor),
        Diagnosis.reviewed_at.is_(None),
        or_(
            Diagnosis.status.in_([s.value for s in REVIEWABLE]),
            and_(Diagnosis.flagged.is_(True), Diagnosis.status != DiagnosisStatus.QUEUED.value),
        ),
    ]


async def reviews_of(session: AsyncSession, diagnosis_id: uuid.UUID) -> list[DiagnosisReview]:
    rows = await session.execute(
        select(DiagnosisReview)
        .where(DiagnosisReview.diagnosis_id == diagnosis_id)
        .order_by(DiagnosisReview.created_at, DiagnosisReview.id)
    )
    return list(rows.scalars())


__all__ = [
    "REVIEWER_ROLES",
    "ask_expert",
    "create_diagnosis",
    "crop_id_for_code",
    "deliver_diagnosis",
    "diagnosis_filters",
    "queue_filters",
    "review",
    "reviews_of",
    "season_for",
    "visible_diagnosis",
]
