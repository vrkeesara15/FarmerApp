"""Request/response models for the auth endpoints."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field

from farmerapp.auth.models import User
from farmerapp.pii.crypto import normalise_phone as _normalise_phone

# One normalisation for validation and the SEC-026 phone hash (farmerapp.pii.crypto).
normalise_phone = _normalise_phone


Phone = Annotated[str, AfterValidator(normalise_phone)]
DeviceId = Annotated[str | None, Field(default=None, max_length=128, min_length=1)]


class OtpSendRequest(BaseModel):
    phone: Phone
    purpose: Literal["login"] = "login"
    device_id: DeviceId = None


class OtpSendResponse(BaseModel):
    challenge_id: uuid.UUID
    phone_masked: str
    channel: Literal["sms", "whatsapp"]
    expires_in: int = Field(description="Seconds until the code expires.")
    resend_after: int = Field(description="Seconds the client should wait before offering resend.")
    resends_left: int


Platform = Annotated[str | None, Field(default=None, max_length=32)]
DeviceModel = Annotated[str | None, Field(default=None, max_length=200)]
AppVersion = Annotated[str | None, Field(default=None, max_length=32)]


class OtpVerifyRequest(BaseModel):
    phone: Phone
    code: str = Field(pattern=r"^\d{6}$")
    device_id: DeviceId = None
    device_name: str | None = Field(default=None, max_length=200)
    platform: Platform = Field(default=None, description="WC-011 device list, e.g. `android`.")
    model: DeviceModel = None
    app_version: AppVersion = None


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    phone: str
    name: str
    role: str
    store_id: uuid.UUID | None
    cluster_id: uuid.UUID | None
    language: str
    status: str
    created_at: datetime

    @classmethod
    def from_user(cls, user: User) -> UserOut:
        return cls.model_validate(user)


class AssignedOfficerOut(BaseModel):
    """FM-011 / F62: the farmer's field officer (call / WhatsApp from the farmer app).

    ``phone`` is the decrypted number (SEC-026 field cipher) for the farmer themself, the
    officer themself and the roles that read user profiles (``GET /v1/users``); masked
    (``+91******3210``) for every other reader.
    """

    id: uuid.UUID
    name: str
    phone: str


class MeOut(UserOut):
    """``GET /v1/me``: the profile plus, for a farmer login, their field officer (FM-011)."""

    officer: AssignedOfficerOut | None = Field(
        default=None,
        description="Farmer logins only: who registered them, else their village store's officer.",
    )


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["Bearer"] = "Bearer"
    expires_in: int = Field(description="Access token lifetime in seconds.")
    user: UserOut


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=16, max_length=256)
    device_id: DeviceId = None
    app_version: AppVersion = None


class StepUpVerifyRequest(BaseModel):
    code: str = Field(pattern=r"^\d{6}$")


class StepUpTokenResponse(BaseModel):
    step_up_token: str = Field(description="Send as `X-Step-Up-Token` with the admin action.")
    expires_in: int = Field(description="Seconds the step-up token stays valid.")


class LogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=1, max_length=256)
