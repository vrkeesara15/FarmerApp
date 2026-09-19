-- Visits. Check-in / check-out points, notes and override notes are not replicated (AN-014):
-- the marts need scores and times, not locations.
-- SPEC 5.2 / VV-004: a verified visit has score >= 70 (farmerapp.visits.scoring.VERIFIED_MIN).
with src as (
    {{ latest_cdc_rows('visit') }}
),

typed as (
    select
        {{ as_id('id') }} as visit_id,
        {{ as_id('tenant_id') }} as tenant_id,
        {{ as_id('officer_id') }} as officer_id,
        {{ as_id('farmer_id') }} as farmer_id,
        {{ as_id('farm_id') }} as farm_id,
        {{ as_id('village_id') }} as village_id,
        cast(purpose as {{ dbt.type_string() }}) as purpose,
        cast(checkin_at as {{ dbt.type_timestamp() }}) as checkin_at,
        cast(checkout_at as {{ dbt.type_timestamp() }}) as checkout_at,
        cast(geofence_result as {{ dbt.type_string() }}) as geofence_result,
        cast(crop_stage as {{ dbt.type_string() }}) as crop_stage,
        cast(score as {{ dbt.type_int() }}) as score,
        cast(status as {{ dbt.type_string() }}) as status,
        cast(confirmation_channel as {{ dbt.type_string() }}) as confirmation_channel,
        cast(confirmed_at as {{ dbt.type_timestamp() }}) as confirmed_at
    from src
    where deleted_at is null
)

select
    *,
    {{ ist_date('checkin_at') }} as visit_date,
    coalesce(score >= 70, false) as is_verified,
    confirmed_at is not null as is_confirmed,
    case
        when checkout_at is null then null
        when {{ seconds_between('checkin_at', 'checkout_at') }} < 0 then 0
        else {{ seconds_between('checkin_at', 'checkout_at') }}
    end as duration_s
from typed
