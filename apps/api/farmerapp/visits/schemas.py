"""Read and write models for visits (FA-014 .. FA-017, FA-028, VV-003 .. VV-005).

Write models are the REST bodies *and* the ``POST /v1/sync`` payloads (the sync service
validates the same classes), so a device queues exactly what it would POST.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from farmerapp.api.pagination import PageOut
from farmerapp.farmers.models import CropStage
from farmerapp.farmers.schemas import LatLon
from farmerapp.visits.models import (
    OverrideRequest,
    Visit,
    VisitConfirmation,
    VisitPhoto,
    VisitPurpose,
)
from farmerapp.visits.scoring import DeviceIntegrity


# --------------------------------------------------------------------------- write models
class CheckinPoint(LatLon):
    accuracy_m: float | None = Field(default=None, ge=0, le=10_000)


class DeviceIntegrityIn(BaseModel):
    """FA-028 flags the app reports at check-in; recorded, never blocking."""

    is_mock: bool = False
    is_rooted: bool = False
    clock_drift_s: int = Field(default=0, ge=-86_400 * 365, le=86_400 * 365)


class VisitCheckIn(BaseModel):
    """FA-014 check-in (REST ``POST /v1/visits/check-in``; sync ``visit.create``)."""

    id: uuid.UUID | None = Field(default=None, description="Client-generated visit id (offline).")
    farmer_id: uuid.UUID
    farm_id: uuid.UUID | None = None
    village_id: uuid.UUID | None = Field(
        default=None, description="Meeting-point village; defaults to the farmer's village."
    )
    purpose: VisitPurpose
    checkin_at: datetime = Field(description="Device time of the check-in (aware).")
    checkin_point: CheckinPoint
    device_integrity: DeviceIntegrityIn = Field(default_factory=DeviceIntegrityIn)
    override_note: str | None = Field(
        default=None,
        min_length=1,
        max_length=2000,
        description="FA-014: why the officer checks in outside the geofence (needs approval).",
    )
    client_visit_id: uuid.UUID | None = Field(
        default=None, description="The device's own id for replays; defaults to `id`."
    )

    @model_validator(mode="after")
    def _aware(self) -> VisitCheckIn:
        if self.checkin_at.tzinfo is None:
            raise ValueError("checkin_at must carry a timezone")
        return self


class VisitCapture(BaseModel):
    """FA-015 notes / crop stage / purpose (REST ``PATCH``; sync ``visit.update``)."""

    model_config = ConfigDict(extra="forbid")

    notes: str | None = Field(default=None, max_length=4000)
    crop_stage: CropStage | None = None
    purpose: VisitPurpose | None = None


class VisitCheckOut(BaseModel):
    """FA-017 check-out (REST ``POST .../check-out``; sync ``visit.update`` with these keys)."""

    checkout_at: datetime
    checkout_point: LatLon | None = None

    @model_validator(mode="after")
    def _aware(self) -> VisitCheckOut:
        if self.checkout_at.tzinfo is None:
            raise ValueError("checkout_at must carry a timezone")
        return self


class VisitPhotoCreate(BaseModel):
    """FA-015 in-app photo (REST ``POST .../photos``; sync ``visit_photo.create``).

    ``blob_uri`` is the completed NF-003 upload (``purpose = visit_photo``). ``exif_time`` /
    ``exif_point`` come from the in-app camera (NF-004); when absent the server reads the
    JPEG's EXIF. ``taken_in_app: false`` is refused (``gallery_not_allowed``).
    """

    id: uuid.UUID | None = Field(default=None, description="Client-generated photo id.")
    visit_id: uuid.UUID | None = Field(default=None, description="Sync payloads carry it.")
    blob_uri: str = Field(min_length=6, max_length=512, pattern=r"^gs://")
    sha256: str | None = Field(default=None, pattern=r"^[0-9a-f]{64}$")
    exif_time: datetime | None = None
    exif_point: LatLon | None = None
    taken_in_app: bool = True
    device_time: datetime | None = None


class ConfirmationRequest(BaseModel):
    """FA-016: ask the farmer to confirm through one channel."""

    channel: Literal["sms_otp", "app_push", "qr"]


class ConfirmationSubmit(BaseModel):
    """FA-016 officer-side completion: the OTP the farmer read out (``sms_otp``)."""

    channel: Literal["sms_otp", "app_push", "qr"]
    code: str | None = Field(default=None, min_length=4, max_length=8)
    token: str | None = Field(default=None, min_length=16, max_length=2048)


class FarmerConfirm(BaseModel):
    """FA-016 / FM-011 farmer-side completion for ``app_push`` and ``qr``."""

    token: str = Field(min_length=16, max_length=2048)
    rating: int | None = Field(default=None, ge=1, le=5)
    reason: str | None = Field(default=None, max_length=200)


class OverrideDecisionIn(BaseModel):
    note: str | None = Field(default=None, max_length=500)


# --------------------------------------------------------------------------- read models
class DeviceIntegrityOut(BaseModel):
    is_mock: bool
    is_rooted: bool
    clock_drift_s: int


class VisitPhotoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    visit_id: uuid.UUID
    blob_uri: str
    sha256: str | None
    phash: str | None
    exif_time: datetime | None
    exif_point: LatLon | None
    taken_in_app: bool
    device_time: datetime | None
    server_time: datetime
    photo_flags: list[str] = Field(
        default_factory=list, description="VA-E08 evidence flags (never a rejection)."
    )
    signed_url: str | None = Field(
        default=None, description="15-minute read URL (SEC-016); detail reads only."
    )
    signed_url_expires_at: datetime | None = None
    created_at: datetime
    version: int

    @classmethod
    def from_row(
        cls,
        row: VisitPhoto,
        *,
        signed_url: str | None = None,
        signed_url_expires_at: datetime | None = None,
    ) -> VisitPhotoOut:
        return cls(
            id=row.id,
            visit_id=row.visit_id,
            blob_uri=row.blob_uri,
            sha256=row.sha256,
            phash=row.phash,
            exif_time=row.exif_time,
            exif_point=_latlon(row.exif_lat, row.exif_lon),
            taken_in_app=row.taken_in_app,
            device_time=row.device_time,
            server_time=row.server_time,
            photo_flags=list(row.photo_flags or []),
            signed_url=signed_url,
            signed_url_expires_at=signed_url_expires_at,
            created_at=row.created_at,
            version=row.version,
        )


class VisitConfirmationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    visit_id: uuid.UUID
    channel: str
    status: str = Field(description="pending | confirmed | expired")
    otp_challenge_id: uuid.UUID | None
    farmer_phone_last4: str | None
    requested_at: datetime | None
    expires_at: datetime | None
    confirmed_at: datetime | None
    confirmed_via_device_id: str | None
    rating: int | None
    rating_reason: str | None
    created_at: datetime
    version: int

    @classmethod
    def from_row(cls, row: VisitConfirmation) -> VisitConfirmationOut:
        return cls.model_validate(row)


class ConfirmationRequestOut(BaseModel):
    """Answer to ``POST /v1/visits/{id}/confirm/request``."""

    confirmation: VisitConfirmationOut
    channel: str
    phone_masked: str | None = Field(default=None, description="`sms_otp`: where the code went.")
    expires_in: int = Field(description="Seconds until the code / token lapses.")
    resend_after: int | None = None
    resends_left: int | None = None
    token: str | None = Field(
        default=None,
        description="`qr`: the signed token to render as a QR for the farmer app to scan.",
    )


class OverrideRequestOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    visit_id: uuid.UUID
    note: str
    requested_at: datetime
    requested_by: uuid.UUID
    approver_role: str
    decided_at: datetime | None
    decision: str | None = Field(description="null while pending; approved | rejected")
    decided_by: uuid.UUID | None
    decision_note: str | None
    created_at: datetime
    version: int

    @classmethod
    def from_row(cls, row: OverrideRequest) -> OverrideRequestOut:
        return cls.model_validate(row)


class VisitOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    officer_id: uuid.UUID
    farmer_id: uuid.UUID
    farm_id: uuid.UUID | None
    village_id: uuid.UUID | None
    purpose: str
    checkin_at: datetime
    checkout_at: datetime | None
    checkin_point: LatLon
    checkin_accuracy_m: float | None
    checkout_point: LatLon | None
    geofence_result: str
    override_note: str | None
    override_approved_by: uuid.UUID | None
    notes: str | None
    crop_stage: str | None
    duration_s: int | None = Field(description="Generated by the database (FA-017).")
    score: int | None = Field(description="VV-004, 0-100; null while open.")
    status: str = Field(description="VV-005: verified | partial | unverified | open.")
    confirmation_channel: str
    confirmed_at: datetime | None
    device_integrity: DeviceIntegrityOut
    integrity_issues: list[str] = Field(
        default_factory=list,
        description="FA-028: mock_location | rooted_device | clock_drift (recorded, not blocking).",
    )
    flags: list[str] = Field(default_factory=list, description="FA-017: under_minimum.")
    client_visit_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(cls, row: Visit) -> VisitOut:
        return cls(**_visit_fields(row))


class VisitDetailOut(VisitOut):
    """One visit with its photos, confirmations, override request and the VV-004 components."""

    score_components: dict[str, int] | None
    photos: list[VisitPhotoOut] = Field(default_factory=list)
    confirmations: list[VisitConfirmationOut] = Field(default_factory=list)
    override_request: OverrideRequestOut | None = None

    @classmethod
    def from_rows(
        cls,
        row: Visit,
        photos: list[VisitPhotoOut] | None = None,
        confirmations: list[VisitConfirmation] | None = None,
        override_request: OverrideRequest | None = None,
    ) -> VisitDetailOut:
        return cls(
            **_visit_fields(row),
            score_components=dict(row.score_components) if row.score_components else None,
            photos=list(photos or []),
            confirmations=[VisitConfirmationOut.from_row(c) for c in confirmations or []],
            override_request=(
                OverrideRequestOut.from_row(override_request)
                if override_request is not None
                else None
            ),
        )


VisitPage = PageOut[VisitOut]


def _latlon(lat: float | None, lon: float | None) -> LatLon | None:
    if lat is None or lon is None:
        return None
    return LatLon(lat=lat, lon=lon)


def integrity_issues(raw: dict[str, Any] | None) -> list[str]:
    """FA-028: the failed checks recorded in ``visit.device_integrity``."""
    issues = (raw or {}).get("issues")
    return [str(i) for i in issues] if isinstance(issues, list) else []


def _visit_fields(row: Visit) -> dict[str, Any]:
    integrity = DeviceIntegrity.from_dict(row.device_integrity)
    return {
        "id": row.id,
        "tenant_id": row.tenant_id,
        "officer_id": row.officer_id,
        "farmer_id": row.farmer_id,
        "farm_id": row.farm_id,
        "village_id": row.village_id,
        "purpose": row.purpose,
        "checkin_at": row.checkin_at,
        "checkout_at": row.checkout_at,
        "checkin_point": LatLon(lat=row.checkin_lat, lon=row.checkin_lon),
        "checkin_accuracy_m": row.checkin_accuracy_m,
        "checkout_point": _latlon(row.checkout_lat, row.checkout_lon),
        "geofence_result": row.geofence_result,
        "override_note": row.override_note,
        "override_approved_by": row.override_approved_by,
        "notes": row.notes,
        "crop_stage": row.crop_stage,
        "duration_s": row.duration_s,
        "score": row.score,
        "status": row.status,
        "confirmation_channel": row.confirmation_channel,
        "confirmed_at": row.confirmed_at,
        "device_integrity": DeviceIntegrityOut(
            is_mock=integrity.is_mock,
            is_rooted=integrity.is_rooted,
            clock_drift_s=integrity.clock_drift_s,
        ),
        "integrity_issues": integrity_issues(row.device_integrity),
        "flags": list(row.flags or []),
        "client_visit_id": row.client_visit_id,
        "created_at": row.created_at,
        "updated_at": row.updated_at,
        "deleted_at": row.deleted_at,
        "version": row.version,
    }


__all__ = [
    "CheckinPoint",
    "ConfirmationRequest",
    "ConfirmationRequestOut",
    "ConfirmationSubmit",
    "DeviceIntegrityIn",
    "DeviceIntegrityOut",
    "FarmerConfirm",
    "OverrideDecisionIn",
    "OverrideRequestOut",
    "VisitCapture",
    "VisitCheckIn",
    "VisitCheckOut",
    "VisitConfirmationOut",
    "VisitDetailOut",
    "VisitOut",
    "VisitPage",
    "VisitPhotoCreate",
    "VisitPhotoOut",
    "integrity_issues",
]
