-- Validation flags (VA-002). Titles, evidence and notes are not replicated (they can quote
-- people); rule id, subject, severity, status and times are enough for AN-009.
with src as (
    {{ latest_cdc_rows('flag') }}
),

typed as (
    select
        {{ as_id('id') }} as flag_id,
        {{ as_id('tenant_id') }} as tenant_id,
        cast(rule_id as {{ dbt.type_string() }}) as rule_id,
        cast(subject_type as {{ dbt.type_string() }}) as subject_type,
        {{ as_id('subject_id') }} as subject_id,
        cast(severity as {{ dbt.type_string() }}) as severity,
        cast(status as {{ dbt.type_string() }}) as status,
        {{ as_id('scope_cluster_id') }} as cluster_id,
        {{ as_id('scope_store_id') }} as store_id,
        cast(sla_due_at as {{ dbt.type_timestamp() }}) as sla_due_at,
        cast(resolved_at as {{ dbt.type_timestamp() }}) as resolved_at,
        cast(created_at as {{ dbt.type_timestamp() }}) as created_at
    from src
    where deleted_at is null
)

select
    *,
    {{ ist_date('created_at') }} as raised_date,
    status in ('open', 'in_review', 'escalated') as is_open
from typed
