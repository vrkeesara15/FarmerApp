-- Corpus problems (the diagnosis labels), joined to the catalogue pest / disease code.
with src as (
    {{ latest_cdc_rows('corpus_problem') }}
),

pests as (
    {{ latest_cdc_rows('pest_or_disease') }}
)

select
    {{ as_id('p.id') }} as problem_id,
    {{ as_id('p.tenant_id') }} as tenant_id,
    {{ as_id('p.crop_id') }} as crop_id,
    {{ as_id('p.pest_or_disease_id') }} as pest_or_disease_id,
    cast(d.code as {{ dbt.type_string() }}) as problem_code,
    cast(d.name as {{ dbt.type_string() }}) as problem_name,
    cast(p.problem_type as {{ dbt.type_string() }}) as problem_type,
    cast(p.status as {{ dbt.type_string() }}) as status
from src as p
left join pests as d
    on d.id = p.pest_or_disease_id
-- Retired problems stay: past diagnoses still point at them.
where p.deleted_at is null
