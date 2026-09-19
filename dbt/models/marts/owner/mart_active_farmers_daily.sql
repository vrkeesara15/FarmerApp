{{ config(partition_by=bq_date_partition('date_day')) }}

-- SPEC 5.2 "Active farmer": a purchase, a verified visit or an app session in the last 60 days
-- (day - 59 .. day, inclusive; kpi.active_window), counted per tenant for each of the 90 days
-- up to the as-of date (the owner-home trend). Live (not deleted) farmers only.
with params as (
    select {{ as_of_date() }} as as_of_date
),

days as (
    {{ date_series(add_days(as_of_date(), -89), as_of_date()) }}
),

events as (
    select tenant_id, farmer_id, sold_date as event_date
    from {{ ref('stg_order') }}
    where is_fulfilled and farmer_id is not null
    union all
    select tenant_id, farmer_id, visit_date as event_date
    from {{ ref('stg_visit') }}
    where is_verified
    union all
    select tenant_id, farmer_id, session_date as event_date
    from {{ ref('stg_app_session') }}
),

live_events as (
    select distinct e.tenant_id, e.farmer_id, e.event_date
    from events as e
    inner join {{ ref('stg_farmer') }} as f
        on f.farmer_id = e.farmer_id
        and f.tenant_id = e.tenant_id
)

select
    {{ row_key(['t.tenant_id', 'd.date_day']) }} as tenant_day_key,
    t.tenant_id,
    d.date_day,
    60 as active_window_days,
    count(distinct e.farmer_id) as active_farmers
from days as d
cross join {{ ref('stg_tenant') }} as t
left join live_events as e
    on e.tenant_id = t.tenant_id
    and e.event_date <= d.date_day
    and e.event_date >= {{ add_days('d.date_day', -59) }}
group by t.tenant_id, d.date_day
