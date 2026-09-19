with src as (
    {{ latest_cdc_rows('day_close') }}
)

select
    {{ as_id('id') }} as day_close_id,
    {{ as_id('tenant_id') }} as tenant_id,
    {{ as_id('store_id') }} as store_id,
    cast(business_date as date) as business_date,
    cast(cash_expected_paise as {{ dbt.type_bigint() }}) as cash_expected_paise,
    cast(cash_counted_paise as {{ dbt.type_bigint() }}) as cash_counted_paise,
    cast(variance_paise as {{ dbt.type_bigint() }}) as variance_paise,
    cast(status as {{ dbt.type_string() }}) as status,
    cast(variance_flagged as {{ dbt.type_boolean() }}) as variance_flagged,
    cast(closed_at as {{ dbt.type_timestamp() }}) as closed_at
from src
where deleted_at is null
