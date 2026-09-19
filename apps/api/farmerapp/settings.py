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


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(str(_REPO_ROOT_ENV), ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # --- Runtime -----------------------------------------------------------
    app_env: Environment = Field(default="local", description="Deployment environment.")
    service_name: str = Field(default="api", description="api | worker | jobs; used in logs.")
    log_level: str = Field(default="INFO")
    log_json: bool = Field(default=True, description="JSON logs (Cloud Logging) vs console.")

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
    blob_store: Literal["local", "fake_gcs"] = Field(
        default="local",
        description="'local' is a directory (unit tests, bare laptop); 'fake_gcs' talks to "
        "STORAGE_EMULATOR_HOST (docker compose). The real GCS adapter with V4 signed URLs "
        "lands with SEC-016 (M5), together with the prd guard rail that requires it.",
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

    # --- Providers (base URLs only; keys come from Secret Manager) -----------
    sms_provider_url: str = Field(default="http://localhost:8090/sms")
    whatsapp_provider_url: str = Field(default="http://localhost:8090/whatsapp")
    razorpay_base_url: str = Field(default="http://localhost:8090/razorpay")
    razorpay_key_id: str = Field(default="rzp_test_mock", description="Public key id (not secret).")
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

    # --- CORS (console origin) ----------------------------------------------------
    cors_origins: list[str] = Field(
        default=["http://localhost:3000", "http://localhost:3100"],
        description="Console origins allowed to call the API from the browser.",
    )

    @property
    def is_local(self) -> bool:
        return self.app_env in ("local", "test")

    @field_validator("otp_dev_code", mode="before")
    @classmethod
    def _empty_dev_code_is_none(cls, value: object) -> object:
        return None if value == "" else value

    @model_validator(mode="after")
    def _prd_guard_rails(self) -> Settings:
        """Refuse to start in production with development-only auth settings."""
        if self.app_env != "prd":
            return self
        problems: list[str] = []
        if self.otp_dev_code is not None:
            problems.append("OTP_DEV_CODE must be unset in prd")
        if self.jwt_signing_key == DEV_JWT_SIGNING_KEY or len(self.jwt_signing_key) < 32:
            problems.append("JWT_SIGNING_KEY must be a strong secret (>= 32 chars) in prd")
        if self.otp_pepper == DEV_OTP_PEPPER or len(self.otp_pepper) < 32:
            problems.append("OTP_PEPPER must be a strong secret (>= 32 chars) in prd")
        if self.otp_provider == "fake":
            problems.append("OTP_PROVIDER=fake is not allowed in prd")
        if self.payment_provider == "fake":
            problems.append("PAYMENT_PROVIDER=fake is not allowed in prd")
        if self.razorpay_webhook_secret in ("", DEV_RAZORPAY_WEBHOOK_HMAC_KEY):
            problems.append("RAZORPAY_WEBHOOK_SECRET must be set from Secret Manager in prd")
        if self.razorpay_key_secret in ("", DEV_RAZORPAY_API_KEY_PLACEHOLDER):
            problems.append("RAZORPAY_KEY_SECRET must be set from Secret Manager in prd")
        if self.migration_database_url == self.database_url:
            problems.append("MIGRATION_DATABASE_URL must use a different role than DATABASE_URL")
        if problems:
            raise ValueError("; ".join(problems))
        return self


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Cached settings instance. Tests call ``get_settings.cache_clear()`` after monkeypatching."""
    return Settings()
