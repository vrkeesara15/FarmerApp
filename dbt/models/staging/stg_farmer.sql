-- Farmers, PII-minimised (AN-014): no name, no phone, no landmark. The phone survives only
-- as the masked form the console shows without PII access (9 stars + last 4 digits).
with src as (
    {{ latest_cdc_rows('farmer') }}
)

select
    {{ as_id('id') }} as farmer_id,
    {{ as_id('tenant_id') }} as tenant_id,
    {{ as_id('village_id') }} as village_id,
    {{ mask_phone_last4('cast(phone_last4 as ' ~ dbt.type_string() ~ ')') }} as phone_masked,
    cast(language as {{ dbt.type_string() }}) as language,
    cast(consent_marketing as {{ dbt.type_boolean() }}) as consent_marketing,
    cast(phone_verified as {{ dbt.type_boolean() }}) as phone_verified,
    {{ as_id('registered_by') }} as registered_by,
    {{ as_id('user_id') }} as user_id,
    cast(source as {{ dbt.type_string() }}) as source,
    cast(land_ownership as {{ dbt.type_string() }}) as land_ownership,
    cast(created_at as {{ dbt.type_timestamp() }}) as created_at,
    {{ ist_date('cast(created_at as ' ~ dbt.type_timestamp() ~ ')') }} as registered_date
from src
where deleted_at is null
