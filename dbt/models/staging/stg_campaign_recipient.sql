-- One row per farmer of a scheduled campaign (WC-008, AN-008): the arm (target / holdout),
-- the delivery status and the send / delivery / open timestamps. The provider reference, the
-- DLT template id, the push notification id and the provider error string are NOT replicated
-- (AN-014); the farmer is identified by farmer_id only.
with src as (
    {{ latest_cdc_rows('campaign_recipient') }}
),

typed as (
    select
        {{ as_id('id') }} as campaign_recipient_id,
        {{ as_id('tenant_id') }} as tenant_id,
        {{ as_id('campaign_id') }} as campaign_id,
        {{ as_id('farmer_id') }} as farmer_id,
        cast(arm as {{ dbt.type_string() }}) as arm,
        cast(language as {{ dbt.type_string() }}) as language,
        cast(status as {{ dbt.type_string() }}) as status,
        cast(skip_reason as {{ dbt.type_string() }}) as skip_reason,
        cast(sent_at as {{ dbt.type_timestamp() }}) as sent_at,
        cast(delivered_at as {{ dbt.type_timestamp() }}) as delivered_at,
        cast(opened_at as {{ dbt.type_timestamp() }}) as opened_at,
        cast(created_at as {{ dbt.type_timestamp() }}) as created_at
    from src
    where deleted_at is null
)

select
    *,
    -- campaigns.service.SENT_STATUSES: the message left FarmerApp (a delivery receipt may or
    -- may not have come back). Everything else (pending, failed, skipped, holdout) did not.
    status in ('sent', 'delivered') as is_sent,
    case when sent_at is not null then {{ ist_date('sent_at') }} end as sent_date
from typed
