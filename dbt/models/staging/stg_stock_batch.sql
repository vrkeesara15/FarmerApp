-- Stock batches. Soft-deleted batches are kept with is_deleted: the API costs a line sold
-- without a batch at the store's average cost over ALL its batches of the SKU (facts._avg_cost),
-- while stock value and stockouts use live batches only.
with src as (
    {{ latest_cdc_rows('stock_batch') }}
)

select
    {{ as_id('id') }} as batch_id,
    {{ as_id('tenant_id') }} as tenant_id,
    {{ as_id('store_id') }} as store_id,
    {{ as_id('sku_id') }} as sku_id,
    cast(expiry as date) as expiry,
    -- on-hand quantity (cache of sum(stock_movement.qty) for the batch)
    cast(qty as {{ dbt.type_numeric() }}) as qty,
    cast(cost_paise as {{ dbt.type_bigint() }}) as cost_paise,
    cast(received_at as {{ dbt.type_timestamp() }}) as received_at,
    deleted_at is not null as is_deleted
from src
