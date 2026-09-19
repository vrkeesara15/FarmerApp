-- AN-002 field team scorecard: one row per active field officer for the last 30 IST days ending
-- on the as-of date, as farmerapp.analytics.field_team computes it:
--   verified visits per duty day (duty day = IST day with a duty session), unique farmers
--   reached, new registrations, confirmation rate, average time on farm per verified visit,
--   km per duty day, visit conversion, collections (paid, reconciled or cash awaiting the day
--   close), open flags (on the officer or on their visits), rank (verified visits per duty day,
--   then verified visits; 1 = best, per tenant).
with params as (
    select
        {{ as_of_date() }} as as_of_date,
        {{ add_days(as_of_date(), -29) }} as window_start
),

officers as (
    select *
    from {{ ref('dim_employee') }}
    where role = 'field_officer' and status = 'active'
),

visits as (
    select
        v.tenant_id,
        v.officer_id,
        count(*) as visits,
        sum(case when v.is_verified then 1 else 0 end) as verified_visits,
        sum(case when v.is_confirmed then 1 else 0 end) as confirmed_visits,
        count(distinct case when v.is_verified then v.farmer_id end) as unique_farmers_reached,
        count(distinct v.farmer_id) as farmers_visited,
        count(distinct case when v.converted_30d then v.farmer_id end) as farmers_converted,
        sum(v.verified_duration_s) as time_on_farm_s
    from {{ ref('fct_visit') }} as v
    cross join params as p
    where v.date_day between p.window_start and p.as_of_date
    group by v.tenant_id, v.officer_id
),

duty as (
    select
        d.tenant_id,
        d.officer_id,
        count(distinct d.duty_date) as duty_days,
        sum(coalesce(d.km, 0)) as km
    from {{ ref('stg_duty_session') }} as d
    cross join params as p
    where d.duty_date between p.window_start and p.as_of_date
    group by d.tenant_id, d.officer_id
),

registrations as (
    select f.tenant_id, f.registered_by as officer_id, count(*) as registrations
    from {{ ref('stg_farmer') }} as f
    cross join params as p
    where f.registered_by is not null
        and f.registered_date between p.window_start and p.as_of_date
    group by f.tenant_id, f.registered_by
),

collections as (
    select c.tenant_id, c.collected_by as officer_id, sum(c.amount_paise) as collections_paise
    from {{ ref('stg_payment') }} as c
    cross join params as p
    where c.is_received
        and c.collected_by is not null
        and c.received_date between p.window_start and p.as_of_date
    group by c.tenant_id, c.collected_by
),

flag_subjects as (
    select tenant_id, officer_id, is_open
    from {{ ref('int_flag_officer') }}
),

open_flags as (
    select tenant_id, officer_id, sum(case when is_open then 1 else 0 end) as open_flags
    from flag_subjects
    group by tenant_id, officer_id
),

scored as (
    select
        o.tenant_id,
        o.cluster_id,
        o.store_id,
        o.employee_id as officer_id,
        p.as_of_date,
        p.window_start,
        30 as window_days,
        coalesce(v.visits, 0) as visits,
        coalesce(v.verified_visits, 0) as verified_visits,
        coalesce(d.duty_days, 0) as duty_days,
        {{ safe_ratio('v.verified_visits', 'd.duty_days') }} as verified_visits_per_duty_day,
        coalesce(v.unique_farmers_reached, 0) as unique_farmers_reached,
        coalesce(r.registrations, 0) as new_registrations,
        {{ safe_ratio('v.confirmed_visits', 'v.visits') }} as confirmation_rate,
        coalesce(v.time_on_farm_s, 0) as time_on_farm_s,
        case when coalesce(v.verified_visits, 0) = 0 then null
             else cast(round(cast(v.time_on_farm_s as {{ type_double() }}) / v.verified_visits, 0) as {{ dbt.type_bigint() }})
        end as avg_time_on_farm_s,
        cast(coalesce(d.km, 0) as {{ type_double() }}) as km,
        {{ safe_ratio('d.km', 'd.duty_days') }} as km_per_duty_day,
        coalesce(v.farmers_visited, 0) as farmers_visited,
        coalesce(v.farmers_converted, 0) as farmers_converted,
        {{ safe_ratio('v.farmers_converted', 'v.farmers_visited') }} as conversion_rate,
        coalesce(c.collections_paise, 0) as collections_paise,
        coalesce(f.open_flags, 0) as open_flags
    from officers as o
    cross join params as p
    left join visits as v on v.tenant_id = o.tenant_id and v.officer_id = o.employee_id
    left join duty as d on d.tenant_id = o.tenant_id and d.officer_id = o.employee_id
    left join registrations as r on r.tenant_id = o.tenant_id and r.officer_id = o.employee_id
    left join collections as c on c.tenant_id = o.tenant_id and c.officer_id = o.employee_id
    left join open_flags as f on f.tenant_id = o.tenant_id and f.officer_id = o.employee_id
)

select
    *,
    row_number() over (
        partition by tenant_id
        order by coalesce(verified_visits_per_duty_day, -1) desc, verified_visits desc, officer_id
    ) as officer_rank
from scored
