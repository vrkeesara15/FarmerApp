{#
  Small cross-database helpers so every model runs unchanged on BigQuery (dev/stg/prd) and on
  DuckDB (ci). Anything dialect-specific lives here behind adapter.dispatch.
#}

{# The IST calendar date of a UTC timestamp (IST = UTC+05:30, no DST). #}
{% macro ist_date(ts) -%}
  {{ return(adapter.dispatch('ist_date', 'farmerapp')(ts)) }}
{%- endmacro %}
{% macro default__ist_date(ts) -%}
  cast(({{ ts }}) + interval 330 minute as date)
{%- endmacro %}
{% macro bigquery__ist_date(ts) -%}
  date({{ ts }}, 'Asia/Kolkata')
{%- endmacro %}

{# The UTC calendar date of a timestamp (khata default due date, farmerapp.khata.aging). #}
{% macro utc_date(ts) -%}
  {{ return(adapter.dispatch('utc_date', 'farmerapp')(ts)) }}
{%- endmacro %}
{% macro default__utc_date(ts) -%}
  cast({{ ts }} as date)
{%- endmacro %}
{% macro bigquery__utc_date(ts) -%}
  date({{ ts }}, 'UTC')
{%- endmacro %}

{# date + n days (n may be negative or a column), always a DATE. #}
{% macro add_days(d, n) -%}
  {{ return(adapter.dispatch('add_days', 'farmerapp')(d, n)) }}
{%- endmacro %}
{% macro default__add_days(d, n) -%}
  cast(cast({{ d }} as date) + cast({{ n }} as integer) as date)
{%- endmacro %}
{% macro bigquery__add_days(d, n) -%}
  date_add(cast({{ d }} as date), interval cast({{ n }} as int64) day)
{%- endmacro %}

{# Whole days from a to b (b - a) for DATEs. #}
{% macro days_between(a, b) -%}
  {{ return(adapter.dispatch('days_between', 'farmerapp')(a, b)) }}
{%- endmacro %}
{% macro default__days_between(a, b) -%}
  date_diff('day', cast({{ a }} as date), cast({{ b }} as date))
{%- endmacro %}
{% macro bigquery__days_between(a, b) -%}
  date_diff(cast({{ b }} as date), cast({{ a }} as date), day)
{%- endmacro %}

{# Seconds from timestamp a to timestamp b. #}
{% macro seconds_between(a, b) -%}
  {{ return(adapter.dispatch('seconds_between', 'farmerapp')(a, b)) }}
{%- endmacro %}
{% macro default__seconds_between(a, b) -%}
  date_diff('second', {{ a }}, {{ b }})
{%- endmacro %}
{% macro bigquery__seconds_between(a, b) -%}
  timestamp_diff({{ b }}, {{ a }}, second)
{%- endmacro %}

{# Timestamp + n days. #}
{% macro ts_add_days(ts, n) -%}
  {{ return(adapter.dispatch('ts_add_days', 'farmerapp')(ts, n)) }}
{%- endmacro %}
{% macro default__ts_add_days(ts, n) -%}
  ({{ ts }} + interval {{ n }} day)
{%- endmacro %}
{% macro bigquery__ts_add_days(ts, n) -%}
  timestamp_add({{ ts }}, interval {{ n }} day)
{%- endmacro %}

{# Monday of the ISO week of a DATE. #}
{% macro week_start(d) -%}
  {{ return(adapter.dispatch('week_start', 'farmerapp')(d)) }}
{%- endmacro %}
{% macro default__week_start(d) -%}
  cast(date_trunc('week', cast({{ d }} as date)) as date)
{%- endmacro %}
{% macro bigquery__week_start(d) -%}
  date_trunc(cast({{ d }} as date), isoweek)
{%- endmacro %}

{# First day of the month of a DATE. #}
{% macro month_start(d) -%}
  {{ return(adapter.dispatch('month_start', 'farmerapp')(d)) }}
{%- endmacro %}
{% macro default__month_start(d) -%}
  cast(date_trunc('month', cast({{ d }} as date)) as date)
{%- endmacro %}
{% macro bigquery__month_start(d) -%}
  date_trunc(cast({{ d }} as date), month)
{%- endmacro %}

{# Last day of the month of a DATE. #}
{% macro month_end(d) -%}
  {{ return(adapter.dispatch('month_end', 'farmerapp')(d)) }}
{%- endmacro %}
{% macro default__month_end(d) -%}
  last_day(cast({{ d }} as date))
{%- endmacro %}
{% macro bigquery__month_end(d) -%}
  last_day(cast({{ d }} as date), month)
{%- endmacro %}

{# One row per day from start to end inclusive, column date_day (DATE). #}
{% macro date_series(start, end) -%}
  {{ return(adapter.dispatch('date_series', 'farmerapp')(start, end)) }}
{%- endmacro %}
{% macro default__date_series(start, end) -%}
  select cast(g.generate_series as date) as date_day
  from generate_series(cast({{ start }} as timestamp), cast({{ end }} as timestamp), interval 1 day) as g
{%- endmacro %}
{% macro bigquery__date_series(start, end) -%}
  select date_day from unnest(generate_date_array(cast({{ start }} as date), cast({{ end }} as date))) as date_day
{%- endmacro %}

{# Text value at a JSON path of a JSON / JSON-text column (tenant.settings). #}
{% macro json_text(col, path) -%}
  {{ return(adapter.dispatch('json_text', 'farmerapp')(col, path)) }}
{%- endmacro %}
{% macro default__json_text(col, path) -%}
  json_extract_string({{ col }}, '{{ path }}')
{%- endmacro %}
{% macro bigquery__json_text(col, path) -%}
  json_value({{ col }}, '{{ path }}')
{%- endmacro %}

{# 8-byte float for ratios (dbt.type_float is a 4-byte FLOAT on DuckDB). #}
{% macro type_double() -%}
  {{ return(adapter.dispatch('type_double', 'farmerapp')()) }}
{%- endmacro %}
{% macro default__type_double() -%}double{%- endmacro %}
{% macro bigquery__type_double() -%}float64{%- endmacro %}

{# SPEC 5.2 ratios: NULL when the denominator is 0 (the console shows "--", never 0 %). #}
{% macro safe_ratio(numerator, denominator) -%}
  case when coalesce({{ denominator }}, 0) = 0 then null
       else cast({{ numerator }} as {{ type_double() }}) / cast({{ denominator }} as {{ type_double() }}) end
{%- endmacro %}

{# Integer paise from a fractional sum (money is integer paise; sums are rounded once). #}
{% macro paise(expr) -%}
  cast(round(coalesce({{ expr }}, 0), 0) as {{ dbt.type_bigint() }})
{%- endmacro %}

{# AN-014: the phone as the console shows it without PII access: 9 stars + last 4 digits
   (farmerapp.analytics.farmers.mask_last4). The full number never reaches BigQuery. #}
{% macro mask_phone_last4(last4) -%}
  case when {{ last4 }} is null then null else concat('*********', {{ last4 }}) end
{%- endmacro %}

{# BigQuery partitioning of a daily / weekly mart by a DATE column; DuckDB (ci) has none. #}
{% macro bq_date_partition(field) -%}
  {%- if target.type == 'bigquery' -%}
    {{ return({'field': field, 'data_type': 'date'}) }}
  {%- else -%}
    {{ return(none) }}
  {%- endif -%}
{%- endmacro %}

{# The grain of a composite-key mart as one string column (tested unique + not_null, AN-012).
   NULL parts become '~' so a NULL dimension (farmer without a crop) is still one key. #}
{% macro row_key(cols) -%}
  concat(
    {%- for c in cols -%}
      coalesce(cast({{ c }} as {{ dbt.type_string() }}), '~'){% if not loop.last %}, '|', {% endif %}
    {%- endfor -%}
  )
{%- endmacro %}

{# A string id column (UUIDs arrive as STRING from Datastream). #}
{% macro as_id(col) -%}
  cast({{ col }} as {{ dbt.type_string() }})
{%- endmacro %}
