{{ config(enabled=(target.name == 'ci'), tags=['fixture', 'AN-001']) }}
{#
  SPEC 5.2 active farmers (event in day - 59 .. day), t1:
  06-18  f3's verified visit v7 on 06-01 is inside 04-20 .. 06-18 -> 1
  08-19  v7 fell out on 07-31; nothing else before 08-20 -> 0 (o6 is a walk-in)
  08-20  f3 verified visit v4 -> 1
  09-01  + f1 verified visit v1 -> 2
  09-15  f1, f2, f3 -> 3 (f4 only has an open visit; the officer's refresh token rt2 is not a
         farmer session)
#}
{{ reconcile(
    ref('mart_active_farmers_daily'),
    [
      {'tenant_id': 't1', 'date_day': 'date:2026-06-18', 'active_farmers': 1},
      {'tenant_id': 't1', 'date_day': 'date:2026-08-19', 'active_farmers': 0},
      {'tenant_id': 't1', 'date_day': 'date:2026-08-20', 'active_farmers': 1},
      {'tenant_id': 't1', 'date_day': 'date:2026-09-01', 'active_farmers': 2},
      {'tenant_id': 't1', 'date_day': 'date:2026-09-15', 'active_farmers': 3},
      {'tenant_id': 't2', 'date_day': 'date:2026-09-09', 'active_farmers': 1},
      {'tenant_id': 't2', 'date_day': 'date:2026-09-08', 'active_farmers': 0},
    ],
    keys=['tenant_id', 'date_day'],
    exact=['active_farmers']
) }}
