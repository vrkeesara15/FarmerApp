-- Duty sessions (FA-010): times and km only. Start / end points and stops are not replicated.
with src as (
    {{ latest_cdc_rows('duty_session') }}
),

typed as (
    select
        {{ as_id('id') }} as duty_session_id,
        {{ as_id('tenant_id') }} as tenant_id,
        {{ as_id('officer_id') }} as officer_id,
        cast(start_at as {{ dbt.type_timestamp() }}) as start_at,
        cast(end_at as {{ dbt.type_timestamp() }}) as end_at,
        cast(km as {{ dbt.type_numeric() }}) as km,
        cast(end_reason as {{ dbt.type_string() }}) as end_reason
    from src
    where deleted_at is null
)

select
    *,
    {{ ist_date('start_at') }} as duty_date
from typed
