-- App sessions of FARMERS (SPEC 5.2 "active farmer"): the API's proxy is a refresh token
-- issued to the farmer's own login (the farmer app refreshes on every launch; no session table
-- until P1 analytics events). Only id, tenant, user and time of refresh_token are replicated:
-- never token hashes or device ids.
with src as (
    {{ latest_cdc_rows('refresh_token') }}
),

tokens as (
    select
        {{ as_id('id') }} as refresh_token_id,
        {{ as_id('tenant_id') }} as tenant_id,
        {{ as_id('user_id') }} as user_id,
        cast(created_at as {{ dbt.type_timestamp() }}) as created_at
    from src
)

select
    t.refresh_token_id as app_session_id,
    t.tenant_id,
    f.farmer_id,
    t.created_at as session_at,
    {{ ist_date('t.created_at') }} as session_date
from tokens as t
inner join {{ ref('stg_farmer') }} as f
    on f.user_id = t.user_id
    and f.tenant_id = t.tenant_id
