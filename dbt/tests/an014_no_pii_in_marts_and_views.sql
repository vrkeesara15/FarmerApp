{{ config(tags=['AN-014']) }}
{#
  AN-014 "masking verified", on every target: no staging model, mart or authorised view has a
  column that carries direct PII -- names of people, phone numbers (other than the masked
  form), landmarks, exact locations, token hashes or free-text notes. The allowed phone column
  is phone_masked (9 stars + last 4, checked by the expression tests in the yml files).

  The check reads the built relations' columns (adapter.get_columns_in_relation) of EVERY
  staging / marts / views model in the graph, so a column added by any future model is caught.
  The refs below only order the test after the whole DAG (every mart feeds a view; stg_crop is
  the one staging model no mart reads); a model that is not built yet fails the test as
  "cannot verify" instead of passing silently -- add a ref here when adding a leaf model.
#}
-- depends_on: {{ ref('stg_crop') }}
-- depends_on: {{ ref('v_owner_kpi_30d') }}
-- depends_on: {{ ref('v_active_farmers_daily') }}
-- depends_on: {{ ref('v_store_daily') }}
-- depends_on: {{ ref('v_officer_scorecard_30d') }}
-- depends_on: {{ ref('v_officer_daily') }}
-- depends_on: {{ ref('v_farmer_360') }}
-- depends_on: {{ ref('v_farmer_segments') }}
-- depends_on: {{ ref('v_store_snapshot') }}
-- depends_on: {{ ref('v_store_category_monthly') }}
-- depends_on: {{ ref('v_credit_accounts') }}
-- depends_on: {{ ref('v_crop_health_weekly') }}
-- depends_on: {{ ref('v_diagnosis_quality_weekly') }}
-- depends_on: {{ ref('v_diagnosis_unknowns') }}
-- depends_on: {{ ref('v_campaign_roi') }}
-- depends_on: {{ ref('v_flags_weekly') }}
-- depends_on: {{ ref('v_flag_repeat_offenders') }}

{% set forbidden_exact = ['name', 'phone', 'phone_enc', 'phone_hash', 'phone_plain', 'landmark',
                          'landmark_enc', 'email', 'address', 'notes', 'note', 'override_note',
                          'token_hash', 'device_id', 'home_point', 'checkin_point', 'checkout_point',
                          'location', 'boundary', 'centroid', 'point', 'lat', 'lon', 'title',
                          'evidence', 'survey_no', 'qr_payload', 'receipt_uri', 'blob_uri'] %}
{% set forbidden_parts = ['phone', 'landmark', 'latitude', 'longitude', '_lat', '_lon', 'token'] %}
{% set allowed = ['phone_masked', 'phone_verified'] %}
{# People's names are not allowed; names of places, stores, clusters, crops and pests are. #}
{% set allowed_names = ['tenant_name', 'cluster_name', 'store_name', 'village_name', 'crop_name', 'problem_name'] %}

{% set violations = [] %}
{% set unchecked = [] %}
{% if execute %}
  {% for node in graph.nodes.values() | selectattr('resource_type', 'equalto', 'model') %}
    {% if node.package_name == project_name and node.fqn[1] in ['staging', 'marts', 'views'] %}
      {% set rel = adapter.get_relation(database=node.database, schema=node.schema, identifier=node.alias) %}
      {% set columns = adapter.get_columns_in_relation(rel) if rel is not none else [] %}
      {% if columns | length == 0 %}
        {% do unchecked.append(node.name) %}
      {% endif %}
        {% for col in columns %}
          {% set c = col.name | lower %}
          {% if c not in allowed and c not in allowed_names %}
            {% if c in forbidden_exact or c.endswith('_name') and c not in allowed_names %}
              {% do violations.append((node.name, c)) %}
            {% else %}
              {% for part in forbidden_parts %}
                {% if part in c %}{% do violations.append((node.name, c)) %}{% endif %}
              {% endfor %}
            {% endif %}
          {% endif %}
        {% endfor %}
    {% endif %}
  {% endfor %}
{% endif %}

select 'pii column' as problem, 'model' as model_name, 'column' as column_name
where 1 = 0
{% for model_name, column_name in violations %}
union all
select 'pii column', '{{ model_name }}', '{{ column_name }}'
{% endfor %}
{% for model_name in unchecked %}
union all
select 'relation not built (cannot verify)', '{{ model_name }}', ''
{% endfor %}
