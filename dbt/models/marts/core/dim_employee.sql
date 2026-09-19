-- Employees (every non-farmer user) by id, role, store and cluster. No name, no phone (AN-014):
-- the console shows names from the API.
select
    u.user_id as employee_id,
    u.tenant_id,
    u.role,
    u.status,
    u.store_id,
    coalesce(u.cluster_id, s.cluster_id) as cluster_id
from {{ ref('stg_user') }} as u
left join {{ ref('stg_store') }} as s
    on s.store_id = u.store_id
    and s.tenant_id = u.tenant_id
where u.role <> 'farmer'
