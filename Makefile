# FarmerApp — developer entrypoints (CLAUDE.md "Commands"). `make check` mirrors CI.
SHELL := /bin/bash
.DEFAULT_GOAL := help

# Local overrides (git-ignored). docker compose reads the same file itself.
-include .env
export

COMPOSE   ?= docker compose
API_DIR   := apps/api
UV        := uv
UV_RUN    := cd $(API_DIR) && $(UV) run
CORE_SERVICES := db pubsub gcs mockserver

.PHONY: help up down db db-roles seed migrate openapi test-api test-api-fast test-console test-mobile \
        check-api check-console check-mobile check-infra check plan-dev logs

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make <target>\n\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo

# ---------------------------------------------------------------- local env
up: ## Start db, pubsub, gcs, mockserver and wait for health
	$(COMPOSE) up -d --build --wait $(CORE_SERVICES)
	$(MAKE) db-roles

down: ## Stop and remove local containers (volumes kept)
	$(COMPOSE) down --remove-orphans

# --no-recreate: never replace a running db container. Every checkout / worktree shares the
# compose project `farmerapp`; a worktree without this .env (another DB_PORT) used to recreate
# farmerapp-db-1 and drop the connections of a test suite running elsewhere. After changing
# docker/postgres or the port, run `make down` first.
db: ## Start only Postgres (PostGIS + pgvector) and make sure the app role exists
	$(COMPOSE) up -d --build --no-recreate --wait db
	$(MAKE) db-roles

db-roles: ## (Re)apply docker/postgres/initdb roles on an existing volume (idempotent, SEC-011)
	$(COMPOSE) exec -T db psql -q -v ON_ERROR_STOP=1 -U farmerapp -d farmerapp \
	  -f /docker-entrypoint-initdb.d/10-roles.sql

logs: ## Tail compose logs
	$(COMPOSE) logs -f --tail=100

# ---------------------------------------------------------------- api
$(API_DIR)/.venv/.synced: $(API_DIR)/pyproject.toml $(API_DIR)/uv.lock
	cd $(API_DIR) && $(UV) sync --frozen
	@touch $@

migrate: db $(API_DIR)/.venv/.synced ## Run Alembic migrations to head (as the owner: MIGRATION_DATABASE_URL)
	$(UV_RUN) alembic upgrade head

seed: db $(API_DIR)/.venv/.synced ## Load the demo tenants (runs as the app role under RLS)
	$(UV_RUN) python -m farmerapp.jobs seed

openapi: $(API_DIR)/.venv/.synced ## Export apps/api/openapi.yaml from the app (commit it)
	$(UV_RUN) python scripts/export_openapi.py

# pytest-xdist workers, each with its own database cloned from a migrated template
# (apps/api/tests/conftest.py). `auto` = one per CPU core; API_TEST_WORKERS=0 runs the first
# phase serially against farmerapp_test as before. --dist worksteal: idle workers take queued
# tests from busy ones, so the slow seed / synthetic-data tests do not leave a long tail.
# Two phases: everything but `serial` in parallel, then the `serial` (wall-clock budget) tests
# alone on an idle machine (-n 1: its own database); coverage is appended across both phases
# and the --cov-fail-under=80 gate (pyproject addopts) applies to the combined total.
API_TEST_WORKERS ?= auto
PYTEST_PARALLEL   = pytest -n $(API_TEST_WORKERS) --dist worksteal -m "not serial"
PYTEST_SERIAL     = pytest -n 1 -m serial
CHECK_API_STARTED := $(shell date +%s)

test-api: db $(API_DIR)/.venv/.synced ## pytest in parallel with coverage >= 80% (starts db)
	$(UV_RUN) $(PYTEST_PARALLEL) --cov-report= --cov-fail-under=0
	$(UV_RUN) $(PYTEST_SERIAL) --cov-append

test-api-fast: db $(API_DIR)/.venv/.synced ## pytest in parallel without coverage (local iteration)
	$(UV_RUN) $(PYTEST_PARALLEL) --no-cov
	$(UV_RUN) $(PYTEST_SERIAL) --no-cov

check-api: $(API_DIR)/.venv/.synced ## ruff, mypy strict, rules, pytest, openapi diff, bandit, pip-audit
	$(UV_RUN) ruff check .
	$(UV_RUN) ruff format --check .
	$(UV_RUN) mypy
	$(UV_RUN) python -m farmerapp.jobs validate-rules  # VA-001 / VA-007: YAML valid, fixtures present
	$(MAKE) test-api
	$(UV_RUN) python scripts/export_openapi.py --check
	$(UV_RUN) bandit -q -c pyproject.toml -r farmerapp
	@if [ "$(SKIP_AUDIT)" = "1" ]; then echo "check-api: SKIP_AUDIT=1, skipping pip-audit"; \
	else $(UV_RUN) pip-audit --skip-editable --progress-spinner off; fi
	@secs=$$(( $$(date +%s) - $(CHECK_API_STARTED) )); \
	  printf 'check-api: wall clock %dm%02ds\n' $$((secs / 60)) $$((secs % 60))

# ---------------------------------------------------------------- console / mobile / infra
test-console: ## Console tests (npm run check)
	@if [ -f apps/console/package.json ]; then cd apps/console && npm run check; \
	else echo "test-console: apps/console/package.json not found, skipping"; fi

test-mobile: ## Mobile tests (tool/check.sh)
	@if [ -x apps/mobile/tool/check.sh ]; then cd apps/mobile && ./tool/check.sh; \
	else echo "test-mobile: apps/mobile/tool/check.sh not found, skipping"; fi

check-console: test-console ## Console lint/type/test (same as CI)

check-mobile: test-mobile ## Mobile analyze/format/test (same as CI)

check-infra: ## Terraform fmt/validate/tflint/checkov
	@if [ -x infra/scripts/check.sh ]; then cd infra && ./scripts/check.sh; \
	else echo "check-infra: infra/scripts/check.sh not found, skipping"; fi

check: check-api check-console check-mobile check-infra ## Everything CI runs

plan-dev: ## terraform plan for the dev environment
	@if ls infra/envs/dev/*.tf >/dev/null 2>&1; then cd infra/envs/dev && terraform plan; \
	else echo "plan-dev: no Terraform files in infra/envs/dev yet, skipping"; fi
