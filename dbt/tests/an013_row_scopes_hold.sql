{{ config(tags=['AN-013']) }}
{#
  AN-013 on EVERY target (ci fixtures and real BigQuery data): no authorised view returns a row
  outside the viewer's scope.
    - never another tenant's row
    - a cluster head only rows of their own cluster ("cluster head sees only own cluster")
    - a store manager only rows of their own store
    - only roles listed for the view (field officers, accountants, farmers never appear)
  Store-grain views are checked on cluster_id / store_id; tenant-grain views on tenant and role.
#}
{% set store_views = [
    ('v_store_daily', ['cluster_head', 'store_manager']),
    ('v_officer_scorecard_30d', ['cluster_head']),
    ('v_officer_daily', ['cluster_head']),
    ('v_farmer_360', ['cluster_head']),
    ('v_farmer_segments', ['cluster_head']),
    ('v_store_snapshot', ['cluster_head', 'store_manager']),
    ('v_store_category_monthly', ['cluster_head', 'store_manager']),
    ('v_credit_accounts', ['cluster_head', 'store_manager']),
    ('v_flag_repeat_offenders', ['cluster_head']),
] %}
{% set tenant_views = [
    ('v_owner_kpi_30d', []),
    ('v_active_farmers_daily', []),
    ('v_crop_health_weekly', ['agronomist']),
    ('v_diagnosis_quality_weekly', ['agronomist']),
    ('v_diagnosis_unknowns', ['agronomist']),
    ('v_campaign_roi', []),
    ('v_flags_weekly', []),
] %}

{% for name, scoped in store_views %}
select
    '{{ name }}' as view_name,
    v.viewer_user_id,
    v.viewer_role,
    v.tenant_id,
    v.cluster_id,
    v.store_id
from {{ ref(name) }} as v
inner join {{ ref('dim_viewer_scope') }} as s
    on s.viewer_user_id = v.viewer_user_id
where v.tenant_id <> s.tenant_id
    or v.viewer_role <> s.role
    or v.viewer_role not in ('{{ (var('tenant_wide_roles') + scoped) | join("', '") }}')
    or (s.scope_level = 'cluster' and (v.cluster_id is null or v.cluster_id <> s.cluster_id))
    or (s.scope_level = 'store' and (v.store_id is null or v.store_id <> s.store_id))
union all
{% endfor %}
{% for name, extra in tenant_views %}
select
    '{{ name }}' as view_name,
    v.viewer_user_id,
    v.viewer_role,
    v.tenant_id,
    cast(null as {{ dbt.type_string() }}) as cluster_id,
    cast(null as {{ dbt.type_string() }}) as store_id
from {{ ref(name) }} as v
inner join {{ ref('dim_viewer_scope') }} as s
    on s.viewer_user_id = v.viewer_user_id
where v.tenant_id <> s.tenant_id
    or s.scope_level <> 'tenant'
    or v.viewer_role not in ('{{ (var('tenant_wide_roles') + extra) | join("', '") }}')
{{ "union all" if not loop.last }}
{% endfor %}
