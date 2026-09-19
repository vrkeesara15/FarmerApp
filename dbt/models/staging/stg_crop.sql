with src as (
    {{ latest_cdc_rows('crop') }}
)

select
    {{ as_id('id') }} as crop_id,
    {{ as_id('tenant_id') }} as tenant_id,
    cast(code as {{ dbt.type_string() }}) as crop_code,
    cast(name as {{ dbt.type_string() }}) as crop_name
from src
where deleted_at is null
