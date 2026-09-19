-- AN-001 owner home KPI row per tenant for the last 30 IST days ending on the as-of date (the
-- API's default range), SPEC 5.2 definitions as in farmerapp.analytics.kpi:
--   net sales, own-brand share (own-brand net / net), gross margin
--   verified visits (score >= 70), unique farmers reached (distinct farmers with a verified visit)
--   confirmation rate (confirmed / all visits), visit conversion (farmers who bought within 30
--   days after a verified visit / farmers visited), time on farm (verified visits)
--   active farmers (as of the as-of date), credit outstanding / overdue (as of), open flags now
-- Distinct counts are not additive, so this is computed from the facts, not from the daily marts.
with params as (
    select
        {{ as_of_date() }} as as_of_date,
        {{ add_days(as_of_date(), -29) }} as window_start
),

sales as (
    select
        s.tenant_id,
        count(distinct s.order_id) as orders,
        sum(s.net_paise) as net_paise,
        sum(case when s.own_brand then s.net_paise else 0 end) as own_brand_net_paise,
        sum(s.cost_paise) as cogs_paise
    from {{ ref('fct_sales_line') }} as s
    cross join params as p
    where s.date_day between p.window_start and p.as_of_date
    group by s.tenant_id
),

visits as (
    select
        v.tenant_id,
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
    group by v.tenant_id
),

credit as (
    select
        tenant_id,
        sum(outstanding_paise) as outstanding_paise,
        sum(overdue_paise) as overdue_paise
    from {{ ref('mart_credit_accounts') }}
    group by tenant_id
),

flags as (
    select
        tenant_id,
        sum(case when is_open then 1 else 0 end) as open_flags,
        sum(case when is_open and severity = 'high' then 1 else 0 end) as open_high_flags
    from {{ ref('stg_flag') }}
    group by tenant_id
),

active as (
    select a.tenant_id, a.active_farmers
    from {{ ref('mart_active_farmers_daily') }} as a
    cross join params as p
    where a.date_day = p.as_of_date
)

select
    t.tenant_id,
    p.as_of_date,
    p.window_start,
    30 as window_days,
    coalesce(s.orders, 0) as orders,
    {{ paise('s.net_paise') }} as net_sales_paise,
    {{ paise('s.own_brand_net_paise') }} as own_brand_net_paise,
    {{ safe_ratio('s.own_brand_net_paise', 's.net_paise') }} as own_brand_share,
    {{ paise('s.net_paise') }} - {{ paise('s.cogs_paise') }} as gross_margin_paise,
    coalesce(v.visits, 0) as visits,
    coalesce(v.verified_visits, 0) as verified_visits,
    coalesce(v.unique_farmers_reached, 0) as unique_farmers_reached,
    {{ safe_ratio('v.confirmed_visits', 'v.visits') }} as confirmation_rate,
    coalesce(v.farmers_visited, 0) as farmers_visited,
    coalesce(v.farmers_converted, 0) as farmers_converted,
    {{ safe_ratio('v.farmers_converted', 'v.farmers_visited') }} as visit_conversion_rate,
    coalesce(v.time_on_farm_s, 0) as time_on_farm_s,
    coalesce(a.active_farmers, 0) as active_farmers,
    coalesce(c.outstanding_paise, 0) as credit_outstanding_paise,
    coalesce(c.overdue_paise, 0) as credit_overdue_paise,
    coalesce(f.open_flags, 0) as open_flags,
    coalesce(f.open_high_flags, 0) as open_high_flags
from {{ ref('stg_tenant') }} as t
cross join params as p
left join sales as s on s.tenant_id = t.tenant_id
left join visits as v on v.tenant_id = t.tenant_id
left join credit as c on c.tenant_id = t.tenant_id
left join flags as f on f.tenant_id = t.tenant_id
left join active as a on a.tenant_id = t.tenant_id
