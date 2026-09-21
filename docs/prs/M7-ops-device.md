# M7 — data and cost alerts, security spikes, certificate and secret age, cost model, app crash and trace reporting, device matrix, formatting audit, accessibility and literacy gates

Branch `feat/M7-ops-device`. Closes **OPS-011, OPS-012, OPS-013, OPS-014, NF-001, NF-008,
NF-009, NF-010, NF-014, NF-015**.

Three strands that happen to share a milestone: the last four SPEC 12.2 monitors, the cost
work NF-015 asks for, and the device / accessibility / literacy gates that until now were
promises in a table rather than things a test could fail on.

## OPS-011 — Datastream lag and dbt failure → ticket to the data owner

Two signals, both sev2 to `data-owner`, both in `infra/modules/monitoring/data.tf`.

**Datastream** publishes its own metric, so that half is a policy on
`datastream.googleapis.com/stream/freshness` above 1800 s for 15 minutes, per stream id taken
from `module.analytics.stream_name` — no stream, no alert, which matters because `dev` has no
stream until the human gate in the CDC runbook is done. A second policy catches
`unsupported_event_count > 0`: rows that could not be replicated at all are *silently* missing
from the marts, which is worse than lag because nothing looks wrong.

**dbt publishes nothing.** It writes `target/run_results.json` and exits. The mechanism this
change defines is a wrapper, `dbt/scripts/dbt_run.py`, which every invocation now goes through
(the Makefile targets, `ci-dbt.yml`, and the scheduled Cloud Run job when it exists). It runs
dbt, reads the artefact, and emits one structured JSON line per invocation in the same shape
as the API's structlog output, so the log-metric machinery reads it with no special cases:

| `event` | Level | Carries |
|---|---|---|
| `dbt_run_result` | info | command, target, status, nodes, errors, warnings, elapsed_s, invocation_id, exit_code |
| `dbt_run_failed` | error | + `first_failure` (a metric label) and `failures[]` with node, status and a trimmed message |
| `dbt_source_freshness` | info | source, state, max_loaded_at, staleness_s, warn/error thresholds |
| `dbt_source_stale` | error | the same, for a source past its AN-010 error threshold |

Two details worth arguing with:

- **A run that dies before writing an artefact is still a failure.** A parse error or a bad
  profile leaves no `run_results.json`; the wrapper reports `first_failure = "no-artifact"`
  rather than reporting nothing, because "dbt did not produce a result" is exactly the case a
  naive parser silently passes.
- **`warn`-severity tests are counted, not escalated.** AN-012 uses warn severity for
  data-quality signals; turning those into OPS-011 tickets would train the data owner to
  ignore the alert within a week.

With `DBT_CLOUD_LOG_PROJECT` set, the wrapper also writes the line to Cloud Logging
(`logName=projects/<p>/logs/dbt`) using the run's own credentials — the WIF token `ci-dbt.yml`
already has. That is what makes OPS-011 real *today*, without waiting for a dbt Cloud Run job
to exist. A failure to write is reported on stderr and never changes the exit code: an
alerting side-channel must not break the build it is watching.

`--self-test` runs the parser over synthetic artefacts with no dbt, no cloud and no
credentials (20 assertions), and runs in `make check-dbt` and in CI.

## OPS-012 / NF-015 — cost

New module `infra/modules/cost`, plus `docs/cost-model.md` and
`docs/runbooks/cost-and-budget.md`.

### The model, and what it found

`docs/cost-model.md` prices every resource at 5 stores and at 50, with the assumptions written
down (asia-south1 list prices, ₹88/USD, 730 hours, the traffic shape) so the estimate can be
argued with rather than believed.

**The pilot breaches NF-015 by 2.1× on the SPEC 9.2 `prd` shape.** HA-regional Cloud SQL plus a
read replica is ₹37,200 of a ₹25,000 budget before a single request is served. That is not a
contradiction so much as two requirements written for different moments: NF-006 asks for
**99.5% in the pilot** and 99.9% at SaaS launch, and 99.5% is met by a zonal instance with
backups and PITR (a zone failure is a restore, not a failover — the runbook already covers it).
Three decisions get the pilot to **₹23,500**:

1. zonal Cloud SQL until SaaS launch,
2. no read replica — from M7 the console reads the BigQuery authorised views (AN-013), so the
   replica pays twice for the same answer,
3. `console` min-instances 0 — a 2-second cold start on a manager's laptop is not the problem
   NF-005 is about.

At 50 stores HA *is* justified and the shape lands at **₹77,500** against ₹1,00,000 — but only
with the committed-use discount and without the replica. Without both it is ₹1,14,700, so the
levers are load-bearing and are written into the prd tfvars with a comment rather than left to
be rediscovered.

SMS and LLM are excluded from the budget by NF-015 and modelled separately, because at 50
stores they are **₹1,94,800/month — larger than the infrastructure bill**. The lever for the
LLM is the corpus, not the model: each point of fallback rate is about ₹6,000/month at that
scale.

### The measurement

| Piece | What |
|---|---|
| `farmerapp_cost` dataset | Where the Cloud Billing export lands. Terraform creates it; enabling the export is a billing-account human gate. |
| Views | `v_cost_daily_by_service` (by service **and** by labelled component), `v_cost_daily_by_sku` (which knob), `v_cost_daily_total`, `v_cost_anomaly_daily` (each day against the 7 before it), `v_cost_monthly_vs_budget`, `v_cost_daily_by_tenant`. |
| Daily cost watch | A BigQuery scheduled query, not a Cloud Run job: the computation is one SQL statement over a BigQuery table and a job would need an image, a service account and a scheduler for the same answer. It writes `cost_watch_daily` and then `RAISE`s on a breach, so the **failed transfer run** is the metric the alert watches. |
| Budget | `google_billing_budget` at 50 / 90 / 100 / 130%, actual *and* forecast, publishing to `cost.budget`. |
| Alerts | Daily anomaly; LLM spend per tenant; SMS spend per tenant; budget threshold. All sev2 to owner + platform lead — SPEC 12.2 says "notify", and paging someone at 03:00 about a bill teaches them to ignore pages. |

**The deliberate trade in the cost watch:** a genuine query error and a breach look identical
to the alert. That is the point — both mean "the cost watch did not come back clean" — and the
runbook's first step is the table, which says which it was.

### Tenant attribution, stated honestly

Every Cloud Run service and job now carries `app`, `env`, `component` and `tenancy` labels
(`modules/run_service`, `modules/run_job`). But:

- **Nothing is single-tenant.** `api`, `worker`, `console`, `embed`, Cloud SQL and the buckets
  serve every tenant, and the jobs take `--tenant-id` arguments rather than running one job
  per tenant. A label on a shared service can say *what* it is, never *whose*.
- So shared cost is **apportioned** by the tenant's share of the day's visits + order lines
  from the marts. A tenant that mostly reads pays for a bill it did not create.
- **LLM and SMS genuinely are per tenant** (`llm_call` and `otp_sent` both carry `tenant_id`),
  and they are the two costs that scale with one tenant's behaviour. They are not in the
  billing export at all — different vendors — so they are metered from log-based metrics and
  priced with a rate card.

Those limits are written into the view's own description, the dashboard note and the cost model,
so nobody invoices a customer from this view by accident. A per-tenant *invoice* needs
per-tenant metering of requests, storage and database time; that is a SaaS pricing decision
with real engineering behind it.

The Monitoring cost dashboard stops being a placeholder: usage drivers (Cloud Run instance
time, SQL CPU, log bytes, BigQuery scanned bytes, bucket size) plus SMS sends and LLM tokens
**by tenant**. The rupees stay in BigQuery because Cloud Monitoring cannot query it and GCP
publishes no spend metric.

## OPS-013 — security spikes → page

Three sev1 policies (`infra/modules/monitoring/security.tf`):

- **SCC high findings.** Terraform creates the `scc.findings` topic and grants the SCC
  notification service agent publish on it. Pointing SCC at the topic is org-level and a human
  gate, so the exact `gcloud scc notifications create` is in the alert's own documentation;
  until then the topic stays empty and the alert never fires. Anything published *is* a
  HIGH/CRITICAL finding, because the filter lives in the notification config — so the condition
  is "any message".
- **Cloud Armor spikes.** A log-based metric over the load-balancer request log
  (`enforcedSecurityPolicy.outcome="DENY"`; `modules/lb` already logs at 100% on the API
  backend), alerting above 500 blocks in 5 minutes per backend. The runbook query separates the
  two causes that matter — many IPs on one rule is an attack doing its job; one rule on real
  paths from Indian IPs is a rule locking real users out.
- **OTP send spikes.** `farmerapp_otp_sent{channel="sms"}` above 300 in 5 minutes **for one
  tenant**. The metric gained a `tenant_id` label (the log line has carried it since M5), which
  is what makes pumping visible at all — and OPS-012 reuses the same label for spend.

## OPS-014 — certificate expiry and secret age → ticket

Neither needs a scheduled job, which is the interesting part.

**Certificates:** the OPS-001 uptime checks already run `validate_ssl` from three regions, so
Cloud Monitoring exports `uptime_check/time_until_ssl_cert_expires` in days. One sev2 alert per
checked host under 21 days. Google-managed certificates renew ~30 days out, so this firing
means the renewal is stuck — the alert text says to check the A record, and warns that a new
leaf needs a matching SEC-009 pin **shipped in an app release first**.

**Secrets:** `modules/secrets` now owns the `secret.rotation` topic, grants the Secret Manager
service agent publish on it (without which creating a secret with a rotation period is rejected
outright) and sets `rotation_period = 90 days` on every secret. Secret Manager then publishes
the reminder itself: a message on the topic *is* "secret age > 90 days". No polling, no job, and
the reminder survives Terraform being idle.

Only the topic **name** is shared with `modules/monitoring`, never a resource reference —
monitoring already sits downstream of the jobs, which sit downstream of the secrets, so a
reference would have closed a dependency cycle.

## NF-014 — the app half of observability

The API and worker half landed in M5. This is the phone.

**Traces.** `SecureApiClient` — the single client both apps send every API call through — now
puts a W3C `traceparent` on every request (`packages/core/lib/src/obs/trace_context.dart`). The
API already accepts one, continues it through SQLAlchemy, injects it into Pub/Sub attributes
and picks it up in the worker, so a farmer's tap and the spans behind it are finally one trace,
and every log line on the way shares its `trace_id`. The same id is set as the Crashlytics
`trace_id` custom key, so a crash report and the API's logs meet.

The apps run **no OpenTelemetry SDK**, deliberately: a mobile exporter adds a background queue
and several hundred kilobytes against a 25 MB APK budget (FM-014) for spans nobody reads. The
useful span tree is on the server; what the phone has to do is start the trace and hand the id
over. Head sampling is on the phone, and an unsampled request still carries a `traceparent` —
it only asks the server not to record spans, so the log lines still join.

**Crashlytics, Performance, Remote Config.** Three seams in `packages/core/lib/src/obs/` with
Firebase adapters in `apps/*/lib/observability.dart`, behind exactly the same no-Firebase
fallback as the FA-007 push transport. A build without `google-services.json` gets
`NoCrashReporter`, `NoPerformanceMonitor` and `LocalRemoteFlags` and works unchanged:
observability is diagnostics, never a dependency of the farmer's work. `runWithCrashReporting`
installs the reporter on `FlutterError.onError`, `PlatformDispatcher.onError` and a guarded
zone around start-up, so an error on the start-up path is a reported crash rather than a blank
screen. Reporting is off in debug, because a developer's own crashes would swamp the
crash-free-sessions number that decides whether a release ships (OPS-002).

**Remote config** is fetched *before the first frame* (`remoteFlagOverrides`, like
`settingsOverrides` in FA-004): a kill switch that takes effect on the second start is not a
kill switch. Every flag has a local default equal to the shipped behaviour, unknown keys are
ignored and missing keys keep their default, so an old app and a new config never disagree
dangerously. Intervals are clamped on read — a remotely configured 0-second location sampling
interval would flatten a battery within the hour.

The division of labour with the two config planes that already existed is written into the
file: tenant settings are what a **tenant owner** decides (audited, per tenant); remote config
is what **we** decide across every tenant without shipping an APK. Where both speak — only
`on_device_crop_guess` today — the tenant's opt-in is required and remote config can only take
it away.

## NF-001 — devices

`docs/device-matrix.md`: the support matrix, an explicit note on what CI can and cannot prove,
the three reference devices (and why device C, the 2 GB entry-level phone, is the acceptance
device), and a five-section manual test plan covering install, the farmer flows, the officer
flows that break on cheap phones, memory and stability, and an accessibility spot check.

Automated guards:

- `apps/mobile/test/device_support_test.dart` asserts `minSdk = 26` in both apps, that no
  manifest `<uses-sdk>` quietly overrides it, that both apps share the floor, and that the size
  gate really is per ABI. `minSdk` moves on its own — a plugin upgrade raises it, `flutter
  create` regenerates the file — and nothing complains until an Android 8 phone finds the app
  missing from the Play Store.
- `ci-mobile.yml` now runs `APK_SIZE_CHECK=1 ./tool/check.sh` instead of its own arm64-only
  build, so CI builds **both** shipped ABIs the way a release is built (obfuscated, R8) and
  fails on the larger. Play delivers one ABI per device, and armeabi-v7a is exactly the older
  phone NF-001 is written for. Measured with the three new Firebase SDKs: **armeabi-v7a
  17.01 MB, arm64-v8a 17.66 MB** against the 25 MB budget.
- `AppStartTrace` measures `main()` → first **rasterised** frame (via `addTimingsCallback`, not
  a post-frame callback, which fires before the raster work and flatters the number on a slow
  GPU) and `main()` → interactive. Both go to Firebase Performance *and* to `debugPrint`, so a
  release build on device C gives the NF-005 number with `adb logcat` and no cloud at all.

## NF-008 — formats and the translation review pack

The audit found Indian grouping and DD-MM-YYYY already correct in both the app and the console.
The gap was **units and non-money numbers**: acres were formatted ad hoc at each call site
(`acres.toStringAsFixed(2)`), so a large holding printed as `100000.00` rather than `1,00,000`.
Added `formatIndianDecimal`, `formatAcres` and `formatVolume` (ml below a litre, L above — the
way a pesticide label and a spray tank are actually written) and routed every acre call site
through them.

The **review pack** is the half NF-008 was really blocked on: "reviewed by a native speaker" is
a human gate, and a Telugu-speaking agronomist cannot be handed five 2,000-line JSON files.
`tool/translations.dart export` produces one CSV per language — 1,516 strings — carrying the
English, the current translation, the ARB description, the placeholders that must survive, and
**the screens each string appears on**, found by scanning the sources for `l10n.<key>`. Context
is the whole point: "Done" on a payment screen and "Done" on a photo screen are different words
in Telugu. The file starts with a UTF-8 BOM, because without it Excel on Windows renders Telugu
as mojibake and the reviewer "fixes" text that was never broken.

`import` reads the sheet back (BOM, CRLF, columns reordered — all of which happen once a file
has been through Excel) and **refuses the whole file** if any row dropped or invented a
placeholder. Partial application is worse than none: a lost `{count}` is a runtime crash in one
language and nobody else's, which is exactly the bug that survives to production. Rows left
blank are skipped, because a reviewer working through 2,000 strings over a week sends back a
partly filled sheet and that has to be normal.

## NF-009 — accessibility

**Contrast, over the tokens rather than over screenshots.**
`packages/core/test/theme/contrast_test.dart` checks every text pair at 4.5:1 and every control
boundary and meaningful graphic at 3:1, across all three themes, and proves its own ratio
function against the WCAG worked examples. It found six real failures:

| Theme | Token | Was | Now |
|---|---|---|---|
| light | `textMuted` (captions, helper text) | 3.61:1 | **4.80:1** |
| light | `statusSuccess` on its container | 4.45:1 | **5.30:1** |
| light | `statusWarning` on its container | 3.70:1 | **5.58:1** |
| dark | `statusDanger` on its container | 4.38:1 | **5.37:1** |
| sunlight | `secondaryOn` on `secondary` | 3.75:1 | **5.59:1** (white, not black) |
| light / dark | `border` used as a text-field outline | 1.35:1 | split, below |

The last one is the interesting one. A single `border` token was doing two jobs: the decorative
hairline between rows, where WCAG 1.4.11 does not apply, and the outline of a text field, where
it does. Splitting it into `border.default` and `border.strong` (5.51:1, used by `inputBorder`
and Material's `outline`) fixes the control without making every divider heavy. The confidence
and visit ramps are aliases of the status hues, so they followed on their own — which is what
aliases are for. Goldens regenerated.

**Targets and labels.** `apps/farmer/test/a11y_test.dart` walks every farmer route asserting
`androidTapTargetGuideline` (48 dp), `labeledTapTargetGuideline` (an icon-only control must
carry a label a screen reader can announce) and no rendered text below 12 sp. Two more tests
prove the gates actually fail — on a 32 dp target and on a bare icon — because a gate nobody
has seen fail is a gate nobody can trust. Three real fixes came out of the walk:

- flutter_map installs gesture recognisers even with `InteractiveFlag.none`, so every farm map
  was an unlabelled tappable node under a labelled container. Naming that node (rather than
  excluding the subtree) keeps the corner and position markers, which carry their own labels.
- The consent `Switch` announced "switch, on" and nothing about *what* was being consented to.
  On a DPDP consent toggle (NF-013) that is the whole meaning.
- F41's Material `CalendarDatePicker` had 43.4 dp day cells, because Material sizes a cell at
  width / 7 and the screen's 16 dp side padding ate the difference. The calendar is now the one
  full-bleed item on that screen: 49 dp. The design (F41.md, from SPEC 13.3) asks for a
  calendar, so the fix is layout, not a redesign.

**Audio.** F02 (phone) and F03 (OTP) — the only two screens a farmer types on, and so the two
that most need reading aloud — now speak their instruction. The phone prompt speaks the title
*and* the helper, because the helper is the part that says what to type.

## NF-010 — literacy

The route walk already proved no farmer screen asks for text outside F02 and F03. It now also
asserts that `AppRoutes.typingAllowed` **equals** `{phone, otp}` — a closed set, so a third
screen added to it fails the test rather than passing it — and that both of those screens open
a **number pad** rather than a letter keyboard. "No typing beyond phone and OTP" is only true if
those two are themselves usable by someone who cannot read a QWERTY layout.

The walk is shared with the NF-009 test through `allPaths`, so a screen added to the router is
covered by both gates the moment it exists.

**Flows that still require typing: none.** F02 and F03 only, both numeric.

## Checks

| Check | Result |
|---|---|
| `cd apps/mobile && ./tool/check.sh` | OK — core 725 (1 skipped), agent 259, farmer 210, workspace tooling 34 |
| `cd apps/mobile && APK_SIZE_CHECK=1 ./tool/check.sh` | OK — armeabi-v7a **17.01 MB**, arm64-v8a **17.66 MB** (budget 25 MB), release manifest verified |
| `cd infra && ./scripts/check.sh` | OK — fmt, validate ×4, `terraform test` 35 passed (analytics 7, **cost 5**, db_budget 9, **monitoring 6**, run_job 4, run_service 4), checkov 115 passed / 0 failed |
| `dbt/scripts/dbt_run.py --self-test` | 20 assertions passed |

Not run (owned by other agents this milestone): the API and console checks.

## Human gates

| Gate | Blocks | Where |
|---|---|---|
| Billing admin enables the Cloud Billing export and sets `billing_export_table` | the cost views, the daily anomaly watch (the LLM/SMS alerts work without it) | docs/runbooks/cost-and-budget.md |
| Billing admin sets `billing_account` | the NF-015 budget resource | same |
| Org owner points SCC at the `scc.findings` topic | OPS-013 SCC findings | the alert's own documentation |
| Firebase projects + `google-services.json` per flavour | Crashlytics, Performance, Remote Config, and the OPS-002 crash-free number | docs/runbooks/bad-mobile-release-rollback.md |
| `roles/cloudtrace.agent` on the api / worker SAs | traces reaching Cloud Trace | docs/runbooks/observability.md |
| The three reference devices, and a completed device-C pass per release | NF-001 sign-off | docs/device-matrix.md |
| Native-speaker review per language | NF-008 sign-off | the review pack above |
| TalkBack walk and an outdoor Sunlight pass | NF-009 sign-off | docs/device-matrix.md §5 |
| Product owner's decision on the pilot Cloud SQL shape | NF-015 pilot budget | docs/cost-model.md |

## Files

**Infra** — `modules/cost/` (new: main, views, alerts, variables, outputs, versions, tests),
`modules/monitoring/{data,security,certs}.tf` (new), `modules/monitoring/tests/ops.tftest.hcl`
(new), `modules/monitoring/{main,variables,log_metrics,dashboards}.tf`,
`modules/secrets/{main,outputs}.tf`, `modules/run_service/{main,variables}.tf`,
`modules/run_job/{main,variables}.tf`, `envs/{dev,stg,prd}/{main,variables,outputs}.tf` and
their tfvars.

**Analytics** — `dbt/scripts/dbt_run.py` (new), `dbt/README.md`, `Makefile`,
`.github/workflows/ci-dbt.yml`.

**Mobile** — `packages/core/lib/src/obs/` (new: `trace_context`, `crash_reporter`,
`performance_monitor`, `remote_flags`), `packages/core/lib/src/security/api_http_client.dart`,
`packages/core/lib/src/{theme/app_theme,widgets/map_panel,widgets/consent_card,utils/format}.dart`,
`packages/core/lib/src/tokens/tokens.g.dart`, `apps/{agent,farmer}/lib/observability.dart`
(new), `apps/{agent,farmer}/lib/main.dart`, `apps/farmer/lib/screens/{phone,otp,welcome}_screen.dart`,
`apps/farmer/lib/screens/advisory/add_crop_screen.dart`, `apps/farmer/lib/widgets/farm_edit.dart`,
`apps/agent/lib/screens/farmers/wizard_copy.dart`, `lib/translation_pack.dart` (new),
`tool/translations.dart` (new), `design/tokens.json`, goldens, and the tests named above.

**Docs** — `docs/cost-model.md` (new), `docs/device-matrix.md` (new),
`docs/runbooks/cost-and-budget.md` (new), `docs/runbooks/{observability,datastream-cdc-setup,README}.md`,
`docs/progress.md`, this file.

## Follow-ups

- A scheduled dbt **Cloud Run job** in stg/prd. The alerting path already accepts it (the log
  metric matches `job_name="dbt"`), but the job needs a dbt image and a place in `local.jobs`.
- `llm_call_log` and `otp_challenge` are not in the Datastream allowlist, so per-tenant LLM and
  SMS **rupees** are alert thresholds and dashboard tiles rather than a BigQuery view. Adding a
  minimal projection of both (tenant, day, tokens / count — no prompts, no phones) would let
  `v_cost_daily_by_tenant` carry the full picture. That is an AN-014 allowlist decision.
- The agent app has no route-walk accessibility test. Officers type by design (FA-005 gives
  them voice input), so NF-010 does not apply, but the 48 dp and label gates should.
- Recorded audio clips by native speakers replace device TTS behind the existing `AudioPrompt`
  seam once the NF-008 review is done.
