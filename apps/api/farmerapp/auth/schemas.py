"""Request/response models for the auth endpoints."""

from __future__ import annotations

import re
import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field

from farmerapp.auth.models import User

_INDIAN_MOBILE = re.compile(r"^\+91[6-9]\d{9}$")


def normalise_phone(value: str) -> str:
    """Accept ``9876543210`` / ``+91 98765 43210`` / ``+919876543210``; return E.164."""
    digits = re.sub(r"[\s\-()]", "", value)
    if re.fullmatch(r"[6-9]\d{9}", digits):
        digits = "+91" + digits
    elif re.fullmatch(r"0[6-9]\d{9}", digits):
        digits = "+91" + digits[1:]
    elif re.fullmatch(r"91[6-9]\d{9}", digits):
        digits = "+" + digits
    if not _INDIAN_MOBILE.fullmatch(digits):
        raise ValueError("must be an Indian mobile number (+91 and 10 digits starting 6-9)")
    return digits


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


class OtpVerifyRequest(BaseModel):
    phone: Phone
    code: str = Field(pattern=r"^\d{6}$")
    device_id: DeviceId = None
    device_name: str | None = Field(default=None, max_length=200)


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


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["Bearer"] = "Bearer"
    expires_in: int = Field(description="Access token lifetime in seconds.")
    user: UserOut


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=16, max_length=256)
    device_id: DeviceId = None


class LogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=1, max_length=256)
