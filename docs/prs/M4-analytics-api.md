# M4 analytics read API — AN-001, AN-002, AN-003, AN-011, WC-001 .. WC-004 (API half)

Branch `feat/M4-analytics-api` (from `main` c2e85e0). New package `apps/api/farmerapp/analytics/`;
additive edits to `api/app.py` (router), `tests/authz/test_matrix.py` (route fixtures),
`openapi.yaml`, `docs/progress.md`, `apps/api/README.md`. **No migration.** Console screens
(C10, C20-C22, C30-C31, C40-C41) are the other half.

SPEC 5.3: for P0 the console reads Postgres (read replica in prd); BigQuery / dbt are P1. Every
figure below comes from the live tables, so the console always shows the latest sync.

## Conventions (all endpoints)

* Money: integer paise. Ratios: float `0..1`, `null` when the denominator is 0 (show "–").
  Durations: seconds. Distances: km. Timestamps: UTC RFC 3339. Days: IST `YYYY-MM-DD`.
* Tenant always from the token.
* **AN-011 filter set** on every route: `from`, `to` (IST dates, inclusive; default the 30
  days ending today IST; max 366 days), `cluster_id`, `store_id`, `officer_id`, `crop_id`.
  * `from > to` or > 366 days: 422 `invalid_date_range`.
  * An id the caller cannot see (other tenant, another cluster for a cluster head, a colleague
    for an officer, unknown): 404 `not_found`.
  * A combination that cannot match (store outside the cluster, officer outside the selected
    store / cluster): 422 `invalid_filter_combination`.
  * Every response carries `filters` — echo them into the URL:

```json
"filters": {"from": "2026-08-01", "to": "2026-08-30", "cluster_id": null, "store_id": null,
            "officer_id": null, "crop_id": null, "days": 30, "scope": "tenant"}
```

  `scope` is the role narrowing applied on top: `tenant` (owner, director, tenant admin,
  auditor, accountant), `cluster` (cluster head), `store` (store manager), `own` (field
  officer).
* What a filter narrows: `store_id` / `cluster_id` → sales and khata at those stores,
  officers placed there, farmers whose village is served by them; `officer_id` → that
  officer's visits / duty / collections, the orders they placed and the farmers they
  registered; `crop_id` → farmers with a live crop plot of that crop (and their orders,
  visits, khata).

## Roles (SPEC 2.6)

| Route | Roles (others: 403 `forbidden`) |
|---|---|
| `GET /v1/analytics/owner-home` | owner, director, tenant_admin, auditor, cluster_head (own cluster), store_manager (own store) |
| `GET /v1/analytics/field-team`, `GET /v1/analytics/officers/{id}` | the above + field_officer (own row only; another officer's id is 404) |
| `GET /v1/analytics/officers/{id}/day-replay` | owner, director, tenant_admin, auditor, cluster_head (own cluster), field_officer (self) — **store_manager 403** |
| `GET /v1/analytics/farmers`, `GET /v1/analytics/farmers/{id}/360` | owner, director, tenant_admin, auditor, cluster_head, store_manager, field_officer (own farmers) |
| `GET /v1/analytics/stores`, `GET /v1/analytics/stores/{id}` | owner, director, tenant_admin, auditor, accountant, cluster_head, store_manager (own store) |

Location-derived figures (km, tracks) are never returned to store managers: `km_per_day` and
per-day `km` are `null` and `location_visible` is `false`.

## KPI definitions (SPEC 5.2, `farmerapp/analytics/kpi.py`)

| KPI | Implementation |
|---|---|
| Verified visit | `score >= 70` |
| Unique farmers reached | distinct farmers with ≥ 1 verified visit in the range |
| Confirmation rate | visits with `confirmed_at` ÷ all visits in the range (open ones included) |
| Visit conversion | farmers with a fulfilled order in `(check-in, check-in + 30 days]` of one of their verified visits ÷ distinct farmers visited |
| Own-brand share | own-brand net ÷ total net; net = pre-GST line total less its pro-rata share of the order discount; sales = `handed_over` / `delivered` orders dated by `placed_at` (IST) |
| Active farmer | a purchase, a verified visit or an app session in the 60 days ending on the as-of day. **App session proxy: a `refresh_token` issued to the farmer's own login** (the farmer app refreshes on every launch; no session table before P1 events) |
| Credit overdue | per farmer × store ledger, credits settle the oldest due first (`khata.aging`); buckets `0_30` / `31_60` / `61_90` / `90_plus` days past due, as of the end of `to` |
| Farmer LTV | cumulative net − COGS; COGS = qty × `stock_batch.cost_paise` of the sold batch (store's average batch cost of the SKU when the line has no batch) |
| Time on farm | Σ (check-out − check-in) of verified visits |

## `GET /v1/analytics/owner-home` (C10)

```json
{
  "filters": {...},
  "granularity": "day",                       // "week" above 31 days (7-day buckets from `from`)
  "kpis": [                                   // always in this order
    {"key": "revenue", "unit": "paise", "value": 5120, "target": 10000.0, "last_year": 1000,
     "trend": [{"start": "2026-08-01", "end": "2026-08-01", "value": 0}, ...]},
    {"key": "own_brand_share", "unit": "ratio", ...},
    {"key": "credit_outstanding", "unit": "paise", ...},   // trend: as of each bucket end
    {"key": "credit_overdue", "unit": "paise", ...},
    {"key": "verified_visits", "unit": "count", ...},
    {"key": "active_farmers", "unit": "count", ...},       // trend: as of each bucket end
    {"key": "open_flags", "unit": "count", ...}
  ],
  "credit_overdue_buckets": {"0_30": 5000, "31_60": 0, "61_90": 6000, "90_plus": 0},
  "series": {"revenue": [...], "revenue_last_year": [...], "own_brand_share": [...]},
  "stores": [{"id": "…", "code": "WGL", "name": "FCC Warangal", "district": "Warangal",
              "cluster_id": "…", "lat": 17.97, "lon": 79.59, "revenue_paise": 2520,
              "own_brand_share": 0.71, "overdue_paise": 6000, "score": 100, "band": "green"}],
  "officers_top": [{"id": "…", "name": "…", "store_id": "…", "verified_visits": 12,
                    "duty_days": 5, "verified_visits_per_day": 2.4}],
  "officers_bottom": [...],                   // ascending
  "high_severity_flags": [{"id": "…", "rule": "VA-E02", "severity": "high", "title": "…",
                           "opened_at": "…", "officer_id": "…", "store_id": null, "farmer_id": null}],
  "crop_health_alerts": [],                   // AN-006 (P1)
  "notes": {"crop_health_alerts": "pending_an006", "open_flags": "pending_flags_branch"}
}
```

* **Targets**: tenant setting `targets` (WC-009 will write it): `revenue_paise`,
  `own_brand_share`, `credit_outstanding_paise`, `credit_overdue_paise`, `verified_visits`,
  `active_farmers`, `open_flags`, `store_revenue_paise: {store_id: paise}`. Revenue and
  visit targets are monthly and scaled to the range (`× days / 30`); the rest are levels.
  Missing → `null`.
* **Last year**: the same calendar range a year earlier (29 Feb → 28 Feb).
* **Store score** 0-100: revenue ÷ store target (capped 100) when a target exists, else
  revenue ÷ best store in view. Band `green` ≥ 80, `amber` ≥ 50, `red` < 50, `none` when
  nothing sold in view.
* **Officers**: verified visits per duty day (IST days with a duty session); top 5 descending,
  bottom 5 ascending.
* **Flags** come through `FlagCountsPort` (`analytics/ports.py`). Until the flags branch
  registers its adapter (`app.state.flag_counts`, TODO in the module) every flag figure is 0
  and `notes.open_flags = "pending_flags_branch"`.

**Performance (WC-001 "under 3 s for 50 stores")**: `tests/analytics/test_performance.py`
seeds a synthetic 50-store tenant (10 clusters, 2,000 farmers, ~36,000 orders / ~72,000 lines,
15,000 visits, 3,000 duty sessions, ~3,600 khata rows over 60 days) and times the endpoint
end to end: **~1.2 s for 30 days and ~1.2 s for 60 days** on the dev Mac (budget 3 s,
asserted). No index was needed; range aggregates run with `enable_nestloop = off` for the
statement (`facts.hash_joins`) so an unanalysed bulk load cannot push the planner into a
quadratic nested loop (it did: 28 s before).

## `GET /v1/analytics/field-team` (C20)

```json
{"filters": {...}, "location_visible": true,
 "items": [{"officer_id": "…", "name": "…", "store_id": "…", "cluster_id": "…", "rank": 1,
            "duty_days": 2, "visits": 2, "verified_visits": 1, "verified_visits_per_day": 0.5,
            "unique_farmers_reached": 1, "new_registrations": 1, "confirmation_rate": 0.5,
            "avg_time_on_farm_s": 1200, "time_on_farm_s": 1200,
            "km_per_day": 10.0,                  // null when location_visible is false
            "conversion_rate": 0.5, "converted_farmers": 1, "visited_farmers": 2,
            "collections_paise": 1500, "flags": 0,
            "trend": [{"start": "2026-08-01", "end": "2026-08-07", "value": 1}, ...]}]}
```

Rank: verified visits / duty day, then verified visits, then name. `trend` is always weekly.
Collections: payments the officer collected with status paid / reconciled / cash pending the
day close, dated by `paid_at`. New registrations: farmers with `registered_by` = the officer
created in the range.

## `GET /v1/analytics/officers/{id}` (C21)

`{filters, id, name, phone, status, store_id, store_name, cluster_id, on_duty,
location_visible, scorecard: <ScorecardRow>, duty_days: [{day, start_at, end_at, km, visits,
verified_visits, time_on_farm_s}] (newest first), recent_visits: [{id, farmer_id, farmer_name,
checkin_at, checkout_at, status, score, purpose}] (20, newest first)}`. `officer_id` in the
query is ignored (the path names the officer).

## `GET /v1/analytics/officers/{id}/day-replay?date=YYYY-MM-DD` (C22)

```json
{"filters": {...}, "officer_id": "…", "officer_name": "…", "date": "2026-08-12",
 "duty_sessions": [{"id": "…", "start_at": "…", "end_at": "…", "end_reason": "manual", "km": 5.84}],
 "km": 5.84,
 "track": {"type": "MultiLineString", "coordinates": [[[79.48, 17.9], ...], [...]]},
 "points": [{"ts": "…", "lat": 17.9, "lon": 79.48, "accuracy_m": 10.0}],   // playback slider
 "stops": [{"lat": …, "lon": …, "start": "…", "end": "…", "duration_s": 1200}],
 "gaps": [{"start": "…", "end": "…", "duration_s": 3000, "duty_session_id": "…", "reason": null}],
 "visits": [{"id": "…", "farmer_id": "…", "farmer_name": "…", "purpose": "advisory",
             "checkin_at": "…", "checkout_at": "…", "duration_s": 960, "lat": …, "lon": …,
             "geofence_result": "inside", "status": "verified", "colour": "green", "score": 80,
             "score_components": {"geofence": 30, "confirmation": 30, "photo": 0, "duration": 10, "integrity": 10},
             "proof": [{"kind": "geofence", "satisfied": true, "points": 30, "max_points": 30}, ...],
             "confirmed_at": "…", "photos": 1}],
 "timeline": [{"ts": "…", "type": "duty_start|gap_start|gap_end|visit_checkin|visit_checkout|stop|duty_end",
               "ref_id": "…", "detail": {...}}]}
```

Kept points: accuracy ≤ 100 m, no jump > 90 km/h (same filter as the duty-end summary).
Stops: ≥ 5 min within 100 m. Gaps: > 30 min with no kept point while on duty (session start
→ first point, between points, last point → session end; an open session is measured up to
now / end of day). The track is split at every gap. `reason` stays `null` until VV-008.
Colours: verified green, partial amber, unverified red, open grey. `proof` rows map to the
ProofChecklist (`satisfied` = the component scored > 0; integrity is the caption row).

## `GET /v1/analytics/farmers` (C30)

Query (besides AN-011): `q` (name contains; 4 digits also match the phone's last four; village
name contains), `district`, `stage`, `credit_risk` (`low` / `medium` / `high`), `last_visit`
(`7d` / `30d` / `90d` = visited in the last N days up to `to`; `over_90d`; `never`), `sort`
(`name` default, `last_visit`, `last_purchase`, `ltv`, `balance`, `overdue`; `-` prefix =
descending, nulls last; bad value 422 `invalid_sort`), `cursor` (opaque; bad 400
`invalid_cursor`), `limit` (1-200, default 50).

```json
{"filters": {...}, "total": 3, "next_cursor": null,
 "items": [{"id": "…", "name": "…", "phone_masked": "*********1234", "village_id": "…",
            "village": "…", "district": "…", "store_id": "…", "registered_by": "…",
            "crops": ["paddy"], "stages": ["vegetative"], "acres": 2.5,
            "last_visit_at": "…", "last_purchase_at": "…", "balance_paise": 6000,
            "overdue_paise": 6000, "credit_risk": "high", "ltv_paise": 920,
            "app_user": true, "consent_marketing": false}]}
```

Credit risk: `high` = anything > 60 days overdue, `medium` = overdue, `low` otherwise (as of
`to`). The directory never carries the full phone (AN-014).

## `GET /v1/analytics/farmers/{id}/360` (C31)

`{filters, profile {id, name, phone, phone_verified, language, landmark, source, village_id,
village, district, store_id, registered_by, registered_by_name, created_at, updated_at},
farms [{id, name, survey_no, area_acres, area_acres_computed, soil, irrigation, boundary
(GeoJSON Polygon), centroid (GeoJSON Point), crop_plots [{id, crop_id, crop_code, crop_name,
variety, season, sowing_date, stage, expected_harvest, area_acres}]}], visits (50 newest:
{id, officer_id, officer_name, purpose, checkin_at, checkout_at, status, score, confirmed,
crop_stage}), diagnoses [] (M6), orders (50 newest: {id, store_id, channel, status,
total_paise, placed_at, invoice_no, lines}), khata {balance_paise, overdue_paise,
overdue_buckets, next_due_date, credit_limits [{store_id, limit_paise}], last_payment_at,
credit_risk}, consent {current {data: bool, marketing: bool}, history [{purpose, granted, at,
version, channel}]}, app_usage {has_app_login, last_session_at, sessions_last_60_days, proxy:
"refresh_token_issuance"}, ltv_paise, last_visit_at, last_purchase_at, active, notes
{diagnoses: "pending_m6_diagnosis"}}`. Only the role scope applies (list filters in the query
are echoed, not applied); out of scope → 404.

## `GET /v1/analytics/stores` (C40)

`{filters, items: [{id, code, name, district, cluster_id, net_sales_paise, cogs_paise,
gross_margin_paise, gross_margin_pct, own_brand_share, orders, stock_value_paise (current, at
cost), credit_outstanding_paise, credit_overdue_paise, last_day_close {business_date,
variance_paise, status} | null}]}`.

## `GET /v1/analytics/stores/{id}` (C41, "Store P&L view by month")

`{filters, id, code, name, district, cluster_id, net_sales_paise, cogs_paise,
gross_margin_paise, gross_margin_pct, sales_by_category [{category, net_sales_paise,
gross_margin_paise, share}], brand_split {own_brand_paise, multi_brand_paise, own_brand_share,
own_brand_margin_paise, multi_brand_margin_paise}, stock {value_paise, skus_in_stock, turns,
turns_annualised, stockouts [{sku_id, product_name, pack}]}, credit_book {outstanding_paise,
overdue_paise, buckets, accounts}, day_closes [{business_date, cash_expected_paise,
cash_counted_paise, variance_paise, status, variance_flagged}] (in range, newest first),
pnl [{month "YYYY-MM", partial, gross_sales_paise, discounts_paise, net_sales_paise,
cogs_paise, gross_margin_paise, gross_margin_pct, write_offs_paise, contribution_paise}],
pnl_opex_included: false, pnl_note: "operating_expenses_out_of_scope"}`.

P&L: gross − discounts = net; net − COGS = gross margin; gross margin − write-offs (damage
movements at batch cost) = contribution. **Operating expenses are out of scope** (no expense
ledger in P0) — say so on the screen (`pnl_note` is a copy key, not prose). Ask for a 12-month
range to draw the monthly P&L; months cut by the range are `partial`. Stock turns = COGS in
the range ÷ current stock value at cost (annualised × 365 / days). A stockout is a SKU the
store has stocked (a batch exists) whose on-hand quantity is 0.

## Tests (`apps/api/tests/analytics/`, 98)

* `test_kpi.py` — every SPEC 5.2 KPI on hand-built facts (verified threshold, reach,
  confirmation, conversion window edges, own-brand share, LTV incl. below-cost sales, active
  window edges, credit buckets per ledger, risk), trend buckets.
* `builders.py` — `Mini`: a hand-built tenant (2 clusters, 3 stores, users for every role, 2
  SKUs with batches) so endpoint figures are asserted exactly.
* `test_owner_home.py` — exact KPI values / targets / last year / trends / store map /
  officer ranks; scope per role; each AN-011 filter; 422 / 404 cases; forbidden roles.
* `test_field_team.py` — every scorecard column, store manager gets no km, officer sees own
  row only, profile.
* `test_replay.py` — hand-built day (track split at the gap, stop, visits with proof,
  timeline), roles, and the seeded day with an injected 90-minute gap.
* `test_farmers.py` — directory rows, search / filters / sorts / cursor, scope, 360 contents,
  360 reflects new writes.
* `test_stores.py` — list, detail and P&L by month (full and partial months), scope.
* `test_flag_port.py` — a fake flags adapter on `app.state.flag_counts` feeds the owner home
  and scorecard with the caller's scope.
* `test_performance.py` + `synthetic.py` — the 50-store latency budget.
* Authz matrix: the 8 routes join `tests/authz/test_matrix.py` (every role, cross-tenant 404,
  collections never leak tenant B).

## Assumptions / follow-ups

* Open flags: `FlagCountsPort` returns zeros until `farmerapp/flags` lands (TODO in
  `analytics/ports.py`; the flags branch sets `app.state.flag_counts`).
* Gap reasons (VV-008) and diagnoses (M6) are `null` / empty placeholders.
* App sessions are approximated by refresh-token issuance (documented in the payload `proxy`).
* Store score formula and target scaling are assumptions until WC-009 defines targets.
* No migration: the 3 s budget holds without new indexes; revisit
  (`0019_analytics`, branch `analytics`) if production plans regress.
