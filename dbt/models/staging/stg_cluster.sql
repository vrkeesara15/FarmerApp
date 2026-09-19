with src as (
    {{ latest_cdc_rows('cluster') }}
)

select
    {{ as_id('id') }} as cluster_id,
    {{ as_id('tenant_id') }} as tenant_id,
    cast(name as {{ dbt.type_string() }}) as cluster_name,
    cast(district as {{ dbt.type_string() }}) as district,
    cast(state as {{ dbt.type_string() }}) as state
from src
where deleted_at is null
