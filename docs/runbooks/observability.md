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
| diagnosis turnaround | p95 < 5 s | M6 (DX-*) |

## Dashboards (SPEC 12.4)

- **FarmerApp <env> platform**: requests, 5xx, latency p95 per service, API read / write p95, instances, error lines, Cloud SQL CPU / disk / connections / replica lag, Pub/Sub age and undelivered (incl. DLQ), job executions by result, sync requests vs 2xx.
- **FarmerApp <env> business ops**: officers on duty, open flags, visits / orders / payments captured per hour, webhooks applied, flags raised by rule, OTP sent / delivered / WhatsApp fallback.
- **FarmerApp <env> cost (placeholder)**: Cloud Run instance time by service and job, SQL CPU, OTP volume. Spend by service / tenant needs the billing export to BigQuery (human gate, OPS-012).
- **Mobile** (active devices, versions, crash-free, sync backlog): Firebase, outside Terraform.

## Structured-log contract (what the log-based metrics read)

The API, worker and jobs log one JSON object per line (structlog, `farmerapp/logging.py`);
Cloud Logging stores it as `jsonPayload`. Always present: `event` (the message), `level`,
`timestamp`, `service`, `logger`; inside a request also `trace_id`, `method`, `path`.

### Emitted today

| `event` | Fields used | Metric |
|---|---|---|
| `request` (access log, `farmerapp/api/middleware.py`) | `method`, `path`, `status` (int), `duration_ms` (float) | `farmerapp_api_read_latency`, `farmerapp_api_write_latency`, `farmerapp_sync_requests`, `farmerapp_sync_success` |
| `otp_sent` (`auth/otp.py`) | `channel` (`sms` / `whatsapp`), `purpose`, `tenant_id` | `farmerapp_otp_sent` |
| `otp_delivered` | — | `farmerapp_otp_delivered` |
| `otp_fallback_whatsapp` | — | `farmerapp_otp_whatsapp_fallback` |
| `webhook_applied` (`payments/webhooks.py`) | `status`, `event_type`, `event_id` | `farmerapp_webhook_applied` |
| any line with `level` = `error` / `critical` (e.g. `unhandled_error`) | `event` | `farmerapp_app_errors` |

### Expected (API follow-up; charts / SLO stay empty until emitted)

| `event` | Required fields | Metric | Where to emit |
|---|---|---|---|
| `webhook_applied` | **`processing_ms`** = `processed_at - received_at` in ms (int) | `farmerapp_webhook_processing` (webhook SLO) | `apply_webhook_event` |
| `visit_created` | `tenant_id` | `farmerapp_visits_created` | visit service (API and sync paths) |
| `order_created` | `tenant_id` | `farmerapp_orders_created` | order service |
| `payment_captured` | `tenant_id`, `mode` (`upi_qr`, `payment_link`, `cash`, `card_terminal`, `credit`) | `farmerapp_payments_captured` | payment state change to paid |
| `flag_raised` | `tenant_id`, `rule_id` | `farmerapp_flags_raised` | flags service on insert (not on dedupe) |
| `ops_snapshot` | `tenant_id`, `officers_on_duty` (int), `open_flags` (int) | `farmerapp_officers_on_duty`, `farmerapp_open_flags` | one line per tenant from a scheduled job (e.g. `officer-sync-silence`, every 15 min) |

Also recommended: add a `severity` key mirroring `level` (upper-case) in the structlog
renderer, so Cloud Logging severity filters and Error Reporting pick errors up natively.
Never log raw phone numbers, OTP codes, tokens or payment secrets (use `mask_phone`).
