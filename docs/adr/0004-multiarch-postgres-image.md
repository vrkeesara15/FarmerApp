# ADR 0004: Native multi-arch Postgres image (PostGIS 3 + pgvector)

Date: 2026-09-19. Status: accepted.

## Context

`docker/postgres/Dockerfile` (local `make db` and the `ci-api` service container) was
`FROM postgis/postgis:16-3.4` plus `postgresql-16-pgvector`. That image is published for
linux/amd64 only, so on Apple Silicon the database ran under amd64 emulation and a full API
suite (`make check-api`) took roughly 50–60 minutes.

## Decision

Build on the official, multi-arch `postgres:16-bookworm` image and install
`postgresql-16-postgis-3`, `postgresql-16-postgis-3-scripts` and `postgresql-16-pgvector`
from the PGDG apt repository the official image already configures. Pins: Postgres major 16,
Debian bookworm, PostGIS `3.6.*`, pgvector `0.8.*` (PGDG only keeps recent patch releases, so
exact patch pins would break builds); the resolved versions are recorded in the Dockerfile.

- The PostGIS image's own `10_postgis.sh` (postgis, topology, tiger geocoder in
  `template_postgis` and `POSTGRES_DB`) is dropped. Nothing depended on it: Alembic 0001
  creates `postgis`, `vector`, `pg_trgm` (0014 `btree_gist`) as the owner role, and the test
  database is created from `template1`, which that script never touched.
- Compose tag `farmerapp/postgres:16-postgis3-pgvector-multiarch` and a new volume
  `farmerapp_pgdata_arm64`, so the old amd64 image and its `farmerapp_pgdata` volume are not
  reused. Removing the old volume is optional and manual: `docker volume rm farmerapp_pgdata`.
- CI (`ubuntu-latest`, amd64) builds the same Dockerfile; the base supports both arches.

## Consequences

- PostGIS 3.4.3 / GEOS 3.9.0 / PROJ 7.2.1 (bullseye) become PostGIS 3.6.4 / GEOS 3.11.1 /
  PROJ 9.8.1. Cloud SQL's PostGIS version is managed separately; geometry code must not depend
  on library-specific output (e.g. exact `ST_IsValidReason` wording).
- The database now runs natively on Apple Silicon, but the local API suite barely got faster:
  `SKIP_AUDIT=1 make check-api` took 54.4 min (pytest 54:08, 2783 passed, 1 skipped) against
  roughly 50–60 min before. During the run the db container sat near 10% CPU while the pytest
  process was CPU-bound; emulation was not the bottleneck. Coverage tracing (`branch = true`,
  `concurrency = ["greenlet", "thread"]`, CTracer) accounts for about 2.4–3x: `tests/visits`
  118 s with coverage vs 50 s with `--no-cov`, `tests/rls` 21 s vs 7 s. Speeding up the suite
  further means working on the pytest side (e.g. `--no-cov` for local iteration,
  pytest-xdist with per-worker databases), not the database image.
