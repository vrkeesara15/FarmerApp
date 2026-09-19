{{ config(tags=['AN-010']) }}
{#
  AN-010 "freshness test in dbt": the operational sources (orders, payments, visits, duty
  sessions -- what the owner home and scorecards read) must carry a freshness check that warns
  at 15 minutes and errors at 30 (OPS-011) with the Datastream loaded_at_field. `dbt source
  freshness` enforces it against BigQuery; this test, which runs on every target (ci too),
  makes sure nobody drops or loosens the contract.
#}
{% set required = ['public_order', 'public_payment', 'public_visit', 'public_duty_session'] %}
{% set problems = [] %}
{% if execute %}
  {% set found = [] %}
  {% for src in graph.sources.values() if src.source_name == 'farmerapp_raw' %}
    {% if src.name in required %}
      {% do found.append(src.name) %}
      {% set f = src.freshness or (src.config.freshness if src.config else none) %}
      {% set loaded_at = src.loaded_at_field or (src.config.loaded_at_field if src.config else none) %}
      {% set warn = f.warn_after if f else none %}
      {% set err = f.error_after if f else none %}
      {% if not f or not warn or warn.count != 15 or warn.period != 'minute' %}
        {% do problems.append((src.name, 'warn_after must be 15 minute')) %}
      {% endif %}
      {% if not f or not err or err.count != 30 or err.period != 'minute' %}
        {% do problems.append((src.name, 'error_after must be 30 minute')) %}
      {% endif %}
      {% if 'datastream_metadata.source_timestamp' not in (loaded_at or '') %}
        {% do problems.append((src.name, 'loaded_at_field must be the Datastream source_timestamp')) %}
      {% endif %}
    {% endif %}
  {% endfor %}
  {% for name in required if name not in found %}
    {% do problems.append((name, 'source missing')) %}
  {% endfor %}
{% endif %}

select 'source' as source_name, 'problem' as problem
where 1 = 0
{% for name, problem in problems %}
union all
select '{{ name }}', '{{ problem }}'
{% endfor %}
