-- AN-005 store performance snapshot, one row per store as of the as-of date
-- (farmerapp.analytics.stores):
--   stock value      live batches' on-hand qty x batch cost
--   stockouts        SKUs the store has stocked (a live batch exists) with zero on hand
--   stock turns      COGS of the last 30 days / current stock value at cost; annualised x 365/30
--   credit book      outstanding, overdue and ageing buckets (mart_credit_accounts)
--   last day close   latest close on or before the as-of date and its variance
with params as (
    select
        {{ as_of_date() }} as as_of_date,
        {{ add_days(as_of_date(), -29) }} as window_start
),

sku_stock as (
    select
        tenant_id,
        store_id,
        sku_id,
        sum(qty) as on_hand,
        sum(qty * cost_paise) as value_paise
    from {{ ref('stg_stock_batch') }}
    where not is_deleted
    group by tenant_id, store_id, sku_id
),

stock as (
    select
        tenant_id,
        store_id,
        sum(value_paise) as stock_value_paise,
        count(*) as stocked_skus,
        sum(case when on_hand <= 0 then 1 else 0 end) as stockout_skus
    from sku_stock
    group by tenant_id, store_id
),

cogs as (
    select s.tenant_id, s.store_id, sum(s.cost_paise) as cogs_paise, sum(s.net_paise) as net_paise
    from {{ ref('fct_sales_line') }} as s
    cross join params as p
    where s.date_day between p.window_start and p.as_of_date
    group by s.tenant_id, s.store_id
),

credit as (
    select
        tenant_id,
        store_id,
        count(*) as open_accounts,
        sum(outstanding_paise) as outstanding_paise,
        sum(overdue_paise) as overdue_paise,
        sum(overdue_0_30_paise) as overdue_0_30_paise,
        sum(overdue_31_60_paise) as overdue_31_60_paise,
        sum(overdue_61_90_paise) as overdue_61_90_paise,
        sum(overdue_90_plus_paise) as overdue_90_plus_paise
    from {{ ref('mart_credit_accounts') }}
    group by tenant_id, store_id
),

closes as (
    select
        c.tenant_id,
        c.store_id,
        c.business_date,
        c.variance_paise,
        row_number() over (partition by c.tenant_id, c.store_id order by c.business_date desc) as recency
    from {{ ref('stg_day_close') }} as c
    cross join params as p
    where c.business_date <= p.as_of_date
),

base as (
    select
        st.tenant_id,
        st.cluster_id,
        st.store_id,
        p.as_of_date,
        30 as turns_window_days,
        {{ paise('sk.stock_value_paise') }} as stock_value_paise,
        coalesce(sk.stocked_skus, 0) as stocked_skus,
        coalesce(sk.stockout_skus, 0) as stockout_skus,
        {{ paise('cg.net_paise') }} as net_sales_30d_paise,
        {{ paise('cg.cogs_paise') }} as cogs_30d_paise,
        coalesce(cr.open_accounts, 0) as open_credit_accounts,
        coalesce(cr.outstanding_paise, 0) as credit_outstanding_paise,
        coalesce(cr.overdue_paise, 0) as credit_overdue_paise,
        coalesce(cr.overdue_0_30_paise, 0) as overdue_0_30_paise,
        coalesce(cr.overdue_31_60_paise, 0) as overdue_31_60_paise,
        coalesce(cr.overdue_61_90_paise, 0) as overdue_61_90_paise,
        coalesce(cr.overdue_90_plus_paise, 0) as overdue_90_plus_paise,
        cl.business_date as last_day_close_date,
        cl.variance_paise as last_day_close_variance_paise
    from {{ ref('dim_store') }} as st
    cross join params as p
    left join stock as sk on sk.tenant_id = st.tenant_id and sk.store_id = st.store_id
    left join cogs as cg on cg.tenant_id = st.tenant_id and cg.store_id = st.store_id
    left join credit as cr on cr.tenant_id = st.tenant_id and cr.store_id = st.store_id
    left join closes as cl on cl.tenant_id = st.tenant_id and cl.store_id = st.store_id and cl.recency = 1
)

select
    *,
    {{ safe_ratio('cogs_30d_paise', 'stock_value_paise') }} as stock_turns_30d,
    {{ safe_ratio('cogs_30d_paise', 'stock_value_paise') }} * 365 / 30 as stock_turns_annualised
from base
