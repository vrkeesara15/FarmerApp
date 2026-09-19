with src as (
    {{ latest_cdc_rows('store') }}
)

select
    {{ as_id('id') }} as store_id,
    {{ as_id('tenant_id') }} as tenant_id,
    {{ as_id('cluster_id') }} as cluster_id,
    cast(code as {{ dbt.type_string() }}) as store_code,
    cast(name as {{ dbt.type_string() }}) as store_name,
    cast(district as {{ dbt.type_string() }}) as district,
    cast(state as {{ dbt.type_string() }}) as state
from src
where deleted_at is null
