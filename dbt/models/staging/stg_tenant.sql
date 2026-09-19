-- Tenants with the settings the marts need (farmerapp.tenants.settings defaults applied).
with src as (
    {{ latest_cdc_rows('tenant') }}
)

select
    {{ as_id('id') }} as tenant_id,
    cast(name as {{ dbt.type_string() }}) as tenant_name,
    -- FA-022 due days of a credit sale without a due date or harvest month (default 90).
    coalesce(cast({{ json_text('settings', '$.credit_due_days') }} as {{ dbt.type_int() }}), 90) as credit_due_days,
    cast(created_at as {{ dbt.type_timestamp() }}) as created_at
from src
where deleted_at is null
