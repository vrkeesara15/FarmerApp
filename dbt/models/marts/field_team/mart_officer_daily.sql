{{ config(partition_by=bq_date_partition('date_day')) }}

-- AN-002 per field officer and IST day (trend / sparkline grain): visits, verified visits,
-- confirmations, farmers visited / reached that day, time on farm, duty day and km,
-- registrations and collections. Period figures with distinct counts come from
-- mart_officer_scorecard_30d, not from summing these rows.
with params as (
    select {{ as_of_date() }} as as_of_date
),

visits as (
    select
        tenant_id,
        officer_id,
        date_day,
        count(*) as visits,
        sum(case when is_verified then 1 else 0 end) as verified_visits,
        sum(case when is_confirmed then 1 else 0 end) as confirmed_visits,
        count(distinct farmer_id) as farmers_visited,
        count(distinct case when is_verified then farmer_id end) as farmers_reached,
        sum(verified_duration_s) as time_on_farm_s
    from {{ ref('fct_visit') }}
    group by tenant_id, officer_id, date_day
),

duty as (
    select
        tenant_id,
        officer_id,
        duty_date as date_day,
        sum(coalesce(km, 0)) as km
    from {{ ref('stg_duty_session') }}
    group by tenant_id, officer_id, duty_date
),

registrations as (
    select
        tenant_id,
        registered_by as officer_id,
        registered_date as date_day,
        count(*) as registrations
    from {{ ref('stg_farmer') }}
    where registered_by is not null
    group by tenant_id, registered_by, registered_date
),

collections as (
    select
        tenant_id,
        collected_by as officer_id,
        received_date as date_day,
        sum(amount_paise) as collections_paise
    from {{ ref('stg_payment') }}
    where is_received and collected_by is not null
    group by tenant_id, collected_by, received_date
),

keys as (
    select distinct tenant_id, officer_id, date_day
    from (
        select tenant_id, officer_id, date_day from visits
        union all
        select tenant_id, officer_id, date_day from duty
        union all
        select tenant_id, officer_id, date_day from registrations
        union all
        select tenant_id, officer_id, date_day from collections
    ) as k
)

select
    {{ row_key(['k.officer_id', 'k.date_day']) }} as officer_day_key,
    k.tenant_id,
    e.cluster_id,
    e.store_id,
    k.officer_id,
    k.date_day,
    coalesce(v.visits, 0) as visits,
    coalesce(v.verified_visits, 0) as verified_visits,
    coalesce(v.confirmed_visits, 0) as confirmed_visits,
    coalesce(v.farmers_visited, 0) as farmers_visited,
    coalesce(v.farmers_reached, 0) as farmers_reached,
    coalesce(v.time_on_farm_s, 0) as time_on_farm_s,
    d.date_day is not null as on_duty,
    cast(coalesce(d.km, 0) as {{ type_double() }}) as km,
    coalesce(r.registrations, 0) as registrations,
    coalesce(c.collections_paise, 0) as collections_paise
from keys as k
cross join params as p
inner join {{ ref('dim_employee') }} as e
    on e.employee_id = k.officer_id
    and e.tenant_id = k.tenant_id
left join visits as v
    on v.tenant_id = k.tenant_id and v.officer_id = k.officer_id and v.date_day = k.date_day
left join duty as d
    on d.tenant_id = k.tenant_id and d.officer_id = k.officer_id and d.date_day = k.date_day
left join registrations as r
    on r.tenant_id = k.tenant_id and r.officer_id = k.officer_id and r.date_day = k.date_day
left join collections as c
    on c.tenant_id = k.tenant_id and c.officer_id = k.officer_id and c.date_day = k.date_day
where k.date_day <= p.as_of_date
