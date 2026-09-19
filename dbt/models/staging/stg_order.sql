-- Orders. A sale (SPEC 5.2, farmerapp.analytics.facts) is a fulfilled order (handed_over /
-- delivered) dated by placed_at, else created_at, in IST.
with src as (
    {{ latest_cdc_rows('order') }}
),

typed as (
    select
        {{ as_id('id') }} as order_id,
        {{ as_id('tenant_id') }} as tenant_id,
        {{ as_id('farmer_id') }} as farmer_id,
        {{ as_id('store_id') }} as store_id,
        cast(channel as {{ dbt.type_string() }}) as channel,
        cast(status as {{ dbt.type_string() }}) as status,
        cast(subtotal_paise as {{ dbt.type_bigint() }}) as subtotal_paise,
        cast(discount_paise as {{ dbt.type_bigint() }}) as discount_paise,
        cast(tax_paise as {{ dbt.type_bigint() }}) as tax_paise,
        cast(total_paise as {{ dbt.type_bigint() }}) as total_paise,
        {{ as_id('placed_by') }} as placed_by,
        cast(placed_at as {{ dbt.type_timestamp() }}) as placed_at,
        cast(created_at as {{ dbt.type_timestamp() }}) as created_at
    from src
    where deleted_at is null
)

select
    *,
    coalesce(placed_at, created_at) as sold_at,
    {{ ist_date('coalesce(placed_at, created_at)') }} as sold_date,
    status in ('handed_over', 'delivered') as is_fulfilled
from typed
