# DX-002 — kNN over 200k vectors (pgvector HNSW)

Acceptance: kNN over 200k vectors under 150 ms p95.

Benchmark: `apps/api/tests/diagnosis/test_knn_benchmark.py` (marked `slow`, skipped by default;
`FARMERAPP_SLOW=1 uv run pytest -m slow tests/diagnosis/test_knn_benchmark.py --no-cov -s`).
One rolled-back transaction: 200 000 random 768-dim vectors over 6 crops × 10 problems (Gaussian
problem centroids plus uniform noise, so a problem's images cluster as real embeddings do), the
HNSW index rebuilt exactly as Alembic 0027 defines it (`vector_cosine_ops`, m 16,
ef_construction 64), then 200 production queries (`farmerapp.diagnosis.knn.nearest`: approved
images of one crop, same encoder, top 20, iterative scan) as the **app role under RLS**, after 20
warm-up queries.

## Result (2026-09-19, dev laptop: Apple Silicon, 10 cores; compose Postgres 16 + pgvector 0.8.6, default `shared_buffers` 128 MB)

| Setting | p50 | p95 | max | rows / query |
|---|---|---|---|---|
| `hnsw.ef_search` **40** (default, `DIAGNOSIS_HNSW_EF_SEARCH`) | **9.2 ms** | **80.0 ms** | 144.8 ms | 20 |
| `hnsw.ef_search` 100 | 10.7 ms | 52.6 ms | 156.2 ms | 20 |

Load: insert 173 s (vectors generated in SQL), serial HNSW build 137 s (the compose container's
64 MB `/dev/shm` rules out a parallel build; Cloud SQL has no such limit). `EXPLAIN (ANALYZE,
BUFFERS)` of one query: HNSW index scan, 3.8 ms execution, ~900 buffers read — the index
(~800 MB) does not fit in 128 MB `shared_buffers`, so the tail is page reads; size Cloud SQL
memory so the index stays cached (human gate with the prd sizing).

## What had to change on the way

1. **Generic plans.** asyncpg prepares statements and Postgres switches to a generic plan after
   five executions; the generic plan cannot see the crop / vector values and the HNSW walk
   degraded (p50 ~140 ms, flat). `knn.tune_session` now sets `plan_cache_mode =
   force_custom_plan` for the transaction.
2. **Approved problems as constants.** The approved-problem filter was an `IN (subquery)`;
   it is now a small id list fetched first, so the planner keeps the index scan and filters.
3. With uniformly random vectors (no neighbourhood structure at all) and the two issues above,
   the first run measured p50 103 ms / p95 842 ms — a worst case real embeddings never show.

Re-run the benchmark after changing the encoder dimension, `m` / `ef_construction`, or the
kNN query.
