{#
  AN-013 row-level security for BigQuery, as authorised views.

  The console queries BigQuery as ONE service account (farmerapp-bi-reader), so IAM-based
  row access policies (grantees = Google principals) or SESSION_USER() cannot tell FarmerApp
  users apart. Instead every view in farmerapp_views joins its mart to dim_viewer_scope and
  returns one row per (viewer_user_id, mart row the viewer may see):

    tenant-wide roles  every row of the viewer's tenant
    cluster head       rows whose cluster_id is the viewer's cluster
    store manager      rows whose store_id is the viewer's store
    anyone else        nothing (the view lists which roles may read it at all)

  The console passes the signed-in user's id as a query parameter
  (`WHERE viewer_user_id = @viewer_user_id`), exactly like the API binds app.tenant_id for
  Postgres RLS. The reader SA can read ONLY farmerapp_views; the views dataset is authorised
  on farmerapp_marts (Terraform), so the marts themselves stay unreadable to it.

  grain = 'store'  : the mart has tenant_id, cluster_id and store_id
  grain = 'tenant' : the mart has tenant_id only (tenant-level scopes only)
#}
{% macro authorised_view(mart, extra_roles=[], grain='store', scoped_roles=[]) -%}
  {%- set tenant_roles = var('tenant_wide_roles') + extra_roles -%}
  {%- if grain == 'tenant' and scoped_roles | length > 0 -%}
    {{ exceptions.raise_compiler_error("authorised_view(" ~ mart ~ "): a tenant-grain mart cannot be read by cluster or store scoped roles") }}
  {%- endif -%}
  select
    s.viewer_user_id,
    s.role as viewer_role,
    m.*
  from {{ ref(mart) }} as m
  inner join {{ ref('dim_viewer_scope') }} as s
    on s.tenant_id = m.tenant_id
  where
    (s.scope_level = 'tenant' and s.role in ({{ "'" ~ tenant_roles | join("', '") ~ "'" }}))
    {%- if grain == 'store' and 'cluster_head' in scoped_roles %}
    or (s.scope_level = 'cluster' and s.role = 'cluster_head' and m.cluster_id = s.cluster_id)
    {%- endif %}
    {%- if grain == 'store' and 'store_manager' in scoped_roles %}
    or (s.scope_level = 'store' and s.role = 'store_manager' and m.store_id = s.store_id)
    {%- endif %}
{%- endmacro %}
