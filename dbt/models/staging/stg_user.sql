-- Users (employees and farmer logins) WITHOUT name or phone (AN-014): marts identify people
-- by id only; the console resolves names through the API, under Postgres RLS and audit.
with src as (
    {{ latest_cdc_rows('user') }}
)

select
    {{ as_id('id') }} as user_id,
    {{ as_id('tenant_id') }} as tenant_id,
    cast(role as {{ dbt.type_string() }}) as role,
    {{ as_id('store_id') }} as store_id,
    {{ as_id('cluster_id') }} as cluster_id,
    cast(status as {{ dbt.type_string() }}) as status,
    cast(created_at as {{ dbt.type_timestamp() }}) as created_at
from src
where deleted_at is null
