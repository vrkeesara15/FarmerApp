{#
  Helpers for the singular reconciliation tests (tests/fixture_*.sql): compare a mart to
  hand-computed expected rows and return every row that differs or is missing.

  reconcile(actual_relation, expected_rows, keys, exact=[...], approx=[...])
    expected_rows  list of dicts (the hand-computed fixture values)
    keys           columns joining expected to actual
    exact          columns compared with = (NULL = NULL counts as equal)
    approx         float columns compared within 1e-6 (ratios)
  Every expected row must exist in the mart; extra mart rows are ignored unless
  `complete=true`, in which case rows of the mart missing from `expected` also fail.
#}
{% macro sql_literal(v) -%}
  {%- if v is none -%}null
  {%- elif v is sameas true -%}true
  {%- elif v is sameas false -%}false
  {%- elif v is number -%}{{ v }}
  {%- elif v is string and v.startswith('date:') -%}cast('{{ v[5:] }}' as date)
  {%- else -%}'{{ v }}'
  {%- endif -%}
{%- endmacro %}

{% macro reconcile(actual_relation, expected_rows, keys, exact=[], approx=[], complete=false, where=none) %}
  {%- set cols = keys + exact + approx -%}
with expected as (
  {%- for row in expected_rows %}
  select
    {%- for c in cols %}
    {% if c in approx %}cast({{ sql_literal(row[c]) }} as {{ type_double() }}){% else %}{{ sql_literal(row[c]) }}{% endif %} as {{ c }}{{ "," if not loop.last }}
    {%- endfor %}
  {{ "union all" if not loop.last }}
  {%- endfor %}
),

actual as (
  select {{ cols | join(', ') }}
  from {{ actual_relation }}
  {% if where %}where {{ where }}{% endif %}
),

compared as (
  select
    {%- for k in keys %}
    coalesce(e.{{ k }}, a.{{ k }}) as {{ k }},
    {%- endfor %}
    case
      when a.{{ keys[0] }} is null then 'missing in mart'
      when e.{{ keys[0] }} is null then 'unexpected row in mart'
      {%- for c in exact %}
      when not ((e.{{ c }} is null and a.{{ c }} is null) or e.{{ c }} = a.{{ c }}) then 'mismatch: {{ c }}'
      {%- endfor %}
      {%- for c in approx %}
      when not ((e.{{ c }} is null and a.{{ c }} is null) or abs(e.{{ c }} - a.{{ c }}) < 0.000001) then 'mismatch: {{ c }}'
      {%- endfor %}
    end as problem
  from expected as e
  {{ "full outer join" if complete else "left join" }} actual as a
    on {% for k in keys %}e.{{ k }} = a.{{ k }}{{ " and " if not loop.last }}{% endfor %}
)

select * from compared where problem is not null
{% endmacro %}
