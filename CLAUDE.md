# FarmerApp — instructions for Claude Code

## Source of truth
- docs/SPEC.md is the specification. Requirement IDs (FA-, FM-, ST-, WC-, DX-, VV-, AN-, VA-, NF-, SEC-, OPS-) define scope.
- design/ holds the approved design: tokens.json, screens/<ID>.md, components/<Name>.md, copy.csv. Match them exactly.
  (No Claude Design export was supplied; design/tokens.json is derived from SPEC section 13.1 and component names from 13.1. Screen specs are derived from 13.2–13.4 as needed.)
- docs/progress.md tracks status per requirement ID: todo | in-progress | done | blocked (with reason).

## Stack (do not change without an ADR in docs/adr/)
API/worker/jobs: Python 3.12, FastAPI, SQLAlchemy 2, Alembic, Pydantic v2, pytest.
Console: Next.js (App Router), TypeScript strict, Tailwind, shadcn/ui, TanStack Query.
Mobile: Flutter, Riverpod, Drift, WorkManager; shared code in apps/mobile/packages/core.
Infra: Terraform in infra/. Analytics: dbt in dbt/.

## Rules
- Work one requirement ID at a time. Write or update tests first; implementation second.
- Every table has tenant_id and RLS; every endpoint has role checks and an authz test for every role.
- Money is integer paise. Timestamps UTC in DB. Strings go in i18n files, never hard-coded.
- Never recommend a SKU without a matching label_claim (DX-007).
- Location is collected only on duty (FA-010). Never add hidden tracking.
- No secrets in code, fixtures or logs. Use Secret Manager references and .env.example.
- Migrations must be backward compatible.
- Run `make check` before declaring anything done; it must pass.
- Update docs/progress.md and the OpenAPI spec in the same change.

## Never do (human-only)
- terraform apply to stg or prd; deploy to prd; publish to Play Console.
- Create or rotate real secrets; call real payment or SMS providers outside test mode.
- Delete data in any shared environment.

## Commands
make up | make seed | make check | make test-api | make test-console | make test-mobile | make plan-dev

## Local git workflow (no remote configured yet)
- Work on a branch feat/<ID>-<slug>; commit with Conventional Commits + requirement ID; write docs/prs/<ID>.md; then fast-forward merge into main so the next loop iteration builds on it. Squash/PR review happens when a GitHub remote is added.
