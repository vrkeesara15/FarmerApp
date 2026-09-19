{{ config(partition_by=bq_date_partition('date_day')) }}

-- One row per order line of a SALE (fulfilled order: handed_over / delivered), the fact every
-- sales KPI is built on. Mirrors farmerapp.analytics.facts.sales_lines_where:
--   net   = pre-GST line total less its pro-rata share of the order discount
--   cost  = qty x the sold batch's cost, else the store's average batch cost of the SKU, else 0
--   day   = IST date of placed_at, else created_at
-- Money columns stay fractional here (pro-rata discounts); marts round each sum once.
with orders as (
    select * from {{ ref('stg_order') }} where is_fulfilled
),

avg_cost as (
    select
        tenant_id,
        store_id,
        sku_id,
        avg(cast(cost_paise as {{ dbt.type_numeric() }})) as avg_cost_paise
    from {{ ref('stg_stock_batch') }}
    group by tenant_id, store_id, sku_id
),

skus as (
    select
        k.sku_id,
        k.tenant_id,
        k.product_id,
        p.own_brand,
        p.category,
        p.brand
    from {{ ref('stg_sku') }} as k
    left join {{ ref('stg_product') }} as p
        on p.product_id = k.product_id
        and p.tenant_id = k.tenant_id
),

lines as (
    select
        l.order_line_id as sales_line_id,
        o.order_id,
        o.tenant_id,
        o.store_id,
        st.cluster_id,
        o.farmer_id,
        o.placed_by,
        o.channel,
        o.sold_at,
        o.sold_date as date_day,
        l.sku_id,
        k.product_id,
        coalesce(k.own_brand, false) as own_brand,
        coalesce(k.category, 'other') as category,
        k.brand,
        l.qty,
        l.line_total_paise as gross_paise,
        case
            when o.subtotal_paise = 0 then cast(0 as {{ dbt.type_numeric() }})
            else cast(o.discount_paise as {{ dbt.type_numeric() }}) * l.line_total_paise / o.subtotal_paise
        end as discount_paise,
        l.qty * coalesce(cast(b.cost_paise as {{ dbt.type_numeric() }}), a.avg_cost_paise, 0) as cost_paise
    from orders as o
    inner join {{ ref('stg_order_line') }} as l
        on l.order_id = o.order_id
        and l.tenant_id = o.tenant_id
    left join {{ ref('stg_stock_batch') }} as b
        on b.batch_id = l.batch_id
        and b.tenant_id = l.tenant_id
    left join avg_cost as a
        on a.tenant_id = o.tenant_id
        and a.store_id = o.store_id
        and a.sku_id = l.sku_id
    left join skus as k
        on k.sku_id = l.sku_id
        and k.tenant_id = l.tenant_id
    left join {{ ref('dim_store') }} as st
        on st.store_id = o.store_id
        and st.tenant_id = o.tenant_id
)

select
    *,
    gross_paise - discount_paise as net_paise,
    gross_paise - discount_paise - cost_paise as margin_paise
from lines
