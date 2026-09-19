-- AN-009 repeat offenders: field staff with 2 or more flags (on themselves or on their visits)
-- raised in the 90 IST days ending on the as-of date. Ids only; names come from the API.
with params as (
    select
        {{ as_of_date() }} as as_of_date,
        {{ add_days(as_of_date(), -89) }} as window_start
),

flags as (
    select f.*
    from {{ ref('int_flag_officer') }} as f
    cross join params as p
    where f.raised_date between p.window_start and p.as_of_date
),

per_officer as (
    select
        tenant_id,
        officer_id,
        count(distinct flag_id) as flags_90d,
        count(distinct case when is_open then flag_id end) as open_flags,
        count(distinct rule_id) as distinct_rules,
        max(created_at) as last_flag_at
    from flags
    group by tenant_id, officer_id
)

select
    o.tenant_id,
    e.cluster_id,
    e.store_id,
    o.officer_id,
    p.as_of_date,
    90 as window_days,
    o.flags_90d,
    o.open_flags,
    o.distinct_rules,
    o.last_flag_at
from per_officer as o
cross join params as p
inner join {{ ref('dim_employee') }} as e
    on e.employee_id = o.officer_id and e.tenant_id = o.tenant_id
where o.flags_90d >= 2
