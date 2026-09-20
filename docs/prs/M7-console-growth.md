# M7 console: campaigns, targets and incentives, travel approvals, reports, crop health, diagnosis quality and model releases

Branch `feat/M7-console-growth` (worktree of `main` at `f9d2b8d`). Scope: `apps/console`, `design/` and `docs/` only.

PR title: `feat(M7): console campaigns, targets and incentives, travel approvals, reports, crop health map, diagnosis quality and model releases (WC-008, WC-009, WC-013, AN-004..AN-009)`

## Requirement IDs

| ID | Status after this PR | What the console gained |
|---|---|---|
| WC-008 | in-progress (console done; DLT / WhatsApp template registration is the human gate) | C80 list, C81 builder (segment with the live **consented** count, channel, message per language + phone preview, holdout, schedule), C82 results |
| AN-008 | in-progress (console done; the dbt `mart_campaign_roi` body is still a placeholder) | C82: sent / delivered / failed / skipped / opened, attributed orders and revenue, own-brand and conversion lift vs the holdout arm, the conversion window spelled out |
| WC-009 | in-progress (console done; the owner confirms the rules and targets) | C90 targets per officer and store, the versioned rule editor with validation, payout preview of the **unsaved** document, frozen payouts and the monthly close behind step-up |
| WC-013 | in-progress (console done; email provider is the human gate) | C100 run an export with the current filters (step-up), past exports with signed links, scheduled reports with the cron shown in IST and in words |
| AN-004 | in-progress (console segment entry point done; the 360 dashboard on the marts is still left) | C32 segments builder reached from C30, handing its segment to C81 |
| AN-005 | in-progress (no new API fields since M4) | no change: `GET /v1/analytics/stores` returns the same shape C40 / C41 already render; see "Left" |
| AN-006 | in-progress (console done) | crop-health map: graduated district markers on the existing Leaflet / OSM setup, crop and week filters, outbreak flags and a district drill-down |
| AN-007 | in-progress (console done) | C62 now reads `GET /v1/diagnoses/quality`; the browser-side computation is gone |
| AN-009 | in-progress (console done; a summary endpoint would replace the client-side roll-up) | "Data quality" tab on the C70 inbox: flag volume by rule, resolution time, false-positive rate, repeat subjects |
| DX-012 | in-progress (console done) | model-release view: candidates with their evaluation numbers, the current approved version, approve / reject behind step-up |
| FA-023 | in-progress (console done) | C91 travel allowance approvals with computed km, receipts, decisions and the monthly statement export |

## Screens

| Screen | Route | Roles | Component |
|---|---|---|---|
| C80 campaigns | `/campaigns` | owner, director, tenant admin (write), auditor (read) | `components/growth/CampaignsView.tsx` |
| C81 builder | `/campaigns/new[?id=&from=segment]` | owner, director, tenant admin | `CampaignBuilder.tsx`, `SegmentBuilder.tsx`, `PhonePreview.tsx` |
| C82 results | `/campaigns/{id}` | as C80 | `CampaignResults.tsx` |
| C90 targets and incentives | `/incentives?month=&tab=` | admins write; auditor / accountant / cluster head / store manager read; owner + director close | `IncentivesView.tsx`, `RuleEditor.tsx` |
| C91 travel claims | `/travel?month=&officer=&status=` | cluster head + admins decide; auditor, accountant, officer read | `TravelView.tsx` |
| C100 reports and exports | `/reports?tab=` | every staff role (per-resource roles server-side) | `ReportsView.tsx` |
| AN-006 crop health | `/crop-health?crop=&week=&weeks=&district=` | owner, director, tenant admin, auditor, agronomist | `CropHealthView.tsx`, `analytics/maps/CropHealthMap.tsx` |
| C62 diagnosis quality | `/agronomist/quality` | as crop health | `agronomist/QualityView.tsx` (rewritten) |
| DX-012 model releases | `/agronomist/models` | agronomist, owner, director, tenant admin; agronomist + owner decide | `agronomist/ModelReleases.tsx` |
| C32 segments | `/farmers/segments` | the C30 roles | `growth/SegmentsView.tsx` |
| AN-009 data quality | `/flags` (second tab) | the C70 roles | `flags/DataQuality.tsx` |

`lib/nav.ts` gained `CAMPAIGN_NAV_ROLES`, `INCENTIVE_NAV_ROLES`, `TRAVEL_NAV_ROLES`, `REPORT_NAV_ROLES` and `CROP_HEALTH_NAV_ROLES`, and the SideNav five entries; a role that cannot read a screen never sees its entry and gets the explanatory 403 state if it navigates there.

## Consent is the point of C81 (WC-008, DPDP)

The count next to a segment is never a bare audience size. `consentNote()` (`lib/campaigns.ts`, unit-tested, asserted on the exact English sentences in `components/growth/growth.test.tsx`) picks one of three lines:

* "120 farmers with marketing consent will receive this."
* "120 farmers with marketing consent will receive this. 31 matching farmers are left out because they never granted marketing consent or withdrew it."
* "No farmer with marketing consent matches. 8 matching farmers were left out for consent."

An empty segment shows no number at all. Under every count sits the permanent note that consent cannot be switched off and is re-checked per batch at send time, so a withdrawal between scheduling and sending skips that farmer (`skipped / consent_withdrawn` in C82).

## VV-005 on C90

The screen states, from the **active rule document**, whether the rules count verified visits only (the default) or a wider status set, and warns in the second case (`verifiedVisitsNote()`), so a visit count on a payout is never ambiguous.

## Data layer

New typed clients and hooks, all money in integer paise and all timestamps IST where shown:

* `lib/campaigns.ts` + `lib/incentives.ts` + `lib/travel.ts` + `lib/exports.ts` + `lib/mlops.ts` + `lib/data-quality.ts`
* `lib/hooks/growth.ts` (campaigns, targets, rules, previews, payouts, claims, statements, exports, schedules) and `lib/hooks/mlops.ts` (crop health, quality, evaluations, releases)
* deleted: `lib/diagnosis-quality.ts` (+ its test) and `useRecentDiagnoses` — AN-007 replaced the browser-side computation.

Pure helpers carry the logic the screens must not re-derive: `validateDraft`, `consentNote`, `splitArms`, `smsParts`, `sendAtToIso` (a bare `datetime-local` value is read as **IST**, not the browser zone); `validateDefinition`, `verifiedVisitsNote`, `previousMonth` / `recentMonths`; `describeCron` / `cronSummary` / `validateSchedule`; `rollupByDistrict` / `bandFor` / `weekKeys`; `summariseDataQuality`.

## Mock API (Playwright runs offline)

`lib/mock/growth.ts` and `lib/mock/mlops.ts`, wired into `app/api/mock/[...path]/route.ts` (which also gained a `DELETE` handler and resets the two new stores):

* campaigns: segment matching over the seeded farmers with a **fixed fifth without marketing consent** (only ever reported as `excluded_no_consent`), schedule freezing the audience and a deterministic holdout split, an immediate "send job" so C82 has results, per-recipient statuses incl. `consent_withdrawn`, and an ROI with last-touch attribution and holdout lift;
* incentives: a rule engine mirroring `farmerapp/incentives/rules.py` (components -> multipliers -> total cap -> clawback), so editing a rate changes the preview; targets upsert; close behind step-up;
* travel: seeded claims with inline SVG receipts, computed km per day, decisions, the monthly statement;
* exports: the resource catalogue with per-resource roles, `POST /exports` and schedule writes behind step-up, signed (data-URI) links, cron validation;
* mlops: crop-health cells with one deliberate Warangal cotton outbreak, the AN-007 summary with the latest evaluation, and three model releases (candidate / approved / rejected) with the DX-012 transitions and `evaluation_missing`.

`mockStepUpOk()` is now exported from `lib/mock/admin.ts` so the new modules share the real step-up check. Each mock role gained a second phone number (`900000001X`) so spec files running in parallel do not share one number's OTP budget (documented in `apps/console/README.md`).

## i18n

1876 keys in each catalogue after this change (about 190 new) across `campaigns`, `incentives`, `travel`, `reports`, `cropHealth`, `models`, `segments`, `dataQuality`, `quality` and `nav`, with real Telugu, Kannada, Hindi and Marathi translations; five stale `quality.*` keys removed. `lib/i18n.test.ts` (every locale carries every key with the same placeholders) and `scripts/lint-strings.mjs` both pass.

## Tests

* vitest: **367 tests in 58 files, all passing**, of which **58 are new** — `lib/campaigns.test.ts` (12), `lib/incentives.test.ts` (13), `lib/exports.test.ts` (11), `lib/data-quality.test.ts` (6), `lib/mlops.test.ts` (6), `components/growth/growth.test.tsx` (10: payout-preview rendering, the consented-count copy, the cron sentence); `lib/diagnosis-quality.test.ts` was deleted with its module.
* Playwright: **36 tests, all passing**, of which **9 are new** — `e2e/growth.spec.ts` — build a campaign on a consented segment -> schedule -> results; edit an incentive rule -> preview payout; approve a travel claim; run an export (step-up) and find it in the history; crop-health map filter and drill-down; C62 from the API; approve a model release (step-up); the flags data-quality tab; C30 -> C32 -> C81. `e2e/agronomist.spec.ts` updated for the new C62.
* `npm run check` (lint + string lint + typecheck + vitest + build) passes.

## Design

`design/screens/C62.md` (rewritten, plus the model-release view), `C80.md`, `C81.md`, `C82.md`, `C90.md`, `C91.md`, `C100.md`.

## Left / follow-ups

* **AN-005 store performance**: `GET /v1/analytics/stores` and `/stores/{id}` returned nothing new in M7, so C40 / C41 are unchanged. The marts (`mart_store_category_monthly`, `mart_store_snapshot`, `mart_credit_accounts`) carry more than the API exposes — the API half has to surface category x brand margin and stock turns before the console can show them.
* **AN-004 farmer 360**: only the segments entry point landed here; the 360 dashboard on `v_farmer_360` / `v_farmer_segments` (LTV, churn risk, segment membership) is still to come, and the segment / churn thresholds are working definitions the owner must confirm.
* **AN-009**: the tab rolls up `/v1/flags` in the browser (the same approach C62 used before AN-007). A `mart_flags_weekly`-backed summary endpoint should replace it.
* A segment built on C32 is handed to C81 through `sessionStorage` (nothing leaves the browser); a saved-segment resource would be better once the API has one.
* Campaign recipients are fetched as a single page (50 rows); the API's cursor is not paged through yet.
* Human gates unchanged from the API PR: DLT / WhatsApp template registration, the email provider and sending domain, the owner confirming incentive rules and targets, and the agronomist-labelled held-out set for DX-011 (until it exists, C62 shows "No evaluation run yet").
