-- Campaigns (WC-008, AN-008). The message text, the segment definition, the campaign notes
-- and the DLT / WhatsApp template body are NOT replicated (AN-014): ids, channel, status and
-- the attribution / holdout settings only, which is everything mart_campaign_roi needs.
with src as (
    {{ latest_cdc_rows('campaign') }}
),

typed as (
    select
        {{ as_id('id') }} as campaign_id,
        {{ as_id('tenant_id') }} as tenant_id,
        cast(channel as {{ dbt.type_string() }}) as channel,
        cast(status as {{ dbt.type_string() }}) as status,
        cast(template_key as {{ dbt.type_string() }}) as template_key,
        cast(attribution_days as {{ dbt.type_bigint() }}) as attribution_days,
        cast(holdout_pct as {{ dbt.type_bigint() }}) as holdout_pct,
        cast(audience_size as {{ dbt.type_bigint() }}) as audience_size,
        {{ as_id('created_by') }} as created_by,
        cast(scheduled_at as {{ dbt.type_timestamp() }}) as scheduled_at,
        cast(started_at as {{ dbt.type_timestamp() }}) as started_at,
        cast(finished_at as {{ dbt.type_timestamp() }}) as finished_at,
        cast(created_at as {{ dbt.type_timestamp() }}) as created_at
    from src
    where deleted_at is null
)

select
    *,
    case when started_at is not null then {{ ist_date('started_at') }} end as started_date
from typed
