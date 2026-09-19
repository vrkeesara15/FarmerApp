# M6 follow-ups — field officer on the farmer profile, documented diagnosis settings, diagnosis infra (FM-011, OPS-009)

Branch `chore/M6-followups` (from `main` at `f23e287`). Touches `apps/api`, `infra`,
`.env.example` and `docs/` only.

## FM-011 / F62: `officer` on the farmer's own profile

`GET /v1/farmers/{id}` (`FarmerDetailOut`) and `GET /v1/me` (`MeOut`, farmer logins) carry

```json
"officer": {"id": "uuid", "name": "Ramesh", "phone": "+919876543210"} | null
```

**Which officer** (`farmerapp/farmers/officer.py`):

1. the user who registered the farmer (`farmer.registered_by`) while that user is an **active
   field officer** of the tenant (status `active`, not deleted, role still `field_officer`);
2. else the active field officer assigned to the store of the farmer's village
   (`village.store_id`); several → the longest-serving (`user.created_at`, then `id`), so the
   card does not flip between reads;
3. else `null` (the app shows "your field officer").

Rationale: the registering officer is the person the farmer has met (F05 "from Ramesh");
when they leave or are disabled, the village store's officer is who now serves the village.

**Phone** — decrypted through the SEC-026 field cipher (`User.phone`), in full only for the
farmer themself, the officer themself and the roles that already read user profiles with phones
(`GET /v1/users`: owner, director, cluster head, auditor, tenant admin — a test pins the two lists
together). Everyone else who can read the farmer (store manager, agronomist) gets
`+91******3210`. A farmer reading another farmer still gets `404` (no officer leak). `officer`
is filled on reads only (writes that return `FarmerDetailOut` leave it `null`). Staff `GET
/v1/me` has `officer: null`.

OpenAPI regenerated (`AssignedOfficerOut`, `MeOut`, `FarmerDetailOut.officer`). Tests:
`tests/farmers/test_officer.py` (farmer self + `/v1/me`, other farmer / other tenant 404, masking
per reader, role-list parity, fallback to the senior active store officer ignoring disabled
ones, `null` when nobody is active, registrar no longer a field officer, farmer login without a
record).

## `.env.example`

Added every diagnosis setting (`DIAGNOSIS_ENCODER`, `_ENCODER_NAME`, `_ENCODER_VERSION`,
`_EMBED_URL`, `_EMBED_TIMEOUT_S`, `DIAGNOSIS_LLM`, `DIAGNOSIS_LLM_MODEL=claude-opus-5`,
`_LLM_MAX_TOKENS`, `_LLM_EFFORT`, `DIAGNOSIS_DELIVERY`, `_KNN_K`, `_HNSW_EF_SEARCH`,
`_MAX_ATTEMPTS`), `ANTHROPIC_API_KEY` as an empty placeholder (Secret Manager
`anthropic-api-key`), and the other `Settings` fields that were read but undocumented
(`UPLOAD_CHUNK_SIZE`, `OTP_TTL_SECONDS` … `OTP_WHATSAPP_FALLBACK_SECONDS`, `JWT_ALGORITHM`,
`JWT_ISSUER`, `STEP_UP_TOKEN_TTL_SECONDS`, `SECURITY_CACHE_TTL_SECONDS`). OTel and SEC-026
KMS / field-cipher settings were already there. There is no thresholds file: DX-003
thresholds are versioned rows in `diagnosis_threshold` (noted in the file). There is also no
`ENCODER_REMOTE_URL`: the setting is `DIAGNOSIS_EMBED_URL`.

## Pub/Sub wiring fix (found while verifying `diagnosis.requested`)

The push subscription existed with a DLQ, but it could not have delivered anything:

* Terraform pushed to `<worker>/pubsub/<topic>`; the worker only serves `POST /push`. Now
  `push_endpoint = <worker>/push` (every topic).
* The API published to `topics/diagnosis-requested` (dots → dashes) while Terraform creates
  `diagnosis.requested` (SPEC 9.2 names). `PubSubRestPublisher` now publishes to the topic id
  as named (`payment.webhook`, `diagnosis.requested`, …). The worker also resolves the topic from
  a `<topic>.worker` subscription name (the `topic` attribute is always set anyway).

## Infra (`cd infra && ./scripts/check.sh` green: fmt, validate ×4, tflint, checkov 90 / 0)

* **Cloud Scheduler**: job `diagnosis-queue-age` (`python -m farmerapp.jobs diagnosis-queue-age
  --tenant-id …`), `5 * * * *` Asia/Kolkata, owner `agronomist-lead`, OPS-005 failure alert.
  Per tenant: unscheduled until `job_tenant_ids` is set (dev has the demo tenants).
* **`diagnosis.requested.worker`**: push to the worker (OIDC, pubsub-push SA), ack deadline
  300 s (LLM fallback), dead letter after 7 deliveries (> `DIAGNOSIS_MAX_ATTEMPTS` 5, so the
  worker closes the case as "unknown" first), DLQ `diagnosis.requested.dlq` +
  `.dlq.replay`. New module input `subscription_overrides`.
* **Secret `anthropic-api-key`** (replaces the never-populated `llm-api-key`), created empty,
  accessor worker SA only, mounted as `ANTHROPIC_API_KEY` on the worker.
* **Settings** `local.diagnosis_env` on api, worker and jobs: `DIAGNOSIS_ENCODER=remote`,
  name / version (`diagnosis_encoder_name` / `_version`), `DIAGNOSIS_EMBED_URL` = `embed`
  URL, `DIAGNOSIS_LLM` (`claude` | `off`), `DIAGNOSIS_LLM_MODEL` (`claude-opus-5`),
  `DIAGNOSIS_DELIVERY=pubsub`. `embed` invokers: worker + api (corpus uploads embed in the
  api). `embed` gets `EMBED_MODEL` / `EMBED_VERSION` for the future service to pin.
* **OPS-009 alerts** (`modules/monitoring/diagnosis.tf`): log-based metrics
  `farmerapp_diagnosis_queue_oldest_hours`, `_queue_aged`, `_llm_fallback_rate`,
  `_llm_fallback_alert` over the job's `diagnosis_queue_snapshot` / `diagnosis_queue_aged` /
  `diagnosis_llm_fallback_rate` / `diagnosis_llm_fallback_alert` lines; alerts "review queue
  older than 18 h" (sev2) and "LLM fallback > 40 % today" (sev3), per tenant. Steps in
  docs/runbooks/observability.md#ops-009-diagnosis-review-queue-and-llm-fallback.

## Human gates / follow-ups

* Apply (dev by CI once WIF exists; stg / prd by a human). Renaming `llm-api-key` destroys that
  empty secret. Add the key: `gcloud secrets versions add anthropic-api-key --data-file=-`.
* The `embed` service image does not exist yet (`ml/embed` has only the README); until it is
  deployed with the pinned model, keep `DIAGNOSIS_ENCODER=remote` environments off diagnosis.
* Pre-existing, not changed here: the Terraform env names for the database and environment
  (`DB_HOST`, `DB_NAME`, `ENV`) are not what `Settings` reads (`DATABASE_URL`,
  `MIGRATION_DATABASE_URL`, `APP_ENV`), and `OTEL_EXPORTER` / `BLOB_STORE` /
  `PII_*` are not set on the services. This needs its own infra change before the first stg deploy.
  **Resolved** on `chore/deploy-config-alignment` (docs/prs/deploy-config-alignment.md,
  docs/deploy/configuration.md).
