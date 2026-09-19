-- Flags attributed to a field officer, as farmerapp.flags.analytics does: flags on the
-- employee themself and flags on one of their visits. Shared by the scorecard (open flags) and
-- the repeat-offender list (AN-009).
with flags as (
    select * from {{ ref('stg_flag') }}
)

select
    f.flag_id,
    f.tenant_id,
    f.subject_id as officer_id,
    f.rule_id,
    f.severity,
    f.is_open,
    f.created_at,
    f.raised_date
from flags as f
where f.subject_type = 'employee'

union all

select
    f.flag_id,
    f.tenant_id,
    v.officer_id,
    f.rule_id,
    f.severity,
    f.is_open,
    f.created_at,
    f.raised_date
from flags as f
inner join {{ ref('stg_visit') }} as v
    on v.visit_id = f.subject_id
    and v.tenant_id = f.tenant_id
where f.subject_type = 'visit'
