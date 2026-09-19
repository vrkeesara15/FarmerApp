-- Villages: the farmer's home store (village.store_id) scopes farmers to a store / cluster.
-- Location columns (location, meeting_point) are not replicated (AN-014).
with src as (
    {{ latest_cdc_rows('village') }}
)

select
    {{ as_id('id') }} as village_id,
    {{ as_id('tenant_id') }} as tenant_id,
    {{ as_id('store_id') }} as store_id,
    cast(name as {{ dbt.type_string() }}) as village_name,
    cast(mandal as {{ dbt.type_string() }}) as mandal,
    cast(district as {{ dbt.type_string() }}) as district,
    cast(state as {{ dbt.type_string() }}) as state
from src
where deleted_at is null
