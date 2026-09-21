# Observability reference (SPEC 12): alerts, SLOs, dashboards, log contract

Everything here is Terraform in `infra/modules/monitoring` (per env, wired in
`infra/envs/*/main.tf`). Nothing is clicked together in the console except the channels that
hold tokens (Slack, PagerDuty) and Firebase Crashlytics.

## Channels

| Variable (env tfvars) | Receives | Created by |
|---|---|---|
| `notification_email` | Sev 1, 2, 3 | Terraform (e-mail channel) |
| `page_channels` | Sev 1 | human (PagerDuty / SMS; token) |
| `ticket_channels` | Sev 1, 2 | human (Slack `#farmerapp-ops`; token) |
| `digest_channels` | Sev 3 | human |
| `runbook_base_url` | link base in every alert | set to `https://github.com/<org>/farmerapp/blob/main/docs/runbooks` once the remote exists |

## Alert inventory

| ID | Alert policy (display name) | Severity | Owner | Runbook |
|---|---|---|---|---|
| OPS-001 | `[env] api / console / webhook down` — uptime from ASIA_PACIFIC, EUROPE, USA_OREGON every 60 s, fails from 2+ regions for 2 min | sev1 | platform-lead | platform-incident / payment-webhook-backlog |
| OPS-002 | `[env] <api/console/worker> 5xx ratio > 2%` (10 min) | sev2 | platform-lead | platform-incident |
| OPS-002 | `[env] application error burst` (> 20 error lines / 5 min / service) | sev2 | platform-lead | platform-incident |
| OPS-002 | Crashlytics crash-free < 99% per version (Firebase, outside Terraform) | sev1 | mobile-lead | bad-mobile-release-rollback |
| OPS-003 | `[env] Cloud SQL CPU > 80% / storage > 80% / connections > 80% of max_connections / replication lag > 60 s` — ticket after 5 min, page after 30 min | sev2 / sev1 | platform-lead | cloud-sql-failover-restore |
| OPS-004 | `[env] <topic>: oldest unacked > 10 min` (per `<topic>.worker`) | sev2 (`payment.webhook` sev1) | platform-lead | payment-webhook-backlog |
| OPS-004 | `[env] <topic>: message in dead-letter queue` (per `<topic>.dlq.replay`) | sev2 (`payment.webhook` sev1) | platform-lead | payment-webhook-backlog |
| OPS-005 | `[env] job <name> failed` (one per Cloud Run job) | sev2 | job owner | job-failure |
| OPS-009 | `[env] diagnosis review queue older than 18 h` (per tenant, `farmerapp_diagnosis_queue_oldest_hours` p99 > 18 in the hourly window) | sev2 | agronomist-lead | [OPS-009 below](#ops-009-diagnosis-review-queue-and-llm-fallback) |
| OPS-009 | `[env] diagnosis LLM fallback > 40% today` (per tenant, any `diagnosis_llm_fallback_alert` line) | sev3 | agronomist-lead | [OPS-009 below](#ops-009-diagnosis-review-queue-and-llm-fallback) |
| OPS-011 | `[env] Datastream <stream> lag > 30 min` (`stream/freshness` > 1800 s for 15 min) and `[env] Datastream <stream> dropped events` (`unsupported_event_count` > 0) | sev2 | data owner | [datastream-cdc-setup §6b](datastream-cdc-setup.md#6b-ops-011-the-stream-is-behind-or-dbt-failed) |
| OPS-011 | `[env] dbt run or test failed` and `[env] dbt source past 30 min` — log-based, from the JSON lines `dbt/scripts/dbt_run.py` emits after every dbt invocation (CI, `make dbt*`, the scheduled job) | sev2 | data owner | [datastream-cdc-setup §6b](datastream-cdc-setup.md#6b-ops-011-the-stream-is-behind-or-dbt-failed) |
| OPS-012 | `[env] daily spend above 130% of the 7-day average` — the BigQuery cost watch (`modules/cost`) fails its run on a breach; the alert watches `transfer_config/completed_transfer_run_count{run_status="FAILED"}` | sev2 | product owner + platform lead | [cost-and-budget](cost-and-budget.md) |
| OPS-012 | `[env] LLM spend above Rs <n>/day for one tenant` (`farmerapp_llm_input_tokens` / `_output_tokens` per tenant) and the same for SMS (`farmerapp_otp_sent{channel="sms"}`), converted with the rate card in `modules/cost` | sev2 | product owner | [cost-and-budget](cost-and-budget.md) |
| OPS-012 / NF-015 | `[env] monthly budget threshold crossed` — Cloud Billing budget at 50 / 90 / 100 / 130%, actual and forecast, via the `cost.budget` topic | sev2 | product owner | [cost-and-budget](cost-and-budget.md) |
| OPS-013 | `[env] Security Command Center high finding` — anything published to the `scc.findings` topic (the org-level notification config is a human gate) | sev1 | platform lead | [suspected-data-breach](suspected-data-breach.md) |
| OPS-013 | `[env] Cloud Armor blocked-request spike` — > 500 DENY responses / 5 min per backend, from the load-balancer request log | sev1 | platform lead | [platform-incident](platform-incident.md) |
| OPS-013 | `[env] OTP send spike, possible SMS pumping` — > 300 SMS OTPs for one tenant / 5 min | sev1 | platform lead | [otp-provider-outage](otp-provider-outage.md), [cost-and-budget](cost-and-budget.md) |
| OPS-014 | `[env] <check> certificate expires in < 21 days` — `uptime_check/time_until_ssl_cert_expires`, one per OPS-001 host | sev2 | platform lead | [platform-incident](platform-incident.md) |
| OPS-014 / SEC-013 | `[env] secret older than 90 days` — Secret Manager's own rotation reminder on the `secret.rotation` topic (`modules/secrets` owns the topic and sets `rotation_period` on every secret) | sev2 | platform lead | [platform-incident](platform-incident.md) |
| SLO | availability burn 14x / 1 h, 6x / 6 h | sev1 / sev2 | platform-lead | platform-incident |
| SLO | read p95 > 300 ms, write p95 > 600 ms for 15 min | sev2 | platform-lead | platform-incident |
| SLO | sync success < 97% for 30 min (burn > 3x / 30 min) | sev2 | mobile-lead | mass-location-anomaly |
| SLO | OTP delivery < 95% for 10 min (burn > 2.5x / 10 min) | sev1 | platform-lead | otp-provider-outage |

## SLOs (SPEC 12.1) — custom service `farmerapp-<env>-api`, 28-day rolling

| SLO | Goal | SLI |
|---|---|---|
| availability | 99.5% (`availability_goal`) | Cloud Run `request_count`, `response_code_class=5xx` = bad |
| latency-read | 95% < 300 ms | log metric `farmerapp_api_read_latency` (GET / HEAD) |
| latency-write | 95% < 600 ms | log metric `farmerapp_api_write_latency` (POST / PUT / PATCH / DELETE) |
| sync-success | 99% | `farmerapp_sync_success` / `farmerapp_sync_requests` |
| payment-webhook-2min | 99.9% < 120 000 ms | `farmerapp_webhook_processing` |
| otp-delivery-30s | 98% | `farmerapp_otp_delivered` / `farmerapp_otp_sent{channel="sms"}` |
| diagnosis turnaround | p95 < 5 s | `diagnosis_answered.turnaround_ms` (M6; log metric + SLO still to add in infra) |

## Dashboards (SPEC 12.4)

- **FarmerApp <env> platform**: requests, 5xx, latency p95 per service, API read / write p95, instances, error lines, Cloud SQL CPU / disk / connections / replica lag, Pub/Sub age and undelivered (incl. DLQ), job executions by result, sync requests vs 2xx.
- **FarmerApp <env> business ops**: officers on duty, open flags, visits / orders / payments captured per hour, webhooks applied, flags raised by rule, OTP sent / delivered / WhatsApp fallback.
- **FarmerApp <env> cost**: the usage drivers behind each line of the bill (Cloud Run instance time by service and by job, SQL CPU, log bytes ingested, BigQuery bytes scanned, bucket size) plus the two vendors that never appear on the GCP bill and *are* per tenant — SMS OTP sends and LLM tokens by `tenant_id`. The rupee figures are BigQuery views over the Cloud Billing export (`v_cost_daily_by_service`, `v_cost_daily_by_sku`, `v_cost_daily_by_tenant`, `v_cost_monthly_vs_budget`, `modules/cost`), because Cloud Monitoring cannot query BigQuery and GCP publishes no spend metric. Cost by tenant is an apportionment, not a measurement: see [docs/cost-model.md](../cost-model.md).
- **Mobile** (active devices, versions, crash-free, sync backlog): Firebase, outside Terraform.

## Structured-log contract (what the log-based metrics read)

The API, worker and jobs log one JSON object per line (structlog, `farmerapp/logging.py`);
Cloud Logging stores it as `jsonPayload`. Always present: `event` (the message), `level`,
`severity` (upper-case `level`, so Cloud Logging severity filters and Error Reporting work
natively), `timestamp`, `service`, `logger`; inside a request also `trace_id`, `method`,
`path`, and in GCP `logging.googleapis.com/trace` (links the line to its Cloud Trace span).
Each event below has a test asserting its JSON fields (`apps/api/tests/logcontract.py`).
`severity` is reserved for the log level: a flag's severity is logged as `flag_severity`.

| `event` | Fields used | Metric | Emitted by |
|---|---|---|---|
| `request` (access log) | `method`, `path`, `status` (int), `duration_ms` (float), `trace_id` | `farmerapp_api_read_latency`, `farmerapp_api_write_latency`, `farmerapp_sync_requests`, `farmerapp_sync_success` | `api/middleware.py` |
| `otp_sent` | `channel` (`sms` / `whatsapp`), `purpose`, `tenant_id` | `farmerapp_otp_sent` | `auth/otp.py` |
| `otp_delivered` | `channel`, `purpose`, `tenant_id`, `challenge_id` | `farmerapp_otp_delivered` | `auth/otp.py` (delivery check) |
| `otp_fallback_whatsapp` | `challenge_id` | `farmerapp_otp_whatsapp_fallback` | `auth/otp.py` |
| `webhook_applied` | `status`, `event_type`, `event_id`, `tenant_id`, **`processing_ms`** = `processed_at - received_at` in ms (int; includes the Pub/Sub queue time) | `farmerapp_webhook_applied`, `farmerapp_webhook_processing` (webhook SLO) | `payments/webhooks.py::apply_webhook_event` |
| `visit_created` | `tenant_id`, `visit_id`, `officer_id`, `geofence_result` | `farmerapp_visits_created` | visit service (REST and sync; not on replays) |
| `order_created` | `tenant_id`, `order_id`, `channel`, `total_paise` | `farmerapp_orders_created` | order service and POS port |
| `payment_captured` | `tenant_id`, `mode` (`upi_qr`, `payment_link`, `cash`, `card_terminal`, `credit`), `payment_id`, `amount_paise` | `farmerapp_payments_captured` | `payments/service.py::emit_captured` (every capture) |
| `flag_raised` | `tenant_id`, `rule_id`, `flag_id`, `flag_severity` | `farmerapp_flags_raised` | flags service on insert (not on dedupe) |
| `ops_snapshot` | `tenant_id`, `officers_on_duty` (int), `open_flags` (int) | `farmerapp_officers_on_duty`, `farmerapp_open_flags` | `officer-sync-silence` job, one line per tenant per run (every 15 min) |
| `sync_batch` | `tenant_id`, `status` (`ok` / `partial` / `failed` / `empty`), `ops`, `applied`, `rejected`, `conflicts`, `duplicates`, `changes` (ints), `has_more` | (dashboards; `farmerapp_sync_*` still count the access log) | `sync/router.py`, one per `POST /v1/sync` |
| `store_day_alert` (WARNING) | `tenant_id`, `store_id`, `store_code`, `day`, `kind` (`store_zero_sales` / `store_day_not_closed`) | (log-based alert candidate, OPS-007) | `store-day-watch` job |
| `integrity_signal` (WARNING) / `integrity_verdict` | `status` (`failed` / `absent` for the signal), `actions`, `reasons`, `device_id` | (VA-E01 reads the audit rows) | `integrity/deps.py` (login and sensitive actions) |
| `diagnosis_requested` / `diagnosis_answered` | `tenant_id`, `diagnosis_id`; answered: `status`, `source`, `confidence`, `llm_used`, `out_of_scope_reason`, `top1`, `processing_ms`, `turnaround_ms` (int) | (diagnosis turnaround SLI, M6) | `diagnosis/service.py`, `diagnosis/pipeline.py` |
| `llm_call` / `llm_refusal` (WARNING) | **`tenant_id`**, `diagnosis_id`, `provider`, `model`, `attempt`, `outcome`, `stop_reason`, `latency_ms`, `input_tokens`, `output_tokens` (never prompts or images; those are in `llm_call_log`) | `farmerapp_llm_calls`, `farmerapp_llm_input_tokens`, `farmerapp_llm_output_tokens` (OPS-012 LLM spend by tenant) | `diagnosis/pipeline.py`, `diagnosis/llm.py` |
| `diagnosis_queue_snapshot` / `diagnosis_queue_aged` (WARNING) | `tenant_id`, `queue`, `overdue`, `oldest_hours`; aged: `newly_overdue`, `notified` | OPS-009 business metric / log-based alert (review queue > 18 h) | `diagnosis-queue-age` job |
| `diagnosis_llm_fallback_rate` / `diagnosis_llm_fallback_alert` (WARNING) | `tenant_id`, `day`, `answered`, `llm_fallbacks`, `rate` (float); alert: `threshold` | OPS-009 (LLM fallback > 40 % in a day) | `diagnosis-queue-age` job |
| `data_request_received` | `tenant_id`, `data_request_id`, `type`, `role`, `notified` | (FM-015 / NF-013 ticket volume) | `privacy/router.py` |
| `dbt_run_result` / `dbt_run_failed` (ERROR) | `command`, `target`, `status`, `nodes`, `errors`, `warnings`, `elapsed_s`, `invocation_id`; failed also `first_failure`, `failures[]` | `farmerapp_dbt_failed` (OPS-011) | `dbt/scripts/dbt_run.py`, one line per dbt invocation |
| `dbt_source_freshness` / `dbt_source_stale` (ERROR) | `source`, `state`, `max_loaded_at`, `staleness_s`, `warn_after_s`, `error_after_s` | `farmerapp_dbt_staleness_seconds`, `farmerapp_dbt_source_stale` (OPS-011 / AN-010) | `dbt/scripts/dbt_run.py` on `source freshness` |
| any line with `level` = `error` / `critical` | `event` | `farmerapp_app_errors` | everywhere |

Never log raw phone numbers, OTP codes, tokens or payment secrets (use `mask_phone`).

## OPS-009: diagnosis review queue and LLM fallback

**Owner** agronomist lead (ML owner for encoder / threshold causes). **Severity** queue age sev2
(ticket); LLM fallback rate sev3 (digest). IaC: `infra/modules/monitoring/diagnosis.tf`.

**Where the signal comes from.** Cloud Run job `diagnosis-queue-age`
(`python -m farmerapp.jobs diagnosis-queue-age --tenant-id <id>`, Cloud Scheduler `5 * * * *`
Asia/Kolkata; per tenant, so it stays unscheduled until `job_tenant_ids` is set). Each run, per
tenant: notifies agronomists in the app once per diagnosis past 18 h, re-publishes `queued`
diagnoses older than 15 min to `diagnosis.requested`, and logs the events above. Its failures
raise the usual OPS-005 `job diagnosis-queue-age failed` alert.

| Log-based metric | From | Used by |
|---|---|---|
| `farmerapp_diagnosis_queue_oldest_hours` (distribution, h, label `tenant_id`; buckets ... 12, 18, 24 ...) | `diagnosis_queue_snapshot.oldest_hours` (absent when the queue is empty) | alert "review queue older than 18 h": p99 in the 1 h window > 18, per tenant; auto-closes 2 h after the queue is back under 18 h |
| `farmerapp_diagnosis_queue_aged` (counter, `tenant_id`) | `diagnosis_queue_aged` | dashboards (new overdue cases per hour) |
| `farmerapp_diagnosis_llm_fallback_rate` (distribution 0..1, `tenant_id`) | `diagnosis_llm_fallback_rate.rate` (IST day so far) | dashboards / trend |
| `farmerapp_diagnosis_llm_fallback_alert` (counter, `tenant_id`) | `diagnosis_llm_fallback_alert` (the job logs it when the day's rate > 40 % with >= 5 answers) | alert "LLM fallback > 40% today": any line in the hour, per tenant; auto-close 24 h |

The 40 % / 5-answer rule is applied by the job (`LLM_RATE_ALERT`, `MIN_SAMPLE` in
`farmerapp/ops/diagnosis_watch.py`), so the alert and the in-app notification never disagree.

**Queue older than 18 h — steps**

1. Console review queue (WC-006, `GET /v1/diagnoses/review-queue?min_age_hours=18`): how many
   are overdue, which crops, `flagged` ones first.
2. If one agronomist is out: add reviewers (tenant admin grants the `agronomist` role) or ask the
   owner to review; confirm / correct / not diagnosable closes a case.
3. If the queue is flooded with `out_of_scope` / `unknown`: check the LLM fallback alert and the
   `diagnosis_answered` lines (`source`, `confidence`) — an encoder or corpus regression sends
   everything to the queue; see [corpus-rollback.md](corpus-rollback.md).
4. Cases stuck in `queued` (never answered) are re-published by the job; if they stay queued,
   check `diagnosis.requested.worker` backlog / DLQ (OPS-004, [payment-webhook-backlog.md](payment-webhook-backlog.md) "Replay a DLQ").

**LLM fallback > 40 % — steps**

1. `llm_call` lines: `outcome` / `stop_reason` (refusals, errors) vs genuinely weak matches.
2. `diagnosis_answered` by crop: one crop or region with no approved corpus images → schedule
   field photos and corpus approvals (WC-007); a sudden jump for every crop after a deploy → roll
   back the encoder / thresholds ([corpus-rollback.md](corpus-rollback.md)).
3. Cost check: `llm_call` `input_tokens` / `output_tokens`; `DIAGNOSIS_LLM=off` (Terraform
   `diagnosis_llm = "off"`) sends every fallback straight to the agronomist queue if spend must stop.

**Infra wiring (M6 follow-up)**

- Settings on api, worker and jobs (`local.diagnosis_env`): `DIAGNOSIS_ENCODER=remote`,
  `DIAGNOSIS_ENCODER_NAME` / `_VERSION` (`diagnosis_encoder_name` / `_version`),
  `DIAGNOSIS_EMBED_URL` = the internal `embed` service URL, `DIAGNOSIS_LLM`,
  `DIAGNOSIS_LLM_MODEL` (`claude-opus-5`), `DIAGNOSIS_DELIVERY=pubsub`.
- `embed` invokers: worker and api service accounts (OIDC, audience = service URL).
- Secret `anthropic-api-key` (created empty; accessor: worker SA only) -> worker env
  `ANTHROPIC_API_KEY`. Add the value by hand:
  `gcloud secrets versions add anthropic-api-key --project <p> --data-file=-`.
- `diagnosis.requested.worker` push subscription -> worker `POST /push` (OIDC, pubsub-push SA),
  ack deadline 300 s, retry 10 s..600 s, dead letter to `diagnosis.requested.dlq` after 7
  deliveries (the worker already turns the case into "unknown" at its 5th,
  `DIAGNOSIS_MAX_ATTEMPTS`), replay from `diagnosis.requested.dlq.replay`.

## Crash, performance and remote config in the apps (NF-014 / SPEC 8.4)

Three transports, all behind seams in `packages/core/lib/src/obs/` with the Firebase adapters
in `apps/*/lib/observability.dart` — the same shape as the FA-007 push transport, so the core,
the workspace tests and any build without `google-services.json` stay free of Firebase. A
build with no Firebase gets `NoCrashReporter`, `NoPerformanceMonitor` and `LocalRemoteFlags`
and every farmer-facing flow works unchanged.

| Seam | Firebase | What it is for |
|---|---|---|
| `CrashReporter` | Crashlytics | Crash-free sessions per app version (OPS-002) is what halts a staged rollout, and it is only trustworthy if handled failures are reported too (`recordError(..., fatal: false)`). `runWithCrashReporting` installs it on `FlutterError.onError`, `PlatformDispatcher.onError` and a guarded zone around start-up. Custom keys: `app_version`, `tenant_id`, `trace_id`, `route`, `online`. |
| `PerformanceMonitor` | Performance | `AppStartTrace` reports `app_start` with `time_to_first_frame_ms` and `time_to_interactive_ms` against the NF-005 3 s budget. It also *prints* them, so a release build on an NF-001 reference device needs no cloud at all (docs/device-matrix.md). |
| `RemoteFlagSource` | Remote Config | SPEC 8.4's "feature flags and thresholds", and the kill switch the bad-release runbook asks for. Every flag has a local default equal to the shipped behaviour, so a phone that never fetches is not a degraded phone. Fetched **before the first frame** (`remoteFlagOverrides`), because a kill switch that takes effect on the second start is not a kill switch. |

Flags today: `on_device_crop_guess_killed` (DX-001 — the tenant setting opts *in*, this can
only take it away), `crash_reporting_enabled`, `performance_monitoring_enabled`,
`trace_sample_ratio`, `sampling_moving_s` / `sampling_stationary_s` / `sampling_upload_s`
(FA-010, clamped to 30 s..1 h on read), `min_supported_version`. An unknown key in the payload
is ignored and a missing key keeps its default, so an old app and a new config never disagree
dangerously.

Reporting is **off in debug**: a developer's own crashes would swamp the number that decides
whether a release ships.

## Traces (NF-014)

OpenTelemetry, configured by `farmerapp/telemetry.py`: `OTEL_EXPORTER=gcp` (Cloud Trace; the
api / worker service accounts need `roles/cloudtrace.agent` — human gate with the env apply),
`console` (stdout) or `none` (default; tests). FastAPI (server spans, `/v1/health` excluded)
and SQLAlchemy (one span per statement) are instrumented; `OTEL_SAMPLE_RATIO` sets head
sampling. W3C `traceparent` is accepted from clients (console, apps), injected into Pub/Sub
message attributes by the publisher and continued by the worker (`pubsub.process <topic>`
consumer span), so one trace covers app -> API -> worker. The log `trace_id` **is** the OTel
trace id; with tracing off it is still carried from `traceparent` / `X-Cloud-Trace-Context`
into the Pub/Sub attributes, so API and worker log lines correlate.

**The phone starts the trace** (M7). `SecureApiClient` — the one client both apps send every
API call through — puts a W3C `traceparent` on each request
(`packages/core/lib/src/obs/trace_context.dart`), so the API's server span and every worker
span behind it are children of the tap that caused them, and the API's log line carries the
same `trace_id`. The same id is set as the Crashlytics `trace_id` custom key, so a crash
report and the API's logs meet. Head sampling is on the phone (`TraceSampler`, ratio from the
`trace_sample_ratio` remote flag); an unsampled request still carries a `traceparent`, it just
asks the server not to record spans, so the log lines still join. The apps run no
OpenTelemetry SDK: a mobile exporter would add a background queue and hundreds of kilobytes to
a 25 MB APK budget (FM-014) for spans nobody reads — the useful span tree is on the server, and
what the phone has to do is start the trace and hand the id over.
