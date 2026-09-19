# ml/embed — DX-002 encoder service. Run from this directory.
UV ?= uv
PORT ?= 8095
IMAGE ?= farmerapp-embed:2024-01

.PHONY: help setup model run test test-integration lint bench docker docker-run check-api-client

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/'

setup: ## .venv from uv.lock (Python 3.12, CPU torch)
	$(UV) sync --frozen

model: ## fetch the pinned weights (sha256-checked) into .model/ (vision tower, ~355 MB)
	$(UV) run --frozen python -m embed.fetch --out .model

run: ## serve on :$(PORT) (the API's default DIAGNOSIS_EMBED_URL is http://localhost:8095)
	EMBED_MODEL_DIR=.model $(UV) run --frozen uvicorn --factory embed.app:app_from_env --port $(PORT)

test: ## contract + validation tests (tiny random SigLIP, no download)
	$(UV) run --frozen pytest

test-integration: ## real pinned weights (fetches .model/ if missing)
	$(UV) run --frozen pytest -m integration -s

lint: ## ruff
	$(UV) run --frozen ruff check . && $(UV) run --frozen ruff format --check .

bench: ## CPU latency on this machine -> bench_mac.json
	$(UV) run --frozen python bench.py --model-dir .model --out bench_mac.json

docker: ## build the image (native arch; add --platform linux/amd64 for Cloud Run)
	docker build -t $(IMAGE) .

docker-run: ## run the image on :$(PORT) with the pilot's 2 vCPU / 4 GiB
	docker run --rm -p $(PORT):8080 --cpus 2 --memory 4g $(IMAGE)

check-api-client: ## the API's RemoteEncoder against a running service (uses apps/api's locked env)
	UV_PROJECT_ENVIRONMENT=$(CURDIR)/.api-venv $(UV) sync --frozen --project ../../apps/api
	$(CURDIR)/.api-venv/bin/python scripts/check_remote_encoder.py --url http://localhost:$(PORT)
