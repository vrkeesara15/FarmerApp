"""Runtime configuration.

Every value is read from the environment (or a local ``.env`` file). Nothing here is a
secret: production secrets are injected by Secret Manager into the environment and are
only ever *referenced* by name in code. See ``/.env.example`` for the full list.
"""

from __future__ import annotations

import tempfile
from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

Environment = Literal["local", "test", "dev", "stg", "prd"]

# Monorepo root .env (apps/api/farmerapp/settings.py -> repo root); a cwd .env overrides it.
# In containers the package lives at /app/farmerapp, so fall back to the filesystem root.
_PARENTS = Path(__file__).resolve().parents
_REPO_ROOT_ENV = (_PARENTS[3] if len(_PARENTS) > 3 else _PARENTS[-1]) / ".env"

# Development-only placeholders (not secrets). ``_prd_guard_rails`` rejects them in prd.
DEV_JWT_SIGNING_KEY = "dev-only-jwt-signing-key-not-a-secret"
DEV_OTP_PEPPER = "dev-only-otp-pepper-not-a-secret"
DEV_RAZORPAY_API_KEY_PLACEHOLDER = "dev-only-razorpay-key-secret-not-a-secret"
#: The mockserver's default signing secret (docker/mockserver, ``MOCK_RAZORPAY_WEBHOOK_SECRET``).
DEV_RAZORPAY_WEBHOOK_HMAC_KEY = "test_webhook_secret"
#: SEC-026 dev / test key-encryption key (base64 of 32 bytes) and hash pepper. Never in prd:
#: ``_prd_guard_rails`` requires Cloud KMS and a Secret Manager pepper there.
DEV_PII_LOCAL_KEK = "ZGV2LW9ubHktcGlpLWtlay1ub3QtYS1zZWNyZXQhISE="
DEV_PII_HASH_PEPPER = "dev-only-pii-hash-pepper-not-a-secret"

#: SEC-011: the Cloud SQL IAM user of the ``migrate`` job (service account
#: ``farmerapp-migrate@<project>.iam.gserviceaccount.com``, infra/modules/iam). The only
#: identity granted ``farmerapp_migrate``; no other process may log in as it.
MIGRATE_DB_USER_PREFIX = "farmerapp-migrate@"

# --- Cloud deployment contract ---------------------------------------------------------
# Environment variable names every Cloud Run service / job must set (dev, stg and prd alike),
# by SERVICE_NAME. Terraform sets exactly these (infra/envs/*/main.tf, checked by
# preconditions in modules/run_service and modules/run_job) and tests/deploy/test_terraform_env.py
# fails when the two drift apart. docs/deploy/configuration.md has the full table.
_CLOUD_BASE_ENV = frozenset(
    {
        "APP_ENV",
        "SERVICE_NAME",
        "LOG_JSON",
        "GCP_PROJECT",
        "OTEL_EXPORTER",
        "DB_IAM_AUTH",
        "DB_INSTANCE_CONNECTION_NAME",
        "DB_IP_TYPE",
        "DB_USER",
        "DB_NAME",
    }
)
_CLOUD_RUNTIME_ENV = _CLOUD_BASE_ENV | {
    "BLOB_STORE",
    "PHOTOS_BUCKET",
    "EXPORTS_BUCKET",
    "PII_KEK_BACKEND",
    "PII_KMS_KEY_NAME",
    "PII_HASH_PEPPER",
    "DIAGNOSIS_ENCODER",
    "DIAGNOSIS_ENCODER_NAME",
    "DIAGNOSIS_ENCODER_VERSION",
    "DIAGNOSIS_EMBED_URL",
    "DIAGNOSIS_LLM",
    "DIAGNOSIS_LLM_MODEL",
    "DIAGNOSIS_DELIVERY",
    "PAYMENT_PROVIDER",
    "PAYMENT_WEBHOOK_DELIVERY",
    "RAZORPAY_BASE_URL",
}
_RAZORPAY_SECRETS = frozenset({"RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET"})
CLOUD_REQUIRED_ENV: dict[str, frozenset[str]] = {
    "api": _CLOUD_RUNTIME_ENV
    | _RAZORPAY_SECRETS
    | {
        "JWT_SIGNING_KEY",
        "OTP_PEPPER",
        "OTP_PROVIDER",
        "SMS_PROVIDER_URL",
        "WHATSAPP_PROVIDER_URL",
        "CORS_ORIGINS",
        "GCS_SIGNING_SERVICE_ACCOUNT",
    },
    # ANTHROPIC_API_KEY is read by the Anthropic SDK (DX-004 fallback runs in the worker).
    "worker": _CLOUD_RUNTIME_ENV | _RAZORPAY_SECRETS | {"ANTHROPIC_API_KEY"},
    # M7: flags-summarise (VA-004) reads ANTHROPIC_API_KEY; DX-011 / DX-012 use CORPUS_BUCKET.
    "jobs": _CLOUD_RUNTIME_ENV | {"ANTHROPIC_API_KEY", "CORPUS_BUCKET"},
    "migrate": _CLOUD_BASE_ENV,
}
#: Extra names for single Cloud Run jobs (``python -m farmerapp.jobs <command>``).
CLOUD_REQUIRED_JOB_ENV: dict[str, frozenset[str]] = {
    "reconcile-payments": frozenset({"RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET"}),
}
#: Local / dev-only names no Cloud Run service or job may set (emulators, mockserver, local KEK).
CLOUD_FORBIDDEN_ENV = frozenset(
    {
        "PUBSUB_EMULATOR_HOST",
        "STORAGE_EMULATOR_HOST",
        "BLOB_LOCAL_DIR",
        "PII_LOCAL_KEK",
        "DATABASE_URL",
        "MIGRATION_DATABASE_URL",
        "MOCK_RAZORPAY_WEBHOOK_SECRET",
        "MOCK_RAZORPAY_KEY_ID",
    }
)
#: Additionally forbidden in stg / prd (allowed, but not set by Terraform, in dev).
CLOUD_FORBIDDEN_ENV_STG_PRD = CLOUD_FORBIDDEN_ENV | {"OTP_DEV_CODE"}


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(str(_REPO_ROOT_ENV), ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # --- Runtime -----------------------------------------------------------
    app_env: Environment = Field(default="local", description="Deployment environment.")
    service_name: str = Field(
        default="api",
        description="api | worker | jobs | migrate; used in logs and to scope the prd guard "
        "rails to what the process uses (unknown names get the api's full checks).",
    )
    log_level: str = Field(default="INFO")
    log_json: bool = Field(default=True, description="JSON logs (Cloud Logging) vs console.")

    # --- Tracing (NF-014) ------------------------------------------------------------
    otel_exporter: Literal["none", "console", "gcp"] = Field(
        default="none",
        description="OpenTelemetry span exporter: 'gcp' = Cloud Trace (stg / prd), 'console' "
        "= stdout (local debugging), 'none' = tracing off (default; tests). Trace ids are "
        "logged and propagated to Pub/Sub either way.",
    )
    otel_sample_ratio: float = Field(
        default=1.0, ge=0.0, le=1.0, description="Head sampling ratio for new traces."
    )

    # --- Database ----------------------------------------------------------
    database_url: str = Field(
        default="postgresql+asyncpg://farmerapp_app:farmerapp@localhost:5432/farmerapp",
        description="Runtime SQLAlchemy async URL: the *app* role (DML only, subject to RLS; "
        "SEC-011). Cloud SQL uses IAM auth; local uses compose creds.",
    )
    migration_database_url: str = Field(
        default="postgresql+asyncpg://farmerapp:farmerapp@localhost:5432/farmerapp",
        description="Alembic URL: the owner/migrate role (DDL). Only the migrate job needs it.",
    )
    # Cloud SQL IAM database authentication (SEC-011; farmerapp.db.connect). When true the
    # two URLs above are ignored: the Cloud SQL Python Connector logs in as DB_USER with an
    # IAM token of the runtime service account.
    db_iam_auth: bool = Field(
        default=False,
        description="Connect through the Cloud SQL Python Connector with IAM auth (Cloud Run); "
        "false = DATABASE_URL / MIGRATION_DATABASE_URL (local, CI).",
    )
    db_instance_connection_name: str | None = Field(
        default=None, description="Cloud SQL instance connection name project:region:instance."
    )
    db_user: str | None = Field(
        default=None,
        description="IAM database user: the runtime service account email without "
        "'.gserviceaccount.com' (farmerapp-api@<project>.iam).",
    )
    db_name: str = Field(default="farmerapp", description="Database name (IAM mode).")
    db_ip_type: Literal["private", "public", "psc"] = Field(
        default="private", description="Cloud SQL address the connector uses (private IP)."
    )
    db_pool_size: int = Field(default=5)
    db_max_overflow: int = Field(default=10)
    db_echo: bool = Field(default=False)

    # --- Google Cloud (emulators locally) -----------------------------------
    gcp_project: str = Field(default="farmerapp-local")
    pubsub_emulator_host: str | None = Field(default=None, description="host:port when local.")
    storage_emulator_host: str | None = Field(
        default=None, description="fake-gcs-server URL when local."
    )
    photos_bucket: str = Field(default="farmerapp-local-photos")
    exports_bucket: str = Field(default="farmerapp-local-exports")

    # --- Blob store + resumable uploads (NF-003, SEC-016) ------------------------
    blob_store: Literal["local", "fake_gcs", "gcs"] = Field(
        default="local",
        description="'local' is a directory (unit tests, bare laptop); 'fake_gcs' talks to "
        "STORAGE_EMULATOR_HOST (docker compose); 'gcs' is Cloud Storage with V4 signed URLs "
        "signed through IAM signBlob (SEC-016; required in prd).",
    )
    gcs_signing_service_account: str | None = Field(
        default=None,
        description="Service account whose IAM signBlob signs V4 URLs (BLOB_STORE=gcs). "
        "Default: the runtime service account from the metadata server.",
    )
    blob_local_dir: str = Field(
        default_factory=lambda: str(Path(tempfile.gettempdir()) / "farmerapp-blobs"),
        description="Root directory of the 'local' blob store (dev / unit tests only).",
    )
    upload_chunk_size: int = Field(default=262_144, description="256 KB chunks (NF-003).")
    upload_max_bytes: int = Field(default=20 * 1024 * 1024, description="Largest upload (20 MB).")
    upload_ttl_seconds: int = Field(default=900, description="Pending upload TTL (15 min).")
    signed_url_ttl_seconds: int = Field(default=900, description="Signed URL lifetime (15 min).")

    # --- Sync + idempotency (FA-025, NF-003, SPEC 8.3) ---------------------------
    idempotency_ttl_seconds: int = Field(default=86_400, description="Idempotency-Key kept 24 h.")
    phone_verification_ttl_seconds: int = Field(
        default=1800, description="Farmer phone verification token lifetime (30 min)."
    )
    visit_confirm_token_ttl_seconds: int = Field(
        default=86_400,
        description="FA-016 push / QR confirmation token lifetime (24 h): the farmer app may "
        "scan offline and post the token when back online.",
    )

    # --- Validation agents (VA-001) -------------------------------------------------
    rules_dir: str | None = Field(
        default=None,
        description="Directory of the rule YAML files (VA-001). Default: the monorepo's "
        "rules/ next to apps/; containers set it to the copied rules directory.",
    )

    # --- PII field encryption (SEC-026) ---------------------------------------------
    pii_kek_backend: Literal["local", "kms"] = Field(
        default="local",
        description="Who wraps the per-tenant data keys: 'kms' = Cloud KMS (PII_KMS_KEY_NAME; "
        "required in prd), 'local' = AES-256-GCM with PII_LOCAL_KEK (dev / test only).",
    )
    pii_kms_key_name: str | None = Field(
        default=None,
        description="projects/<p>/locations/asia-south1/keyRings/<r>/cryptoKeys/<k> (NF-011).",
    )
    pii_local_kek: str | None = Field(
        default=None,
        description="base64 of a 32-byte key-encryption key for PII_KEK_BACKEND=local; unset "
        "means the built-in dev key (local / test / dev only). Refused in prd.",
    )
    pii_hash_pepper: str = Field(
        default=DEV_PII_HASH_PEPPER,
        description="HMAC-SHA256 pepper of the searchable phone hash. Secret Manager in "
        "stg / prd; changing it needs a re-hash of every phone_hash column.",
    )
    pii_plaintext_writes: bool = Field(
        default=False,
        description="Transition switch (expand -> migrate -> contract): also write the legacy "
        "plain phone / landmark columns, so the previous release can still read new rows "
        "during a rollout or rollback. Off by default; must be off before the contract step.",
    )

    # --- Play Integrity (SEC-024 server side) -------------------------------------------
    play_integrity_mode: Literal["off", "fake", "google"] = Field(
        default="off",
        description="'google' decodes X-Integrity-Token with the Play Integrity API "
        "(decodeIntegrityToken, service account); 'fake' accepts test tokens; 'off' records "
        "every token as unverified. Never blocks a request (FA-028 / VA-E01).",
    )
    play_integrity_package_names: list[str] = Field(
        default=["in.farmerapp.mitra", "in.farmerapp.kisan"],
        description="Android package names whose tokens are accepted (agent, farmer apps).",
    )
    play_integrity_timeout_s: float = Field(default=2.0, description="decode call timeout.")

    # --- Diagnosis engine (M6, SPEC 3) -------------------------------------------------
    diagnosis_encoder: Literal["fake", "remote"] = Field(
        default="fake",
        description="DX-002 image encoder: 'remote' = the embed Cloud Run service "
        "(DIAGNOSIS_EMBED_URL; required in prd), 'fake' = the deterministic pixel-DCT encoder "
        "(tests, seed, CI evaluation, local dev).",
    )
    diagnosis_encoder_name: str = Field(
        default="siglip-base-patch16-224",
        description="DX-005 pinned encoder name for DIAGNOSIS_ENCODER=remote (stored on every "
        "corpus image and diagnosis; the embed service must answer with the same).",
    )
    diagnosis_encoder_version: str = Field(
        default="2024-01", description="DX-005 pinned encoder weights version (remote)."
    )
    diagnosis_embed_url: str = Field(
        default="http://localhost:8095", description="Base URL of the embed service (ml/embed)."
    )
    diagnosis_embed_timeout_s: float = Field(default=20.0, description="embed call timeout.")
    diagnosis_llm: Literal["claude", "fake", "off"] = Field(
        default="claude",
        description="DX-004 LLM fallback: 'claude' = Anthropic Messages API (ANTHROPIC_API_KEY "
        "from Secret Manager; the client is built on first use), 'fake' = deterministic "
        "in-process stand-in (tests, CI evaluation), 'off' = every fallback is 'unknown'.",
    )
    diagnosis_llm_model: str = Field(default="claude-opus-5", description="DX-004 model id.")
    diagnosis_llm_max_tokens: int = Field(
        default=16_000, description="max_tokens of a fallback call (retried once 2x larger)."
    )
    diagnosis_llm_effort: Literal["low", "medium", "high"] = Field(
        default="medium", description="output_config.effort of the fallback call."
    )
    diagnosis_delivery: Literal["inline", "pubsub"] = Field(
        default="inline",
        description="'pubsub' publishes diagnosis.requested for the worker (stg / prd); "
        "'inline' runs the pipeline in the request (local / dev without the emulator).",
    )
    flag_summary_llm: Literal["claude", "fake", "off"] = Field(
        default="off",
        description="VA-004 review agent: 'claude' = Anthropic Messages API (ANTHROPIC_API_KEY; "
        "worker and jobs), 'fake' = deterministic stand-in (local dev), 'off' = no summaries "
        "(the default until stg / prd set it; docs/prs/M7-rules.md).",
    )
    flag_summary_llm_model: str = Field(
        default="claude-opus-5", description="VA-004 model id (FLAG_SUMMARY_LLM_MODEL)."
    )
    flag_summary_llm_max_tokens: int = Field(
        default=4_000, ge=256, description="max_tokens of one VA-004 summary call."
    )
    # --- M7 farmer P1: weather, evaluation, model releases (FM-008, DX-011, DX-012) ---------
    weather_provider: Literal["open_meteo", "fake"] = Field(
        default="open_meteo",
        description="FM-008 forecast source: 'open_meteo' = the free Open-Meteo API (no key; "
        "called by the server only, with the 0.1-degree grid cell's coordinates and nothing "
        "else), 'fake' = deterministic in-process forecast (tests, offline dev).",
    )
    weather_base_url: str = Field(
        default="https://api.open-meteo.com", description="Open-Meteo forecast API base URL."
    )
    weather_timeout_s: float = Field(default=8.0, gt=0, le=30, description="Forecast timeout.")
    weather_cache_ttl_seconds: int = Field(
        default=10_800,
        ge=0,
        le=86_400,
        description="FM-008 forecast cache per 0.1-degree grid cell (3 h), per instance.",
    )
    corpus_bucket: str = Field(
        default="farmerapp-local-corpus",
        description="DX-011 / DX-012 corpus bucket: held-out test manifest, training-set "
        "exports, candidate on-device models (the 'corpus' bucket of infra/modules/storage).",
    )
    diagnosis_eval_manifest: str = Field(
        default="eval/heldout/manifest.csv",
        description="DX-011 held-out, agronomist-labelled manifest: a key in CORPUS_BUCKET or "
        "a full gs:// URI. Image paths in it are relative to the manifest.",
    )
    diagnosis_knn_k: int = Field(default=20, ge=1, le=100, description="DX-002 neighbours.")
    diagnosis_hnsw_ef_search: int = Field(
        default=40,
        ge=10,
        le=1000,
        description="SET LOCAL hnsw.ef_search for the kNN (pgvector's default, >= k=20; the "
        "iterative scan tops up filtered-out rows). docs/perf/M6-knn.md has the trade-off.",
    )
    diagnosis_max_attempts: int = Field(
        default=5,
        ge=1,
        description="Worker deliveries of one diagnosis before a failing LLM call becomes "
        "'unknown' (provisional + agronomist queue) instead of another Pub/Sub retry.",
    )

    # --- Providers (base URLs only; keys come from Secret Manager) -----------
    sms_provider_url: str = Field(default="http://localhost:8090/sms")
    whatsapp_provider_url: str = Field(default="http://localhost:8090/whatsapp")
    razorpay_base_url: str = Field(default="http://localhost:8090/razorpay")
    razorpay_key_id: str = Field(default="rzp_test_mock", description="Public key id (not secret).")
    # --- Email (WC-013 scheduled reports, AN-015, ST-008) ------------------------------
    email_provider: Literal["log", "fake", "smtp", "sendgrid"] = Field(
        default="log",
        description="EmailSender adapter: 'log' writes an `email_logged` line and sends nothing "
        "(default everywhere until a provider is configured), 'fake' keeps messages in memory "
        "(tests), 'smtp' (EMAIL_SMTP_*), 'sendgrid' (SendGrid-style HTTP API, "
        "EMAIL_API_KEY from Secret Manager).",
    )
    email_from: str = Field(default="reports@farmerapp.local", description="From address.")
    email_smtp_host: str = Field(default="localhost")
    email_smtp_port: int = Field(default=587)
    email_smtp_username: str | None = Field(default=None)
    email_smtp_password: str | None = Field(
        default=None, description="Secret Manager in stg / prd; never in code or .env files."
    )
    email_smtp_starttls: bool = Field(default=True)
    email_api_url: str = Field(default="https://api.sendgrid.com/v3/mail/send")
    email_api_key: str | None = Field(
        default=None, description="HTTP email API key (Secret Manager in stg / prd)."
    )
    email_timeout_s: float = Field(default=20.0)

    # --- Payments (FA-021, SEC-023) ------------------------------------------------
    razorpay_key_secret: str = Field(
        default=DEV_RAZORPAY_API_KEY_PLACEHOLDER,
        description="Razorpay API key secret (basic auth). Secret Manager in stg / prd.",
    )
    razorpay_webhook_secret: str = Field(
        default=DEV_RAZORPAY_WEBHOOK_HMAC_KEY,
        description="HMAC-SHA256 secret of the Razorpay webhook (SEC-023). Secret Manager in "
        "stg / prd; the default is the mockserver's test secret.",
    )
    payment_provider: Literal["razorpay", "fake"] = Field(
        default="razorpay",
        description="'razorpay' talks HTTP to RAZORPAY_BASE_URL (the mockserver locally); "
        "'fake' is in-process (tests).",
    )
    payment_webhook_delivery: Literal["inline", "pubsub"] = Field(
        default="inline",
        description="'inline' applies a verified webhook in the request transaction (local / "
        "dev without the emulator); 'pubsub' publishes it to payment.webhook for the worker.",
    )
    payment_qr_ttl_seconds: int = Field(default=900, description="UPI QR / link validity.")

    # --- M7 field P1: push (FA-007), road snapping (VV-006), meeting QR (FA-027) -------
    push_provider: Literal["fcm", "fake", "off"] = Field(
        default="off",
        description="FA-007 push delivery: 'fcm' = FCM HTTP v1 with the runtime service "
        "account's token (no server key), 'fake' = in-memory (tests), 'off' = nothing is "
        "pushed (rows stay pending; the in-app inbox still lists them).",
    )
    fcm_project: str | None = Field(
        default=None, description="Firebase project id of FCM (default: GCP_PROJECT)."
    )
    notify_max_attempts: int = Field(
        default=5, ge=1, le=20, description="FA-007 push attempts before a row is 'failed'."
    )
    road_snapper: Literal["off", "google"] = Field(
        default="off",
        description="VV-006: 'google' snaps tracks with the Roads API in the process-tracks "
        "job (needs GOOGLE_MAPS_API_KEY from Secret Manager); 'off' = haversine + filters.",
    )
    google_maps_api_key: str | None = Field(
        default=None, description="VV-006 Roads API key (Secret Manager; never in code)."
    )
    meeting_qr_ttl_seconds: int = Field(
        default=300, ge=30, le=3600, description="FA-027 farmer attendance QR validity."
    )

    # --- Auth: OTP (FA-001, SEC-021) --------------------------------------------
    otp_provider: Literal["mockserver", "fake"] = Field(
        default="mockserver",
        description="SMS/WhatsApp adapter. 'fake' is in-process (tests); prod gets a real adapter.",
    )
    otp_pepper: str = Field(
        default=DEV_OTP_PEPPER,
        description="Server pepper for HMAC-SHA256 of OTP codes at rest. Secret Manager in prod.",
    )
    otp_dev_code: str | None = Field(
        default=None,
        description="Fixed OTP accepted in local/dev only (e.g. 123456). Must be unset in prd.",
    )
    otp_ttl_seconds: int = Field(default=300, description="OTP validity (5 min).")
    otp_max_attempts: int = Field(default=5, description="Wrong attempts before lockout.")
    otp_lockout_seconds: int = Field(default=900, description="Lockout duration after 5 misses.")
    otp_max_resends: int = Field(default=3, description="Resends allowed per window.")
    otp_resend_window_seconds: int = Field(default=900, description="Resend window (15 min).")
    otp_resend_after_seconds: int = Field(default=30, description="Client resend timer hint.")
    otp_whatsapp_fallback_seconds: int = Field(
        default=30, description="Send by WhatsApp if SMS is not confirmed delivered by then."
    )

    # --- Auth: SMS pumping protection (SEC-021) ---------------------------------
    # An OTP send costs money and an attacker's revenue: "SMS pumping" farms premium
    # international numbers. Four layers, all tenant-safe and all tested
    # (farmerapp/auth/otp_abuse.py, tests/auth/test_otp_abuse.py).
    otp_allowed_country_codes: list[str] = Field(
        default=["+91"],
        description="SEC-021: E.164 country prefixes an OTP may be sent to. India only by "
        "default; adding a country is a deliberate change, not a config accident.",
    )
    otp_blocked_country_codes: list[str] = Field(
        default=[],
        description="SEC-021: prefixes refused even when the allow list would permit them "
        "(a country turned into a pumping source mid-incident).",
    )
    otp_max_sends_per_phone_day: int = Field(
        default=10,
        ge=1,
        description="SEC-021 velocity: sends to one number per 24 h, across purposes and "
        "resend windows (the 3-per-15-min resend limit only covers one window).",
    )
    otp_max_sends_per_ip_hour: int = Field(
        default=20,
        ge=1,
        description="SEC-021 velocity: sends from one client IP per hour, across phones.",
    )
    otp_abuse_block_seconds: int = Field(
        default=86_400,
        ge=60,
        description="SEC-021: how long a phone or IP that broke a velocity rule stays on the "
        "block list (repeat abusers). Doubled on every further breach, capped at 30 days.",
    )
    otp_cost_alert_per_hour: int = Field(
        default=200,
        ge=1,
        description="SEC-021 cost guard: tenant sends per hour above which an "
        "`otp_cost_alert` ERROR is logged (OPS alert; never blocks a login).",
    )
    otp_cost_block_per_hour: int = Field(
        default=2_000,
        ge=1,
        description="SEC-021 cost guard: tenant sends per hour at which new sends are "
        "refused (429 `otp_cost_limited`). The circuit breaker behind the alert.",
    )

    # --- Auth: JWT (SEC-020) -----------------------------------------------------
    jwt_signing_key: str = Field(
        default=DEV_JWT_SIGNING_KEY,
        description="HS256 key. Secret Manager in prod. TODO: RS256 with a key id once the "
        "console verifies tokens on its own (then publish a JWKS endpoint).",
    )
    jwt_algorithm: Literal["HS256"] = Field(default="HS256")
    jwt_issuer: str = Field(default="farmerapp")
    access_token_ttl_seconds: int = Field(default=900, description="15 minutes.")
    refresh_token_ttl_seconds: int = Field(default=30 * 86400, description="30 days.")
    step_up_token_ttl_seconds: int = Field(
        default=300, ge=60, le=900, description="SEC-028 re-auth token lifetime (5 minutes)."
    )
    security_cache_ttl_seconds: int = Field(
        default=30,
        ge=0,
        le=60,
        description="WC-011 / SEC-025: how long an instance caches a device's status (lost / "
        "revoked) before re-reading it. At most 60 s, so revocation lands well within 5 min.",
    )

    # --- DPDP data-principal rights (NF-013) ---------------------------------------
    # The grievance-redressal contact the apps and the console show, and that
    # ``GET /v1/privacy/contact`` returns. Not a secret; a tenant may override the name and
    # e-mail in its own settings once WC-012 carries them.
    grievance_officer_name: str = Field(
        default="Grievance Officer", description="NF-013: who a data principal may complain to."
    )
    grievance_officer_email: str = Field(
        default="grievance@farmerapp.in", description="NF-013 grievance contact e-mail."
    )
    grievance_officer_phone: str = Field(
        default="+911800000000", description="NF-013 grievance contact phone."
    )
    grievance_response_days: int = Field(
        default=30, ge=1, le=90, description="NF-013 / FM-015: we answer within this many days."
    )

    # --- CORS (console origin) ----------------------------------------------------
    cors_origins: list[str] = Field(
        default=["http://localhost:3000", "http://localhost:3100"],
        description="Console origins allowed to call the API from the browser.",
    )

    @property
    def is_local(self) -> bool:
        return self.app_env in ("local", "test")

    @field_validator(
        "otp_dev_code",
        "pii_local_kek",
        "pii_kms_key_name",
        "db_instance_connection_name",
        "db_user",
        "google_maps_api_key",
        "fcm_project",
        mode="before",
    )
    @classmethod
    def _empty_is_none(cls, value: object) -> object:
        return None if value == "" else value

    @model_validator(mode="after")
    def _prd_guard_rails(self) -> Settings:
        """Refuse to start in production with development-only settings.

        Scoped by ``SERVICE_NAME`` to what the process uses, so the ``migrate`` job needs no
        application secret and the worker no JWT key (least privilege, SEC-013); an unknown
        service name gets every check.
        """
        if self.app_env != "prd":
            return self
        service = self.service_name if self.service_name in CLOUD_REQUIRED_ENV else "api"
        needs = CLOUD_REQUIRED_ENV[service]
        problems: list[str] = []
        if self.otp_dev_code is not None:
            problems.append("OTP_DEV_CODE must be unset in prd")
        if "JWT_SIGNING_KEY" in needs and (
            self.jwt_signing_key == DEV_JWT_SIGNING_KEY or len(self.jwt_signing_key) < 32
        ):
            problems.append("JWT_SIGNING_KEY must be a strong secret (>= 32 chars) in prd")
        if "OTP_PEPPER" in needs and (
            self.otp_pepper == DEV_OTP_PEPPER or len(self.otp_pepper) < 32
        ):
            problems.append("OTP_PEPPER must be a strong secret (>= 32 chars) in prd")
        if self.otp_provider == "fake":
            problems.append("OTP_PROVIDER=fake is not allowed in prd")
        if self.payment_provider == "fake":
            problems.append("PAYMENT_PROVIDER=fake is not allowed in prd")
        if "RAZORPAY_WEBHOOK_SECRET" in needs and self.razorpay_webhook_secret in (
            "",
            DEV_RAZORPAY_WEBHOOK_HMAC_KEY,
        ):
            problems.append("RAZORPAY_WEBHOOK_SECRET must be set from Secret Manager in prd")
        if "RAZORPAY_KEY_SECRET" in needs and self.razorpay_key_secret in (
            "",
            DEV_RAZORPAY_API_KEY_PLACEHOLDER,
        ):
            problems.append("RAZORPAY_KEY_SECRET must be set from Secret Manager in prd")
        if "PII_KMS_KEY_NAME" in needs and (
            self.pii_kek_backend != "kms" or not self.pii_kms_key_name
        ):
            problems.append("PII_KEK_BACKEND=kms with PII_KMS_KEY_NAME is required in prd")
        if self.pii_local_kek:
            problems.append("PII_LOCAL_KEK must be unset in prd (Cloud KMS wraps data keys)")
        if "PII_HASH_PEPPER" in needs and (
            self.pii_hash_pepper == DEV_PII_HASH_PEPPER or len(self.pii_hash_pepper) < 32
        ):
            problems.append("PII_HASH_PEPPER must be a strong secret (>= 32 chars) in prd")
        if "BLOB_STORE" in needs and self.blob_store != "gcs":
            problems.append("BLOB_STORE=gcs is required in prd (SEC-016 signed URLs)")
        if "DIAGNOSIS_ENCODER" in needs and self.diagnosis_encoder != "remote":
            problems.append("DIAGNOSIS_ENCODER=remote is required in prd (DX-002)")
        if self.diagnosis_llm == "fake":
            problems.append("DIAGNOSIS_LLM=fake is not allowed in prd")
        if self.push_provider == "fake":
            problems.append("PUSH_PROVIDER=fake is not allowed in prd")
        problems.extend(self._prd_database_problems(service))
        if problems:
            raise ValueError("; ".join(problems))
        return self

    def _prd_database_problems(self, service: str) -> list[str]:
        """SEC-011: the runtime and the migrations never share a database identity."""
        if not self.db_iam_auth:
            if self.migration_database_url == self.database_url:
                return ["MIGRATION_DATABASE_URL must use a different role than DATABASE_URL"]
            return []
        if not self.db_instance_connection_name or not self.db_user:
            return ["DB_IAM_AUTH=true needs DB_INSTANCE_CONNECTION_NAME and DB_USER in prd"]
        is_migrate_user = self.db_user.startswith(MIGRATE_DB_USER_PREFIX)
        if service == "migrate" and not is_migrate_user:
            return [f"the migrate job must log in as {MIGRATE_DB_USER_PREFIX}… (SEC-011)"]
        if service != "migrate" and is_migrate_user:
            return [f"DB_USER {MIGRATE_DB_USER_PREFIX}… is reserved for the migrate job (SEC-011)"]
        return []


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Cached settings instance. Tests call ``get_settings.cache_clear()`` after monkeypatching."""
    return Settings()
