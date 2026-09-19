{{ config(partition_by=bq_date_partition('week_start')) }}

-- AN-007 diagnosis quality per tenant and ISO week of the request (IST):
--   corpus_share         answered by the corpus (source = corpus) / requests
--   escalation_rate      sent to an expert (expert_requested_at set) / requests
--   review_sla_rate      escalations reviewed within 24 h of the expert request / escalations
--                        (an escalation still unreviewed counts as outside the SLA)
--   avg_review_hours     expert request -> review, reviewed escalations
--   test_set_accuracy    NULL: DX-011 accuracy comes from the evaluation run over
--                        ml/eval/testset, which is not in the database (joins here once the
--                        eval results are published to BigQuery)
with params as (
    select {{ as_of_date() }} as as_of_date
),

requests as (
    select
        d.*,
        {{ week_start('d.requested_date') }} as week_start,
        d.expert_requested_at is not null as escalated,
        case
            when d.expert_requested_at is not null and d.reviewed_at is not null
                then {{ seconds_between('d.expert_requested_at', 'd.reviewed_at') }}
        end as review_s
    from {{ ref('stg_diagnosis') }} as d
    cross join params as p
    where d.requested_date <= p.as_of_date
),

weekly as (
    select
        tenant_id,
        week_start,
        count(*) as requests,
        sum(case when source = 'corpus' then 1 else 0 end) as answered_by_corpus,
        sum(case when escalated then 1 else 0 end) as escalated,
        sum(case when review_s is not null then 1 else 0 end) as reviewed,
        sum(case when review_s is not null and review_s <= 86400 then 1 else 0 end) as reviewed_within_24h,
        avg(case when review_s is not null then cast(review_s as {{ type_double() }}) / 3600 end) as avg_review_hours,
        sum(case when status = 'out_of_scope' then 1 else 0 end) as out_of_scope,
        sum(case when llm_used then 1 else 0 end) as llm_used
    from requests
    group by tenant_id, week_start
)

select
    {{ row_key(['tenant_id', 'week_start']) }} as tenant_week_key,
    tenant_id,
    week_start,
    requests,
    answered_by_corpus,
    {{ safe_ratio('answered_by_corpus', 'requests') }} as corpus_share,
    escalated,
    {{ safe_ratio('escalated', 'requests') }} as escalation_rate,
    reviewed,
    reviewed_within_24h,
    24 as review_sla_hours,
    {{ safe_ratio('reviewed_within_24h', 'escalated') }} as review_sla_rate,
    avg_review_hours,
    out_of_scope,
    llm_used,
    cast(null as {{ type_double() }}) as test_set_accuracy
from weekly
