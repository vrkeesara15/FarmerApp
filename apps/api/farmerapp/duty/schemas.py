"""``/v1/duty/*`` request / response models (FA-010, VV-001, VV-007).

The same payloads travel as ``duty_session`` sync ops (``create`` = ``DutyStartIn``,
``update`` = ``DutyEndIn``); the REST twins exist for tests and the console.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.location.schemas import DutySessionOut


class DeviceIntegrityIn(BaseModel):
    """FA-028 flags the app reports at duty start (never blocking, flagged to VA-E01)."""

    model_config = ConfigDict(extra="ignore")

    is_mock: bool = False
    is_rooted: bool = False
    clock_drift_s: int = 0


class PointIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0)


class DutyStartIn(BaseModel):
    id: uuid.UUID | None = Field(default=None, description="Client id (sync); else server-set.")
    device_id: str = Field(min_length=1, max_length=128)
    app_version: str = Field(min_length=1, max_length=32)
    policy_version: str = Field(
        min_length=1, max_length=32, description="The location policy version the app holds."
    )
    start_at: datetime = Field(description="When the officer toggled duty on (device clock).")
    start_point: PointIn
    integrity: DeviceIntegrityIn = Field(default_factory=DeviceIntegrityIn)


EndReasonIn = Literal["manual", "auto_time", "auto_idle"]


class DutyEndIn(BaseModel):
    end_at: datetime = Field(description="When the officer toggled duty off (device clock).")
    end_point: PointIn | None = None
    end_reason: EndReasonIn = Field(
        default="manual", description="`auto_*` when the app ended it on the device (VV-007)."
    )


class DutyStatusOut(BaseModel):
    session: DutySessionOut | None = Field(description="The caller's open session, if any.")
    policy_version: str = Field(description="Tenant `location_policy_version` to accept (VV-010).")
    policy_accepted: bool = Field(description="Whether the caller has accepted that version.")


class DutyPolicyOut(BaseModel):
    """VV-001 sampling policy served to the app, from the tenant settings."""

    moving_interval_s: int
    stationary_interval_s: int
    upload_interval_s: int
    upload_on_wifi_or_charging: bool = True


__all__ = [
    "DeviceIntegrityIn",
    "DutyEndIn",
    "DutyPolicyOut",
    "DutyStartIn",
    "DutyStatusOut",
    "EndReasonIn",
    "PointIn",
]
