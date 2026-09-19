-- SKUs are kept even when soft-deleted: old sales still need their product attributes
-- (the API's sku_attributes() does not filter deleted SKUs either).
with src as (
    {{ latest_cdc_rows('sku') }}
)

select
    {{ as_id('id') }} as sku_id,
    {{ as_id('tenant_id') }} as tenant_id,
    {{ as_id('product_id') }} as product_id,
    cast(mrp_paise as {{ dbt.type_bigint() }}) as mrp_paise,
    deleted_at is not null as is_deleted
from src
