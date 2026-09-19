## Requirement IDs

- OPS-001 uptime checks — done (IaC)
- OPS-002 error rate / crash-free — done (IaC; Crashlytics human-gated)
- OPS-003 Cloud SQL alerts — done (IaC)
- OPS-004 Pub/Sub age / DLQ — done (IaC + DLQ replay runbook)
- OPS-005 job failures — done (IaC; jobs rewired to the real CLI and scheduled)
- SEC-014 Cloud Armor — done (reCAPTCHA bot management human-gated)
- SEC-015 ingress from the LB only — done (IAP P1 toggle, off)
- SEC-016 private buckets, signed URLs — done on the infra side (API GCS signer is a follow-up)
- SEC-017 audit logs export — done
- SEC-018 org policies — done (bootstrap, human apply)
- SEC-019 SCC — done behind a flag (org enablement human-gated)
- NF-006 availability — done (IaC + DR runbook; drills human); NF-005 in-progress (API latency SLOs)

PR title: `feat(M5): monitoring, SLOs, dashboards, Cloud Armor, audit logs, org policies, scheduling, console image and runbooks (OPS-001..OPS-005, SEC-014..SEC-019, NF-006)`

Nothing under apps/api, apps/mobile or the Makefile changed. Nothing was applied to any
GCP project (stg / prd apply is human-only; dev apply happens from CI once WIF exists).

## What changed

### infra/modules/monitoring (rewritten, split by concern)

- `main.tf` — severity routing per SPEC 12.3: sev1 = page + ticket (+ e-mail), sev2 = ticket, sev3 = digest; only the e-mail channel is created (Slack / PagerDuty channels hold tokens, passed as ids). Runbook URLs from `runbook_base_url`.
- `uptime.tf` — OPS-001: api `/v1/health`, console `/login`, webhook `GET /v1/webhooks/razorpay` expecting 405, from 3 regions every 60 s; sev1.
- `alerts.tf` — OPS-002 5xx ratio per service + error-burst log metric; OPS-003 CPU / disk / connections / replica lag as ticket (5 min) + page (30 min); OPS-004 per topic backlog and DLQ (`payment.webhook` sev1); OPS-005 one policy per job with its owner.
- `log_metrics.tf` — log-based counters and distributions over the structured JSON logs (access log `duration_ms`, sync status, `otp_sent` / `otp_delivered`, `webhook_applied`, business events).
- `slo.tf` — custom service `farmerapp-<env>-api` with SLOs: availability 99.5% / 28 d (burn 14x / 1 h sev1, 6x / 6 h sev2), read p95 < 300 ms and write p95 < 600 ms (alerts after 15 min), sync success 99% (< 97% / 30 min), payment webhook 99.9% within 2 min, OTP delivery 98% (< 95% / 10 min, sev1).
- `dashboards.tf` — platform, business ops and cost (placeholder) dashboards.
- `audit.tf` — SEC-017 Data Access (ADMIN_READ, DATA_READ, DATA_WRITE) for Cloud SQL, Secret Manager, GCS; sink to `farmerapp-audit` (400 days, locked in prd).
- Every alert: `user_labels {ops|slo, owner, sev}`, Cloud Monitoring severity, documentation block with owner, severity and runbook link.

### infra/modules/lb

- `armor.tf` — OWASP CRS 3.3 (sqli, xss, lfi, rfi, rce, scanner detection, protocol attack) with JSON parsing, Log4j canary, OTP send 5/min/IP and login 10/min/IP on the real auth paths, India geo allow-list on the api host for field paths only (console, auth, health, webhooks excluded), adaptive protection; preview in stg, enforce in prd. reCAPTCHA bot management left as a documented TODO.
- Console backend: optional IAP (`console_iap_enabled`, default false; Google-managed OAuth client, no secret in state) + `roles/iap.httpsResourceAccessor` members.

### infra/envs/* (identical main.tf / variables.tf; tfvars differ)

- Jobs rewired to `python -m farmerapp.jobs <command>` (the previous `farmerapp.jobs.validation_batch` etc. modules never existed): run-rules --mode batch 02:00, flags-sla-escalation hourly, officer-sync-silence every 15 min, auto-end-duty every 10 min, ensure-partitions 00:30, purge-location-points 04:00 (`--apply` only when `location_purge_apply`, true in prd), purge-expired hourly, reconcile-payments 06:00, backfill-farm-photo-phash manual. All in Asia/Kolkata. Per-tenant jobs take `--tenant-id` from `job_tenant_ids` (dev: the two demo tenants; stg / prd: empty, so those jobs stay unscheduled until set). jobs SA gets the Razorpay key secrets (reconcile) and photos objectViewer (backfill).
- api / console: `invoker_iam_disabled = true` instead of an `allUsers` binding (compatible with domain-restricted sharing; ingress internal-LB stays the gate). api `container_port = 8000` + startup probe `/v1/health` (was the module default 8080; the image listens on 8000). console gets `API_URL` for server-side calls.
- worker / embed ingress fixed to `INGRESS_TRAFFIC_INTERNAL_ONLY` (`INGRESS_TRAFFIC_INTERNAL` is not a Cloud Run v2 value; tflint's google ruleset flagged it).
- SEC-016: `roles/iam.serviceAccountTokenCreator` for the api SA on itself (V4 signing through IAM signBlob, no key file).
- New variables: channels per severity, `runbook_base_url`, `availability_goal`, `sql_max_connections`, `job_tenant_ids`, `location_purge_apply`, `console_iap_enabled`, `console_iap_members`. Removed unused `image_registry` and `data.google_project.this`.

### infra/modules (other)

- `sql` — logging flags on primary and replica (log_connections / disconnections / lock_waits / checkpoints / hostname, log_min_messages warning, log_min_error_statement error, log_statement ddl, pgAudit ddl+role); `replica_instance_name` output.
- `iam` — Pub/Sub service agent's Token Creator scoped to the push SA instead of the whole project.
- `run_service` — `invoker_iam_disabled` input; ingress validation uses the v2 enum.

### infra/bootstrap

- `security.tf` — SEC-018 project-level org policies (resource locations India on env projects; `sql.restrictPublicIp`, `compute.requireOsLogin` on all; domain-restricted sharing when customer ids are set) and SEC-019 SCC notification config (org-level, `scc_notifications_enabled = false` by default) to an `scc-findings` topic + security-channel subscription.
- env projects created with `auto_create_network = false`.

### infra/.checkov.yaml

Documented skips for checks that conflict with the accepted design: CSEK on BigQuery / Pub/Sub / Artifact Registry (Google-managed keys, CMEK optional), `CKV_GCP_6` (ssl_mode ENCRYPTED_ONLY + IAM auth), `CKV_GCP_79` (SPEC pins Postgres 16), `CKV2_GCP_13` log_duration (Query Insights instead), `CKV2_GCP_5` all-services Data Access, `CKV_GCP_125` (repository pinned via variable).

### Console image

- `apps/console/Dockerfile` — multi-stage node:22-slim: `npm ci`, `npm run build` (prebuild tokens + `next build`), runtime copies `.next/standalone` + static, non-root uid 10001, port 3000. `NEXT_PUBLIC_API_URL` build arg.
- `apps/console/Dockerfile.dockerignore` — per-Dockerfile ignore (context = apps/console + design/tokens.json); the root `.dockerignore` for the api / worker / jobs images is unchanged.
- `apps/console/next.config.ts` — one line: `output: "standalone"`.

### .github/workflows/deploy.yml

- Console built by the existing matrix with `NEXT_PUBLIC_API_URL` = the dev API URL; job images updated to the jobs image for the new job names. Comment on per-env console images for stg / prd promotion.

### Runbooks (docs/runbooks)

Real content replacing the stubs: OTP provider outage and failover, payment webhook backlog (DLQ replay commands), Cloud SQL failover and restore, bad mobile release rollback, corpus rollback (placeholder until M6), mass location anomaly, data-subject erasure, suspected data breach (CERT-In 6 h, DPDP Board + principals, 72 h detailed report). New: platform-incident, job-failure, disaster-recovery (RPO / RTO, region-loss procedure, quarterly drill checklist), observability (alert inventory, SLOs, dashboards, log-field contract). Each has owner, severity, detection signal, steps with commands, verification, communication.

## Checks

- `cd infra && ./scripts/check.sh`: terraform fmt, validate (bootstrap, dev, stg, prd), tflint 0.64 (google ruleset 0.30.0; installed from the GitHub release, brew has no formula) with no issues, checkov (installed with `uv tool install checkov`) 96 passed / 0 failed.
- `actionlint` on deploy.yml and ci-infra.yml: clean.
- `docker build -f apps/console/Dockerfile .` builds (context 1.8 MB); `docker run -p 13000:3000` serves `GET /login` 200 as uid 10001.

## Human gates

- Apply: dev first (human once, then CI), stg / prd by a human after review. Bootstrap `security.tf` needs `roles/orgpolicy.policyAdmin`; SCC needs org-level activation of SCC Standard, `org_id`, `scc_notifications_enabled = true`, and a Slack relay for the `scc-findings.security-channel` subscription.
- Notification channels with tokens (Slack, PagerDuty / SMS) created by hand; ids into `page_channels` / `ticket_channels` / `digest_channels`; `notification_email`; `runbook_base_url` once the GitHub remote exists.
- `job_tenant_ids` for stg / prd; confirm `sql_max_connections` per env.
- reCAPTCHA Enterprise keys for Cloud Armor bot management; review stg preview logs before prd enforce.
- Firebase Crashlytics (crash-free per version alerts) and Error Reporting notifications.
- Customer id for domain-restricted sharing; OAuth consent screen before enabling console IAP.
- Billing export to BigQuery for the cost dashboard (OPS-012).
- First quarterly restore drill on stg; Artifact Registry copy in asia-south2 for DR.

## Follow-ups for other owners

- API: `processing_ms` on `webhook_applied`; business events `visit_created`, `order_created`, `payment_captured`, `flag_raised`, `ops_snapshot` (field contract in docs/runbooks/observability.md); a `severity` key in the log renderer; `GcsBlobStore` V4 signing via IAM signBlob.
- Mobile: remote-config kill switch / `min_supported_version`.
