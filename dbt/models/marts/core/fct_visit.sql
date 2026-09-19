{{ config(partition_by=bq_date_partition('date_day')) }}

-- One row per visit with the SPEC 5.2 flags (farmerapp.analytics.kpi):
--   is_verified          score >= 70 (VV-004)
--   is_confirmed         confirmed by the farmer (confirmed_at set)
--   verified_duration_s  check-in -> check-out of a verified visit ("time on farm"), else 0
--   converted_30d        verified visit followed by a sale to the farmer (any store) in
--                        (check-in, check-in + 30 days]: after, not at, the check-in
with visits as (
    select * from {{ ref('stg_visit') }}
),

purchases as (
    select tenant_id, farmer_id, sold_at
    from {{ ref('stg_order') }}
    where is_fulfilled and farmer_id is not null
),

converted as (
    select distinct v.visit_id
    from visits as v
    inner join purchases as p
        on p.tenant_id = v.tenant_id
        and p.farmer_id = v.farmer_id
        and p.sold_at > v.checkin_at
        and p.sold_at <= {{ ts_add_days('v.checkin_at', 30) }}
    where v.is_verified
)

select
    v.visit_id,
    v.tenant_id,
    v.officer_id,
    e.store_id,
    e.cluster_id,
    v.farmer_id,
    v.visit_date as date_day,
    v.purpose,
    v.checkin_at,
    v.checkout_at,
    v.score,
    v.status,
    v.is_verified,
    v.is_confirmed,
    v.duration_s,
    case when v.is_verified then coalesce(v.duration_s, 0) else 0 end as verified_duration_s,
    c.visit_id is not null as converted_30d
from visits as v
left join {{ ref('dim_employee') }} as e
    on e.employee_id = v.officer_id
    and e.tenant_id = v.tenant_id
left join converted as c
    on c.visit_id = v.visit_id
