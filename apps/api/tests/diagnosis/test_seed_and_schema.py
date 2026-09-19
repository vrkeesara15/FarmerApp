"""M6 seed (public bootstrap corpus) and the Alembic 0027 schema."""

from __future__ import annotations

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

from farmerapp.catalog.crops import PILOT_CROPS
from farmerapp.db.base import Base
from farmerapp.diagnosis.models import CorpusImage, CorpusProblem, CorpusVersion
from farmerapp.jobs.seed_catalog import PROBLEMS
from farmerapp.jobs.seed_corpus import KN_MR, corpus_codes, symptom_list
from tests.authz.conftest import World

NEW_TABLES = (
    "corpus_problem",
    "corpus_image",
    "corpus_version",
    "diagnosis",
    "diagnosis_review",
    "diagnosis_threshold",
    "llm_call_log",
    "data_request",
)


def test_every_pilot_crop_gets_10_to_15_common_problems() -> None:
    """SPEC 3.3 step 1: the six pilot crops, 10-15 most common problems each."""
    available = {p.code for p in PROBLEMS}
    total = 0
    for code, *_ in PILOT_CROPS:
        codes = corpus_codes(code, available)
        assert 10 <= len(codes) <= 15, (code, len(codes))
        total += len(codes)
        for problem in codes:
            assert problem in KN_MR, problem  # names in all five languages
    assert 60 <= total <= 90  # "about 80 problems"


def test_symptom_checklist_split() -> None:
    assert symptom_list("Yellow streaks; wavy edges, dry tips") == [
        "Yellow streaks",
        "Wavy edges",
        "Dry tips",
    ]


async def test_small_seed_corpus_is_public_approved_and_versioned(
    db_session: AsyncSession, world: World
) -> None:
    tid = world.a.tenant.id
    problems = (
        (await db_session.execute(select(CorpusProblem).where(CorpusProblem.tenant_id == tid)))
        .scalars()
        .all()
    )
    assert len(problems) == 3
    for problem in problems:
        assert problem.source == "public" and problem.status == "approved"
        assert set(problem.names) == {"en", "te", "hi", "kn", "mr"}
        assert problem.symptoms["en"] and problem.cultural_practices["en"]
        assert problem.approved_in_version == 1 and problem.approved_by is not None
    images = await db_session.scalar(
        select(func.count()).select_from(CorpusImage).where(CorpusImage.tenant_id == tid)
    )
    assert images == 3 * 8
    version = (
        await db_session.execute(select(CorpusVersion).where(CorpusVersion.tenant_id == tid))
    ).scalar_one()
    assert version.version == 1 and len(version.changes["images"]) == 24


async def test_new_tables_match_the_models(migrate_engine: AsyncEngine) -> None:
    async with migrate_engine.connect() as conn:
        for table in NEW_TABLES:
            rows = await conn.execute(
                text("SELECT column_name FROM information_schema.columns WHERE table_name = :t"),
                {"t": table},
            )
            columns = {r[0] for r in rows}
            assert columns == set(Base.metadata.tables[table].columns.keys()), table
        index = await conn.scalar(
            text(
                "SELECT indexdef FROM pg_indexes WHERE indexname = 'ix_corpus_image_embedding_hnsw'"
            )
        )
        assert index is not None and "hnsw" in index and "vector_cosine_ops" in index
        purpose = await conn.scalar(
            text(
                "SELECT pg_get_constraintdef(oid) FROM pg_constraint "
                "WHERE conname = 'ck_upload_session_purpose'"
            )
        )
        assert purpose is not None and "corpus" in purpose
