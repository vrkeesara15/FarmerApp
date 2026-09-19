"""Request/response models for ``/v1/users`` and ``/v1/devices`` (WC-011)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from farmerapp.api.pagination import PageOut
from farmerapp.auth.models import Device, UserRole, UserStatus
from farmerapp.auth.schemas import Phone, UserOut
from farmerapp.tenants.settings import Language


class UserCreate(BaseModel):
    """A staff account (farmers sign up through ``/v1/farmers``)."""

    model_config = ConfigDict(extra="forbid")

    phone: Phone
    name: str = Field(min_length=1, max_length=200)
    role: UserRole
    store_id: uuid.UUID | None = None
    cluster_id: uuid.UUID | None = None
    language: Language | None = Field(
        default=None, description="Defaults to the tenant's `default_language`."
    )

    @field_validator("role")
    @classmethod
    def _staff_role(cls, value: UserRole) -> UserRole:
        if value == UserRole.FARMER:
            raise ValueError("farmers are created through /v1/farmers")
        return value


class UserUpdate(BaseModel):
    """PATCH body: only the fields present are changed; ``null`` clears store/cluster.

    Changing ``role`` or ``status`` needs a step-up token (SEC-028); ``status=disabled``
    signs the user out everywhere and makes their apps wipe local data (SEC-025).
    """

    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=1, max_length=200)
    role: UserRole | None = None
    status: UserStatus | None = None
    store_id: uuid.UUID | None = None
    cluster_id: uuid.UUID | None = None

    @model_validator(mode="after")
    def _at_least_one_field(self) -> UserUpdate:
        if not self.model_fields_set:
            raise ValueError("at least one field must be provided")
        return self


class DeviceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    device_id: str
    platform: str | None
    model: str | None
    app_version: str | None
    first_seen: datetime
    last_seen: datetime
    status: Literal["pending", "active", "revoked", "lost"]
    bound_at: datetime | None
    revoked_at: datetime | None

    @classmethod
    def from_row(cls, row: Device) -> DeviceOut:
        return cls.model_validate(row)


class DeviceList(BaseModel):
    items: list[DeviceOut]


class ForceLogoutOut(BaseModel):
    user_id: uuid.UUID
    revoked_sessions: int = Field(description="Refresh token families signed out.")
    tokens_valid_after: datetime


class DeviceStatusOut(BaseModel):
    """``GET /v1/devices/me/status`` (SEC-025): polled by the apps on start."""

    device_id: str | None
    status: Literal["pending", "active", "revoked", "lost", "unknown"]
    wipe_required: bool = Field(description="Wipe local data now and return to login.")
    user_status: Literal["active", "disabled"]


UserPage = PageOut[UserOut]

__all__ = [
    "DeviceList",
    "DeviceOut",
    "DeviceStatusOut",
    "ForceLogoutOut",
    "UserCreate",
    "UserOut",
    "UserPage",
    "UserUpdate",
]
