{#
  Custom schemas map to the Terraform-owned datasets on every target:
    +schema: raw      -> farmerapp_raw      (Datastream; ci: fixture seeds)
    +schema: staging  -> farmerapp_staging
    +schema: marts    -> farmerapp_marts
    +schema: views    -> farmerapp_views    (the only dataset the console reader can read)
  dbt's default would prefix the target dataset (farmerapp_staging_marts), which Terraform
  does not create and IAM does not cover.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
  {%- if custom_schema_name is none -%}
    {{ target.schema }}
  {%- else -%}
    farmerapp_{{ custom_schema_name | trim }}
  {%- endif -%}
{%- endmacro %}
