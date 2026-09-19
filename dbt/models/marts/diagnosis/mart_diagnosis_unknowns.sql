{{ config(partition_by=bq_date_partition('week_start')) }}

-- AN-007 "top unknowns": out-of-scope diagnoses (DX-010: not a plant, unsupported crop, no
-- corpus match...) per tenant, ISO week, crop and reason. The dashboard ranks by cases.
with params as (
    select {{ as_of_date() }} as as_of_date
)

select
    {{ row_key(['d.tenant_id', week_start('d.requested_date'), 'd.crop_id', "coalesce(d.out_of_scope_reason, 'unspecified')"]) }} as unknown_key,
    d.tenant_id,
    {{ week_start('d.requested_date') }} as week_start,
    d.crop_id,
    coalesce(d.out_of_scope_reason, 'unspecified') as reason,
    count(*) as cases
from {{ ref('stg_diagnosis') }} as d
cross join params as p
where d.status = 'out_of_scope'
    and d.requested_date <= p.as_of_date
group by d.tenant_id, {{ week_start('d.requested_date') }}, d.crop_id, coalesce(d.out_of_scope_reason, 'unspecified')
