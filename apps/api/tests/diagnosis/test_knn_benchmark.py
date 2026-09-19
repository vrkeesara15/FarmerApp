"""DX-002 acceptance: kNN over 200k vectors under 150 ms p95 (pgvector HNSW).

``slow``: skipped unless ``FARMERAPP_SLOW=1`` (``FARMERAPP_SLOW=1 uv run pytest -m slow
tests/diagnosis/test_knn_benchmark.py --no-cov -s``). Everything happens in one transaction
of the migrate role that is rolled back: the HNSW index is dropped, 200 000 random 768-dim
vectors are generated in SQL across six crops and 60 problems (Gaussian problem centroids plus
uniform noise, so a problem's images cluster like real embeddings), the index is rebuilt exactly
as Alembic 0027 defines it (m 16, ef_construction 64, ``vector_cosine_ops``), then the
production query (``farmerapp.diagnosis.knn.nearest``: approved images of one crop, same
encoder, top 20, ``hnsw.ef_search`` 40 = the setting's default (100 reported too),
iterative scan) runs as the **app role under RLS**
for 200 random query vectors (noisy copies of a random problem centroid, after 20 warm-up
queries). Results are printed and recorded in docs/perf/M6-knn.md.
"""

from __future__ import annotations

import random
import statistics
import time
import uuid

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

from farmerapp.db.rls import APP_ROLE
from farmerapp.diagnosis.encoder import EncoderInfo
from farmerapp.diagnosis.knn import DEFAULT_EF_SEARCH, nearest, tune_session

VECTORS = 200_000
QUERIES = 200
CROPS = 6
PROBLEMS_PER_CROP = 10
ENCODER = EncoderInfo("bench", "1")
#: Uniform noise around a per-problem centroid: images of one problem cluster, as real
#: embeddings do (uniformly random vectors have no neighbourhood structure at all).
NOISE = 3.0
WARMUP = 20
NL = chr(10)

pytestmark = [pytest.mark.slow, pytest.mark.timeout(3600)]


async def test_knn_p95_under_150ms_over_200k_vectors(migrate_engine: AsyncEngine) -> None:
    tenant = uuid.uuid4()
    async with migrate_engine.connect() as conn:
        trans = await conn.begin()
        try:
            # Serial in-memory build: the compose container has a 64 MB /dev/shm, too small
            # for a parallel build's shared memory (Cloud SQL has no such limit).
            await conn.execute(text("SET LOCAL maintenance_work_mem = '2GB'"))
            await conn.execute(text("SET LOCAL max_parallel_maintenance_workers = 0"))
            await conn.execute(
                text("INSERT INTO tenant (id, tenant_id, name, slug) VALUES (:t, :t, 'bench', :s)"),
                {"t": tenant, "s": f"bench-{tenant.hex[:8]}"},
            )
            crops = [uuid.uuid4() for _ in range(CROPS)]
            problems: list[tuple[uuid.UUID, uuid.UUID]] = []
            for c, crop in enumerate(crops):
                await conn.execute(
                    text(
                        "INSERT INTO crop (id, tenant_id, code, name) "
                        "VALUES (:id, :t, :code, :code)"
                    ),
                    {"id": crop, "t": tenant, "code": f"crop{c}"},
                )
                for p in range(PROBLEMS_PER_CROP):
                    pest, problem = uuid.uuid4(), uuid.uuid4()
                    await conn.execute(
                        text(
                            "INSERT INTO pest_or_disease (id, tenant_id, code, name, type) "
                            "VALUES (:id, :t, :code, :code, 'disease')"
                        ),
                        {"id": pest, "t": tenant, "code": f"p{c}_{p}"},
                    )
                    await conn.execute(
                        text(
                            "INSERT INTO corpus_problem (id, tenant_id, pest_or_disease_id, "
                            "crop_id, problem_type, names, symptoms, cultural_practices, status, "
                            "approved_at) VALUES (:id, :t, :pest, :crop, 'disease', '{}', '{}', "
                            "'{}', 'approved', now())"
                        ),
                        {"id": problem, "t": tenant, "pest": pest, "crop": crop},
                    )
                    problems.append((problem, crop))
            await conn.execute(
                text("CREATE TEMP TABLE bench_problem (n int, id uuid, crop uuid, c real[])")
            )
            rng = random.Random(42)
            centroids: list[list[float]] = []
            for n, (problem, crop) in enumerate(problems):
                centroid = [rng.gauss(0, 1) for _ in range(768)]
                centroids.append(centroid)
                await conn.execute(
                    text("INSERT INTO bench_problem VALUES (:n, :id, :crop, :c)"),
                    {"n": n, "id": problem, "crop": crop, "c": centroid},
                )
            await conn.execute(text("DROP INDEX ix_corpus_image_embedding_hnsw"))
            started = time.perf_counter()
            await conn.execute(
                text(
                    """
INSERT INTO corpus_image (tenant_id, problem_id, crop_id, blob_uri, sha256, embedding,
                          encoder_name, encoder_version, status, approved_at, source)
SELECT :t, bp.id, bp.crop, 'gs://bench/' || g, md5(g::text) || md5((g + 1)::text),
       (SELECT array_agg(bp.c[i] + (random() - 0.5) * :noise ORDER BY i)::real[]
          FROM generate_series(1, 768) AS i WHERE g > 0)::vector,
       :enc, :ver, 'approved', now(), 'public'
FROM generate_series(1, :n) AS g
JOIN bench_problem bp ON bp.n = g % :problems
"""
                ),
                {
                    "t": tenant,
                    "n": VECTORS,
                    "problems": len(problems),
                    "noise": NOISE,
                    "enc": ENCODER.name,
                    "ver": ENCODER.version,
                },
            )
            inserted = time.perf_counter() - started
            started = time.perf_counter()
            await conn.execute(
                text(
                    "CREATE INDEX ix_corpus_image_embedding_hnsw ON corpus_image USING hnsw "
                    "(embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)"
                )
            )
            built = time.perf_counter() - started
            await conn.execute(text("ANALYZE corpus_image"))
            # the production path: app role, RLS on, tenant bound
            await conn.execute(text(f"SET LOCAL ROLE {APP_ROLE}"))
            await conn.execute(
                text("SELECT set_config('app.tenant_id', :t, true)"), {"t": str(tenant)}
            )
            session = AsyncSession(bind=conn)
            results: dict[int, tuple[list[float], list[int]]] = {}
            for ef_search in (DEFAULT_EF_SEARCH, 100):
                await tune_session(session, ef_search=ef_search)
                timings: list[float] = []
                counts: list[int] = []
                for i in range(WARMUP + QUERIES):
                    n = rng.randrange(len(problems))
                    vector = [v + (rng.random() - 0.5) * NOISE for v in centroids[n]]
                    crop = problems[n][1]
                    t0 = time.perf_counter()
                    found = await nearest(
                        session, vector, tenant_id=tenant, crop_id=crop, encoder=ENCODER, k=20
                    )
                    if i >= WARMUP:  # the first queries only warm the buffer cache
                        timings.append((time.perf_counter() - t0) * 1000)
                        counts.append(len(found))
                results[ef_search] = (sorted(timings), counts)
            await tune_session(session, ef_search=DEFAULT_EF_SEARCH)
            probe = str([v + 0.1 for v in centroids[0]])
            buffers = NL.join(
                row[0]
                for row in (
                    await conn.execute(
                        text(
                            "EXPLAIN (ANALYZE, BUFFERS) SELECT id FROM corpus_image "
                            "WHERE crop_id = :c AND status = 'approved' "
                            "ORDER BY embedding <=> :v LIMIT 20"
                        ),
                        {"c": problems[0][1], "v": probe},
                    )
                ).all()
            )
            plan = "\n".join(
                row[0]
                for row in (
                    await conn.execute(
                        text(
                            "EXPLAIN SELECT id FROM corpus_image WHERE crop_id = :c "
                            "AND status = 'approved' ORDER BY embedding <=> :v LIMIT 20"
                        ),
                        {"c": crops[0], "v": str([0.1] * 768)},
                    )
                ).all()
            )
        finally:
            await trans.rollback()
    lines = []
    for ef_search, (times, found_counts) in results.items():
        p50 = statistics.median(times)
        p95 = times[int(len(times) * 0.95) - 1]
        lines.append(
            f"ef_search {ef_search}: p50 {p50:.1f} ms, p95 {p95:.1f} ms, max {times[-1]:.1f} ms, "
            f"rows per query min {min(found_counts)}"
        )
    print(  # noqa: T201 - benchmark report (pytest -s)
        f"{NL}DX-002 kNN benchmark: {VECTORS} vectors x 768, {CROPS} crops; "
        f"insert {inserted:.1f} s, HNSW build {built:.1f} s; {QUERIES} queries, top 20 of one "
        f"crop, app role + RLS{NL}" + NL.join(lines) + f"{NL}{plan}{NL}{buffers}"
    )
    times, found_counts = results[DEFAULT_EF_SEARCH]
    assert min(found_counts) == 20
    assert times[int(len(times) * 0.95) - 1] < 150.0
