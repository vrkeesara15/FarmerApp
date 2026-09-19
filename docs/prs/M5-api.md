# M5 API — observability events and tracing, ops watch jobs, PII encryption, GCS signed URLs, Play Integrity, latency suite

Branch `feat/M5-api-ops-pii-perf` (from `main` at `7f07d2b`). API only (`apps/api`), plus
docs, `.env.example`, the `store-day-watch` schedule in `infra/envs/*/main.tf`, metric
description text in `infra/modules/monitoring`, the VA-E01 / VA-E05 / VA-F02 rule versions and
the `perf-api` Make target.

PR title: `feat(M5): observability events and OpenTelemetry tracing, store and payment watch
jobs, PII field encryption with hashed phone lookups, GCS signed URLs, Play Integrity
verification and API latency suite (OPS-006, OPS-007, OPS-008, OPS-010, SEC-026, SEC-016,
NF-005, NF-014)`

## Requirement IDs

| ID | Status after this PR |
|---|---|
| NF-014 | in-progress — API / worker done (log contract, OTel); apps / console `traceparent` pending |
| OPS-006 | done (API + IaC schedule; push delivery with FA-007) |
| OPS-007 | done — new `store-day-watch` job, scheduled 22:15 IST |
| OPS-008 | done — reconciliation mismatches open an `OPS-008` finance ticket (flag) + accountant notifications |
| OPS-009 | blocked — needs the M6 diagnosis queue |
| OPS-010 | done (verified, tests added) |
| SEC-026 | done — expand + migrate; contract step manual; KMS key human-gated |
| SEC-016 | done — `GcsBlobStore` V4 signed URLs via IAM signBlob |
| SEC-024 | server-side Play Integrity verification (groundwork; Google Cloud setup human-gated) |
| NF-005 | in-progress — `make perf-api` suite, fixes, results in docs/perf/NF-005.md; Cloud Run load test human |

## Migrations

- `0024_ops_integrity`: `flag.subject_type` gains `tenant` (CHECK widened); `audit_log.integrity` jsonb.
- `0025_pii_expand`: `tenant_data_key` (append-only, RLS); `user` / `farmer` `phone_enc`,
  `phone_hash` (unique per tenant), `farmer.landmark_enc`, `phone` nullable; index
  `ix_user_phone_hash`; SECURITY DEFINER `auth_find_user_by_phone_hash(hash, phone)`.
- `0026_perf_indexes`: partial index `ix_audit_log_farmer_create_device`.
- Manual, not in the chain: `alembic/manual/pii_contract.py` (drops the plain columns; see the
  runbook). All three automatic migrations are expand-only and downgradeable (0025 refuses to
  downgrade while rows exist whose phone is only encrypted).

## NF-014 — log contract and OpenTelemetry

- `farmerapp/logging.py`: `severity` (upper-case level) on every line; outside a request the
  active OTel span supplies `trace_id`.
- Events (field contract in docs/runbooks/observability.md, one test per event through
  `tests/logcontract.py`, which renders the event with the production JSON renderer):
  `webhook_applied.processing_ms` (+ `tenant_id`), `visit_created`, `order_created` (REST,
  sync and POS), `payment_captured` (every capture, with `mode`), `flag_raised` (+ `tenant_id`;
  the flag severity is `flag_severity` because `severity` is Cloud Logging's), `ops_snapshot`
  (officers on duty, open flags; from `officer-sync-silence`), `sync_batch` (status + counts),
  `otp_delivered` (+ channel, purpose, tenant). `store_day_alert` and `integrity_signal` are
  new WARNINGs.
- `farmerapp/telemetry.py`: `OTEL_EXPORTER` = `gcp` (Cloud Trace exporter) / `console` /
  `none` (default, tests), `OTEL_SAMPLE_RATIO`; FastAPI + SQLAlchemy instrumentation in the api
  and worker; W3C `traceparent` accepted (CORS allows it), injected into Pub/Sub message
  attributes (`payments/publisher.py::message_attributes`) and continued by the worker
  (`pubsub.process <topic>` consumer span). The log trace id equals the OTel trace id
  (`api/middleware.py::resolve_trace_id`); in GCP lines carry `logging.googleapis.com/trace`.
  Without tracing, a 32-hex request trace id still travels to the worker.

## OPS monitors

- **OPS-006** `officer-sync-silence`: verified against SPEC 12.2; tests for ended sessions,
  other clusters, disabled heads; emits `ops_snapshot`.
- **OPS-007** `python -m farmerapp.jobs store-day-watch --tenant … [--date]`
  (`farmerapp/ops/store_watch.py`): tenant calendar settings `working_days` (Mon–Sat),
  `holidays`, `day_close_deadline_local_time` (22:00) in `TenantSettings` / `PATCH /v1/settings`;
  `store_zero_sales` and `store_day_not_closed` notifications to the store managers and cluster
  heads (owners as fallback), deduped per store, day and kind.
- **OPS-008** `reconcile-payments`: one `OPS-008` flag per tenant and day with mismatches
  (`flags.service.raise_system_flag`: same dedupe, routing, SLA, history as rule flags),
  accountants as watchers; accountants can list / read / comment the tickets they watch
  (`GET /v1/flags` now admits `accountant`, scoped to those tickets); notifications carry the
  flag id and are not repeated on a re-run.
- **OPS-010** `flags-sla-escalation`: verified; test for the `flag_escalated` notification and
  the resolved / not-yet-due skips.
- **OPS-009**: blocked on M6 (no diagnosis queue yet).

## SEC-026 — PII field encryption

`farmerapp/pii/`: `crypto.FieldCipher` (AES-256-GCM, per-tenant data keys, associated data
`tenant | table | column`, key version in the ciphertext header), `LocalKeyWrapper` (dev /
test) and `CloudKmsKeyWrapper` (REST encrypt / decrypt with AAD); `keys.ensure_tenant_key`
(called by `set_tenant`: loads or creates the tenant's key on a separate committed
connection, cached per process); `fields.EncryptedField` (`User.phone`, `Farmer.phone`,
`Farmer.landmark`: ciphertext written at flush, legacy plain column read as fallback, class
comparison raises); `lookup.phone_match` / `phone_in`; `backfill` job. Audit rows record
`+91******3210` / `[encrypted]`, never ciphertext or hashes. `PII_PLAINTEXT_WRITES` keeps the
plain columns written during a cautious rollout. prd refuses to start without
`PII_KEK_BACKEND=kms`, a KMS key name, no local key and a strong pepper (also `BLOB_STORE=gcs`).
Runbook: docs/runbooks/pii-encryption.md.

Not encrypted here (follow-ups): `otp_challenge.phone` (short-lived, needed to resend; purge
job to add), `invoice.buyer_phone` (walk-in buyer on a GST invoice, 8-year retention).
Analytics: Datastream replicates ciphertext and hashes only; the dbt staging masks (AN-014,
`dbt/README.md`) must build the masked phone from `farmer.phone_last4` / `user` equivalents,
not from the plain `phone` column (NULL for rows written or backfilled under SEC-026).

## SEC-016 — GCS signed URLs

`uploads/blobstore.py`: `GcsBlobStore` (JSON API upload / download / exists with the runtime
token) and V4 `signed_url` (`GOOG4-RSA-SHA256`, `X-Goog-*` query, 15 min, cap 7 days) signed by
`IamBlobSigner` (`iamcredentials … :signBlob`). `BlobStore.signed_url` became `async` (all
callers updated). `farmerapp/gcp.py::GoogleAccessToken` (ADC, cached, refreshed off the loop).

## SEC-024 — Play Integrity server side

`farmerapp/integrity/`: `verdict` (request hash per the app contract, `evaluate`: package,
request hash, token age 10 min, `PLAY_RECOGNIZED`, `MEETS_DEVICE_INTEGRITY`), `verifier`
(`GooglePlayIntegrityVerifier` decodeIntegrityToken per allowed package, `Fake…`), `deps.
integrity_for(action)` on login, `POST /v1/payments`, POS sales, day close and `/v1/sync`
(header-driven). Verdict statuses `verified`, `failed`, `unavailable`, `absent`, `unverified`,
`not_required`; recorded on `request.state.integrity` and in `audit_log.integrity` of every row
the request writes; never blocks (timeouts and outages are `unverified`). VA-E01 (v2) adds the
reason `play_integrity_failed` from failed verdicts of the officer's requests that day.
Settings: `PLAY_INTEGRITY_MODE` (`off` default), `PLAY_INTEGRITY_PACKAGE_NAMES`
(`in.farmerapp.mitra`, `in.farmerapp.kisan`), `PLAY_INTEGRITY_TIMEOUT_S`.

## NF-005 — latency suite

`make perf-api` (`tests/perf/test_latency.py`, excluded from the default run): FULL seed, 13
hot endpoints, concurrency 4, p50 / p95 report, fails over budget. Fixes it drove: rules run once
per sync batch (`rules.engine.deferred`), per-session caches of tenant settings and slug, VA-F02
hash join, VA-F06 index, owner-home flag trend in one query (`FlagCountsPort.open_totals`).
Results and recommendations: docs/perf/NF-005.md (all green at concurrency 4; owner home and
sync over budget at concurrency 8 in one process, CPU-bound).

Rule versions bumped: VA-E01 v2 (Play Integrity reason), VA-E05 v2 (dedupe key digest is the
peppered phone hash, not a plain SHA-256), VA-F02 v2 (same-phone by hash).

## Tests

New: `tests/logcontract.py` + contract tests in auth, webhooks, visits, orders, flags, sync,
duty and health; `tests/test_telemetry.py`; `tests/ops/test_store_watch.py`;
`tests/payments/test_finance_ticket.py`; `tests/pii/test_crypto.py`, `tests/farmers/test_pii.py`
(round trip, wrong tenant / table / column, lookups and uniqueness by hash, legacy fallback,
another process's key, backfill idempotency / resume / conflicts / clear / restore, prd refuses a
local key); `tests/uploads/test_gcs_blobstore.py` (signature verified with the RSA public
key); `tests/auth/test_integrity.py`; `tests/rules/test_va_e01_play_integrity.py`; OPS-010 and
settings calendar tests. `SKIP_AUDIT=1 make check-api` green (numbers in the commit report).

## Human gates

1. **Cloud KMS**: key ring + key in asia-south1, `cryptoKeyEncrypterDecrypter` for the api /
   worker / jobs SAs, `PII_KEK_BACKEND=kms` + `PII_KMS_KEY_NAME`; Secret Manager
   `pii-hash-pepper`; run `pii-backfill` per tenant per env, later `--clear-plaintext`, then
   the manual contract migration (docs/runbooks/pii-encryption.md).
2. **Play Integrity**: link a Google Cloud project in Play Console for both apps, enable the
   Play Integrity API, give the api SA access, set `PLAY_INTEGRITY_MODE=google` (and
   `PLAY_INTEGRITY_PROJECT_NUMBER` in the app builds).
3. **Cloud Trace**: `roles/cloudtrace.agent` for the api / worker SAs, `OTEL_EXPORTER=gcp`.
4. **GCS**: `BLOB_STORE=gcs` in stg / prd and a signed-URL check against a real bucket.
5. **NF-005**: a load test against Cloud Run + Cloud SQL in stg before the pilot.
