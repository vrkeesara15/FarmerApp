{#
  The IST date the snapshot marts are computed for (the API computes the same KPIs for a
  request's `to` date). Precedence: --vars as_of, then the ci fixture date, then today in IST.
  The ci date is the fixture "today" that the reconciliation tests in tests/ were computed for.
#}

{% macro as_of_date() -%}
  {%- set v = var('as_of', none) -%}
  {%- if v -%}
    cast('{{ v }}' as date)
  {%- elif target.name == 'ci' -%}
    cast('2026-09-15' as date)
  {%- else -%}
    {{ ist_date(dbt.current_timestamp()) }}
  {%- endif -%}
{%- endmacro %}
