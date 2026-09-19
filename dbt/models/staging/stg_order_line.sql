with src as (
    {{ latest_cdc_rows('order_line') }}
)

select
    {{ as_id('id') }} as order_line_id,
    {{ as_id('tenant_id') }} as tenant_id,
    {{ as_id('order_id') }} as order_id,
    {{ as_id('sku_id') }} as sku_id,
    {{ as_id('batch_id') }} as batch_id,
    cast(qty as {{ dbt.type_numeric() }}) as qty,
    cast(unit_price_paise as {{ dbt.type_bigint() }}) as unit_price_paise,
    -- qty x unit price, pre-GST
    cast(line_total_paise as {{ dbt.type_bigint() }}) as line_total_paise
from src
where deleted_at is null
