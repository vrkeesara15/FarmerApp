{{ config(enabled=(target.name == 'ci'), tags=['fixture', 'AN-005']) }}
{#
  SPEC 5.2 credit overdue buckets as of 2026-09-15 (FIFO: credits settle the debit due first):
  f1/s1  k1 debit 50000 due 06-01, k3 debit 30000 harvest 2026-08 -> due 08-31, k2 credit 20000
         k1 open 30000, 106 days overdue -> 90_plus; k3 open 30000, 15 days -> 0_30
         (k8 was written on 09-16, after the as-of day: ignored)
  f2/s1  k4 debit 10000 without due date or harvest: created 08-01 (UTC) + 60 tenant due days
         = 09-30 -> outstanding, not overdue
  f3/s3  k5 40000 settled by k6 -> no open balance, no row
  f4/s3  k7 25000 due 04-01 -> 167 days -> 90_plus
  f6/s4  (t2, default 90 due days unused: due date set) k9 8000 due 08-20 -> 26 days -> 0_30
#}
{{ reconcile(
    ref('mart_credit_accounts'),
    [
      {'farmer_id': 'f1', 'store_id': 's1', 'outstanding_paise': 60000, 'overdue_paise': 60000,
       'overdue_0_30_paise': 30000, 'overdue_31_60_paise': 0, 'overdue_61_90_paise': 0,
       'overdue_90_plus_paise': 30000, 'credit_risk': 'high'},
      {'farmer_id': 'f2', 'store_id': 's1', 'outstanding_paise': 10000, 'overdue_paise': 0,
       'overdue_0_30_paise': 0, 'overdue_31_60_paise': 0, 'overdue_61_90_paise': 0,
       'overdue_90_plus_paise': 0, 'credit_risk': 'low'},
      {'farmer_id': 'f4', 'store_id': 's3', 'outstanding_paise': 25000, 'overdue_paise': 25000,
       'overdue_0_30_paise': 0, 'overdue_31_60_paise': 0, 'overdue_61_90_paise': 0,
       'overdue_90_plus_paise': 25000, 'credit_risk': 'high'},
      {'farmer_id': 'f6', 'store_id': 's4', 'outstanding_paise': 8000, 'overdue_paise': 8000,
       'overdue_0_30_paise': 8000, 'overdue_31_60_paise': 0, 'overdue_61_90_paise': 0,
       'overdue_90_plus_paise': 0, 'credit_risk': 'medium'},
    ],
    keys=['farmer_id', 'store_id'],
    exact=['outstanding_paise', 'overdue_paise', 'overdue_0_30_paise', 'overdue_31_60_paise',
           'overdue_61_90_paise', 'overdue_90_plus_paise', 'credit_risk'],
    complete=true
) }}
