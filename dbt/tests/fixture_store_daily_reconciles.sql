{{ config(enabled=(target.name == 'ci'), tags=['fixture', 'AN-005']) }}
{#
  AN-005 store s1 by IST day: the pro-rata discount (o1: 8000 over 80000 of lines), the IST
  day boundary (o2 at 20:00 UTC on 09-12 is 09-13 IST), the write-off (m3: 1 x b1 at 8000 on
  09-11, a day without sales) and the day closes.
#}
{{ reconcile(
    ref('mart_store_daily'),
    [
      {'store_id': 's1', 'date_day': 'date:2026-09-10', 'orders': 1, 'gross_sales_paise': 80000,
       'discount_paise': 8000, 'net_sales_paise': 72000, 'own_brand_net_paise': 18000, 'cogs_paise': 66000,
       'gross_margin_paise': 6000, 'write_off_paise': 0, 'contribution_paise': 6000,
       'day_close_variance_paise': none, 'own_brand_share': 0.25},
      {'store_id': 's1', 'date_day': 'date:2026-09-11', 'orders': 0, 'gross_sales_paise': 0,
       'discount_paise': 0, 'net_sales_paise': 0, 'own_brand_net_paise': 0, 'cogs_paise': 0,
       'gross_margin_paise': 0, 'write_off_paise': 8000, 'contribution_paise': -8000,
       'day_close_variance_paise': none, 'own_brand_share': none},
      {'store_id': 's1', 'date_day': 'date:2026-09-13', 'orders': 1, 'gross_sales_paise': 10000,
       'discount_paise': 0, 'net_sales_paise': 10000, 'own_brand_net_paise': 10000, 'cogs_paise': 8000,
       'gross_margin_paise': 2000, 'write_off_paise': 0, 'contribution_paise': 2000,
       'day_close_variance_paise': 0, 'own_brand_share': 1.0},
      {'store_id': 's1', 'date_day': 'date:2026-09-14', 'orders': 1, 'gross_sales_paise': 10000,
       'discount_paise': 0, 'net_sales_paise': 10000, 'own_brand_net_paise': 10000, 'cogs_paise': 8000,
       'gross_margin_paise': 2000, 'write_off_paise': 0, 'contribution_paise': 2000,
       'day_close_variance_paise': -500, 'own_brand_share': 1.0},
    ],
    keys=['store_id', 'date_day'],
    exact=['orders', 'gross_sales_paise', 'discount_paise', 'net_sales_paise', 'own_brand_net_paise',
           'cogs_paise', 'gross_margin_paise', 'write_off_paise', 'contribution_paise', 'day_close_variance_paise'],
    approx=['own_brand_share'],
    complete=true,
    where="store_id = 's1'"
) }}
