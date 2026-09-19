{{ config(enabled=(target.name == 'ci'), tags=['fixture', 'AN-001']) }}
{#
  AN-001 / SPEC 5.2 KPIs, as of 2026-09-15 IST, window 2026-08-17 .. 2026-09-15, computed by
  hand from seeds/raw (walk-through in dbt/README.md "Fixture ledger"):

  t1 sales in window (fulfilled, not deleted, IST day of placed_at else created_at):
    o1 09-10  lines 20000 + 60000, order discount 8000 pro rata -> net 18000 (own) + 54000
              cost 2 x 8000 (b1) + 1 x 50000 (b2) = 66000
    o2 09-13  (20:00 UTC on 09-12 is 01:30 IST on 09-13) net 10000 own, no batch -> store
              average cost of sk1 at s1 = 8000
    o8 09-14  placed_at NULL -> created_at; net 10000 own, cost 8000
    o3 09-05  net 120000 (multi-brand), cost 2 x 52000 = 104000 (deleted line l4x ignored)
    o6 08-25  walk-in, net 30000 own, cost 3 x 9000 = 27000
    excluded: o4 cancelled, o5 soft-deleted, o7 2025-12-15 (out of window)
    net 242000, own 68000 -> share 0.28099173553719, margin 242000 - 213000 = 29000, orders 5
  t1 visits in window: v1 (85, confirmed), v2 (72), v3 (50, confirmed), v4 (90, confirmed),
    v5 (open); v6 deleted, v7 out of window
    verified 3, reached {f1, f2, f3} = 3, confirmation 3/5 = 0.6, time on farm 1800+1200+3600
    conversion: visited {f1,f2,f3,f4} = 4; converted f1 (o1 9 days after v1), f2 (o2 after
    v2), f3 (o3 16 days after v4) = 3 -> 0.75
  active farmers on 09-15 (07-18 .. 09-15): f1, f2, f3 (f4's last event is 2025-12-15) = 3
  credit (tenant credit_due_days = 60): f1/s1 60000 (overdue 60000), f2/s1 10000 (due 09-30,
    not overdue), f4/s3 25000 overdue; f3 settled -> outstanding 95000, overdue 85000
  open flags: fl1 (open, high), fl4 (escalated, high); fl6 deleted -> 2 / 2 high
  t2: o9 net 6000 own, cost 4000; v9 verified + confirmed, o9 a day later -> converted;
    k9 8000 due 08-20 -> overdue; fl5 open (medium)
#}
{{ reconcile(
    ref('mart_owner_kpi_30d'),
    [
      {'tenant_id': 't1', 'orders': 5, 'net_sales_paise': 242000, 'own_brand_net_paise': 68000,
       'gross_margin_paise': 29000, 'visits': 5, 'verified_visits': 3, 'unique_farmers_reached': 3,
       'farmers_visited': 4, 'farmers_converted': 3, 'time_on_farm_s': 6600, 'active_farmers': 3,
       'credit_outstanding_paise': 95000, 'credit_overdue_paise': 85000, 'open_flags': 2, 'open_high_flags': 2,
       'as_of_date': 'date:2026-09-15', 'window_start': 'date:2026-08-17',
       'own_brand_share': 0.280991735537190, 'confirmation_rate': 0.6, 'visit_conversion_rate': 0.75},
      {'tenant_id': 't2', 'orders': 1, 'net_sales_paise': 6000, 'own_brand_net_paise': 6000,
       'gross_margin_paise': 2000, 'visits': 1, 'verified_visits': 1, 'unique_farmers_reached': 1,
       'farmers_visited': 1, 'farmers_converted': 1, 'time_on_farm_s': 1800, 'active_farmers': 1,
       'credit_outstanding_paise': 8000, 'credit_overdue_paise': 8000, 'open_flags': 1, 'open_high_flags': 0,
       'as_of_date': 'date:2026-09-15', 'window_start': 'date:2026-08-17',
       'own_brand_share': 1.0, 'confirmation_rate': 1.0, 'visit_conversion_rate': 1.0},
    ],
    keys=['tenant_id'],
    exact=['orders', 'net_sales_paise', 'own_brand_net_paise', 'gross_margin_paise', 'visits',
           'verified_visits', 'unique_farmers_reached', 'farmers_visited', 'farmers_converted',
           'time_on_farm_s', 'active_farmers', 'credit_outstanding_paise', 'credit_overdue_paise',
           'open_flags', 'open_high_flags', 'as_of_date', 'window_start'],
    approx=['own_brand_share', 'confirmation_rate', 'visit_conversion_rate'],
    complete=true
) }}
