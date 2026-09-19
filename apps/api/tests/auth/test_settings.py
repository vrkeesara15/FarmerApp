"""Production guard rails: no dev OTP code, no default signing key / pepper in prd."""

from __future__ import annotations

from typing import Any

import pytest

from farmerapp.settings import Settings

STRONG = "x" * 48
KMS_KEY = "projects/p/locations/asia-south1/keyRings/farmerapp/cryptoKeys/pii"
#: SEC-026 / SEC-016 production settings (Cloud KMS, a real pepper, GCS signed URLs).
PRD_PII_AND_BLOBS: dict[str, Any] = {
    "pii_kek_backend": "kms",
    "pii_kms_key_name": KMS_KEY,
    "pii_hash_pepper": STRONG,
    "blob_store": "gcs",
    "diagnosis_encoder": "remote",  # DX-002: the pinned embed service in prd
    "diagnosis_llm": "claude",  # tests run with DIAGNOSIS_LLM=fake
}


#: The test suite runs with fake providers (conftest); a prd process never does.
PRD_REAL: dict[str, Any] = {
    "app_env": "prd",
    "otp_provider": "mockserver",
    "payment_provider": "razorpay",
    "diagnosis_llm": "claude",
}


def test_prd_rejects_dev_otp_code() -> None:
    with pytest.raises(ValueError, match="OTP_DEV_CODE"):
        Settings(app_env="prd", otp_dev_code="123456", jwt_signing_key=STRONG, otp_pepper=STRONG)


def test_prd_rejects_default_secrets() -> None:
    with pytest.raises(ValueError, match="JWT_SIGNING_KEY"):
        Settings(app_env="prd", otp_pepper=STRONG)
    with pytest.raises(ValueError, match="OTP_PEPPER"):
        Settings(app_env="prd", jwt_signing_key=STRONG)


def test_prd_accepts_strong_secrets() -> None:
    s = Settings.model_validate(
        {
            "app_env": "prd",
            "jwt_signing_key": STRONG,
            "otp_pepper": STRONG,
            "otp_provider": "mockserver",
            "razorpay_key_secret": STRONG,  # FA-021 / SEC-023: Secret Manager in prd
            "razorpay_webhook_secret": STRONG,
            "payment_provider": "razorpay",  # tests run with PAYMENT_PROVIDER=fake
            **PRD_PII_AND_BLOBS,
        }
    )
    assert s.otp_dev_code is None


def test_local_defaults_allow_dev_code() -> None:
    s = Settings(app_env="local", otp_dev_code="123456")
    assert s.otp_dev_code == "123456"


def _prd(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "app_env": "prd",
        "jwt_signing_key": STRONG,
        "otp_pepper": STRONG,
        "otp_provider": "mockserver",
        "razorpay_key_secret": STRONG,
        "razorpay_webhook_secret": STRONG,
        "payment_provider": "razorpay",
        **PRD_PII_AND_BLOBS,
    }
    values.update(overrides)
    return Settings.model_validate(values)


def test_prd_refuses_a_local_pii_key() -> None:
    """SEC-026: production never wraps data keys with a key from settings."""
    with pytest.raises(ValueError, match="PII_KEK_BACKEND=kms"):
        _prd(pii_kek_backend="local")
    with pytest.raises(ValueError, match="PII_LOCAL_KEK must be unset"):
        _prd(pii_local_kek="QUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUE=")
    with pytest.raises(ValueError, match="PII_KEK_BACKEND=kms"):
        _prd(pii_kms_key_name=None)


def test_prd_requires_a_pepper_and_gcs() -> None:
    with pytest.raises(ValueError, match="PII_HASH_PEPPER"):
        _prd(pii_hash_pepper="short")
    with pytest.raises(ValueError, match="BLOB_STORE=gcs"):
        _prd(blob_store="local")
    assert _prd().pii_kek_backend == "kms"


def test_prd_requires_the_remote_encoder_and_a_real_llm() -> None:
    """M6: the fake encoder / fake LLM never serve farmers in production."""
    with pytest.raises(ValueError, match="DIAGNOSIS_ENCODER=remote"):
        _prd(diagnosis_encoder="fake")
    with pytest.raises(ValueError, match="DIAGNOSIS_LLM=fake"):
        _prd(diagnosis_llm="fake")
    assert _prd(diagnosis_llm="off").diagnosis_llm == "off"


def test_prd_guard_rails_are_scoped_to_what_the_process_uses() -> None:
    """Least privilege (SEC-013): the migrate job mounts no secret, the worker no JWT key or OTP
    pepper; neither may refuse to start only because the api needs them."""
    migrate = Settings.model_validate({**PRD_REAL, "service_name": "migrate"})
    assert migrate.service_name == "migrate"
    worker = Settings.model_validate(
        {
            **PRD_REAL,
            "service_name": "worker",
            "razorpay_key_secret": STRONG,
            "razorpay_webhook_secret": STRONG,
            **PRD_PII_AND_BLOBS,
        }
    )
    assert worker.pii_kek_backend == "kms"
    jobs = {**PRD_REAL, "service_name": "jobs", **PRD_PII_AND_BLOBS}
    assert Settings.model_validate(jobs).service_name == "jobs"
    with pytest.raises(ValueError, match="PII_HASH_PEPPER"):
        Settings.model_validate({**jobs, "pii_hash_pepper": "short"})
    # An unknown process gets every check (the api's).
    with pytest.raises(ValueError, match="JWT_SIGNING_KEY"):
        Settings.model_validate({**PRD_REAL, "service_name": "cron", **PRD_PII_AND_BLOBS})
    # Checks every process shares.
    with pytest.raises(ValueError, match="OTP_DEV_CODE"):
        Settings.model_validate({**PRD_REAL, "service_name": "migrate", "otp_dev_code": "1"})


def test_prd_iam_database_login_needs_instance_and_user() -> None:
    """SEC-011 with Cloud SQL IAM auth (DB_IAM_AUTH=true): no password URL, but an instance
    and a user; the two-URL role check applies only without IAM."""
    iam: dict[str, Any] = {**PRD_REAL, "service_name": "migrate", "db_iam_auth": True}
    with pytest.raises(ValueError, match="DB_INSTANCE_CONNECTION_NAME and DB_USER"):
        Settings.model_validate(iam)
    same_urls = {"database_url": "x", "migration_database_url": "x"}
    ok = Settings.model_validate(
        {
            **iam,
            **same_urls,
            "db_instance_connection_name": "p:asia-south1:i",
            "db_user": "farmerapp-migrate@p.iam",
        }
    )
    assert ok.db_iam_auth
    with pytest.raises(ValueError, match="MIGRATION_DATABASE_URL must use a different role"):
        Settings.model_validate({**PRD_REAL, "service_name": "migrate", **same_urls})
