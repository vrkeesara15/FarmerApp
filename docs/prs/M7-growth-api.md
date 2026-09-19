# M7 growth API: campaigns, targets and incentives, exports and scheduled reports, owner PDF, stock alerts, accounting exports

Branch `feat/M7-growth-api` (worktree of `main` at 5eeb562). Scope: `apps/api` and `docs/` only.

PR title: `feat(M7): campaigns with consented segments and conversion, targets and incentive rules, exports and scheduled reports, weekly owner PDF, stock alerts and accounting exports (WC-008, WC-009, WC-013, AN-008, AN-015, ST-004, ST-008)`

## Requirement IDs

| ID | Status after this PR | What |
|---|---|---|
| WC-008 | in-progress (API done; console C80-C82 left) | segment builder with live count, consent-only audiences (query + send-time re-check), SMS / WhatsApp through the provider adapters with per-tenant DLT / WhatsApp template ids, push via `notification` rows, languages, schedule, throttled send job, per-recipient delivery status, conversion attribution |
| AN-008 | in-progress (API done; console C82 + dbt mart body left) | `GET /v1/campaigns/{id}/roi`: sent, delivered, opened (push), orders, revenue, own-brand share and lift vs holdout |
| WC-009 | in-progress (API done; console C90 left) | monthly targets per officer / store, versioned declarative incentive rules, payout preview, monthly close job (frozen), `incentive_for` for the FA-024 port |
| WC-013 | in-progress (API done; console C100 left) | `POST /v1/exports` CSV / XLSX of every list resource (step-up, audited, exports bucket, signed URL), `report_schedule` + emailed delivery through an `EmailSender` port |
| AN-015 | done (API / jobs) | Monday 08:00 IST one-page PDF: AN-001 KPIs + top 5 open flags, emailed to owners / directors |
| ST-004 | done (API / jobs) | nightly low-stock (per-store `reorder_level`, tenant default) and 60 / 30-day expiry alerts as notification rows to store managers, deduplicated |
| ST-008 | done (API / jobs; accountant validation is the human gate) | daily per-store Tally CSV + Tally voucher XML + Zoho Books CSV, stored and emailed to accountants; golden-file test |
| VA-F09 | adapter ready | `farmerapp.campaigns.membership.CampaignSegmentMembership` (real `SegmentMembershipPort` adapter) |
| NF-013 | partial | consent records exportable (`resource: consent_records`) |

## Wiring the parent must do (merge of the three M7 branches)

1. **Alembic heads**: this branch adds `0031` (`down_revision "0028"`, branch label `growth`). Merge with
   `0029` (`rules_m7`) and `0030` (`field_p1`) in a merge revision.
2. **VA-F09 `SegmentMembershipPort`** (rules branch): register
   `farmerapp.campaigns.membership.CAMPAIGN_SEGMENT_MEMBERSHIP`. It offers
   `memberships(session, tenant_id, *, farmer_ids=None, now=None) -> list[SegmentMembership]`,
   `farmers_in_segments(session, tenant_id, *, now=None) -> set[UUID]` and
   `members_without_consent(session, tenant_id, *, now=None) -> list[SegmentMembership]`
   (`SegmentMembership(farmer_id, campaign_id, campaign_name, campaign_status, recipient_status)`).
   A farmer is "in a segment" while a target-arm recipient (pending / sent / delivered) of a
   scheduled / sending campaign, or of one finished within 30 days. Adapt the method name to
   the port's if it differs.
3. **FA-024 `IncentivePort`** (field-agent branch): delegate to
   `farmerapp.incentives.service.incentive_for(session, *, tenant_id, officer_id, period_start, period_end) -> IncentiveResult | None`
   (`period_start` inclusive, `period_end` exclusive, IST dates or datetimes; the frozen payout for a
   closed calendar month, else a live preview with the active rules; `None` without active rules or
   for an unknown officer). `IncentiveResult` fields: `officer_id, period_start, period_end, status
   ("preview" | "closed"), rule_set_id, rule_version, eligible, metrics, targets, lines[{component,
   metric, value, amount_paise, capped, note}], gross_paise, clawback_paise, amount_paise, reasons`.
4. **Push**: campaign pushes and stock alerts are `notification` rows (kinds `campaign_message`,
   `stock_low`, `stock_expiry`; i18n keys `notification.<kind>.title|body`). The FCM delivery of the
   field-agent branch picks them up like any other row; add the three keys to the app ARB files.
   Campaign text is in `data.text` (already in the farmer's language).
5. `tests/authz/test_matrix.py`: this branch put its `RouteFixture`s at the **top** of
   `ROUTE_FIXTURES` (plus `_export_resource` / `_RULES_BODY` helpers right above) so the other
   branches' additions at the end merge cleanly.
6. `farmerapp/jobs/cli.py`: one import line at the bottom registers `farmerapp/jobs/growth.py`.
7. Shared test constants touched (merge by adding, not replacing): `tests/admin/test_step_up.py`
   (four step-up operations added), `tests/catalog/test_models.py` (money columns 25 -> 30),
   `docs/deploy/configuration.md` (`EMAIL_*` rows).

## Data model (Alembic `0031_growth`, every table under RLS, expand-only)

`campaign`, `campaign_recipient` (not audited: delivery bookkeeping), `sales_target`,
`incentive_rule_set` (column `version_no` = rule version; partial unique index: one active per
tenant), `incentive_payout` (unique per officer and month), `export_job`, `report_schedule`,
`report_run` (unique `dedupe_key`; not audited), `reorder_level` (unique per store and SKU).

Tenant settings (typed, `PATCH /v1/settings`): `campaigns{attribution_days 14, dlt_templates{},
whatsapp_templates{}, sends_per_run 500, holdout_pct 0}`, `stock_alerts{default_reorder_level 10,
expiry_days [60, 30]}`, `reports{weekly_owner_emails[], accounting_emails[]}` (users carry no email
address), `accounting{sales_ledger_prefix "Sales", output_tax_prefix "Output", round_off_ledger,
cash_ledger, upi_ledger, card_ledger, walk_in_party}`.

Deployment settings: `EMAIL_PROVIDER` `log` (default: logs `email_logged`, sends nothing) | `fake`
| `smtp` (`EMAIL_SMTP_HOST/PORT/USERNAME/PASSWORD/STARTTLS`) | `sendgrid` (`EMAIL_API_URL`,
`EMAIL_API_KEY` from Secret Manager); `EMAIL_FROM`. Exports go to `EXPORTS_BUCKET` (existing).

## Contracts (console)

All money in paise, timestamps UTC, IST where noted. Roles are in `openapi.yaml` (`x-roles`).

### Campaigns (C80-C82) — owner, director, tenant admin write; auditor reads

| Route | Body / query | Answer |
|---|---|---|
| `POST /v1/campaigns/segment-count` | `{segment}` | `{count, excluded_no_consent}` (live count while building) |
| `POST /v1/campaigns` | `{name, channel: sms\|whatsapp\|push, segment, messages: {te, en, ...}, template_key?, attribution_days?, holdout_pct?, notes?}` | 201 `CampaignOut` (draft) |
| `GET /v1/campaigns?status=` | cursor | newest first |
| `GET/PATCH /v1/campaigns/{id}` | PATCH: draft only (409 `invalid_campaign_state`) | `CampaignOut` |
| `POST /v1/campaigns/{id}/schedule` | `{send_at?}` | freezes the consented audience + holdout split; 422 `empty_segment`, `dlt_template_missing`, `whatsapp_template_missing` |
| `POST /v1/campaigns/{id}/cancel` | | draft / scheduled only; pending recipients skipped (`campaign_cancelled`) |
| `GET /v1/campaigns/{id}/recipients?status=` | cursor | `{items[{farmer_id, farmer_name, phone_masked, arm, language, status, skip_reason, dlt_template_id, sent_at, delivered_at, opened_at, error}], counts{status: n}}` |
| `GET /v1/campaigns/{id}/roi` | | `{audience, sent, delivered, failed, skipped, opened (null unless push), orders, converted_farmers, conversion_rate, revenue_paise, own_brand_revenue_paise, own_brand_share, holdout{...} \| null, own_brand_lift, conversion_lift}` |

`segment`: `crop_ids[]`, `stages[]`, `districts[]` (village district, case-insensitive),
`store_ids[]`, `purchase_within_days` + `min_spend_paise` (default window 365 days) or
`no_purchase_within_days`, `visited_within_days` or `not_visited_within_days`, `app_user`
(bool), `app_active_within_days`, `languages[]`. **Consent is not a criterion the console can
switch off**: every audience requires the latest `(farmer, marketing)` consent row to be a grant.
Recipient `status`: `pending → sent → delivered | failed`, `skipped` (`consent_withdrawn`,
`no_app`, `farmer_deleted`, `campaign_cancelled`), `holdout`.
Attribution: an order (placed, not cancelled) by a target recipient after its send and within
`attribution_days`; the latest campaign that reached the farmer before the order wins (last
touch). Holdout: orders in the same window from the campaign start.

### Targets and incentives (C90)

| Route | Roles | What |
|---|---|---|
| `GET /v1/targets?month=&subject_type=` | owner, director, tenant admin, cluster head (cluster), auditor, accountant, store manager (store), officer (own) | `{month, items[TargetOut]}` |
| `PUT /v1/targets` | owner, director, tenant admin, cluster head (own cluster's officers / stores) | `{month, items[{subject_type: officer\|store, subject_id, visits_verified?, new_farmers?, sales_paise?, collections_paise?, own_brand_share_bp?}]}`; upsert, untouched keys kept |
| `GET /v1/incentive-rules`, `GET /v1/incentive-rules/{id}` | admins + auditor, accountant, cluster head | versions newest first `{id, name, version, status, definition, ...}` |
| `POST /v1/incentive-rules` | owner, director, tenant admin | `{name, definition, activate?}` → new version; 422 `invalid_incentive_rules` with `errors[]` |
| `POST /v1/incentive-rules/{id}/activate` | same | previous active → `retired` |
| `GET /v1/incentives/preview?month=&officer_id=&rule_set_id=` | readers + store manager, officer (own; default self) | `IncentiveOut` (`status` `preview` or `closed`) |
| `POST /v1/incentives/preview` | admins | `{officer_id, month, definition}` evaluates an unsaved document (rule editor) |
| `GET /v1/incentives/payouts?month=` | readers | frozen payouts in scope + `total_paise` |
| `POST /v1/incentives/close` | owner, director; **step-up** | `{month}` (ended months only: 409 `incentive_month_open`; 409 `no_active_incentive_rules`) |

Rule document (see `farmerapp/incentives/rules.py`):

```json
{
  "eligibility": {"min_verified_visits": 20, "count_visit_statuses": ["verified"]},
  "components": [
    {"id": "visits", "metric": "verified_visits", "kind": "slab_per_unit",
     "slabs": [{"from": 0, "to": 40, "rate_paise": 0}, {"from": 40, "rate_paise": 2000}]},
    {"id": "sales", "metric": "sales_paise", "kind": "percent", "rate_bp": 100, "cap_paise": 500000},
    {"id": "own_brand", "metric": "own_brand_share", "kind": "threshold", "threshold": 0.4, "amount_paise": 100000},
    {"id": "farmers", "metric": "new_farmers", "kind": "per_unit", "rate_paise": 5000}
  ],
  "multipliers": [{"metric": "attainment.sales_paise", "gte": 1.0, "factor": 1.1}],
  "cap_paise": 1500000,
  "clawback": {"cancelled_orders": true}
}
```

Kinds: `per_unit`, `slab_per_unit` (tiered), `slab_flat`, `percent` (paise metrics), `threshold`.
Metrics: `verified_visits` (VV-005: only `count_visit_statuses`, verified by default), `visits`,
`new_farmers`, `sales_paise`, `own_brand_sales_paise`, `own_brand_share`, `collections_paise`, and
`attainment.<metric>` (actual / monthly target). Order: components (each capped) → multipliers →
total cap → minus clawback (orders placed in an earlier month and cancelled in this one, at every
`percent` sales rate) → never below zero. Ineligible → 0 with `reasons`.

### Exports and scheduled reports (C100)

| Route | Roles | What |
|---|---|---|
| `GET /v1/exports/resources` | every staff role | resources the caller may export: `{name, formats, columns, filters, description}` |
| `POST /v1/exports` | every staff role; **step-up**; resource roles checked inside (403) | `{resource, filters, format: csv\|xlsx\|xml}` → 201 `{id, rows, size_bytes, filename, url, url_expires_at, ...}` |
| `GET /v1/exports`, `GET /v1/exports/{id}` | same | the caller's own exports; `{id}` returns a fresh 15-minute URL |
| `GET/POST /v1/report-schedules`, `PATCH/DELETE /v1/report-schedules/{id}` | owner, director, tenant admin, auditor, accountant, cluster head, store manager; POST / PATCH **step-up** | `{name, resource, filters, format, recipients[email], cron (IST, default "0 8 * * 1"), active}`; admins see every schedule, others their own |

Resources (filters = the list endpoint's query parameters as JSON; rows = the caller's list
scope): `farmers` (agronomist: masked phone), `orders`, `payments`, `visits`, `flags`,
`stock` (every visible store), `audit_logs`, `consent_records` (NF-013; owner, director, tenant
admin, auditor), `tally` / `tally_xml` (format `xml`) / `zoho` (`{store_id, date}`; ST-008).
Errors: 422 `export_resource_unknown`, `export_filters_invalid`, `export_format_unsupported`,
`cron_invalid`; 401 `step_up_required`. CSV is UTF-8 with BOM, formula cells prefixed with `'`;
XLSX is one sheet of inline strings. At most 100,000 rows.

### Stock (ST-004)

`GET /v1/stores/{id}/reorder-levels` (stock readers) → `{store_id, default_reorder_level, items[{sku_id, reorder_level}]}`;
`PUT` same path (owner, director, cluster head, store manager of the store) `{items[{sku_id, reorder_level}]}`.

## Contracts (mobile)

- Farmer app: campaign pushes arrive as `notification` rows `kind = campaign_message`,
  `data {campaign_id, campaign_name, language, text}`; marking the row read sets the campaign's
  "opened".
- Store manager (agent app / console): `stock_low` `data {store_id, store_code, sku_id, on_hand,
  reorder_level, day}`, `stock_expiry` `data {store_id, store_code, sku_id, batch_id, batch_no,
  expiry, days_left, threshold_days, qty}`.
- Officer "My performance" (FA-024) reads `incentive_for` through the field-agent `IncentivePort`;
  `GET /v1/incentives/preview?month=` (own) is also open to officers.

## Jobs (Cloud Scheduler, time zone Asia/Kolkata; `farmerapp.exports.jobs.SCHEDULES`)

| Command | Schedule | What |
|---|---|---|
| `send-campaigns --tenant …` | every minute | due campaigns, ≤ `campaigns.sends_per_run` recipients per run, consent re-checked per batch, then SMS delivery status / push opens |
| `close-incentives --tenant … [--month]` | 1st 06:00 | freeze last month (idempotent) |
| `stock-alerts --tenant …` | daily 01:30 | ST-004 |
| `accounting-export --tenant … [--date]` | daily 02:30 | ST-008 for yesterday, per store, once |
| `run-report-schedules --tenant …` | every 15 min | WC-013 due schedules, as their owner, once per fire time |
| `weekly-owner-report --tenant …` | Monday 08:00 | AN-015, once per week |

## Tests

`tests/growth/`: `test_campaigns.py` (consent-only selection and re-grant, every segment
criterion, **a farmer withdrawing between build and send is skipped**, DLT template required,
push through notification rows + opens, throttling, holdout determinism, ROI attribution window,
last touch and own-brand lift, VA-F09 adapter, API flow), `test_incentives.py` (hand-computed
fixture: 350.00 + 16.00 + 0 + 100.00 = 466.00 × 1.5 = 699.00 − 8.00 clawback = **691.00**, from the
pure engine and from live data; caps, flat slabs, eligibility, invalid documents, VV-005 default vs
counting partial visits, frozen close, the FA-024 port, API scopes and step-up),
`test_exports.py` (cron incl. Monday 08:00 IST, CSV / XLSX writers, scope + step-up + audit,
roles / formats / filters, consent export, scheduled email once per fire time),
`test_reports.py` (weekly PDF text has the KPIs and the top 5 flags in severity order, one page,
Monday schedule, dedupe; stock alerts + dedupe per batch / threshold and until restock; Tally /
Zoho golden headers, balanced vouchers, XML nets to zero, daily job, API scope),
`test_ports.py` (email adapters, settings, CLI). The authz matrix covers every new route.

## Human gates

- DLT registration of promotional SMS templates (TRAI) and WhatsApp Business template approval;
  fill `campaigns.dlt_templates` / `campaigns.whatsapp_templates`. Real SMS / WhatsApp adapters
  (only fake / mockserver exist).
- Email provider account, sending domain (SPF / DKIM), `EMAIL_PROVIDER` + `EMAIL_API_KEY` in
  Secret Manager; owner / accountant addresses in `reports.*`.
- The accountant validates the first Tally / Zoho files against the books (ST-008 acceptance) and
  confirms ledger names (`accounting.*`).
- Cloud Scheduler entries for the six jobs (infra; not in this branch).
- The owner confirms the incentive rules and monthly targets before the first close.

## Notes and follow-ups

- `analytics/owner_home.py` still reads its KPI targets from the tenant setting `targets`; the
  new `sales_target` rows are per officer / store. Wiring store targets into the store-map score
  is a follow-up.
- `dbt/models/marts/campaigns/mart_campaign_roi.sql` is still the placeholder (dbt is outside this
  branch's scope); the replicated tables it needs are `campaign`, `campaign_recipient`.
- Exports are generated synchronously (≤ 100,000 rows, rows streamed from a server-side cursor
  into a spooled file); move to a worker if tenants outgrow it.
- Test-suite hazard found on the way: `farmerapp.api.app` builds an app (and the cached engine)
  at import, before the test env fixture, so job wrappers that open `job_session` in tests talk to
  the **dev** database. The growth wrapper test patches `job_session` to the test session instead.
