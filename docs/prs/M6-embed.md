# M6 — embed service (DX-002, service half)

Branch `feat/M6-embed-service`. SPEC 3 (flowchart, DX-002), 8.1 (`embed` deployable), 10.1
(`ml/embed/`). Implements the **encoder service contract** of docs/prs/M6-diagnosis-api.md
unchanged; the API side (`RemoteEncoder`, kNN, HNSW) landed with that PR.

## What landed

| | |
|---|---|
| Service | `ml/embed/embed/app.py` — FastAPI: `POST /v1/embed`, `GET /healthz`, `GET /info` |
| Encoder | `ml/embed/embed/encoder.py` — SigLIP vision tower, EXIF-safe decode, processor-faithful pre-processing, `inference_mode`, L2 norm, one forward at a time |
| Pin | `ml/embed/embed/spec.py` — `siglip-base-patch16-224` / `2024-01` / 768, HF revision `7fd15f0689c79d79e38b1c2e2e2370a7bf2761ed`, weights sha256 `2c63cb7d…2af8`, Apache-2.0 |
| Weights | `ml/embed/embed/fetch.py` — download at the pinned revision, verify sha256, keep the vision tower (355 MB), write `embed_manifest.json` |
| Container | `ml/embed/Dockerfile` — python:3.12-slim, CPU torch, non-root 10001, weights baked in, offline at runtime, port 8080, `EMBED_THREADS=2` |
| Tests | `ml/embed/tests/` — 24 contract / validation tests (tiny random SigLIP, 3 s) + 5 `integration` tests on the real weights |
| Contract check | `ml/embed/scripts/check_remote_encoder.py` — the API's `RemoteEncoder` (imported unchanged from apps/api) against the running container |
| Bench | `ml/embed/bench.py`, `ml/embed/bench_mac.json` |
| Docs | `ml/embed/README.md` (run, test, build, deploy, env, GPU, switching models / DX-012), `ml/embed/MODEL_CARD.md` |

## Contract (as specified in M6-diagnosis-api.md)

`POST /v1/embed {"model", "version", "images": [{"b64"}]}` → `{"model", "version", "dim": 768,
"vectors"}`; one unit vector per image in order; batch 1–8; `409 model_mismatch` for any other
model / version. Additional, compatible with `RemoteEncoder` (any non-2xx is an `EncoderError`):
RFC 9457 problem+json errors — `413 request_too_large | image_too_large`, `422 validation_error |
invalid_base64 | unreadable_image` (with `index`). `GET /info` →
`{name, version, dim, revision, weights_sha256, device, max_batch, max_image_bytes}`.

Auth is Cloud Run's (ingress internal + `roles/run.invoker`, OIDC token verified by Cloud Run).

## Results

* **Tests**: `make test` 24 passed (2.9 s); `make test-integration` 5 passed on the real weights
  (dim 768 / unit norm / bit-identical repeat; near-duplicate 0.927 vs street scene 0.628 and
  gradient 0.613; JPEG q95 vs q50 > 0.95; pre-processing = `SiglipImageProcessorPil` within 1e-2);
  `make lint` clean.
* **API contract, live**: the API's `RemoteEncoder` against the container on :8095 —
  5 vectors of 768, unit norm; API seed images: two variants of `paddy_blast` 0.975, a different
  problem 0.872, non-plant (document / brick) ≤ 0.592; a client pinned to `2099-01` refused (409 →
  `EncoderError`). `GET /info` in the container reports the same vision-weights sha256
  (`fad78ac3…f275`) as the macOS fetch.
* **Latency** (decode + preprocess + forward + norm, 1280 x 960 JPEGs), p95:

  | | Threads | Batch 1 | Batch 8 | Per image |
  |---|---|---|---|---|
  | Apple M5, native torch 2.14 CPU | 2 | 94 ms | 568 ms | 71 ms |
  | Apple M5, native torch 2.14 CPU | 4 | 105 ms | 501 ms | 63 ms |
  | Container linux/arm64, Docker `--cpus 2`, over HTTP | 2 | ~345 ms | ~2.65 s | ~330 ms |

  Contract budget (p95 < 1 s per image on CPU) met. Cloud Run x86 numbers to be measured after
  the first dev deploy. Cold start: model load 2.9 s, container ready in ~5 s.
* **Image size**: linux/arm64 660 MB compressed / 2.18 GB unpacked (venv 945 MB, model 355 MB);
  linux/amd64 (the Cloud Run target) **697 MB compressed**, ~1.6 GB unpacked (venv 1.1 GB, model
  355 MB). The amd64 image also passed the live contract check (under QEMU emulation, so no
  latency figure): identical `weights_sha256` and the same cosines to 4 decimals as arm64.

## Decisions

* **SigLIP base/16 over DINOv2 ViT-B/14**: the API was already pinned to
  `siglip-base-patch16-224@2024-01`; SigLIP is Apache-2.0 with a native 768-dim pooled embedding
  (DINOv2 is also Apache-2.0 and a reasonable challenger — compare on the real held-out set via
  `ml/eval` before any switch, which is a DX-012 re-embedding).
* **Base64 bytes, not blob URIs**: the contract carries bytes, so the service needs no bucket
  access; infra's `CORPUS_BUCKET` env and the embed SA's `storage.objectViewer` are unused.
* **Vision tower only** in the image (halves the weights); **fp32** on CPU; one forward pass at a
  time per instance with `EMBED_THREADS` = vCPUs (no thread oversubscription under concurrency).
* **No ONNX**: latency already within budget; a second runtime would need its own parity tests.

## Infra follow-ups (outside this branch; infra/ is read-only here)

1. `embed` `invoker_members` has only the **worker** SA, but `build_encoder` also runs in the
   **api** (corpus manager `POST /v1/corpus/problems/{id}/images` embeds inline) and the **seed /
   jobs** processes — add their SAs or those calls get 403 → `503 encoder_unavailable`.
2. The worker gets `EMBED_URL`, but the API settings read **`DIAGNOSIS_EMBED_URL`** and need
   **`DIAGNOSIS_ENCODER=remote`** — set both on `api`, `worker` and `jobs` (prd refuses `fake`).
3. Optional: `startup_probe_path = "/healthz"` for `embed` (the TCP probe already waits for model
   load, since the port opens after startup); `memory 4Gi` / `cpu 2` / `concurrency 4` fit.
4. Build + push `linux/amd64` in CI (`ml/embed/Dockerfile`, context `ml/embed`).

## Human gates

* **Licence review for commercial use** of the SigLIP weights (Apache-2.0; upstream WebLI
  training data) — legal sign-off.
* **Deploy** the image to dev (then stg by a human; prd human-only) and apply the infra follow-ups.
* **Threshold tuning with real field images** per crop (DX-003 defaults were tuned on the fake
  encoder): run `ml/eval` on the agronomist-labelled held-out set with `DIAGNOSIS_ENCODER=remote`
  after re-embedding the corpus with this encoder.
* **Corpus re-embedding** on switching from `fake-dct` to SigLIP (re-seed / DX-012 job).

## Not run

The repo-wide `make check` does not cover `ml/`; this branch touches only `ml/embed/` and `docs/`.
