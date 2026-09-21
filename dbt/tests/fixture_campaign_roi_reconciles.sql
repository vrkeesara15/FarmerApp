{{ config(enabled=(target.name == 'ci'), tags=['fixture', 'AN-008']) }}
{#
  AN-008 campaign ROI, computed by hand from seeds/raw (as of 2026-09-15).

  c1  sms, started 2026-09-01 04:00 UTC (IST 09-01, ISO week 08-31), attribution 14 days,
      holdout arm. Recipients: cr1 f1 delivered (the older `sent` CDC row is dropped), cr2 f2
      sent, cr3 f3 holdout, cr4 f4 skipped -> sent 2, delivered 1, opened 0 (not push; the
      holdout and the skipped row take the campaign start's week).
      Target orders: f1's o1 (09-10, net 18 000 own brand + 54 000 multi-brand) and f2's o2
      (09-13, net 10 000 own brand) -> 2 orders, 82 000 paise, own-brand share 28 000 / 82 000
      = 0.341463. f1's o8 (09-14 10:00) is NOT c1's: c2 reached f1 at 09-14 05:05, after c1's
      send and before the order (last touch). f2's o2 stays with c1 because the c3 recipient
      that would have taken it (cr9, sent 09-07) is soft-deleted.
      Holdout: f3's o3 (09-05 06:00, inside 14 days of the campaign start), net 120 000, no
      own brand -> share 0. Lift = 0.341463 - 0 = 0.3415 (rounded like the API).
  c2  whatsapp, started 2026-09-14 (ISO week 09-14), attribution 7 days. cr5 f1 delivered,
      cr6 f2 failed -> sent 1, delivered 1. o8 (09-14 10:00, net 10 000 own brand) is c2's by
      last touch -> 1 order, 10 000 paise. No holdout arm -> lift NULL.
  c3  push, started 2026-09-07 (ISO week 09-07). cr7 f3 delivered and opened, cr8 f4 delivered
      -> sent 2, delivered 2, opened 1 (opens count on push only). f3's o3 is before the send
      and f4 last bought in 2025 -> 0 orders, 0 paise, no holdout -> lift NULL.
  c4  t2 sms, started 2026-09-08 (ISO week 09-07). cr10 f6 sent -> sent 1, delivered 0; f6's o9
      (09-10, net 6 000) is inside the window -> 1 order, 6 000 paise, no holdout -> lift NULL.
  c5  scheduled and never started: its pending recipient cr11 has no send and no campaign start,
      so it has no week and no row. c6 is soft-deleted: its recipient cr12 has no row either.
#}
{{ reconcile(
    ref('mart_campaign_roi'),
    [
      {'campaign_id': 'c1', 'week_start': 'date:2026-08-31', 'tenant_id': 't1', 'channel': 'sms',
       'sent': 2, 'delivered': 1, 'opened': 0, 'orders': 2, 'revenue_paise': 82000, 'own_brand_lift': 0.3415},
      {'campaign_id': 'c2', 'week_start': 'date:2026-09-14', 'tenant_id': 't1', 'channel': 'whatsapp',
       'sent': 1, 'delivered': 1, 'opened': 0, 'orders': 1, 'revenue_paise': 10000, 'own_brand_lift': none},
      {'campaign_id': 'c3', 'week_start': 'date:2026-09-07', 'tenant_id': 't1', 'channel': 'push',
       'sent': 2, 'delivered': 2, 'opened': 1, 'orders': 0, 'revenue_paise': 0, 'own_brand_lift': none},
      {'campaign_id': 'c4', 'week_start': 'date:2026-09-07', 'tenant_id': 't2', 'channel': 'sms',
       'sent': 1, 'delivered': 0, 'opened': 0, 'orders': 1, 'revenue_paise': 6000, 'own_brand_lift': none},
    ],
    keys=['campaign_id', 'week_start'],
    exact=['tenant_id', 'channel', 'sent', 'delivered', 'opened', 'orders', 'revenue_paise'],
    approx=['own_brand_lift'],
    complete=true
) }}
