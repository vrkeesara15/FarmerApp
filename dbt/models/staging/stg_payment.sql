-- Payments. "Received" (collections) = paid, reconciled or cash awaiting the day close,
-- dated by paid_at else created_at (farmerapp.analytics.facts.collections). Provider refs,
-- QR payloads and receipt photos are not replicated.
with src as (
    {{ latest_cdc_rows('payment') }}
),

typed as (
    select
        {{ as_id('id') }} as payment_id,
        {{ as_id('tenant_id') }} as tenant_id,
        {{ as_id('farmer_id') }} as farmer_id,
        {{ as_id('store_id') }} as store_id,
        cast(mode as {{ dbt.type_string() }}) as mode,
        cast(amount_paise as {{ dbt.type_bigint() }}) as amount_paise,
        cast(status as {{ dbt.type_string() }}) as status,
        {{ as_id('collected_by') }} as collected_by,
        cast(paid_at as {{ dbt.type_timestamp() }}) as paid_at,
        cast(created_at as {{ dbt.type_timestamp() }}) as created_at
    from src
    where deleted_at is null
)

select
    *,
    status in ('paid', 'reconciled', 'pending_reconciliation') as is_received,
    {{ ist_date('coalesce(paid_at, created_at)') }} as received_date
from typed
