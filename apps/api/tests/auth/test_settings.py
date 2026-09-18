"""Production guard rails: no dev OTP code, no default signing key / pepper in prd."""

from __future__ import annotations

import pytest

from farmerapp.settings import Settings

STRONG = "x" * 48


def test_prd_rejects_dev_otp_code() -> None:
    with pytest.raises(ValueError, match="OTP_DEV_CODE"):
        Settings(app_env="prd", otp_dev_code="123456", jwt_signing_key=STRONG, otp_pepper=STRONG)


def test_prd_rejects_default_secrets() -> None:
    with pytest.raises(ValueError, match="JWT_SIGNING_KEY"):
        Settings(app_env="prd", otp_pepper=STRONG)
    with pytest.raises(ValueError, match="OTP_PEPPER"):
        Settings(app_env="prd", jwt_signing_key=STRONG)


def test_prd_accepts_strong_secrets() -> None:
    s = Settings(
        app_env="prd", jwt_signing_key=STRONG, otp_pepper=STRONG, otp_provider="mockserver"
    )
    assert s.otp_dev_code is None


def test_local_defaults_allow_dev_code() -> None:
    s = Settings(app_env="local", otp_dev_code="123456")
    assert s.otp_dev_code == "123456"
