{{ config(partition_by=bq_date_partition('date_day')) }}

-- AN-001 / AN-005 per store and IST day: sales (gross, discounts, net, own brand, COGS, gross
-- margin), damage write-offs at batch cost, contribution and the day close. One row per store
-- and day with any sale, write-off or day close, up to the as-of date.
with params as (
    select {{ as_of_date() }} as as_of_date
),

sales as (
    select
        tenant_id,
        store_id,
        date_day,
        count(distinct order_id) as orders,
        sum(gross_paise) as gross_paise,
        sum(discount_paise) as discount_paise,
        sum(net_paise) as net_paise,
        sum(case when own_brand then net_paise else 0 end) as own_brand_net_paise,
        sum(cost_paise) as cogs_paise
    from {{ ref('fct_sales_line') }}
    group by tenant_id, store_id, date_day
),

write_offs as (
    select
        m.tenant_id,
        m.store_id,
        m.movement_date as date_day,
        sum(-m.qty * coalesce(b.cost_paise, 0)) as write_off_paise
    from {{ ref('stg_stock_movement') }} as m
    left join {{ ref('stg_stock_batch') }} as b
        on b.batch_id = m.batch_id
        and b.tenant_id = m.tenant_id
    where m.kind = 'damage'
    group by m.tenant_id, m.store_id, m.movement_date
),

closes as (
    select
        tenant_id,
        store_id,
        business_date as date_day,
        variance_paise,
        variance_flagged
    from {{ ref('stg_day_close') }}
),

keys as (
    select distinct tenant_id, store_id, date_day
    from (
        select tenant_id, store_id, date_day from sales
        union all
        select tenant_id, store_id, date_day from write_offs
        union all
        select tenant_id, store_id, date_day from closes
    ) as k
)

select
    {{ row_key(['k.store_id', 'k.date_day']) }} as store_day_key,
    k.tenant_id,
    st.cluster_id,
    k.store_id,
    k.date_day,
    coalesce(s.orders, 0) as orders,
    {{ paise('s.gross_paise') }} as gross_sales_paise,
    {{ paise('s.discount_paise') }} as discount_paise,
    {{ paise('s.net_paise') }} as net_sales_paise,
    {{ paise('s.own_brand_net_paise') }} as own_brand_net_paise,
    {{ safe_ratio('s.own_brand_net_paise', 's.net_paise') }} as own_brand_share,
    {{ paise('s.cogs_paise') }} as cogs_paise,
    {{ paise('s.net_paise') }} - {{ paise('s.cogs_paise') }} as gross_margin_paise,
    {{ paise('w.write_off_paise') }} as write_off_paise,
    {{ paise('s.net_paise') }} - {{ paise('s.cogs_paise') }} - {{ paise('w.write_off_paise') }} as contribution_paise,
    c.variance_paise as day_close_variance_paise,
    c.variance_flagged as day_close_variance_flagged
from keys as k
cross join params as p
left join sales as s
    on s.tenant_id = k.tenant_id and s.store_id = k.store_id and s.date_day = k.date_day
left join write_offs as w
    on w.tenant_id = k.tenant_id and w.store_id = k.store_id and w.date_day = k.date_day
left join closes as c
    on c.tenant_id = k.tenant_id and c.store_id = k.store_id and c.date_day = k.date_day
left join {{ ref('dim_store') }} as st
    on st.store_id = k.store_id and st.tenant_id = k.tenant_id
where k.date_day <= p.as_of_date
