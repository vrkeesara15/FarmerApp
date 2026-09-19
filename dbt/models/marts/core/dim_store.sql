-- Stores with their cluster: the store / cluster keys every store-grain mart carries (AN-011
-- filters, AN-013 row scopes).
select
    s.store_id,
    s.tenant_id,
    s.cluster_id,
    s.store_code,
    s.store_name,
    c.cluster_name,
    s.district,
    s.state
from {{ ref('stg_store') }} as s
left join {{ ref('stg_cluster') }} as c
    on c.cluster_id = s.cluster_id
    and c.tenant_id = s.tenant_id
