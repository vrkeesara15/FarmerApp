-- Khata (credit ledger) entries, append-only. The effective due date follows
-- farmerapp.khata.aging.effective_due_date: due_date, else the end of the harvest month, else
-- the UTC creation date + the tenant's credit_due_days.
with src as (
    {{ latest_cdc_rows('khata_entry') }}
),

typed as (
    select
        {{ as_id('id') }} as khata_entry_id,
        {{ as_id('tenant_id') }} as tenant_id,
        {{ as_id('farmer_id') }} as farmer_id,
        {{ as_id('store_id') }} as store_id,
        cast(type as {{ dbt.type_string() }}) as entry_type,
        cast(amount_paise as {{ dbt.type_bigint() }}) as amount_paise,
        cast(due_date as date) as due_date,
        cast(harvest_month as date) as harvest_month,
        cast(created_at as {{ dbt.type_timestamp() }}) as created_at
    from src
)

select
    e.*,
    {{ ist_date('e.created_at') }} as created_date,
    coalesce(
        e.due_date,
        {{ month_end('e.harvest_month') }},
        {{ add_days(utc_date('e.created_at'), 'coalesce(t.credit_due_days, 90)') }}
    ) as effective_due_date
from typed as e
left join {{ ref('stg_tenant') }} as t
    on t.tenant_id = e.tenant_id
