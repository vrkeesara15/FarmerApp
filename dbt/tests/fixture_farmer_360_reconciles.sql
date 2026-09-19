{{ config(enabled=(target.name == 'ci'), tags=['fixture', 'AN-004']) }}
{#
  AN-004 farmer 360 as of 2026-09-15, by hand from seeds/raw:
  LTV = cumulative gross margin: f1 o1 (72000 - 66000) + o8 (10000 - 8000) = 8000;
  f2 o2 2000 (o5 deleted); f3 o3 16000; f4 o7 8000 (2025, still lifetime); f6 o9 2000.
  Acreage: live farms only (f1's fa1x is deleted -> 3.50). f5 is deleted: no row.
  Last activity (purchase / verified visit / app session): f1 app session 09-15, f2 purchase
  09-13, f3 purchase 09-05, f4 purchase 2025-12-15 (274 days: lapsed, churn high; the open
  visit v5 is not an activity), f6 purchase 09-10.
  Segment: f1 registered 08-20 (within 60 days) -> new; f2, f3, f6 bought within 60 days.
#}
{{ reconcile(
    ref('mart_farmer_360'),
    [
      {'farmer_id': 'f1', 'store_id': 's1', 'cluster_id': 'c1', 'phone_masked': '*********0001',
       'acreage': 3.5, 'current_crop_id': 'cr-paddy', 'lifetime_net_sales_paise': 82000, 'ltv_paise': 8000,
       'credit_outstanding_paise': 60000, 'credit_risk': 'high', 'is_active': true, 'app_user': true,
       'last_activity_date': 'date:2026-09-15', 'segment': 'new', 'churn_risk': 'low'},
      {'farmer_id': 'f2', 'store_id': 's1', 'cluster_id': 'c1', 'phone_masked': '*********0002',
       'acreage': 2.0, 'current_crop_id': 'cr-cotton', 'lifetime_net_sales_paise': 10000, 'ltv_paise': 2000,
       'credit_outstanding_paise': 10000, 'credit_risk': 'low', 'is_active': true, 'app_user': false,
       'last_activity_date': 'date:2026-09-13', 'segment': 'active_buyer', 'churn_risk': 'low'},
      {'farmer_id': 'f3', 'store_id': 's3', 'cluster_id': 'c2', 'phone_masked': '*********0003',
       'acreage': 5.0, 'current_crop_id': 'cr-paddy', 'lifetime_net_sales_paise': 120000, 'ltv_paise': 16000,
       'credit_outstanding_paise': 0, 'credit_risk': 'low', 'is_active': true, 'app_user': false,
       'last_activity_date': 'date:2026-09-05', 'segment': 'active_buyer', 'churn_risk': 'low'},
      {'farmer_id': 'f4', 'store_id': 's3', 'cluster_id': 'c2', 'phone_masked': '*********0004',
       'acreage': 1.25, 'current_crop_id': 'cr-cotton', 'lifetime_net_sales_paise': 60000, 'ltv_paise': 8000,
       'credit_outstanding_paise': 25000, 'credit_risk': 'high', 'is_active': false, 'app_user': false,
       'last_activity_date': 'date:2025-12-15', 'segment': 'lapsed', 'churn_risk': 'high'},
      {'farmer_id': 'f6', 'store_id': 's4', 'cluster_id': 'c3', 'phone_masked': '*********0006',
       'acreage': 4.0, 'current_crop_id': 'cr2-chilli', 'lifetime_net_sales_paise': 6000, 'ltv_paise': 2000,
       'credit_outstanding_paise': 8000, 'credit_risk': 'medium', 'is_active': true, 'app_user': false,
       'last_activity_date': 'date:2026-09-10', 'segment': 'active_buyer', 'churn_risk': 'low'},
    ],
    keys=['farmer_id'],
    exact=['store_id', 'cluster_id', 'phone_masked', 'acreage', 'current_crop_id',
           'lifetime_net_sales_paise', 'ltv_paise', 'credit_outstanding_paise', 'credit_risk',
           'is_active', 'app_user', 'last_activity_date', 'segment', 'churn_risk'],
    complete=true
) }}
