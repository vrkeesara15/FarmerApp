"""DX-012 re-embedding when the encoder changes, and the atomic flip of the active encoder.

Procedure (ml/embed/README.md "Switching models"):

1. Deploy the new embed service version next to the old one.
2. ``python -m farmerapp.jobs reembed-corpus --tenant … --encoder-name N --encoder-version V``
   embeds every live corpus image (draft, reviewed, approved; not retired) with the new
   encoder into ``corpus_embedding`` (staging; resumable: images already staged are
   skipped). Nothing changes for diagnoses yet.
3. Retune the DX-003 thresholds on the held-out set with the new encoder (``ml/eval``).
4. Move the API / worker pin (``DIAGNOSIS_ENCODER_NAME`` / ``_VERSION``). While the corpus
   is still on the old encoder, the kNN answers from the staged vectors
   (``nearest_staged``), so diagnoses keep working through the rollout.
5. ``python -m farmerapp.jobs activate-encoder --tenant … --encoder-name N --encoder-version V``
   flips the tenant in **one transaction**: it refuses unless every live image is staged,
   keeps each image's current vector in ``corpus_embedding`` (rollback = activate the old
   version again), copies the staged vectors into ``corpus_image`` and appends an
   ``encoder_activation`` row (plus an audit row).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field

from sqlalchemy import ColumnElement, and_, func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import ConflictError
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.diagnosis.decision import Neighbour
from farmerapp.diagnosis.encoder import EncoderInfo, ImageEncoder
from farmerapp.diagnosis.models import CorpusImage, CorpusStatus
from farmerapp.logging import get_logger
from farmerapp.mlops.models import CorpusEmbedding, EncoderActivation
from farmerapp.uploads.blobstore import BlobNotFoundError, BlobStore

log = get_logger("farmerapp.mlops.reembed")

DEFAULT_BATCH = 32


class EncoderNotStagedError(ConflictError):
    code = "encoder_not_staged"


#: Live images of the tenant that are not on the target encoder yet (bound parameters only).
#: The two statements below concatenate this literal; nothing user-supplied reaches the SQL
#: (tenant, encoder name and version are bound parameters), hence the B608 markers.
_LIVE = (
    "ci.tenant_id = :t AND ci.deleted_at IS NULL AND ci.status <> 'retired' "
    "AND NOT (ci.encoder_name = :n AND ci.encoder_version = :v)"
)
_KEEP_PREVIOUS = (
    "INSERT INTO corpus_embedding "  # nosec B608
    "(tenant_id, corpus_image_id, encoder_name, encoder_version, embedding) "
    "SELECT ci.tenant_id, ci.id, ci.encoder_name, ci.encoder_version, ci.embedding "
    "FROM corpus_image ci WHERE " + _LIVE + " "
    "ON CONFLICT (corpus_image_id, encoder_name, encoder_version) DO NOTHING"
)
_FLIP = (
    "UPDATE corpus_image ci SET embedding = ce.embedding, encoder_name = :n, "  # nosec B608
    "encoder_version = :v, updated_at = now(), version = ci.version + 1 "
    "FROM corpus_embedding ce WHERE ce.corpus_image_id = ci.id "
    "AND ce.encoder_name = :n AND ce.encoder_version = :v AND " + _LIVE
)


def _live_images(tenant_id: uuid.UUID) -> list[ColumnElement[bool]]:
    return [
        CorpusImage.tenant_id == tenant_id,
        CorpusImage.deleted_at.is_(None),
        CorpusImage.status != CorpusStatus.RETIRED.value,
    ]


def _on(encoder: EncoderInfo) -> ColumnElement[bool]:
    return and_(
        CorpusImage.encoder_name == encoder.name, CorpusImage.encoder_version == encoder.version
    )


@dataclass
class ReembedReport:
    tenant_id: uuid.UUID
    encoder: str
    embedded: int = 0
    already: int = 0
    missing_blobs: list[uuid.UUID] = field(default_factory=list)
    remaining: int = 0


async def _unstaged(
    session: AsyncSession, tenant_id: uuid.UUID, encoder: EncoderInfo, limit: int | None = None
) -> list[CorpusImage]:
    staged = select(CorpusEmbedding.corpus_image_id).where(
        CorpusEmbedding.tenant_id == tenant_id,
        CorpusEmbedding.encoder_name == encoder.name,
        CorpusEmbedding.encoder_version == encoder.version,
    )
    stmt = (
        select(CorpusImage)
        .where(*_live_images(tenant_id), ~_on(encoder), CorpusImage.id.not_in(staged))
        .order_by(CorpusImage.id)
    )
    if limit is not None:
        stmt = stmt.limit(limit)
    return list((await session.execute(stmt)).scalars())


async def reembed_corpus(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    encoder: ImageEncoder,
    blobs: BlobStore,
    batch_size: int = DEFAULT_BATCH,
    max_images: int | None = None,
) -> ReembedReport:
    info = encoder.info
    report = ReembedReport(tenant_id=tenant_id, encoder=info.label)
    skipped: set[uuid.UUID] = set()
    while max_images is None or report.embedded < max_images:
        batch = [
            img
            for img in await _unstaged(session, tenant_id, info, batch_size + len(skipped))
            if img.id not in skipped
        ][:batch_size]
        if not batch:
            break
        images: list[CorpusImage] = []
        data: list[bytes] = []
        for img in batch:
            try:
                data.append(await blobs.get(img.blob_uri))
                images.append(img)
            except (BlobNotFoundError, ValueError):
                skipped.add(img.id)
                report.missing_blobs.append(img.id)
        if not images:
            continue
        vectors = await encoder.encode(data)
        for img, vector in zip(images, vectors, strict=True):
            session.add(
                CorpusEmbedding(
                    tenant_id=tenant_id,
                    corpus_image_id=img.id,
                    encoder_name=info.name,
                    encoder_version=info.version,
                    embedding=list(vector),
                )
            )
        await session.flush()
        report.embedded += len(images)
    report.remaining = len(await _unstaged(session, tenant_id, info)) - len(skipped)
    report.already = int(
        await session.scalar(
            select(func.count()).select_from(CorpusImage).where(*_live_images(tenant_id), _on(info))
        )
        or 0
    )
    log.info(
        "corpus_reembedded",
        tenant_id=str(tenant_id),
        encoder=info.label,
        embedded=report.embedded,
        remaining=report.remaining,
        missing_blobs=len(report.missing_blobs),
    )
    return report


@dataclass
class ActivationReport:
    tenant_id: uuid.UUID
    encoder: str
    images: int
    previous: str | None
    activation_id: uuid.UUID | None


async def activate_encoder(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    encoder: EncoderInfo,
    actor_id: uuid.UUID | None = None,
    note: str | None = None,
) -> ActivationReport:
    """Flip every live corpus image of the tenant to ``encoder`` in this transaction."""
    missing = await _unstaged(session, tenant_id, encoder)
    if missing:
        raise EncoderNotStagedError(
            f"{len(missing)} corpus images are not embedded with {encoder.label} yet; run "
            "reembed-corpus first.",
            extra={"missing": len(missing)},
        )
    previous = (
        await session.execute(
            select(CorpusImage.encoder_name, CorpusImage.encoder_version, func.count())
            .where(*_live_images(tenant_id), ~_on(encoder))
            .group_by(CorpusImage.encoder_name, CorpusImage.encoder_version)
            .order_by(func.count().desc())
        )
    ).first()
    params = {"t": tenant_id, "n": encoder.name, "v": encoder.version}
    # Keep the current vectors (rollback = activate the previous version again).
    await session.execute(text(_KEEP_PREVIOUS), params)
    result = await session.execute(text(_FLIP), params)
    flipped = int(getattr(result, "rowcount", 0) or 0)
    activation = EncoderActivation(
        tenant_id=tenant_id,
        encoder_name=encoder.name,
        encoder_version=encoder.version,
        previous_name=previous[0] if previous else None,
        previous_version=previous[1] if previous else None,
        images=flipped,
        activated_by=actor_id,
        note=note,
    )
    session.add(activation)
    await session.flush()
    audit.record(
        session,
        action="corpus.encoder_activate",
        entity="encoder_activation",
        entity_id=activation.id,
        tenant_id=tenant_id,
        before={"encoder": f"{previous[0]}@{previous[1]}" if previous else None},
        after={"encoder": encoder.label, "images": flipped},
    )
    for obj in list(session.identity_map.values()):  # corpus_image rows changed behind the ORM
        if isinstance(obj, CorpusImage):
            session.expire(obj)
    log.warning(
        "corpus_encoder_activated",
        tenant_id=str(tenant_id),
        encoder=encoder.label,
        images=flipped,
        previous=f"{previous[0]}@{previous[1]}" if previous else None,
    )
    return ActivationReport(
        tenant_id=tenant_id,
        encoder=encoder.label,
        images=flipped,
        previous=f"{previous[0]}@{previous[1]}" if previous else None,
        activation_id=activation.id,
    )


async def nearest_staged(
    session: AsyncSession,
    vector: Sequence[float],
    *,
    tenant_id: uuid.UUID,
    crop_id: uuid.UUID | None,
    encoder: EncoderInfo,
    problem_ids: Sequence[uuid.UUID],
    k: int,
) -> list[Neighbour]:
    """DX-012 rollout: the kNN over staged vectors of ``encoder`` (approved images and
    problems only), used while the API pin is ahead of the corpus activation."""
    distance = CorpusEmbedding.embedding.cosine_distance(list(vector))
    stmt = (
        select(CorpusImage.id, CorpusImage.problem_id, distance.label("distance"))
        .join(CorpusImage, CorpusImage.id == CorpusEmbedding.corpus_image_id)
        .where(
            CorpusEmbedding.tenant_id == tenant_id,
            CorpusEmbedding.encoder_name == encoder.name,
            CorpusEmbedding.encoder_version == encoder.version,
            CorpusImage.status == CorpusStatus.APPROVED.value,
            CorpusImage.deleted_at.is_(None),
            CorpusImage.problem_id.in_(list(problem_ids)),
        )
        .order_by(distance)
        .limit(k)
    )
    if crop_id is not None:
        stmt = stmt.where(CorpusImage.crop_id == crop_id)
    rows = (await session.execute(stmt)).all()
    return [
        Neighbour(image_id=row.id, problem_id=row.problem_id, similarity=1.0 - float(row.distance))
        for row in rows
    ]


async def has_staged(session: AsyncSession, tenant_id: uuid.UUID, encoder: EncoderInfo) -> bool:
    found = await session.scalar(
        select(CorpusEmbedding.id)
        .where(
            CorpusEmbedding.tenant_id == tenant_id,
            CorpusEmbedding.encoder_name == encoder.name,
            CorpusEmbedding.encoder_version == encoder.version,
        )
        .limit(1)
    )
    return found is not None


async def run_reembed(
    tenant_ids: Iterable[uuid.UUID],
    *,
    encoder: ImageEncoder,
    blobs: BlobStore,
    batch_size: int = DEFAULT_BATCH,
    max_images: int | None = None,
) -> list[ReembedReport]:
    reports: list[ReembedReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(
                    await reembed_corpus(
                        session,
                        tenant_id=tenant_id,
                        encoder=encoder,
                        blobs=blobs,
                        batch_size=batch_size,
                        max_images=max_images,
                    )
                )
    return reports


async def run_activate(
    tenant_ids: Iterable[uuid.UUID], *, encoder: EncoderInfo, note: str | None = None
) -> list[ActivationReport]:
    reports: list[ActivationReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(
                    await activate_encoder(session, tenant_id=tenant_id, encoder=encoder, note=note)
                )
    return reports


__all__ = [
    "ActivationReport",
    "EncoderNotStagedError",
    "ReembedReport",
    "activate_encoder",
    "has_staged",
    "nearest_staged",
    "reembed_corpus",
    "run_activate",
    "run_reembed",
]
