# dbt/ — FarmerApp analytics

Skeleton only until milestone M7 (SPEC 14.4). No models yet; `ci-dbt.yml` skips while `models/` is empty.

Planned (SPEC 5, AN-010..016):

- **Source**: Datastream replicates Cloud SQL into BigQuery dataset `farmerapp_raw` (`infra/modules/analytics`,
  enabled in stg/prd; dev in M7).
- **staging/**: one view per replicated table, PII masked (phone → last 4 digits, exact location → village) per AN-014.
- **marts/**: KPIs from SPEC 5.2 by tenant, cluster, store, officer, crop and day — sales, visits, farmers reached,
  outstanding khata, diagnosis quality, flags. Partitioned by `date_day`, clustered by `tenant_id`.
- **tests**: `not_null`, `unique`, `accepted_values` and relationship tests on every mart (AN-012); freshness on sources.
- **authorised views** in `farmerapp_views` filtered by tenant and role (AN-013), consumed by the console dashboards.

Run locally: `gcloud auth application-default login`, then `cd dbt && dbt deps && dbt build --target dev`
(`profiles.yml` lives in this directory: `export DBT_PROFILES_DIR=$PWD`).
