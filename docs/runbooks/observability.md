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
- **FarmerApp <env> cost (placeholder)**: Cloud Run instance time by service and job, SQL CPU, OTP volume. Spend by service / tenant needs the billing export to BigQuery (human gate, OPS-012).
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
| `llm_call` / `llm_refusal` (WARNING) | `provider`, `model`, `attempt`, `outcome`, `stop_reason`, `latency_ms`, `input_tokens`, `output_tokens` (never prompts or images; those are in `llm_call_log`) | (LLM cost / error dashboards) | `diagnosis/pipeline.py`, `diagnosis/llm.py` |
| `diagnosis_queue_snapshot` / `diagnosis_queue_aged` (WARNING) | `tenant_id`, `queue`, `overdue`, `oldest_hours`; aged: `newly_overdue`, `notified` | OPS-009 business metric / log-based alert (review queue > 18 h) | `diagnosis-queue-age` job |
| `diagnosis_llm_fallback_rate` / `diagnosis_llm_fallback_alert` (WARNING) | `tenant_id`, `day`, `answered`, `llm_fallbacks`, `rate` (float); alert: `threshold` | OPS-009 (LLM fallback > 40 % in a day) | `diagnosis-queue-age` job |
| `data_request_received` | `tenant_id`, `data_request_id`, `type`, `role`, `notified` | (FM-015 / NF-013 ticket volume) | `privacy/router.py` |
| any line with `level` = `error` / `critical` | `event` | `farmerapp_app_errors` | everywhere |

Never log raw phone numbers, OTP codes, tokens or payment secrets (use `mask_phone`).

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
