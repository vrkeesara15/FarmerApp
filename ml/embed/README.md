# ml/embed — vision encoder service

Owner: ML / platform. Milestone: M6 (DX-002).

Planned content (SPEC 3.1, 8.1):

- A FastAPI service wrapping a pinned vision encoder (SigLIP or DINOv2 family) that returns 768-dim embeddings.
  Deployed as Cloud Run service `embed` (`infra/modules/run_service`, ingress internal, called by `worker` only);
  CPU in pilot, L4 GPU when volume justifies it.
- Model pinning: encoder name + weights hash recorded in every diagnosis result (DX-005); changing the encoder
  triggers a full re-embedding of the corpus (DX-012).
- Batch re-embedding job over the corpus bucket writing to `pgvector` (HNSW index) — kNN over 200k vectors
  under 150 ms p95 (DX-002).
- Contract: `POST /embed` (image bytes → vector, model_version), `GET /healthz`. Dockerfile at `apps/embed/`
  once the service exists; this directory holds model selection notes and benchmark scripts.
