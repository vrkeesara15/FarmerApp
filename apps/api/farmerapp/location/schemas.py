"""Read models for duty sessions and officer tracks (M2-KICKOFF)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.api.pagination import PageOut
from farmerapp.farmers.schemas import LatLon
from farmerapp.location.models import DutySession, LocationPoint, PolicyAcceptance


class DutySessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    officer_id: uuid.UUID
    start_at: datetime
    end_at: datetime | None
    start_point: LatLon | None
    end_point: LatLon | None
    km: Decimal | None = Field(description="Computed by the track processing (VV-006).")
    stops: list[dict[str, Any]]
    end_reason: str | None
    policy_version: str
    device_id: str | None
    app_version: str | None
    duration_s: int | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(cls, row: DutySession) -> DutySessionOut:
        return cls(
            id=row.id,
            tenant_id=row.tenant_id,
            officer_id=row.officer_id,
            start_at=row.start_at,
            end_at=row.end_at,
            start_point=_latlon(row.start_lat, row.start_lon),
            end_point=_latlon(row.end_lat, row.end_lon),
            km=row.km,
            stops=list(row.stops or []),
            end_reason=row.end_reason,
            policy_version=row.policy_version,
            device_id=row.device_id,
            app_version=row.app_version,
            duration_s=row.duration_s,
            created_at=row.created_at,
            updated_at=row.updated_at,
            deleted_at=row.deleted_at,
            version=row.version,
        )


DutySessionPage = PageOut[DutySessionOut]


class PolicyAcceptanceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    policy_key: str
    version: str
    accepted_at: datetime
    device_id: str | None
    app_version: str | None
    text_hash: str | None
    created_at: datetime

    @classmethod
    def from_row(cls, row: PolicyAcceptance) -> PolicyAcceptanceOut:
        return cls.model_validate(row)


class LocationPointOut(BaseModel):
    ts: datetime
    lat: float
    lon: float
    accuracy_m: float
    speed_mps: float | None
    bearing: float | None
    battery_pct: int | None
    is_mock: bool
    is_rooted: bool
    clock_drift_s: int
    provider: str | None
    duty_session_id: uuid.UUID | None

    @classmethod
    def from_row(cls, row: LocationPoint) -> LocationPointOut:
        return cls(
            ts=row.ts,
            lat=row.lat,
            lon=row.lon,
            accuracy_m=row.accuracy_m,
            speed_mps=row.speed_mps,
            bearing=row.bearing,
            battery_pct=row.battery_pct,
            is_mock=row.is_mock,
            is_rooted=row.is_rooted,
            clock_drift_s=row.clock_drift_s,
            provider=row.provider,
            duty_session_id=row.duty_session_id,
        )


class TrackOut(BaseModel):
    officer_id: uuid.UUID
    day: date = Field(description="Local (IST) day the points belong to.")
    count: int
    points: list[LocationPointOut]


def _latlon(lat: float | None, lon: float | None) -> LatLon | None:
    if lat is None or lon is None:
        return None
    return LatLon(lat=lat, lon=lon)


__all__ = [
    "DutySessionOut",
    "DutySessionPage",
    "LocationPointOut",
    "PolicyAcceptanceOut",
    "TrackOut",
]
