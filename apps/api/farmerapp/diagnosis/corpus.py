"""WC-007 corpus manager: problems, images, status workflow, approvals, versions.

Workflow (``models.CORPUS_TRANSITIONS``): ``draft -> reviewed -> approved -> retired``
(reviewed may go back to draft; anything not yet approved may be retired). Approving records
``approved_by`` / ``approved_at`` and bumps ``corpus_version`` once per approval set (one
item through ``/transition``, many through ``/approvals``); the version is stored on the
approved rows and on every diagnosis (DX-005). Approved and retired entries are immutable
(409 ``corpus_entry_locked``): retire and create a new one.

Images reuse the chunked upload flow (NF-003): the client uploads with purpose ``corpus``
(or the review queue reuses a diagnosis photo), then ``add_image`` reads the blob, checks the
sha256 and computes the embedding with the pinned encoder (DX-002 / DX-005).
"""

from __future__ import annotations

import hashlib
import uuid
from collections.abc import Sequence
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError
from farmerapp.auth.models import User
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import PestOrDisease
from farmerapp.diagnosis.encoder import EncoderError, ImageEncoder
from farmerapp.diagnosis.errors import (
    CorpusEntryLockedError,
    CorpusImageExistsError,
    CorpusProblemExistsError,
    CorpusProblemInvalidError,
    DiagnosisImageMissingError,
    EncoderUnavailableError,
    ImageShaMismatchError,
    InvalidCorpusTransitionError,
)
from farmerapp.diagnosis.images import UnreadableImageError
from farmerapp.diagnosis.models import (
    CORPUS_TRANSITIONS,
    CorpusImage,
    CorpusProblem,
    CorpusStatus,
    CorpusVersion,
)
from farmerapp.diagnosis.schemas import (
    CorpusImageCreate,
    CorpusProblemCreate,
    CorpusProblemUpdate,
)
from farmerapp.uploads.blobstore import BlobNotFoundError, BlobStore, parse_uri

EDITABLE = frozenset({CorpusStatus.DRAFT, CorpusStatus.REVIEWED})


# --------------------------------------------------------------------------- blobs
async def read_tenant_blob(
    blobs: BlobStore, tenant_id: uuid.UUID, uri: str, *, sha256: str | None = None
) -> tuple[bytes, str]:
    """The bytes of a completed upload of ``tenant_id`` and their sha256 (422 otherwise)."""
    try:
        _bucket, key = parse_uri(uri)
    except ValueError as exc:
        raise DiagnosisImageMissingError(f"Unknown blob {uri}.") from exc
    if not key.startswith(f"{tenant_id}/"):
        raise DiagnosisImageMissingError(f"Unknown blob {uri}.")
    try:
        data = await blobs.get(uri)
    except BlobNotFoundError as exc:
        raise DiagnosisImageMissingError("Blob not found; complete the upload first.") from exc
    digest = hashlib.sha256(data).hexdigest()
    if sha256 is not None and sha256 != digest:
        raise ImageShaMismatchError("sha256 does not match the uploaded blob.")
    return data, digest


# --------------------------------------------------------------------------- versions
async def current_version(session: AsyncSession, tenant_id: uuid.UUID) -> int:
    value = await session.scalar(
        select(func.max(CorpusVersion.version)).where(CorpusVersion.tenant_id == tenant_id)
    )
    return int(value or 0)


async def bump_version(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    approved_by: uuid.UUID | None,
    problems: Sequence[uuid.UUID] = (),
    images: Sequence[uuid.UUID] = (),
    retired: Sequence[uuid.UUID] = (),
    note: str | None = None,
) -> CorpusVersion:
    """Append the next version (monotonic; the unique key refuses a concurrent duplicate)."""
    version = CorpusVersion(
        tenant_id=tenant_id,
        version=await current_version(session, tenant_id) + 1,
        approved_by=approved_by,
        note=note,
        changes={
            "problems": [str(p) for p in problems],
            "images": [str(i) for i in images],
            "retired": [str(r) for r in retired],
        },
    )
    session.add(version)
    await session.flush()
    await session.refresh(version)
    return version


async def versions(session: AsyncSession, tenant_id: uuid.UUID) -> list[CorpusVersion]:
    rows = await session.execute(
        select(CorpusVersion)
        .where(CorpusVersion.tenant_id == tenant_id)
        .order_by(CorpusVersion.version.desc())
        .limit(200)
    )
    return list(rows.scalars())


# --------------------------------------------------------------------------- problems
async def get_problem(
    session: AsyncSession, tenant_id: uuid.UUID, problem_id: uuid.UUID, *, for_update: bool = False
) -> CorpusProblem:
    stmt = select(CorpusProblem).where(
        CorpusProblem.id == problem_id,
        CorpusProblem.tenant_id == tenant_id,
        CorpusProblem.deleted_at.is_(None),
    )
    if for_update:
        stmt = stmt.with_for_update()
    problem = (await session.execute(stmt)).scalar_one_or_none()
    if problem is None:
        raise NotFoundError("Corpus problem not found.")
    return problem


async def image_counts(
    session: AsyncSession, problem_ids: Sequence[uuid.UUID]
) -> dict[uuid.UUID, dict[str, int]]:
    if not problem_ids:
        return {}
    rows = await session.execute(
        select(CorpusImage.problem_id, CorpusImage.status, func.count())
        .where(CorpusImage.problem_id.in_(list(problem_ids)), CorpusImage.deleted_at.is_(None))
        .group_by(CorpusImage.problem_id, CorpusImage.status)
    )
    out: dict[uuid.UUID, dict[str, int]] = {}
    for problem_id, status, count in rows.tuples():
        out.setdefault(problem_id, {})[str(status)] = int(count)
    return out


async def pest_codes(session: AsyncSession, pest_ids: Sequence[uuid.UUID]) -> dict[uuid.UUID, str]:
    if not pest_ids:
        return {}
    rows = await session.execute(
        select(PestOrDisease.id, PestOrDisease.code).where(PestOrDisease.id.in_(list(pest_ids)))
    )
    return {pid: str(code) for pid, code in rows.tuples()}


async def create_problem(
    session: AsyncSession, actor: User, body: CorpusProblemCreate
) -> CorpusProblem:
    pest = await session.get(PestOrDisease, body.pest_or_disease_id)
    if pest is None or pest.tenant_id != actor.tenant_id or pest.deleted_at is not None:
        raise CorpusProblemInvalidError("Unknown pest or disease.")
    crop = await session.get(Crop, body.crop_id)
    if crop is None or crop.tenant_id != actor.tenant_id or crop.deleted_at is not None:
        raise CorpusProblemInvalidError("Unknown crop.")
    if pest.crop_id is not None and pest.crop_id != crop.id:
        raise CorpusProblemInvalidError("The pest or disease is specific to another crop.")
    live = await session.scalar(
        select(CorpusProblem.id).where(
            CorpusProblem.tenant_id == actor.tenant_id,
            CorpusProblem.crop_id == crop.id,
            CorpusProblem.pest_or_disease_id == pest.id,
            CorpusProblem.deleted_at.is_(None),
            CorpusProblem.status != CorpusStatus.RETIRED.value,
        )
    )
    if live is not None:
        raise CorpusProblemExistsError(
            "This crop already has a live corpus entry for the problem.",
            extra={"corpus_problem_id": str(live)},
        )
    problem = CorpusProblem(
        tenant_id=actor.tenant_id,
        pest_or_disease_id=pest.id,
        crop_id=crop.id,
        problem_type=pest.type,
        names=dict(body.names),
        symptoms={k: list(v) for k, v in body.symptoms.items()},
        cultural_practices={k: list(v) for k, v in body.cultural_practices.items()},
        status=CorpusStatus.DRAFT.value,
        source=body.source.value,
        labelled_by=actor.id,
        notes=body.notes,
    )
    session.add(problem)
    await session.flush()
    await session.refresh(problem)
    return problem


def _require_editable(status: str) -> None:
    if CorpusStatus(status) not in EDITABLE:
        raise CorpusEntryLockedError(
            "Approved and retired corpus entries are immutable; retire and create a new one."
        )


async def update_problem(
    session: AsyncSession, problem: CorpusProblem, body: CorpusProblemUpdate
) -> CorpusProblem:
    _require_editable(problem.status)
    if body.names is not None:
        if not body.names.get("en"):
            raise CorpusProblemInvalidError("names.en is required.")
        problem.names = dict(body.names)
    if body.symptoms is not None:
        problem.symptoms = {k: list(v) for k, v in body.symptoms.items()}
    if body.cultural_practices is not None:
        problem.cultural_practices = {k: list(v) for k, v in body.cultural_practices.items()}
    if "notes" in body.model_fields_set:
        problem.notes = body.notes
    await session.flush()
    await session.refresh(problem)
    return problem


def _check_transition(current: str, to: CorpusStatus) -> None:
    if to not in CORPUS_TRANSITIONS[CorpusStatus(current)]:
        raise InvalidCorpusTransitionError(
            f"Cannot move a {current} corpus entry to {to.value}.",
            extra={"from": current, "to": to.value},
        )


def _apply_problem(
    problem: CorpusProblem, actor: User, to: CorpusStatus, now: datetime, version: int | None
) -> None:
    problem.status = to.value
    if to == CorpusStatus.REVIEWED:
        problem.reviewed_by, problem.reviewed_at = actor.id, now
    elif to == CorpusStatus.APPROVED:
        problem.approved_by, problem.approved_at = actor.id, now
        problem.approved_in_version = version
    elif to == CorpusStatus.RETIRED:
        problem.retired_at = now


def _apply_image(
    image: CorpusImage, actor: User, to: CorpusStatus, now: datetime, version: int | None
) -> None:
    image.status = to.value
    if to == CorpusStatus.APPROVED:
        image.approved_by, image.approved_at = actor.id, now
        image.approved_in_version = version


async def transition_problem(
    session: AsyncSession,
    actor: User,
    problem: CorpusProblem,
    to: CorpusStatus,
    *,
    now: datetime,
    note: str | None = None,
) -> CorpusProblem:
    _check_transition(problem.status, to)
    version: int | None = None
    was_served = problem.status == CorpusStatus.APPROVED.value
    if to == CorpusStatus.APPROVED or was_served:  # what production serves changes
        bumped = await bump_version(
            session,
            actor.tenant_id,
            approved_by=actor.id,
            problems=[problem.id] if to == CorpusStatus.APPROVED else [],
            retired=[problem.id] if was_served else [],
            note=note,
        )
        version = bumped.version
    _apply_problem(problem, actor, to, now, version)
    await session.flush()
    await session.refresh(problem)
    return problem


async def transition_image(
    session: AsyncSession,
    actor: User,
    image: CorpusImage,
    to: CorpusStatus,
    *,
    now: datetime,
    note: str | None = None,
) -> CorpusImage:
    _check_transition(image.status, to)
    version: int | None = None
    was_served = image.status == CorpusStatus.APPROVED.value
    if to == CorpusStatus.APPROVED or was_served:
        bumped = await bump_version(
            session,
            actor.tenant_id,
            approved_by=actor.id,
            images=[image.id] if to == CorpusStatus.APPROVED else [],
            retired=[image.id] if was_served else [],
            note=note,
        )
        version = bumped.version
    _apply_image(image, actor, to, now, version)
    await session.flush()
    await session.refresh(image)
    return image


async def approve_set(
    session: AsyncSession,
    actor: User,
    *,
    problem_ids: Sequence[uuid.UUID],
    image_ids: Sequence[uuid.UUID],
    note: str | None,
    now: datetime,
) -> CorpusVersion:
    """Approve reviewed problems and images together: one ``corpus_version`` bump."""
    if not problem_ids and not image_ids:
        raise CorpusProblemInvalidError("Nothing to approve.")
    problems = [
        await get_problem(session, actor.tenant_id, pid, for_update=True)
        for pid in dict.fromkeys(problem_ids)
    ]
    images = [
        await get_image(session, actor.tenant_id, iid, for_update=True)
        for iid in dict.fromkeys(image_ids)
    ]
    for status in [p.status for p in problems] + [i.status for i in images]:
        _check_transition(status, CorpusStatus.APPROVED)
    bumped = await bump_version(
        session,
        actor.tenant_id,
        approved_by=actor.id,
        problems=[p.id for p in problems],
        images=[i.id for i in images],
        note=note,
    )
    for problem in problems:
        _apply_problem(problem, actor, CorpusStatus.APPROVED, now, bumped.version)
    for image in images:
        _apply_image(image, actor, CorpusStatus.APPROVED, now, bumped.version)
    await session.flush()
    return bumped


# --------------------------------------------------------------------------- images
async def get_image(
    session: AsyncSession, tenant_id: uuid.UUID, image_id: uuid.UUID, *, for_update: bool = False
) -> CorpusImage:
    stmt = select(CorpusImage).where(
        CorpusImage.id == image_id,
        CorpusImage.tenant_id == tenant_id,
        CorpusImage.deleted_at.is_(None),
    )
    if for_update:
        stmt = stmt.with_for_update()
    image = (await session.execute(stmt)).scalar_one_or_none()
    if image is None:
        raise NotFoundError("Corpus image not found.")
    return image


async def embed_one(encoder: ImageEncoder, data: bytes) -> list[float]:
    try:
        return (await encoder.encode([data]))[0]
    except UnreadableImageError as exc:
        raise CorpusProblemInvalidError("The blob is not a decodable image.") from exc
    except EncoderError as exc:
        raise EncoderUnavailableError("The image encoder is unavailable; retry later.") from exc


async def add_image(
    session: AsyncSession,
    actor: User,
    problem: CorpusProblem,
    body: CorpusImageCreate,
    *,
    encoder: ImageEncoder,
    blobs: BlobStore,
    status: CorpusStatus = CorpusStatus.DRAFT,
    from_diagnosis_id: uuid.UUID | None = None,
) -> CorpusImage:
    if problem.status == CorpusStatus.RETIRED.value:
        raise CorpusEntryLockedError("The corpus problem is retired.")
    data, digest = await read_tenant_blob(blobs, actor.tenant_id, body.blob_uri, sha256=body.sha256)
    existing = await session.scalar(
        select(CorpusImage.id).where(
            CorpusImage.tenant_id == actor.tenant_id,
            CorpusImage.problem_id == problem.id,
            CorpusImage.sha256 == digest,
        )
    )
    if existing is not None:
        raise CorpusImageExistsError(
            "This image is already in the corpus for the problem.",
            extra={"corpus_image_id": str(existing)},
        )
    vector = await embed_one(encoder, data)
    image = CorpusImage(
        tenant_id=actor.tenant_id,
        problem_id=problem.id,
        crop_id=problem.crop_id,
        blob_uri=body.blob_uri,
        sha256=digest,
        embedding=vector,
        encoder_name=encoder.info.name,
        encoder_version=encoder.info.version,
        stage=body.stage,
        part=body.part.value if body.part else None,
        severity=body.severity.value if body.severity else None,
        region=body.region,
        season=body.season,
        source=body.source.value,
        status=status.value,
        labelled_by=actor.id,
        from_diagnosis_id=from_diagnosis_id,
    )
    session.add(image)
    try:
        async with session.begin_nested():
            await session.flush()
    except IntegrityError as exc:  # a concurrent add of the same bytes
        raise CorpusImageExistsError("This image is already in the corpus.") from exc
    await session.refresh(image)
    return image


__all__ = [
    "EDITABLE",
    "add_image",
    "approve_set",
    "bump_version",
    "create_problem",
    "current_version",
    "embed_one",
    "get_image",
    "get_problem",
    "image_counts",
    "pest_codes",
    "read_tenant_blob",
    "transition_image",
    "transition_problem",
    "update_problem",
    "versions",
]
