# Postgres 16 + PostGIS 3.4 + pgvector in one image (local dev and CI service container).
FROM postgis/postgis:16-3.4
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-16-pgvector \
 && rm -rf /var/lib/apt/lists/*
# Dev/CI login roles (SEC-011): the app role next to the POSTGRES_USER owner. The PostGIS
# base image's own init scripts are numbered 10_postgis.sh; ours run after them.
COPY initdb/ /docker-entrypoint-initdb.d/
