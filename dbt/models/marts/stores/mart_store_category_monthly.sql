{{ config(partition_by=bq_date_partition('month_start')) }}

-- AN-005 sales by category and brand per store and IST month: net sales, COGS, gross margin
-- and margin %, own brand vs multi-brand (product.own_brand). Months up to the as-of date.
with params as (
    select {{ as_of_date() }} as as_of_date
),

lines as (
    select
        s.*,
        {{ month_start('s.date_day') }} as month_start
    from {{ ref('fct_sales_line') }} as s
    cross join params as p
    where s.date_day <= p.as_of_date
),

grouped as (
    select
        tenant_id,
        cluster_id,
        store_id,
        month_start,
        category,
        coalesce(brand, 'unknown') as brand,
        own_brand,
        count(distinct order_id) as orders,
        sum(qty) as qty,
        sum(net_paise) as net_paise,
        sum(cost_paise) as cost_paise
    from lines
    group by tenant_id, cluster_id, store_id, month_start, category, coalesce(brand, 'unknown'), own_brand
)

select
    {{ row_key(['store_id', 'month_start', 'category', 'brand', 'own_brand']) }} as store_category_month_key,
    tenant_id,
    cluster_id,
    store_id,
    month_start,
    category,
    brand,
    own_brand,
    orders,
    qty,
    {{ paise('net_paise') }} as net_sales_paise,
    {{ paise('cost_paise') }} as cogs_paise,
    {{ paise('net_paise') }} - {{ paise('cost_paise') }} as gross_margin_paise,
    {{ safe_ratio(paise('net_paise') ~ ' - ' ~ paise('cost_paise'), paise('net_paise')) }} as margin_pct
from grouped
