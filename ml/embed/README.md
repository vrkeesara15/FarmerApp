# ml/embed — vision encoder service (DX-002)

Owner: ML / platform. Milestone: M6. Cloud Run service `embed` (infra/envs/*/main.tf, ingress
internal, port 8080). Contract: docs/prs/M6-diagnosis-api.md, "Encoder service contract";
PR notes: docs/prs/M6-embed.md; model and licence: [MODEL_CARD.md](MODEL_CARD.md).

One pinned open-weights encoder — **SigLIP ViT-B/16 (`google/siglip-base-patch16-224`, revision
`7fd15f06…`, Apache-2.0)** — turns photos into **768-dim L2-normalised** vectors for the pgvector
HNSW kNN. The API (`apps/api/farmerapp/diagnosis/encoder.py`, `RemoteEncoder`) calls it from the
`api`, `worker` and seed-job processes when `DIAGNOSIS_ENCODER=remote`.

## API

`POST /v1/embed` (1–8 images, base64 JPEG / PNG / WebP bytes):

```json
{"model": "siglip-base-patch16-224", "version": "2024-01", "images": [{"b64": "<base64>"}]}
```

→ `200 {"model": "siglip-base-patch16-224", "version": "2024-01", "dim": 768, "vectors": [[…768 floats…]]}`
— one unit vector per image, in order; identical bytes give identical vectors.

`GET /healthz` → `200 {"status": "ok"}` (the port only opens after the model is loaded).
`GET /info` → `{name, version, dim, revision, weights_sha256, device, max_batch, max_image_bytes}`.

Errors are RFC 9457 `application/problem+json` with a stable `code`:

| Status | `code` | When |
|---|---|---|
| 409 | `model_mismatch` | request `model` / `version` is not the one served (body has `served`) |
| 413 | `request_too_large` | `Content-Length` over `max_batch x max_image_bytes` (base64) + 64 KiB |
| 413 | `image_too_large` | one image over `EMBED_MAX_IMAGE_BYTES` (`index`) |
| 422 | `validation_error` | body shape, 0 or more than `EMBED_MAX_BATCH` images, unknown fields |
| 422 | `invalid_base64` | `index` of the bad entry |
| 422 | `unreadable_image` | not a decodable image, truncated, or over 40 MP (`index`) |

The API's `RemoteEncoder` turns any non-2xx into `EncoderError` (the corpus route answers
`503 encoder_unavailable`, the worker retries). Images are decoded to pixels with the EXIF
orientation applied; EXIF / GPS / ICC never reach the model and nothing is stored or logged
(logs carry counts and milliseconds only).

**Auth**: Cloud Run's. Ingress internal + `roles/run.invoker` for the calling service accounts;
Cloud Run verifies the caller's OIDC identity token (audience = service URL, sent by the API's
`MetadataIdentityToken`) before the request reaches the container. Locally there is no auth.

## Run locally

```sh
cd ml/embed
make setup            # uv sync --frozen (Python 3.12, CPU torch)
make model            # pinned weights -> .model/ (downloads ~813 MB once, keeps the 355 MB vision tower)
make run              # http://localhost:8095 — the API's default DIAGNOSIS_EMBED_URL
```

Point the API at it: `DIAGNOSIS_ENCODER=remote` (`DIAGNOSIS_ENCODER_NAME` / `_VERSION` default to
this model). Re-seed the corpus afterwards (`make seed` in the repo root) so stored vectors are in
this encoder's space — vectors from the `fake-dct` encoder are never compared with SigLIP ones.

## Test

```sh
make test               # 24 contract / validation tests, tiny random SigLIP, ~3 s, no download
make test-integration   # 5 tests on the real weights: dim / norm / determinism, near-duplicate
                        # closer than unrelated, JPEG-recompression stability, processor parity
make lint
make check-api-client   # with `make run` (or the container) up: the API's own RemoteEncoder
                        # against this service (scripts/check_remote_encoder.py)
```

The contract tests copy the PR doc's JSON shapes and the API's pinned defaults; the
`check-api-client` script imports `farmerapp.diagnosis.encoder.RemoteEncoder` from apps/api
unchanged (installed into `ml/embed/.api-venv` from apps/api's lock file).

## Environment

| Variable | Default | |
|---|---|---|
| `PORT` | `8080` (image) | Cloud Run sets it; `make run` uses 8095 |
| `EMBED_MODEL_DIR` | `/opt/model` | output of `python -m embed.fetch`; must contain `embed_manifest.json` |
| `EMBED_DEVICE` | `cpu` | `cuda` on an L4 image (see GPU) |
| `EMBED_THREADS` | `2` (image) | torch intra-op threads — **keep equal to the Cloud Run vCPU count** (container `cpu`) |
| `OMP_NUM_THREADS`, `MKL_NUM_THREADS` | `2` (image) | same |
| `EMBED_MAX_BATCH` | `8` | the contract's batch size |
| `EMBED_MAX_IMAGE_BYTES` | `8388608` | per decoded image; phone uploads are resized on device (NF-004) |
| `HF_HUB_OFFLINE`, `TRANSFORMERS_OFFLINE` | `1` (image) | weights are baked in; no Hugging Face call at runtime |
| `LOG_LEVEL` | `INFO` | |

`ENV` and `CORPUS_BUCKET` set by infra are ignored (the contract carries image bytes, not blob URIs).

## Performance

Model loaded once at startup (plus one warm-up batch), inference under `torch.inference_mode()`,
one forward pass at a time per instance (a lock; requests queue — Cloud Run `concurrency 4`
covers that), `torch.set_num_threads(EMBED_THREADS)`.

Latency of decode + preprocess + forward + normalise, 1280 x 960 JPEGs (bench.py, bench_mac.json):

| Where | Threads | Batch 1 p95 | Batch 8 p95 | Per image (batch 8) |
|---|---|---|---|---|
| Apple M5, native macOS torch 2.14 | 2 | 94 ms | 568 ms | 71 ms |
| Apple M5, native macOS torch 2.14 | 4 | 105 ms | 501 ms | 63 ms |
| Container (linux/arm64, Docker VM `--cpus 2`), over HTTP incl. base64 / JSON | 2 | ~345 ms | ~2.65 s | ~330 ms |

The contract asks for p95 < 1 s per image on CPU: met with margin in every setting. Linux CPU
torch is slower than macOS (no Accelerate); expect roughly 150–350 ms per image on a Cloud Run
2 vCPU x86 instance — measure after the first dev deploy with `bench.py` in the container.
Cold start: ~3 s model load + warm-up inside a ~5 s container start on the laptop.

ONNX export was not pursued: CPU latency already meets the budget, and a second runtime would need
its own parity tests. Revisit (ONNX Runtime int8 or OpenVINO) only if CPU cost matters at scale.

### GPU (L4, at scale — SPEC 8.1)

Build a variant with CUDA torch (drop the `pytorch-cpu` source for Linux, or use the `cu12x` index)
on a CUDA runtime base, deploy with one `nvidia-l4` GPU (Cloud Run requires at least 4 vCPU /
16 GiB and always-allocated CPU for GPU services; decide on GPU zonal redundancy with the quota),
set `EMBED_DEVICE=cuda`, raise `EMBED_MAX_BATCH` for the
re-embedding job (32–64) and Cloud Run `concurrency` (8–16). Keep fp32 (or verify fp16 parity:
cosine ≥ 0.999 against the CPU vectors on the corpus) — a precision change that moves vectors is a
new encoder version.

## Container

```sh
make docker                                    # native arch, for local runs
docker build --platform linux/amd64 -t embed .  # what Cloud Run runs
make docker-run                                # :8095, 2 vCPU / 4 GiB like the pilot
```

`python:3.12-slim`, non-root (uid 10001), CPU-only torch from the PyTorch CPU index, weights fetched
at build time from the pinned revision and sha256-checked (build fails otherwise), vision tower
only. Sizes: linux/amd64 697 MB compressed / ~1.6 GB unpacked (venv 1.1 GB, model 355 MB);
linux/arm64 660 MB compressed. Cold start on the laptop: model load 2.9 s, ready in ~5 s.

## Deploy (dev)

CI (or a human) builds `linux/amd64`, pushes to Artifact Registry and updates the `embed` service
image (Terraform ignores image changes). stg / prd deploys are human-only. Then set on the callers
(`api`, `worker`, seed job): `DIAGNOSIS_ENCODER=remote`, `DIAGNOSIS_EMBED_URL=<embed uri>`, and
grant them `roles/run.invoker` on `embed` — see the infra follow-ups in docs/prs/M6-embed.md.

## Switching models (DX-012)

Changing the model, revision, pre-processing or numeric precision is a **new encoder version**:

1. new `VERSION` (and `NAME` / `REVISION` / `WEIGHTS_SHA256`) in `embed/spec.py`, new image;
2. deploy it **next to** the old one (separate service or revision tag) and **re-embed the whole
   corpus** with it: `python -m farmerapp.jobs reembed-corpus --tenant … --encoder-name …
   --encoder-version … [--embed-url <new service>]` stages the new vectors in `corpus_embedding`
   (resumable, nothing changes for diagnoses yet; the kNN only compares vectors with the same
   `encoder` label, so old and new never mix);
3. retune the DX-003 thresholds per crop on the held-out set (`ml/eval`, `diagnosis-evaluate`);
4. move the API pin (`DIAGNOSIS_ENCODER_NAME` / `DIAGNOSIS_ENCODER_VERSION`). While the corpus is
   still on the old encoder the kNN answers from the staged vectors, so the rollout has no gap;
5. `python -m farmerapp.jobs activate-encoder --tenant … --encoder-name … --encoder-version …`
   flips the corpus in **one transaction** (it refuses unless every live image is staged, keeps
   the previous vectors — activating the old version again is the rollback — and writes an
   `encoder_activation` row plus an audit row), then retire the old service. Diagnoses keep their
   `model_versions.encoder` for replay (DX-005). `ml/pipelines` has the Vertex pipeline for
   steps 2-3.

## Layout

| Path | |
|---|---|
| `embed/spec.py` | the pinned identity (name, version, revision, sha256, licence) |
| `embed/fetch.py` | download + verify + save vision tower + manifest (Docker build, `make model`) |
| `embed/encoder.py` | decode (EXIF-safe), pre-process, forward, normalise; `Encoder.load` |
| `embed/app.py` | FastAPI app, limits, problem+json errors |
| `tests/` | contract, validation, integration (`-m integration`), synthetic images |
| `bench.py`, `bench_mac.json` | CPU latency |
| `scripts/check_remote_encoder.py` | the API's `RemoteEncoder` against a live service |
