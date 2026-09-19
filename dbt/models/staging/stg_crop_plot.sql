with src as (
    {{ latest_cdc_rows('crop_plot') }}
)

select
    {{ as_id('id') }} as crop_plot_id,
    {{ as_id('tenant_id') }} as tenant_id,
    {{ as_id('farm_id') }} as farm_id,
    {{ as_id('crop_id') }} as crop_id,
    cast(season as {{ dbt.type_string() }}) as season,
    cast(sowing_date as date) as sowing_date,
    cast(stage as {{ dbt.type_string() }}) as stage,
    cast(expected_harvest as date) as expected_harvest,
    cast(area_acres as {{ dbt.type_numeric() }}) as area_acres,
    cast(created_at as {{ dbt.type_timestamp() }}) as created_at
from src
where deleted_at is null
