{{ config(enabled=(target.name == 'ci'), tags=['fixture', 'AN-009']) }}
{#
  AN-009 by IST week raised: VA-E01 fl2 (09-02, resolved after 36 h, true positive) and fl3
  (09-05, resolved after 6 h, false positive) -> week 08-31, avg 21 h; VA-E03 fl1 and VA-F01 fl4
  (escalated = still open) -> week 09-07; fl6 deleted. Repeat offenders: u-fo1 has fl2, fl3 on
  themself and fl1 on their visit v3 -> 3 flags, 1 open, 2 rules; nobody else reaches 2.
#}
with weekly as (
    {{ reconcile(
        ref('mart_flags_weekly'),
        [
          {'tenant_id': 't1', 'week_start': 'date:2026-08-31', 'rule_id': 'VA-E01', 'raised': 2, 'high_severity': 0,
           'open_now': 0, 'resolved': 2, 'true_positive': 1, 'false_positive': 1, 'avg_resolution_hours': 21.0},
          {'tenant_id': 't1', 'week_start': 'date:2026-09-07', 'rule_id': 'VA-E03', 'raised': 1, 'high_severity': 1,
           'open_now': 1, 'resolved': 0, 'true_positive': 0, 'false_positive': 0, 'avg_resolution_hours': none},
          {'tenant_id': 't1', 'week_start': 'date:2026-09-07', 'rule_id': 'VA-F01', 'raised': 1, 'high_severity': 1,
           'open_now': 1, 'resolved': 0, 'true_positive': 0, 'false_positive': 0, 'avg_resolution_hours': none},
          {'tenant_id': 't2', 'week_start': 'date:2026-09-07', 'rule_id': 'VA-E02', 'raised': 1, 'high_severity': 0,
           'open_now': 1, 'resolved': 0, 'true_positive': 0, 'false_positive': 0, 'avg_resolution_hours': none},
        ],
        keys=['tenant_id', 'week_start', 'rule_id'],
        exact=['raised', 'high_severity', 'open_now', 'resolved', 'true_positive', 'false_positive'],
        approx=['avg_resolution_hours'],
        complete=true
    ) }}
),

offenders as (
    {{ reconcile(
        ref('mart_flag_repeat_offenders'),
        [
          {'officer_id': 'u-fo1', 'flags_90d': 3, 'open_flags': 1, 'distinct_rules': 2},
        ],
        keys=['officer_id'],
        exact=['flags_90d', 'open_flags', 'distinct_rules'],
        complete=true
    ) }}
)

select rule_id as subject, problem from weekly
union all
select officer_id as subject, problem from offenders
