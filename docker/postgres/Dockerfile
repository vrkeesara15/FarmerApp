# Postgres 16 + PostGIS 3 + pgvector in one image (local dev and CI service container).
#
# Multi-arch base (ADR 0004): the official postgres image ships linux/amd64 and linux/arm64,
# so Apple Silicon runs the database natively (postgis/postgis has no arm64 build and ran
# under amd64 emulation). PostGIS and pgvector come from the PGDG apt repository that the
# official image already configures. Pins: Postgres major 16 on Debian bookworm, PostGIS 3.6.x,
# pgvector 0.8.x (PGDG keeps only recent patch releases, so exact patch pins would break).
#
# Resolved 2026-09-19: postgres 16.15-1.pgdg12+2, postgresql-16-postgis-3(-scripts)
# 3.6.4+dfsg-2.pgdg12+1 (GEOS 3.11.1 from bookworm, PROJ 9.8.1 from PGDG), postgresql-16-pgvector
# 0.8.6-1.pgdg12+1. Previous image: postgis/postgis:16-3.4 (bullseye, PostGIS 3.4.3,
# GEOS 3.9.0, PROJ 7.2.1, amd64 only).
FROM postgres:16-bookworm

ARG POSTGIS_VERSION=3.6.*
ARG PGVECTOR_VERSION=0.8.*

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      "postgresql-16-postgis-3=${POSTGIS_VERSION}" \
      "postgresql-16-postgis-3-scripts=${POSTGIS_VERSION}" \
      "postgresql-16-pgvector=${PGVECTOR_VERSION}" \
 && rm -rf /var/lib/apt/lists/*

# No template-database PostGIS step: postgis/postgis ran its own 10_postgis.sh (postgis,
# topology, tiger geocoder in template_postgis and POSTGRES_DB). Nothing relies on it —
# Alembic 0001 creates postgis / vector / pg_trgm itself (0014 adds btree_gist), and the test
# database is created from template1, which that script never touched.
# Dev/CI login roles (SEC-011): the app role next to the POSTGRES_USER owner.
COPY initdb/ /docker-entrypoint-initdb.d/
