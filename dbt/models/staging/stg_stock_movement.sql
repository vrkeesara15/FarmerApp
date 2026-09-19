-- Stock movements (append-only: no soft delete). Photos and notes are not replicated.
with src as (
    {{ latest_cdc_rows('stock_movement') }}
)

select
    {{ as_id('id') }} as stock_movement_id,
    {{ as_id('tenant_id') }} as tenant_id,
    {{ as_id('store_id') }} as store_id,
    {{ as_id('sku_id') }} as sku_id,
    {{ as_id('batch_id') }} as batch_id,
    cast(kind as {{ dbt.type_string() }}) as kind,
    -- signed delta
    cast(qty as {{ dbt.type_numeric() }}) as qty,
    cast(created_at as {{ dbt.type_timestamp() }}) as created_at,
    {{ ist_date('cast(created_at as ' ~ dbt.type_timestamp() ~ ')') }} as movement_date
from src
