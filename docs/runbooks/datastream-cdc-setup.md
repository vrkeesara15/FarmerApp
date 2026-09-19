# Datastream CDC setup, operation and teardown (M7, AN-010 / AN-014)

**Owner:** platform lead (setup), data owner (dbt, freshness). **Severity:** Sev 2 when the stream
fails or lags > 30 min (OPS-011); Sev 1 if the replication slot threatens Cloud SQL disk.
**Detection:** `dbt source freshness` error (orders / payments / visits / duty sessions older than
30 min), Datastream stream state not `RUNNING`, Cloud SQL disk growth with an idle slot (OPS-003).

Datastream replicates Cloud SQL (private IP) into BigQuery `farmerapp_raw` through a Private
Service Connect interface (`infra/modules/analytics`). Only the tables and columns in
`infra/modules/analytics/replicated_columns.json` are read (AN-014): no names, phones, landmarks,
points, notes, token hashes or evidence ever leave Postgres. dbt then builds
`farmerapp_staging` -> `farmerapp_marts` -> `farmerapp_views` (`dbt/README.md`).

Migrations own the database and Terraform never holds a database password, so the replication
login, its grants, the RLS read policies, the publication and the slot are created by the
one-time SQL below. It is **human-only** (CLAUDE.md: secrets and shared environments).

## Conventions

```bash
ENV=dev                                   # dev | stg | prd
PROJECT=farmerapp-$ENV
INSTANCE=farmerapp-$ENV
REGION=asia-south1
```

## 1. First apply: connectivity only (`datastream_enabled = true`)

`infra/envs/<env>/terraform.tfvars` ships `datastream_enabled = true` and
`datastream_stream_enabled = false`. The apply (dev: CI on merge; stg / prd: a human) creates the
four datasets, the `farmerapp-dbt` and `farmerapp-bi-reader` service accounts and their grants,
the `farmerapp-<env>-datastream` subnet (10.20.0.0/28) and network attachment, the PSC private
connection, the BigQuery connection profile and the empty secret `datastream-db-password`
(readable only by the Datastream service agent).

Check: `gcloud datastream private-connections describe farmerapp-$ENV-psc --location $REGION
--project $PROJECT --format='value(state)'` prints `CREATED`.

## 2. The replication login and its password

```bash
# A password that never touches a file, a shell history or Terraform state.
PW=$(openssl rand -base64 30 | tr -d '\n/+=' | cut -c1-32)
printf %s "$PW" | gcloud secrets versions add datastream-db-password --project $PROJECT --data-file=-
```

Connect as the built-in `postgres` user (Cloud SQL Studio, or `gcloud sql connect $INSTANCE
--user=postgres --database=farmerapp --project $PROJECT` from a host with private access) and run
the admin part: it creates the `datastream` role (LOGIN REPLICATION, nothing else) and the
`farmerapp_datastream` pgoutput slot.

```bash
python3 infra/scripts/datastream_sql.py --part admin > /tmp/datastream-admin.sql
# in psql as postgres:
\i /tmp/datastream-admin.sql
\password datastream        -- paste $PW; never put it in a SQL file
```

Then `unset PW`.

## 3. Grants, RLS read policies and the publication (table owner)

Every table has `FORCE ROW LEVEL SECURITY` keyed on `app.tenant_id` (ADR 0003), so the backfill
would see nothing without a policy. Connect as a member of `farmerapp_migrate` (the tables'
owner) and run the owner part:

```bash
python3 infra/scripts/datastream_sql.py --part owner > /tmp/datastream-owner.sql
# in psql as the migrate owner:
\i /tmp/datastream-owner.sql
```

It is idempotent and does, per allowlisted table: `REVOKE ALL`, column-level `GRANT SELECT
(<allowlisted columns>)`, `CREATE POLICY datastream_read ... FOR SELECT TO datastream USING
(true)`; then `ALTER PUBLICATION farmerapp_datastream SET TABLE <table> (<columns>), ...` (column
lists, Postgres 15+). The `datastream` login can therefore not even read a farmer's name.

Verify:

```sql
SELECT pubname, count(*) FROM pg_publication_tables WHERE pubname = 'farmerapp_datastream' GROUP BY 1;  -- 26 tables
SELECT slot_name, plugin, active FROM pg_replication_slots WHERE slot_name = 'farmerapp_datastream';   -- pgoutput, f
SET ROLE datastream; SELECT name FROM public.farmer LIMIT 1;  -- ERROR: permission denied (AN-014)
RESET ROLE;
```

**Follow-up (apps/api, not this runbook):** codify the `datastream_read` policies in an Alembic
migration and teach `tests/rls/test_meta.py` about them, so a migration that recreates a table
keeps the policy. Until then, re-run `--part owner` after any migration that drops and recreates
a replicated table, and after every change to `replicated_columns.json`.

## 4. Turn the stream on (`datastream_stream_enabled = true`)

Set `datastream_stream_enabled = true` in `infra/envs/$ENV/terraform.tfvars` (PR; stg / prd
applies are human-only). The apply creates the Postgres connection profile (private IP, TLS
verified against the instance's server CA, password from `datastream-db-password/versions/latest`)
and the stream `farmerapp-$ENV-cdc`: backfill of every allowlisted table, then CDC, merge mode,
`data_freshness = 600s`.

If the connection profile is rejected for the `latest` alias, pin the version explicitly:
`datastream_password_secret_version = "projects/<number>/secrets/datastream-db-password/versions/1"`.

Verify:

```bash
gcloud datastream streams describe farmerapp-$ENV-cdc --location $REGION --project $PROJECT --format='value(state)'   # RUNNING
bq ls --project_id $PROJECT farmerapp_raw          # public_order, public_visit, ... (26 tables)
bq query --project_id $PROJECT --use_legacy_sql=false \
  'SELECT count(*) FROM farmerapp_raw.public_farmer WHERE true'   # rows; the table has no name / phone column
```

Then publish the dbt service account for CI (repository variable `DBT_SA_DEV` =
`terraform output -json analytics | jq -r .dbt_service_account`) and add the GitHub principal set
to `dbt_workload_identity_members` so `ci-dbt.yml` builds against dev BigQuery.

## 5. Freshness (AN-010) and lag

* `make dbt-freshness` (or `dbt source freshness --target $ENV`): warn at 15 min, error at 30 min
  on orders, payments, visits and duty sessions. In dev the tables are quiet outside testing, so
  a stale warning there is expected; stg / prd run it with the scheduled dbt job.
* Datastream console -> stream -> "Data freshness" shows the lag per table.
* A lag > 30 min: check the stream state (`FAILED` / `PAUSED`), the error on the source profile
  (password rotated? policy dropped by a migration? publication missing a new table?), then
  `gcloud datastream streams update farmerapp-$ENV-cdc --location $REGION --state=RUNNING`.

## 6. Replication slot safety (Sev 1 if ignored)

A logical slot keeps WAL until Datastream confirms it. A stream stopped for days fills the
Cloud SQL disk. If the stream will stay stopped for more than a few hours:

```sql
SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
FROM pg_replication_slots WHERE slot_name = 'farmerapp_datastream';
-- If retained WAL is large and the stream is not coming back:
SELECT pg_drop_replication_slot('farmerapp_datastream');   -- as postgres; the stream must then backfill again
```

## 7. Teardown

1. `datastream_stream_enabled = false` and apply (deletes the stream and source profile).
2. As `postgres`: `SELECT pg_drop_replication_slot('farmerapp_datastream');`
3. As the owner: `DROP PUBLICATION farmerapp_datastream;` and, per table,
   `DROP POLICY datastream_read ON public.<t>;` then `DROP ROLE datastream;`
4. Disable the old secret version (`gcloud secrets versions disable ...`). Dropping BigQuery
   data in stg / prd is human-only (CLAUDE.md "Delete data in any shared environment").

## Communication and follow-up

Post in `#farmerapp-ops` when a stream is enabled, stopped or its slot dropped. After an
incident: record the lag window (dashboards read the API's Postgres replica in P0 -- SPEC 5.3 --
so owners were not affected unless a BigQuery-backed report was due).
