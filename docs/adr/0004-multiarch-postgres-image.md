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

## Follow-up (2026-09-19): parallel API suite

Done on the pytest side as suggested above (branch `chore/parallel-api-tests`):

- **pytest-xdist, one database per worker.** `make test-api` / `check-api` run
  `pytest -n auto --dist worksteal -m "not serial"` (`API_TEST_WORKERS`, default `auto` = 10 on
  this Mac, 4 on GitHub runners). Each worker clones its own database
  `farmerapp_test_<checkout key>_gwN` from a migrated template `farmerapp_test_<checkout key>_template`
  (`CREATE DATABASE … TEMPLATE`, ~0.15 s) and drops it at the end. The template is built once,
  by the first worker, under a Postgres advisory lock, and rebuilt whenever a file under
  `alembic/` changes (fingerprint stored as the database comment). The only database-level
  grant (`CONNECT` for `farmerapp_app`) is re-applied to each clone; everything inside the
  database (RLS, policies, grants, default privileges) comes with the copy. Tests still run as
  the app role and set up as the migrate role. The checkout key (hash of the checkout path)
  keeps concurrent worktrees apart. A plain `pytest` (no `-n`) still uses `farmerapp_test`.
- **`serial` marker.** The WC-001 owner-home 3 s budget measured 4.1 s while nine other
  workers loaded the CPU and database, so it runs afterwards, alone (`pytest -n 1 -m serial
  --cov-append`; 0.98 s untraced). Budget unchanged. No other test needed changes: every
  fixture is function-scoped inside a rolled-back transaction, the few committing tests clean
  up their own tenant, and the pool test only kills backends of its own database. There are no
  migration round-trip tests (Alembic only runs in the fixture), and the mockserver / fake GCS
  tests only read from shared services.
- **Coverage.** pytest-cov combines the workers' data; the report and `--cov-fail-under=80`
  apply to both phases combined. `COVERAGE_CORE=sysmon` is not usable: on Python 3.12
  coverage.py cannot measure branches with sys.monitoring (3.14+) and never supports
  `concurrency = greenlet`, so it would silently fall back to the C tracer. Branch coverage and
  the tracer stay as they were.
- `make test-api-fast` is the same without coverage (about 4.5 min for the whole suite).
  More workers do not help: `-n 14` took 10:47 against 9:31 for `-n 10`.

Result (`SKIP_AUDIT=1 make check-api`, this Mac, three runs in a row, all green): **10m11s,
10m22s, 10m15s** against 54.4 min before (pytest 9:07 / 9:19 / 9:11 + 42 s serial phase;
2783 passed, 1 skipped, as before). Coverage 97.20% on the run that rebuilt the template (the
migrations, and so `db/rls.py`'s Alembic helpers, ran in-process; identical to the 97.20%
before) and 97.16% when the template is reused (the same as a serial run against an
already-migrated `farmerapp_test`). The remaining cost is dominated by `tests/authz/test_matrix.py`
(1,615 of 2,784 tests, each seeding both demo tenants, ~2 s traced); seeding that world once per
worker would be the next step if the suite needs to get faster.
