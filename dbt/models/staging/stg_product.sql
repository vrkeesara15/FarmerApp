-- Products are kept even when soft-deleted (is_deleted): past sales keep their own-brand flag
-- and category, as in the API's sku_attributes().
with src as (
    {{ latest_cdc_rows('product') }}
)

select
    {{ as_id('id') }} as product_id,
    {{ as_id('tenant_id') }} as tenant_id,
    cast(brand as {{ dbt.type_string() }}) as brand,
    cast(own_brand as {{ dbt.type_boolean() }}) as own_brand,
    cast(category as {{ dbt.type_string() }}) as category,
    deleted_at is not null as is_deleted
from src
