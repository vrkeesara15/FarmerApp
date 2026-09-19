-- Crop-doctor diagnoses (SPEC 3). Images, LLM output, notes and scores are not replicated.
with src as (
    {{ latest_cdc_rows('diagnosis') }}
),

typed as (
    select
        {{ as_id('id') }} as diagnosis_id,
        {{ as_id('tenant_id') }} as tenant_id,
        cast(subject as {{ dbt.type_string() }}) as subject,
        {{ as_id('farmer_id') }} as farmer_id,
        {{ as_id('crop_id') }} as crop_id,
        cast(district as {{ dbt.type_string() }}) as district,
        cast(season as {{ dbt.type_string() }}) as season,
        cast(status as {{ dbt.type_string() }}) as status,
        cast(source as {{ dbt.type_string() }}) as source,
        cast(confidence as {{ dbt.type_string() }}) as confidence,
        {{ as_id('final_problem_id') }} as final_problem_id,
        cast(out_of_scope_reason as {{ dbt.type_string() }}) as out_of_scope_reason,
        cast(llm_used as {{ dbt.type_boolean() }}) as llm_used,
        cast(expert_requested_at as {{ dbt.type_timestamp() }}) as expert_requested_at,
        cast(answered_at as {{ dbt.type_timestamp() }}) as answered_at,
        cast(reviewed_at as {{ dbt.type_timestamp() }}) as reviewed_at,
        cast(created_at as {{ dbt.type_timestamp() }}) as created_at
    from src
    where deleted_at is null
)

select
    *,
    {{ ist_date('created_at') }} as requested_date
from typed
