-- Flag history (append-only). Notes are not replicated; the resolution label feeds the
-- true / false positive rates of AN-009.
with src as (
    {{ latest_cdc_rows('flag_event') }}
)

select
    {{ as_id('id') }} as flag_event_id,
    {{ as_id('tenant_id') }} as tenant_id,
    {{ as_id('flag_id') }} as flag_id,
    cast(kind as {{ dbt.type_string() }}) as kind,
    cast(to_status as {{ dbt.type_string() }}) as to_status,
    cast(label as {{ dbt.type_string() }}) as label,
    cast(created_at as {{ dbt.type_timestamp() }}) as created_at
from src
