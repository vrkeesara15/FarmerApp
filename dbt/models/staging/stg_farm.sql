-- Farms: declared acreage only; boundary, centroid and survey number are not replicated.
with src as (
    {{ latest_cdc_rows('farm') }}
)

select
    {{ as_id('id') }} as farm_id,
    {{ as_id('tenant_id') }} as tenant_id,
    {{ as_id('farmer_id') }} as farmer_id,
    cast(area_acres as {{ dbt.type_numeric() }}) as area_acres,
    cast(soil as {{ dbt.type_string() }}) as soil,
    cast(irrigation as {{ dbt.type_string() }}) as irrigation,
    cast(ownership as {{ dbt.type_string() }}) as ownership
from src
where deleted_at is null
