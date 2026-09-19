-- AN-013 viewer -> row scope mapping for the authorised views (macros/authorised_view.sql).
-- One row per active user who may read analytics, with the rows they may see:
--   tenant   owner, director, tenant_admin, auditor (and agronomist, for the crop views only)
--   cluster  cluster head -> their cluster
--   store    store manager -> their store
-- Everyone else (field officers, accountants, farmers, disabled or deleted users, a cluster head
-- without a cluster, a store manager without a store) has no row and therefore sees nothing:
-- fail closed, as Postgres RLS does with an unbound tenant.
{% set tenant_roles = var('tenant_wide_roles') + ['agronomist'] %}

with users as (
    select
        u.user_id,
        u.tenant_id,
        u.role,
        u.store_id,
        u.cluster_id as user_cluster_id,
        s.cluster_id as store_cluster_id
    from {{ ref('stg_user') }} as u
    left join {{ ref('stg_store') }} as s
        on s.store_id = u.store_id
        and s.tenant_id = u.tenant_id
    where u.status = 'active'
),

scoped as (
    select
        user_id as viewer_user_id,
        tenant_id,
        role,
        case
            when role in ('{{ tenant_roles | join("', '") }}') then 'tenant'
            when role = 'cluster_head' and user_cluster_id is not null then 'cluster'
            when role = 'store_manager' and store_id is not null then 'store'
        end as scope_level,
        case
            when role = 'cluster_head' then user_cluster_id
            when role = 'store_manager' then store_cluster_id
        end as cluster_id,
        case when role = 'store_manager' then store_id end as store_id
    from users
)

select *
from scoped
where scope_level is not null
