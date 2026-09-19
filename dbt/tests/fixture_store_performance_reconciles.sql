{{ config(enabled=(target.name == 'ci'), tags=['fixture', 'AN-005']) }}
{#
  AN-005 store snapshot as of 2026-09-15:
  s1  live batches b1 (10 x 8000) + b2 (0 x 50000) -> stock value 80000; sk2 on hand 0 -> 1
      stockout of 2 stocked SKUs; COGS 30 days 66000 + 8000 + 8000 = 82000 -> turns 1.025,
      annualised 1.025 x 365 / 30 = 12.4708333; credit 70000 (overdue 60000, 2 accounts);
      last day close 09-14 variance -500
  s2  only a deleted batch -> nothing stocked, turns NULL (no stock value), no close
  s3  b3 20 x 9000 + b4 5 x 52000 = 440000; COGS 104000 + 27000 = 131000 -> 0.2977273
  s4  (t2) b6 7 x 1000 = 7000; COGS 4000 -> 0.5714286; last close 09-10 variance -2000
#}
{{ reconcile(
    ref('mart_store_snapshot'),
    [
      {'store_id': 's1', 'stock_value_paise': 80000, 'stocked_skus': 2, 'stockout_skus': 1,
       'cogs_30d_paise': 82000, 'credit_outstanding_paise': 70000, 'credit_overdue_paise': 60000,
       'open_credit_accounts': 2, 'last_day_close_date': 'date:2026-09-14', 'last_day_close_variance_paise': -500,
       'stock_turns_30d': 1.025, 'stock_turns_annualised': 12.470833333333333},
      {'store_id': 's2', 'stock_value_paise': 0, 'stocked_skus': 0, 'stockout_skus': 0,
       'cogs_30d_paise': 0, 'credit_outstanding_paise': 0, 'credit_overdue_paise': 0,
       'open_credit_accounts': 0, 'last_day_close_date': none, 'last_day_close_variance_paise': none,
       'stock_turns_30d': none, 'stock_turns_annualised': none},
      {'store_id': 's3', 'stock_value_paise': 440000, 'stocked_skus': 2, 'stockout_skus': 0,
       'cogs_30d_paise': 131000, 'credit_outstanding_paise': 25000, 'credit_overdue_paise': 25000,
       'open_credit_accounts': 1, 'last_day_close_date': 'date:2026-09-13', 'last_day_close_variance_paise': 0,
       'stock_turns_30d': 0.297727272727273, 'stock_turns_annualised': 3.622348484848485},
      {'store_id': 's4', 'stock_value_paise': 7000, 'stocked_skus': 1, 'stockout_skus': 0,
       'cogs_30d_paise': 4000, 'credit_outstanding_paise': 8000, 'credit_overdue_paise': 8000,
       'open_credit_accounts': 1, 'last_day_close_date': 'date:2026-09-10', 'last_day_close_variance_paise': -2000,
       'stock_turns_30d': 0.571428571428571, 'stock_turns_annualised': 6.952380952380952},
    ],
    keys=['store_id'],
    exact=['stock_value_paise', 'stocked_skus', 'stockout_skus', 'cogs_30d_paise',
           'credit_outstanding_paise', 'credit_overdue_paise', 'open_credit_accounts',
           'last_day_close_date', 'last_day_close_variance_paise'],
    approx=['stock_turns_30d', 'stock_turns_annualised'],
    complete=true
) }}
