{{ config(partition_by=bq_date_partition('week_start')) }}

-- AN-009 data quality: validation flag volume by type (rule) and ISO week raised (IST), how
-- many are still open, resolved and how fast, and the resolution labels (true / false positive,
-- the rule-tuning signal of VA-002).
with params as (
    select {{ as_of_date() }} as as_of_date
),

labels as (
    select flag_id, label
    from (
        select
            flag_id,
            label,
            row_number() over (partition by flag_id order by created_at desc, flag_event_id desc) as recency
        from {{ ref('stg_flag_event') }}
        where label is not null
    ) as l
    where recency = 1
),

flags as (
    select
        f.*,
        {{ week_start('f.raised_date') }} as week_start,
        case when f.resolved_at is not null
             then cast({{ seconds_between('f.created_at', 'f.resolved_at') }} as {{ type_double() }}) / 3600 end as resolution_hours,
        l.label
    from {{ ref('stg_flag') }} as f
    cross join params as p
    left join labels as l on l.flag_id = f.flag_id
    where f.raised_date <= p.as_of_date
)

select
    {{ row_key(['tenant_id', 'week_start', 'rule_id']) }} as flag_week_key,
    tenant_id,
    week_start,
    rule_id,
    -- SPEC 6.3 rule families: VA-E* employee, VA-F* farmer, VA-S* store, VA-V* visit
    case
        when rule_id like 'VA-E%' then 'employee'
        when rule_id like 'VA-F%' then 'farmer'
        when rule_id like 'VA-S%' then 'store'
        when rule_id like 'VA-V%' then 'visit'
        else 'other'
    end as rule_family,
    count(*) as raised,
    sum(case when severity = 'high' then 1 else 0 end) as high_severity,
    sum(case when is_open then 1 else 0 end) as open_now,
    sum(case when resolved_at is not null then 1 else 0 end) as resolved,
    avg(resolution_hours) as avg_resolution_hours,
    sum(case when label = 'true_positive' then 1 else 0 end) as true_positive,
    sum(case when label = 'false_positive' then 1 else 0 end) as false_positive
from flags
group by tenant_id, week_start, rule_id
