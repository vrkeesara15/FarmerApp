-- AN-004 farmer 360 and segments: one row per live farmer as of the as-of date. Identified by
-- farmer_id and the masked phone only (AN-014): the console opens the full profile (name,
-- phone) through the API, which audits PII access.
--
--   ltv_paise            SPEC 5.2 Farmer LTV = cumulative gross margin (net sales - cost of goods)
--   is_active            SPEC 5.2 active farmer (purchase, verified visit or app session in the
--                        last 60 days)
--   credit_risk          kpi.credit_risk over the farmer's khata accounts (worst account)
--   segment              new           registered in the last 60 days
--                        active_buyer  bought in the last 60 days
--                        engaged       active (visit / app) without a purchase in 60 days
--                        lapsed        activity before, none in the last 60 days
--                        dormant       never any activity
--   churn_risk           days since the last activity: <= 30 low, 31-60 medium, > 60 high;
--                        no activity yet: low while new, else high
-- Segment and churn thresholds are FarmerApp's working definitions (SPEC 5.1 names the list,
-- not the rule); change them here and in docs/SPEC.md together.
with params as (
    select
        {{ as_of_date() }} as as_of_date,
        {{ add_days(as_of_date(), -59) }} as active_start
),

farmers as (
    select
        f.farmer_id,
        f.tenant_id,
        f.village_id,
        f.phone_masked,
        f.language,
        f.source,
        f.user_id,
        f.registered_by,
        f.registered_date,
        vl.district,
        vl.store_id,
        st.cluster_id
    from {{ ref('stg_farmer') }} as f
    cross join params as p
    left join {{ ref('stg_village') }} as vl
        on vl.village_id = f.village_id and vl.tenant_id = f.tenant_id
    left join {{ ref('dim_store') }} as st
        on st.store_id = vl.store_id and st.tenant_id = f.tenant_id
    where f.registered_date <= p.as_of_date
),

acreage as (
    select tenant_id, farmer_id, sum(area_acres) as acreage
    from {{ ref('stg_farm') }}
    group by tenant_id, farmer_id
),

plots as (
    select
        fm.tenant_id,
        fm.farmer_id,
        cp.crop_id,
        cp.stage,
        row_number() over (
            partition by fm.tenant_id, fm.farmer_id
            order by cp.sowing_date desc, cp.crop_plot_id desc
        ) as recency
    from {{ ref('stg_crop_plot') }} as cp
    inner join {{ ref('stg_farm') }} as fm
        on fm.farm_id = cp.farm_id and fm.tenant_id = cp.tenant_id
),

crops as (
    select
        tenant_id,
        farmer_id,
        count(distinct crop_id) as crops,
        max(case when recency = 1 then crop_id end) as current_crop_id,
        max(case when recency = 1 then stage end) as current_stage
    from plots
    group by tenant_id, farmer_id
),

sales as (
    select
        s.tenant_id,
        s.farmer_id,
        max(s.sold_at) as last_purchase_at,
        max(s.date_day) as last_purchase_date,
        sum(s.net_paise) as net_paise,
        sum(s.margin_paise) as margin_paise
    from {{ ref('fct_sales_line') }} as s
    cross join params as p
    where s.farmer_id is not null and s.date_day <= p.as_of_date
    group by s.tenant_id, s.farmer_id
),

visits as (
    select
        v.tenant_id,
        v.farmer_id,
        max(v.checkin_at) as last_visit_at,
        max(case when v.is_verified then v.date_day end) as last_verified_visit_date
    from {{ ref('fct_visit') }} as v
    cross join params as p
    where v.date_day <= p.as_of_date
    group by v.tenant_id, v.farmer_id
),

sessions as (
    select
        a.tenant_id,
        a.farmer_id,
        max(a.session_at) as last_app_session_at,
        max(a.session_date) as last_app_session_date
    from {{ ref('stg_app_session') }} as a
    cross join params as p
    where a.session_date <= p.as_of_date
    group by a.tenant_id, a.farmer_id
),

credit as (
    select
        tenant_id,
        farmer_id,
        sum(outstanding_paise) as outstanding_paise,
        sum(overdue_paise) as overdue_paise,
        max(case credit_risk when 'high' then 3 when 'medium' then 2 else 1 end) as risk_rank
    from {{ ref('mart_credit_accounts') }}
    group by tenant_id, farmer_id
),

joined as (
    select
        f.*,
        p.as_of_date,
        p.active_start,
        a.acreage,
        c.crops,
        c.current_crop_id,
        c.current_stage,
        s.last_purchase_at,
        s.last_purchase_date,
        s.net_paise,
        s.margin_paise,
        v.last_visit_at,
        v.last_verified_visit_date,
        se.last_app_session_at,
        se.last_app_session_date,
        cr.outstanding_paise,
        cr.overdue_paise,
        cr.risk_rank,
        -- the latest of the three "active" events
        case
            when s.last_purchase_date is null and v.last_verified_visit_date is null and se.last_app_session_date is null then null
            else greatest(
                coalesce(s.last_purchase_date, cast('1900-01-01' as date)),
                coalesce(v.last_verified_visit_date, cast('1900-01-01' as date)),
                coalesce(se.last_app_session_date, cast('1900-01-01' as date))
            )
        end as last_activity_date
    from farmers as f
    cross join params as p
    left join acreage as a on a.tenant_id = f.tenant_id and a.farmer_id = f.farmer_id
    left join crops as c on c.tenant_id = f.tenant_id and c.farmer_id = f.farmer_id
    left join sales as s on s.tenant_id = f.tenant_id and s.farmer_id = f.farmer_id
    left join visits as v on v.tenant_id = f.tenant_id and v.farmer_id = f.farmer_id
    left join sessions as se on se.tenant_id = f.tenant_id and se.farmer_id = f.farmer_id
    left join credit as cr on cr.tenant_id = f.tenant_id and cr.farmer_id = f.farmer_id
),

classified as (
    select
        *,
        coalesce(last_activity_date >= active_start, false) as is_active,
        case when last_activity_date is null then null
             else {{ days_between('last_activity_date', 'as_of_date') }} end as days_since_last_activity,
        case
            when registered_date >= active_start then 'new'
            when last_purchase_date >= active_start then 'active_buyer'
            when last_activity_date >= active_start then 'engaged'
            when last_activity_date is not null then 'lapsed'
            else 'dormant'
        end as segment
    from joined
)

select
    farmer_id,
    tenant_id,
    cluster_id,
    store_id,
    village_id,
    district,
    phone_masked,
    language,
    source,
    registered_by,
    registered_date,
    as_of_date,
    coalesce(acreage, 0) as acreage,
    coalesce(crops, 0) as crops,
    current_crop_id,
    current_stage,
    user_id is not null as app_user,
    last_visit_at,
    last_purchase_at,
    last_app_session_at,
    last_activity_date,
    days_since_last_activity,
    {{ paise('net_paise') }} as lifetime_net_sales_paise,
    {{ paise('margin_paise') }} as ltv_paise,
    coalesce(outstanding_paise, 0) as credit_outstanding_paise,
    coalesce(overdue_paise, 0) as credit_overdue_paise,
    case coalesce(risk_rank, 1) when 3 then 'high' when 2 then 'medium' else 'low' end as credit_risk,
    is_active,
    segment,
    case
        when last_activity_date is null then case when segment = 'new' then 'low' else 'high' end
        when days_since_last_activity > 60 then 'high'
        when days_since_last_activity > 30 then 'medium'
        else 'low'
    end as churn_risk
from classified
