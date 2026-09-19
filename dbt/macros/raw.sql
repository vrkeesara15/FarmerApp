{#
  Raw CDC tables. Datastream (single target dataset, merge mode) writes Postgres table
  public.<t> to farmerapp_raw.public_<t>, with the source columns listed in
  infra/modules/analytics/replicated_columns.json plus a `datastream_metadata` STRUCT
  (uuid, source_timestamp in epoch milliseconds).

  On the ci target the same shape comes from the seeds/raw fixtures: CSV cannot hold a STRUCT,
  so the seeds carry `_ds_uuid` / `_ds_source_timestamp` and raw_table() packs them. ref() (not
  source()) keeps the seed -> staging edge in the DAG so `dbt build` loads fixtures first.
#}
{% macro raw_table(table) -%}
  {%- if target.name == 'ci' -%}
    (select f.*, {{ ds_metadata_struct('f._ds_uuid', 'f._ds_source_timestamp') }} as datastream_metadata
     from {{ ref('public_' ~ table) }} as f)
  {%- else -%}
    {{ source('farmerapp_raw', 'public_' ~ table) }}
  {%- endif -%}
{%- endmacro %}

{% macro ds_metadata_struct(uuid_col, ts_col) -%}
  {{ return(adapter.dispatch('ds_metadata_struct', 'farmerapp')(uuid_col, ts_col)) }}
{%- endmacro %}

{% macro default__ds_metadata_struct(uuid_col, ts_col) -%}
  struct_pack(uuid := {{ uuid_col }}, source_timestamp := {{ ts_col }})
{%- endmacro %}

{% macro bigquery__ds_metadata_struct(uuid_col, ts_col) -%}
  struct({{ uuid_col }} as uuid, {{ ts_col }} as source_timestamp)
{%- endmacro %}

{#
  Latest row per primary key. Merge mode already keeps one row per key, but a backfill that
  overlaps the change stream, a stream recreated in append-only mode or a replayed fixture can
  hold several versions: the highest source_timestamp wins, ties broken by the row uuid.
  Hard deletes are applied by Datastream (the row disappears); soft deletes (deleted_at) are
  filtered by each staging model.
#}
{% macro latest_cdc_rows(table, key='id') -%}
  select * from (
    select
      r.*,
      row_number() over (
        partition by r.{{ key }}
        order by r.datastream_metadata.source_timestamp desc, r.datastream_metadata.uuid desc
      ) as _cdc_rank
    from {{ raw_table(table) }} as r
  ) as latest
  where _cdc_rank = 1
{%- endmacro %}
