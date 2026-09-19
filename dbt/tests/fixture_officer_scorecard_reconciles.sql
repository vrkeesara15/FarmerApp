{{ config(enabled=(target.name == 'ci'), tags=['fixture', 'AN-002']) }}
{#
  AN-002 scorecard, 2026-08-17 .. 2026-09-15 IST, by hand from seeds/raw:
  u-fo1  visits v1, v2, v3 (v6 deleted) -> 3; verified v1, v2 -> 2; confirmed v1, v3 -> 2/3
         duty days 09-01, 09-02, 09-12 (ds6 deleted) -> 3, km 42.5 + 30 + 20 = 92.5
         verified / duty day 2/3; reached {f1, f2}; time on farm 1800 + 1200 = 3000, avg 1500
         registrations: f1 (created 08-20) -> 1; conversion f1, f2 bought after -> 2/2
         collections: pay1 cash pending reconciliation 5000 (pay2 failed, pay4 deleted)
         open flags: fl1 on visit v3 (fl2 / fl3 resolved) -> 1; rank 1 (0.667 > 0.5)
  u-fo2  visits v4, v5 -> 2; verified v4 -> 1; confirmed 1/2; duty 08-20, 09-14 -> 2, km 55.25
         (ds5 still open, km NULL); reached {f3}; time 3600; conversion f3 of {f3, f4} = 1/2
         collections pay3 7000 (pay5 out of window); open flags 0 (fl6 deleted); rank 2
  u2-fo  (t2) v9 verified + confirmed, duty 1 day 12 km, o9 after v9 -> 1/1, pay6 6300, fl5 open
#}
{{ reconcile(
    ref('mart_officer_scorecard_30d'),
    [
      {'officer_id': 'u-fo1', 'tenant_id': 't1', 'store_id': 's1', 'cluster_id': 'c1', 'visits': 3,
       'verified_visits': 2, 'duty_days': 3, 'unique_farmers_reached': 2, 'new_registrations': 1,
       'time_on_farm_s': 3000, 'avg_time_on_farm_s': 1500, 'farmers_visited': 2, 'farmers_converted': 2,
       'collections_paise': 5000, 'open_flags': 1, 'officer_rank': 1,
       'verified_visits_per_duty_day': 0.666666666666667, 'confirmation_rate': 0.666666666666667,
       'km': 92.5, 'km_per_duty_day': 30.833333333333333, 'conversion_rate': 1.0},
      {'officer_id': 'u-fo2', 'tenant_id': 't1', 'store_id': 's3', 'cluster_id': 'c2', 'visits': 2,
       'verified_visits': 1, 'duty_days': 2, 'unique_farmers_reached': 1, 'new_registrations': 0,
       'time_on_farm_s': 3600, 'avg_time_on_farm_s': 3600, 'farmers_visited': 2, 'farmers_converted': 1,
       'collections_paise': 7000, 'open_flags': 0, 'officer_rank': 2,
       'verified_visits_per_duty_day': 0.5, 'confirmation_rate': 0.5,
       'km': 55.25, 'km_per_duty_day': 27.625, 'conversion_rate': 0.5},
      {'officer_id': 'u2-fo', 'tenant_id': 't2', 'store_id': 's4', 'cluster_id': 'c3', 'visits': 1,
       'verified_visits': 1, 'duty_days': 1, 'unique_farmers_reached': 1, 'new_registrations': 0,
       'time_on_farm_s': 1800, 'avg_time_on_farm_s': 1800, 'farmers_visited': 1, 'farmers_converted': 1,
       'collections_paise': 6300, 'open_flags': 1, 'officer_rank': 1,
       'verified_visits_per_duty_day': 1.0, 'confirmation_rate': 1.0,
       'km': 12.0, 'km_per_duty_day': 12.0, 'conversion_rate': 1.0},
    ],
    keys=['officer_id'],
    exact=['tenant_id', 'store_id', 'cluster_id', 'visits', 'verified_visits', 'duty_days',
           'unique_farmers_reached', 'new_registrations', 'time_on_farm_s', 'avg_time_on_farm_s',
           'farmers_visited', 'farmers_converted', 'collections_paise', 'open_flags', 'officer_rank'],
    approx=['verified_visits_per_duty_day', 'confirmation_rate', 'km', 'km_per_duty_day', 'conversion_rate'],
    complete=true
) }}
