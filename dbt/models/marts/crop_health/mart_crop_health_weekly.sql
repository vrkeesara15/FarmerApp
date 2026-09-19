{{ config(partition_by=bq_date_partition('week_start')) }}

-- AN-006 confirmed crop problems by district and ISO week (Monday, IST dates):
--   confirmed case   a diagnosis with a final problem whose status is answered (corpus, high
--                    confidence), confirmed or corrected by an agronomist
--   district         the diagnosis' district, else the farmer's village district
--   outbreak_alert   >= 3 cases in the week AND at least twice the average of the 4 weeks before
-- District-level, never farm-level: no locations leave Postgres (AN-014).
with params as (
    select {{ as_of_date() }} as as_of_date
),

cases as (
    select
        d.tenant_id,
        coalesce(d.district, vl.district) as district,
        coalesce(d.crop_id, pr.crop_id) as crop_id,
        d.final_problem_id as problem_id,
        pr.problem_code,
        pr.problem_type,
        {{ week_start('d.requested_date') }} as week_start,
        d.diagnosis_id,
        d.farmer_id
    from {{ ref('stg_diagnosis') }} as d
    cross join params as p
    left join {{ ref('stg_corpus_problem') }} as pr
        on pr.problem_id = d.final_problem_id and pr.tenant_id = d.tenant_id
    left join {{ ref('stg_farmer') }} as f
        on f.farmer_id = d.farmer_id and f.tenant_id = d.tenant_id
    left join {{ ref('stg_village') }} as vl
        on vl.village_id = f.village_id and vl.tenant_id = f.tenant_id
    where d.status in ('answered', 'confirmed', 'corrected')
        and d.final_problem_id is not null
        and d.requested_date <= p.as_of_date
),

weekly as (
    select
        tenant_id,
        coalesce(district, 'unknown') as district,
        crop_id,
        problem_id,
        problem_code,
        problem_type,
        week_start,
        count(distinct diagnosis_id) as confirmed_cases,
        count(distinct farmer_id) as farmers_affected
    from cases
    group by tenant_id, coalesce(district, 'unknown'), crop_id, problem_id, problem_code, problem_type, week_start
),

prior_weeks as (
    select
        w.tenant_id,
        w.district,
        w.crop_id,
        w.problem_id,
        w.week_start,
        coalesce(sum(prev.confirmed_cases), 0) as prior_4w_cases
    from weekly as w
    left join weekly as prev
        on prev.tenant_id = w.tenant_id
        and prev.district = w.district
        and prev.problem_id = w.problem_id
        and coalesce(prev.crop_id, '') = coalesce(w.crop_id, '')
        and prev.week_start >= {{ add_days('w.week_start', -28) }}
        and prev.week_start < w.week_start
    group by w.tenant_id, w.district, w.crop_id, w.problem_id, w.week_start
)

select
    {{ row_key(['w.tenant_id', 'w.district', 'w.crop_id', 'w.problem_id', 'w.week_start']) }} as crop_health_key,
    w.tenant_id,
    w.district,
    w.crop_id,
    w.problem_id,
    w.problem_code,
    w.problem_type,
    w.week_start,
    w.confirmed_cases,
    w.farmers_affected,
    cast(t.prior_4w_cases as {{ type_double() }}) / 4 as prior_4w_avg_cases,
    (w.confirmed_cases >= 3 and w.confirmed_cases >= 2 * cast(t.prior_4w_cases as {{ type_double() }}) / 4) as outbreak_alert
from weekly as w
inner join prior_weeks as t
    on t.tenant_id = w.tenant_id
    and t.district = w.district
    and t.problem_id = w.problem_id
    and coalesce(t.crop_id, '') = coalesce(w.crop_id, '')
    and t.week_start = w.week_start
