"""DX-002 kNN over the approved corpus (pgvector HNSW, cosine distance).

``nearest(session, vector, crop_id=, encoder=, k=20)`` returns the ``k`` approved corpus
images closest to ``vector`` — only images whose own status **and** whose problem's status
are ``approved`` (WC-007: only approved entries are used in production), of the given crop
(all crops when the crop is unknown), embedded by the same encoder name + version (DX-005).

The query orders by ``embedding <=> :q`` so the ``ix_corpus_image_embedding_hnsw`` index
(``vector_cosine_ops``) drives it. ``hnsw.ef_search`` is set for the transaction
(``SET LOCAL``, default 40 = pgvector's default) and ``hnsw.iterative_scan = strict_order``
(pgvector 0.8) keeps the index scanning until ``k`` rows pass the crop / status / tenant
filters instead of returning fewer. Similarity = ``1 - cosine distance``.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence

from sqlalchemy import and_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.diagnosis.decision import Neighbour
from farmerapp.diagnosis.encoder import EncoderInfo
from farmerapp.diagnosis.models import CorpusImage, CorpusProblem, CorpusStatus

DEFAULT_K = 20
DEFAULT_EF_SEARCH = 40


async def tune_session(session: AsyncSession, *, ef_search: int = DEFAULT_EF_SEARCH) -> None:
    """``SET LOCAL`` the HNSW search parameters for the current transaction."""
    await session.execute(
        text("SELECT set_config('hnsw.ef_search', :ef, true)"), {"ef": str(int(ef_search))}
    )
    await session.execute(text("SELECT set_config('hnsw.iterative_scan', 'strict_order', true)"))
    # asyncpg prepares statements: after five runs Postgres may switch to a generic plan that
    # cannot see the crop / vector values and stops walking the HNSW index. Plan every run.
    await session.execute(text("SELECT set_config('plan_cache_mode', 'force_custom_plan', true)"))


async def nearest(
    session: AsyncSession,
    vector: Sequence[float],
    *,
    tenant_id: uuid.UUID,
    crop_id: uuid.UUID | None,
    encoder: EncoderInfo,
    k: int = DEFAULT_K,
) -> list[Neighbour]:
    distance = CorpusImage.embedding.cosine_distance(list(vector))
    filters = [
        CorpusImage.tenant_id == tenant_id,
        CorpusImage.status == CorpusStatus.APPROVED.value,
        CorpusImage.deleted_at.is_(None),
        CorpusImage.encoder_name == encoder.name,
        CorpusImage.encoder_version == encoder.version,
    ]
    if crop_id is not None:
        filters.append(CorpusImage.crop_id == crop_id)
    # The approved problems (a handful per crop) as constants: the planner keeps the HNSW
    # index scan and filters on them, instead of joining / hashing a subquery per call.
    approved = select(CorpusProblem.id).where(
        and_(
            CorpusProblem.tenant_id == tenant_id,
            CorpusProblem.status == CorpusStatus.APPROVED.value,
            CorpusProblem.deleted_at.is_(None),
        )
    )
    if crop_id is not None:
        approved = approved.where(CorpusProblem.crop_id == crop_id)
    problem_ids = list((await session.execute(approved)).scalars())
    if not problem_ids:
        return []
    stmt = (
        select(CorpusImage.id, CorpusImage.problem_id, distance.label("distance"))
        .where(*filters, CorpusImage.problem_id.in_(problem_ids))
        .order_by(distance)
        .limit(k)
    )
    rows = (await session.execute(stmt)).all()
    if not rows:
        # DX-012 rollout: the API pin moved to a new encoder whose vectors are staged in
        # corpus_embedding but not activated yet (farmerapp.mlops.reembed).
        from farmerapp.mlops.reembed import has_staged, nearest_staged

        if await has_staged(session, tenant_id, encoder):
            return await nearest_staged(
                session,
                vector,
                tenant_id=tenant_id,
                crop_id=crop_id,
                encoder=encoder,
                problem_ids=problem_ids,
                k=k,
            )
    return [
        Neighbour(image_id=row.id, problem_id=row.problem_id, similarity=1.0 - float(row.distance))
        for row in rows
    ]


async def nearest_for_images(
    session: AsyncSession,
    vectors: Sequence[Sequence[float]],
    *,
    tenant_id: uuid.UUID,
    crop_id: uuid.UUID | None,
    encoder: EncoderInfo,
    k: int = DEFAULT_K,
) -> list[Neighbour]:
    """Several photos of one case (FM-004: up to three): the union of each photo's
    neighbours, each corpus image at its best similarity, nearest ``k`` overall."""
    best: dict[uuid.UUID, Neighbour] = {}
    for vector in vectors:
        for n in await nearest(
            session, vector, tenant_id=tenant_id, crop_id=crop_id, encoder=encoder, k=k
        ):
            seen = best.get(n.image_id)
            if seen is None or n.similarity > seen.similarity:
                best[n.image_id] = n
    ranked = sorted(best.values(), key=lambda n: (-n.similarity, str(n.image_id)))
    return ranked[:k]


__all__ = ["DEFAULT_EF_SEARCH", "DEFAULT_K", "nearest", "nearest_for_images", "tune_session"]
