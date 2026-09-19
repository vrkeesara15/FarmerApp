# M7 — remaining validation rules, review agent, officer flag view, rule precision

Branch `feat/M7-rules` (from main `dc29690`). Requirements: VA-F04, VA-F05, VA-F07, VA-F09,
VA-F10, VA-E06, VA-E07, VA-E09, VA-E10, VA-E11 (SPEC 6.2 / 6.3), VA-004, VA-005, VA-006
(SPEC 6.4), SEC-027 for the review agent's LLM calls.

## What changed

### Ten rules (YAML + module + golden fixtures each)

| Rule | Check | Mode | Severity / owner |
|------|-------|------|------------------|
| VA-F04 | farm centroid outside the tenant `service_area` districts (bbox or polygon), or on water / built-up / road through `LandCoverPort` | batch | medium, store manager |
| VA-F05 | crop + sowing date vs season and `crop_calendar` (district row, else state row; windows wrap the year; ±15 days); `season_mismatch`, `sowing_outside_window`, `sowing_in_future` | batch | low, store manager |
| VA-F07 | registered ≥ 60 days ago and never a confirmed visit, a purchase (order not draft / cancelled) or an app login (refresh token of the farmer's login) | batch | medium, store manager |
| VA-F09 | in a campaign segment (`SegmentMembershipPort`) with marketing consent missing or withdrawn (latest `consent_record`) | batch | high, store manager + auditors |
| VA-F10 | a khata debit overdue > 90 days (FA-022 FIFO ageing), or a new debit written while a debit was overdue | batch | medium, store manager |
| VA-E06 | > 3 h of a duty session with no visit check-in / check-out, no stop boundary and no movement ≥ 100 m | batch | low, cluster head |
| VA-E07 | TA claim km vs the sum of `duty_session.km` differ by > 15 % (`TravelClaimPort`) | event `ta.claim.submitted` | medium, cluster head |
| VA-E09 | discount above `discount_policy_max_bps`; sale to a farmer with a staff phone (SEC-026 hash); ≥ 3 cancellations after the `incentive_cutoff_day` of orders placed in that incentive period | batch | high, cluster head + auditors |
| VA-E10 | variance above `day_close_variance_threshold_paise` (event on `CashVarianceDetected`, re-checked nightly); ≥ 3 small variances in 14 days by one closer (batch) | event `day_close.variance` + batch | medium, cluster head |
| VA-E11 | verified visits down > 30 % week on week for two complete IST weeks (coaching) | batch | low, cluster head |

* `farmerapp/rules/checks/va_*.py`, `rules/VA-*.yaml`, `rules/fixtures/VA-*/` (positive,
  negative, plus `VA-F04/negative-no-service-area`, `VA-F09/negative-no-campaigns` — the
  port returns no rows until campaigns exist —, `VA-E10/{positive,negative}-repeated`).
  `tests/rules/test_fixtures.py::test_rules_exist` now requires exactly the 21 rules.
* Ports (`farmerapp/rules/ports.py`): `SegmentMembershipPort` (WC-008 registers the real
  one), `TravelClaimPort` (FA-023), `LandCoverPort` (human gate below); null adapters by
  default, in-memory fakes for fixtures (`override_ports`).
* Event seams (`farmerapp/rules/events.py`): the day close now `await bus.dispatch(...)`es
  `CashVarianceDetected` (was `publish`; plain subscribers still run) and VA-E10 subscribes
  with a writing handler in the close's transaction; `on_travel_claim_submitted(session,
  tenant_id, claim_id, officer_id=, at=)` is the call the travel write path makes.
* Tenant settings (additive): `service_area.districts[]` (code, name, state, bbox | polygon),
  `discount_policy_max_bps` (1000), `incentive_cutoff_day` (25); PATCH-able.
* Migration `0029_rules_m7` (down_revision `0028`, branch label `rules_m7`): `crop_calendar`,
  `flag_summary`, `rule_tenant_override` (all RLS), `llm_call_log.flag_id`. Expand-only.
* Seed (`jobs seed`): demo tenants get a service area (±0.4° boxes around each store) and,
  for Telangana, the crop calendar of the six pilot crops (`farmerapp/rules/reference.py`).

### VA-004 review agent (`farmerapp/flags/review_agent.py`)

* Bundle = rule, severity, subject, record ids, scrubbed metrics, counts of points / polygons
  / photos. No lookups, no flag title (VA-F02 puts a name there), no coordinates, no photos;
  keys carrying names / phones / addresses dropped, 10+-digit runs masked to the last four
  (SEC-027).
* `ClaudeFlagSummaryClient` on `anthropic.AsyncAnthropic` (model `FLAG_SUMMARY_LLM_MODEL`,
  default `claude-opus-5`), `output_config={"format": {"type": "json_schema", ...},
  "effort": "low"}`, schema `summary_lines` / `suggested_action` / `cited_record_ids`,
  `additionalProperties: false` (array length checked client-side: structured outputs do
  not enforce array constraints). `stop_reason` checked first: `refusal` -> no summary,
  `stop_details` logged. Every cited id and every id-shaped string in the text must be in
  the bundle; otherwise rejected and retried once with the reason, then `invalid`.
  429 / 5xx / connection -> deferred (worker nack, job retries next run; 3 attempts max).
* Every attempt in `llm_call_log` (flag_id, prompt, raw output, tokens, stop reason, kept one
  year). Results in `flag_summary`; `GET /v1/flags/{id}` returns `automated_summary` (label
  key `flag.summary.automated_label` = "Automated summary — verify evidence") to reviewers
  only, never to the subject.
* Runs after the flag is committed: the nightly rules job and the worker's event path
  summarise what they raised; worker topic `flag.created`; `jobs flags-summarise` sweeps
  flags raised on the API path. `FLAG_SUMMARY_LLM=off` (default) does nothing.

### VA-005 officer view

* `GET /v1/flags/mine` (`?state=open|resolved`), `GET /v1/flags/mine/{id}`,
  `POST /v1/flags/mine/{id}/explanations` — any staff role (a store manager can be the
  subject of VA-E10). The subject sees state `open` / `in_review` / `resolved` (escalations
  and reviewer notes stay internal), evidence ids + metrics without record summaries, their
  own explanations, and the outcome (status, label, note) only once resolved; explaining a
  resolved flag is 409 `flag_resolved`.
* A subject can no longer move their own flag: 403 `subject_cannot_review`; the detail shows
  no allowed transitions and no automated summary to them.

### VA-006 precision

* `farmerapp/flags/precision.py`: TP / FP from the resolution labels (`resolved_valid` =
  false positive), per rule, last week and last four weeks.
* `jobs rules-quality-report` (weekly): report as a `rule_quality_report` notification to the
  tenant admins (owner if none); a rule under 30 % over four weeks with ≥ 5 resolutions is
  switched off for the tenant (`rule_tenant_override`, source `auto_precision`, reason with
  the numbers, audited `rule.auto_disable`); the engine skips it (`RunReport.skipped`).
* `GET /v1/flags/rules` (owner, director, auditor, tenant admin) lists every rule with its
  precision and state; `POST /v1/flags/rules/{id}/enable` (owner, tenant admin, step-up)
  re-enables it (audited `rule.enable`), restarting its precision window.

## Tests

`tests/rules/test_fixtures.py` (21 rules, every fixture twice for batch idempotency),
`tests/rules/test_m7_rules.py` (event seams, ports, calendar maths, service area, seed),
`tests/flags/test_review_agent.py` (fake `AsyncAnthropic`: call shape, citations, retry,
refusal, temporary errors, logging, PII scrub, sweep + worker, API exposure),
`tests/flags/test_subject_view.py`, `tests/flags/test_precision.py`, authz matrix rows for
the new routes. OpenAPI regenerated.

## Human gates / follow-ups

* **Land cover (VA-F04)**: load ESA WorldCover 10 m (plus a road layer, e.g. OSM) for the
  pilot districts into PostGIS and register a `PostgisLandCoverPort`; until then only the
  district check runs.
* **District boundaries (VA-F04)**: the demo service areas are ±0.4° boxes; replace with
  Survey of India / LGD district polygons per tenant (`PATCH /v1/settings`).
* **Crop calendar (VA-F05)**: agronomist review of the Telangana windows
  (`farmerapp/rules/reference.py`); add district rows where needed.
* **Policies (VA-E09)**: owner confirms the discount policy (10 %) and incentive cut-off
  day (25th) per tenant.
* **Infra (parent / infra agent)**: ~~Pub/Sub topic `flag.created` + worker push subscription;
  Cloud Scheduler jobs `flags-summarise` (every 10 min) and `rules-quality-report` (Monday
  03:00 IST); `FLAG_SUMMARY_LLM=claude` + `ANTHROPIC_API_KEY` on the jobs service~~ — **done
  2026-09-19 in `feat/M7-farmer-p1-api`** (`var.flag_summary_llm`: off in dev, claude in
  stg / prd; the topic gets its DLQ and push subscription from `modules/pubsub`).
  Still open: `.env.example` lines for `FLAG_SUMMARY_LLM*` (outside both branches' paths).
* **Integration**: WC-008 registers its `SegmentMembershipPort`; FA-023 registers its
  `TravelClaimPort` and calls `on_travel_claim_submitted` after a claim is submitted.
* **Console / apps**: the flag detail should render `automated_summary` under
  `flag.summary.automated_label`; the officer app a "My flags" screen on `/v1/flags/mine`;
  i18n strings for `notification.rule_quality_report.*`.
