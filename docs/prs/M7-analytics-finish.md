# M7 analytics finish: store performance, farmer segments, data quality, campaign ROI and evaluation reporting

Branch `feat/M7-analytics-finish` off `main` at `db7d271`. Scope: `apps/api`, `dbt`,
`apps/console` and `docs/` only.

PR title: `feat(M7): store performance and farmer segments on the analytics API, data-quality summary, campaign ROI mart and evaluation reporting (AN-004, AN-005, AN-007, AN-008, AN-009, DX-011)`

Closes the five follow-ups `docs/prs/M7-screens-merge.md` recorded but did not build.

## Requirement IDs

| ID | Status after this PR | What landed |
|---|---|---|
| AN-004 | done (the churn and segment thresholds stay working definitions for the owner to confirm) | segments API (preview + saved segments reusable by campaigns), churn-risk list and LTV, C32 rebuilt on them, churn / credit risk / app usage on the farmer 360 |
| AN-005 | done | sales by brand, stockout **days** per SKU, stock turns, ageing buckets and day-close variance on `GET /v1/analytics/stores[/{id}]`; C40 columns and the C41 brand chart |
| AN-007 | done | C62 reads the real `EvaluationSummaryOut` shape; per-crop accuracy on every run |
| AN-008 | done | the `mart_campaign_roi` body, its staging models, fixtures and tests |
| AN-009 | done | `GET /v1/flags/summary`; the C70 data-quality tab reads it instead of rolling up `/v1/flags` in the browser |
| DX-011 | done (the labelled held-out set is still a human gate) | last-run status, the alert state against the tenant threshold, and accuracy per crop **over time** on C62 |

## API

### AN-005 store performance (`farmerapp/analytics/stores.py`, `facts.py`, `schemas.py`)

`GET /v1/analytics/stores` rows gained `stock_turns_annualised`, `stockouts` (SKUs the store
has stocked whose on-hand is now zero), `credit_overdue_buckets` (the FIFO ageing the detail
already returned) and `day_close_variance_paise` (summed over the range, not just the last
close). `GET /v1/analytics/stores/{id}` gained `sales_by_brand` — net sales, gross margin,
margin % and share per **brand**, own-brand flagged, biggest first — and per-SKU
`days_out_of_stock` / `currently_out` with a `stockout_days` total.

`sales_aggregate` now groups by `brand` as well (`PRODUCT_KEYS`); the SKU attribute map is
`(own_brand, category, brand)`.

**Stockout days** replay the append-only ledger backwards: `stock_movement` rows are never
updated, so on-hand at the end of an earlier IST day is today's on-hand minus every movement
after it. One grouped query per store, then a walk from `to` down to `from`, counting days at
or below zero from the day the store first stocked the SKU (its oldest batch). Counting from
`stock_batch.qty` alone would have called a SKU sold out today "out of stock all month".

### AN-004 farmer segments (`farmerapp/analytics/segments.py`, migration `0036`)

A segment is the **same** `campaigns.segments.Segment` a campaign is sent to, so nothing is
translated between the two screens; it gained `min_acres` / `max_acres` over the live farms.

* `POST /v1/analytics/segments/preview` — matched, consented, excluded-for-consent, churn-risk
  and LTV totals plus the breakdown by crop, district, stage, acreage band, spend band,
  last-visit window, consent and app usage, all inside the caller's role scope. Relative
  windows are measured from the **end of the AN-011 range**, not wall-clock time, so a preview
  of a filtered range is reproducible and a shared URL shows the same numbers.
* `GET/POST /v1/analytics/segments`, `GET/PATCH/DELETE /v1/analytics/segments/{id}` — the new
  `saved_segment` table (tenant-unique name, JSONB definition, cached `last_count`), under RLS
  like every other table. `POST /v1/campaigns` takes `saved_segment_id` and **copies** the
  definition: editing a saved segment later never rewrites what an earlier campaign was sent
  to. Read: owner, director, tenant admin, auditor, cluster head (SPEC 5.1 audience); write:
  owner, director, tenant admin.
* `GET /v1/analytics/farmers-churn-risk?days=&limit=` — prior customers gone quiet, biggest
  LTV first. `churn_risk()` (`farmers.py`): a farmer with at least one fulfilled order whose
  last purchase **and** last visit are both older than `CHURN_WINDOW_DAYS` (90, a working
  definition). A farmer an officer saw last week is not churning whatever the till says, and a
  never-buyer is an acquisition problem, not a retention one.

The directory rows gained `spend_paise`, `orders` and `churn_risk`; the 360 gained
`spend_paise` and a `churn_risk` object with the days behind the flag.

### AN-009 data quality (`farmerapp/flags/summary.py`)

`GET /v1/flags/summary?days=` (default 90, review roles, the WC-010 inbox scope): volume by
rule and by subject type, open / resolved / overdue, **median and p90** resolution hours
overall and per rule, the false-positive rate, repeat subjects (≥ 2 flags in the window) and
each rule's VA-006 four-week precision with the auto-disable floor. Percentiles, not a mean:
a handful of flags left over a weekend drags an average to nonsense.

### AN-007 / DX-011 (`farmerapp/mlops/schemas.py`, `quality.py`)

`EvaluationSummaryOut` gained `crops` — the run's `per_crop` tallies as a stable ordered list
— so the list endpoint can draw a trend without fetching each run. `QualityOut` gained
`evaluation_alert_drop_points`, the tenant's `diagnosis_evaluation.alert_drop_points`, so the
console can say what the threshold was instead of hard-coding 5.

The console's `EvaluationRun` type had been written against a shape the API never returned
(`ran_at`, `model_name`, `per_crop` as a list). The console was corrected to the API rather
than the other way round; the two now match field for field.

## dbt

`mart_campaign_roi` has a real body: one row per campaign and ISO week of the send
(`week_start` = Monday of the IST send date, the campaign start for holdout rows), `sent` /
`delivered` / `opened` from `campaign_recipient`, target-arm attributed orders and revenue
from `fct_sales_line` on the same last-touch rule as `campaigns.service.campaign_roi`, and
`own_brand_lift` = target own-brand share − holdout own-brand share (null without a holdout
arm or with a zero denominator). Two documented deviations from the API: money is
`fct_sales_line` net (post-discount, ex-GST) rather than order totals, and the holdout share
is measured once per campaign, because a holdout has no send and therefore no week of its own.

New `stg_campaign` / `stg_campaign_recipient` (PII and free text dropped), their `_sources.yml`
/ `_staging.yml` entries and fixture seeds `public_campaign.csv` (c1–c6) /
`public_campaign_recipient.csv` (cr1–cr12) reusing the existing tenants, farmers and orders:
c1 has both arms and an older CDC version, c2 steals an order from c1 by last touch, c3 has a
soft-deleted recipient that would otherwise steal one, c5 never started (no row at all).
`dbt/tests/fixture_campaign_roi_reconciles.sql` reconciles all four fixture rows, and the
AN-012 test set was completed for `mart_farmer_360`, `mart_farmer_segments`,
`mart_credit_accounts`, `mart_store_snapshot`, `mart_store_category_monthly`,
`mart_flags_weekly` and `mart_flag_repeat_offenders` as well.

## Console

| Screen | Change |
|---|---|
| C40 stores | stock turns, stockouts and the range day-close variance as sortable columns; the CSV export carries them and the four ageing buckets |
| C41 store detail | a "net sales and gross margin by brand" bar comparison (own brand in Turmeric), stockout rows with the days at zero and whether the SKU is out now, and the SKU-days total on the stock panel |
| C32 segments | rebuilt: saved segments table (load / delete), a name field with save / update, the AN-004 preview (five stat tiles + seven bar comparisons), and "Create a campaign" that saves the segment and opens C81 with `?segment=<id>` |
| C81 builder | seeds from the saved segment id; `readStoredSegment` and its `sessionStorage` key are gone |
| C31 farmer 360 | credit-risk and churn badges, a line saying how long the farmer has been quiet, and lifetime spend / orders on the app tab |
| C70 data quality | reads `GET /v1/flags/summary`, adds a window selector, flags by subject, median / p90 columns and the VA-006 precision column (under the floor in danger red); `lib/data-quality.ts` and its test are deleted |
| C62 quality | the real run fields (status, encoder, LLM), the alert state against the tenant threshold either way, and a new "top-1 accuracy per crop over time" line chart over the last ten nightly runs |

Bars everywhere for comparisons and no pies (SPEC 13.4); the accuracy trend is the one line
chart, because it is a trend over time, which is what lines are for. Filters stay in the URL
on C32 (AN-011). Mock fixtures were added for every new endpoint (`lib/mock/analytics.ts`
segments / churn / the new store fields, `lib/mock/flags.ts` summary, `lib/mock/mlops.ts` the
real evaluation shape), and all five locales gained the new strings.

## Checks

| Surface | Result |
|---|---|
| `SKIP_AUDIT=1 make check-api` | green — ruff, ruff format, mypy strict, validate-rules, **4,751 pytest** (4,749 parallel + 2 serial) in 20m41s, OpenAPI diff clean, bandit |
| `make check-dbt` | green — replication allowlist (28 tables), `dbt build --target ci`: 28 seeds, 22 tables, 43 views, **509 data tests**, PASS 602 |
| `cd apps/console && npm run check` | green — eslint, string lint, typecheck, **373 vitest in 58 files**, build |
| `cd apps/console && npm run test:e2e` | green — **39 Playwright tests** |
| `make openapi` | no diff afterwards |

## What remains

* **AN-004 thresholds** — `CHURN_WINDOW_DAYS = 90`, the acreage bands (2 / 5 / 10 acres) and
  the spend bands (₹5k / ₹25k / ₹1 lakh) are working definitions. The owner confirms them.
* **Datastream allowlist (human gate)** — `infra/modules/analytics/replicated_columns.json` is
  out of this PR's scope, so `dbt/scripts/check_replication.py` carries `campaign` and
  `campaign_recipient` in a documented `PENDING_REPLICATION` dict: they are validated exactly
  as the other tables (columns must match `_sources.yml` and the seed headers, PII still
  rejected), only the "already in Terraform" expectation is deferred. Someone must add the same
  two entries to the Terraform allowlist, re-run the Datastream stream update and delete them
  from `PENDING_REPLICATION`, or the BigQuery targets will have no `farmerapp_raw.public_campaign*`
  to read.
* **DX-011** — the agronomist-labelled held-out set still has to be uploaded to the corpus
  bucket before a nightly run produces real numbers; the log-based monitoring alert belongs to
  the observability track.
* **SPEC 5.3** — all of this reads Postgres, as P0 says. The BigQuery marts hold the same
  definitions (`mart_farmer_360`, `mart_farmer_segments`, `mart_store_snapshot`,
  `mart_flags_weekly`); moving the console onto them is the P1 switch, not this PR.
* Carried over unchanged: native-speaker review of the new Telugu, Hindi, Kannada and Marathi
  strings (NF-008); DLT / WhatsApp template registration; the email provider and sending
  domain; the owner confirming incentive rules and targets.
