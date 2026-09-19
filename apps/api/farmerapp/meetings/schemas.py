"""FA-027 farmer meeting payloads."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

from farmerapp.meetings.models import FarmerMeeting, MeetingAttendance
from farmerapp.visits.schemas import CheckinPoint


class MeetingCreate(BaseModel):
    id: uuid.UUID | None = Field(default=None, description="Client id (offline create).")
    village_id: uuid.UUID
    topic: str = Field(min_length=1, max_length=200)
    held_at: datetime
    checkin_point: CheckinPoint


class AttendanceOtpIn(BaseModel):
    farmer_id: uuid.UUID


class AttendanceOtpOut(BaseModel):
    farmer_id: uuid.UUID
    phone_masked: str
    expires_in: int
    resend_after: int
    resends_left: int


class AttendanceIn(BaseModel):
    id: uuid.UUID | None = Field(default=None, description="Client id (offline create).")
    method: Literal["otp", "qr"]
    farmer_id: uuid.UUID | None = Field(default=None, description="Required for `otp`.")
    code: str | None = Field(default=None, pattern=r"^\d{6}$", description="`otp`: the code.")
    token: str | None = Field(
        default=None, min_length=16, max_length=4096, description="`qr`: the scanned token."
    )
    recorded_at: datetime | None = Field(
        default=None,
        description="When the QR was scanned (offline sync); the token must not have expired "
        "by then. Default: now.",
    )

    @model_validator(mode="after")
    def _method(self) -> AttendanceIn:
        if self.method == "otp" and (self.farmer_id is None or self.code is None):
            raise ValueError("otp attendance needs farmer_id and code")
        if self.method == "qr" and self.token is None:
            raise ValueError("qr attendance needs the scanned token")
        return self


class AttendanceOut(BaseModel):
    id: uuid.UUID
    tenant_id: uuid.UUID
    meeting_id: uuid.UUID
    farmer_id: uuid.UUID
    farmer_name: str | None = None
    method: str
    recorded_at: datetime
    recorded_by: uuid.UUID
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(cls, row: MeetingAttendance, farmer_name: str | None = None) -> AttendanceOut:
        return cls(
            id=row.id,
            tenant_id=row.tenant_id,
            meeting_id=row.meeting_id,
            farmer_id=row.farmer_id,
            farmer_name=farmer_name,
            method=row.method,
            recorded_at=row.recorded_at,
            recorded_by=row.recorded_by,
            created_at=row.created_at,
            updated_at=row.updated_at,
            deleted_at=row.deleted_at,
            version=row.version,
        )


class MeetingOut(BaseModel):
    id: uuid.UUID
    tenant_id: uuid.UUID
    officer_id: uuid.UUID
    village_id: uuid.UUID
    topic: str
    held_at: datetime
    checkin_lat: float
    checkin_lon: float
    checkin_accuracy_m: float | None
    geofence_result: str = Field(description="meeting_point (VV-003, like a `meeting` visit).")
    distance_m: float | None
    status: str
    closed_at: datetime | None
    attendees: int = 0
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(cls, row: FarmerMeeting, attendees: int = 0) -> MeetingOut:
        return cls(
            id=row.id,
            tenant_id=row.tenant_id,
            officer_id=row.officer_id,
            village_id=row.village_id,
            topic=row.topic,
            held_at=row.held_at,
            checkin_lat=row.checkin_lat,
            checkin_lon=row.checkin_lon,
            checkin_accuracy_m=row.checkin_accuracy_m,
            geofence_result=row.geofence_result,
            distance_m=row.distance_m,
            status=row.status,
            closed_at=row.closed_at,
            attendees=attendees,
            created_at=row.created_at,
            updated_at=row.updated_at,
            deleted_at=row.deleted_at,
            version=row.version,
        )


class MeetingDetailOut(MeetingOut):
    attendance: list[AttendanceOut]


class MeetingPage(BaseModel):
    items: list[MeetingOut]
    next_cursor: str | None = None


class AttendanceQrOut(BaseModel):
    token: str = Field(description="Show as a QR; the officer scans it (FA-027).")
    farmer_id: uuid.UUID
    expires_at: datetime


__all__ = [
    "AttendanceIn",
    "AttendanceOtpIn",
    "AttendanceOtpOut",
    "AttendanceOut",
    "AttendanceQrOut",
    "MeetingCreate",
    "MeetingDetailOut",
    "MeetingOut",
    "MeetingPage",
]
