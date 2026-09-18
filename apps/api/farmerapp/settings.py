"""Runtime configuration.

Every value is read from the environment (or a local ``.env`` file). Nothing here is a
secret: production secrets are injected by Secret Manager into the environment and are
only ever *referenced* by name in code. See ``/.env.example`` for the full list.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

Environment = Literal["local", "test", "dev", "stg", "prd"]

# Monorepo root .env (apps/api/farmerapp/settings.py -> repo root); a cwd .env overrides it.
# In containers the package lives at /app/farmerapp, so fall back to the filesystem root.
_PARENTS = Path(__file__).resolve().parents
_REPO_ROOT_ENV = (_PARENTS[3] if len(_PARENTS) > 3 else _PARENTS[-1]) / ".env"


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
        default="postgresql+asyncpg://farmerapp:farmerapp@localhost:5432/farmerapp",
        description="SQLAlchemy async URL. Cloud SQL uses IAM auth; local uses compose creds.",
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

    # --- Providers (base URLs only; keys come from Secret Manager) -----------
    sms_provider_url: str = Field(default="http://localhost:8090/sms")
    whatsapp_provider_url: str = Field(default="http://localhost:8090/whatsapp")
    razorpay_base_url: str = Field(default="http://localhost:8090/razorpay")
    razorpay_key_id: str = Field(default="rzp_test_mock", description="Public key id (not secret).")

    @property
    def is_local(self) -> bool:
        return self.app_env in ("local", "test")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Cached settings instance. Tests call ``get_settings.cache_clear()`` after monkeypatching."""
    return Settings()
