{{ config(enabled=(target.name == 'ci'), tags=['fixture', 'AN-006', 'AN-007']) }}
{#
  AN-006: week of Monday 2026-09-07, confirmed problems (answered / confirmed / corrected with a
  final problem): Warangal paddy blast d1, d5, d8 (farmers f1, f2) = 3 with no cases in the 4
  weeks before -> outbreak; Warangal bollworm d2 (d7 deleted); Karimnagar paddy blast d3 (no
  district on the diagnosis -> farmer f3's village).
  AN-007: week 09-07 requests d1, d2, d3, d4, d5, d8 = 6; corpus d1, d5, d8 -> 0.5; escalated
  d2, d3 -> 1/3; reviewed within 24 h of the expert request: d2 (15 h) yes, d3 (30 h) no -> 0.5.
  Week 09-14: d6 queued, escalated, unreviewed -> SLA 0.
#}
with crop_health as (
    {{ reconcile(
        ref('mart_crop_health_weekly'),
        [
          {'district': 'Warangal', 'crop_id': 'cr-paddy', 'problem_id': 'cpr-blast', 'week_start': 'date:2026-09-07',
           'confirmed_cases': 3, 'farmers_affected': 2, 'outbreak_alert': true},
          {'district': 'Warangal', 'crop_id': 'cr-cotton', 'problem_id': 'cpr-boll', 'week_start': 'date:2026-09-07',
           'confirmed_cases': 1, 'farmers_affected': 1, 'outbreak_alert': false},
          {'district': 'Karimnagar', 'crop_id': 'cr-paddy', 'problem_id': 'cpr-blast', 'week_start': 'date:2026-09-07',
           'confirmed_cases': 1, 'farmers_affected': 1, 'outbreak_alert': false},
        ],
        keys=['district', 'crop_id', 'problem_id', 'week_start'],
        exact=['confirmed_cases', 'farmers_affected', 'outbreak_alert'],
        complete=true
    ) }}
),

quality as (
    {{ reconcile(
        ref('mart_diagnosis_quality_weekly'),
        [
          {'tenant_id': 't1', 'week_start': 'date:2026-09-07', 'requests': 6, 'answered_by_corpus': 3,
           'escalated': 2, 'reviewed_within_24h': 1, 'out_of_scope': 1,
           'corpus_share': 0.5, 'escalation_rate': 0.333333333333333, 'review_sla_rate': 0.5, 'avg_review_hours': 22.5},
          {'tenant_id': 't1', 'week_start': 'date:2026-09-14', 'requests': 1, 'answered_by_corpus': 0,
           'escalated': 1, 'reviewed_within_24h': 0, 'out_of_scope': 0,
           'corpus_share': 0.0, 'escalation_rate': 1.0, 'review_sla_rate': 0.0, 'avg_review_hours': none},
          {'tenant_id': 't2', 'week_start': 'date:2026-09-07', 'requests': 1, 'answered_by_corpus': 0,
           'escalated': 0, 'reviewed_within_24h': 0, 'out_of_scope': 1,
           'corpus_share': 0.0, 'escalation_rate': 0.0, 'review_sla_rate': none, 'avg_review_hours': none},
        ],
        keys=['tenant_id', 'week_start'],
        exact=['requests', 'answered_by_corpus', 'escalated', 'reviewed_within_24h', 'out_of_scope'],
        approx=['corpus_share', 'escalation_rate', 'review_sla_rate', 'avg_review_hours'],
        complete=true
    ) }}
)

select district as subject, problem from crop_health
union all
select tenant_id as subject, problem from quality
