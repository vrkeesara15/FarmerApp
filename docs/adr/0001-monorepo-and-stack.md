# ADR 0001: Monorepo and locked stack

Date: 2026-09-17. Status: accepted.

## Context
SPEC §0.2 locks the stack and §10.1 the repository layout.

## Decision
One monorepo (this repo). FastAPI + SQLAlchemy 2 + Alembic on Python 3.12 (managed with uv); Next.js App Router + TypeScript strict; Flutter monorepo with a shared `packages/core`; Terraform for GCP; dbt for analytics. Trunk-based development on `main`.

## Consequences
Any stack change needs a new ADR. Local tooling: Docker Compose for Postgres 16 + PostGIS + pgvector, Pub/Sub emulator, fake GCS, and a mock SMS/payment server.
