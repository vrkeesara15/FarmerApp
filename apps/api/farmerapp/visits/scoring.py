"""VV-004 visit score and VV-005 status.

Score 0-100 = geofence (30) + farmer confirmation (30) + in-app photo with matching EXIF time
and GPS (20) + duration >= minimum (10) + device integrity (10). Status: ``verified`` >= 70,
``partial`` 40-69, ``unverified`` < 40; only verified visits count toward incentives by
default. The components are stored on the visit (``score_components``) and shown in the
console (WC-004).

Pure functions: the write path (FA-017 check-out, FA-016 confirmation) calls
``score_visit_row`` and stores the result; the seed uses the same function so demo data
and production agree. Geometry is haversine here (no database round trip) — the geofence
decision itself (``geofence_result``) was taken by PostGIS at check-in (FA-014).

Assumptions recorded here (not in the SPEC text):

* An approved override (``geofence_result = override``) earns ``OVERRIDE_POINTS`` (15) of
  the geofence 30: the visit happened, but not where the polygon says.
* A photo matches when it was taken in-app, its EXIF time falls within the visit window
  (check-in .. check-out, each widened by ``PHOTO_TIME_TOLERANCE_S``; check-in plus the
  tolerance while the visit is open) and its EXIF GPS is within ``PHOTO_DISTANCE_M`` of the
  check-in point. One matching photo is enough.
* Integrity fails on a mock location, a rooted device or a clock drift over
  ``MAX_CLOCK_DRIFT_S`` (VA-E01: 5 minutes).
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import TYPE_CHECKING, Any

from farmerapp.db.geo import haversine_m
from farmerapp.visits.models import GeofenceResult, VisitStatus

if TYPE_CHECKING:
    from farmerapp.visits.models import Visit, VisitPhoto

GEOFENCE_POINTS = 30
CONFIRMATION_POINTS = 30
PHOTO_POINTS = 20
DURATION_POINTS = 10
INTEGRITY_POINTS = 10
OVERRIDE_POINTS = 15  # of the geofence 30 (assumption, see module docstring)

VERIFIED_MIN = 70
PARTIAL_MIN = 40

MAX_CLOCK_DRIFT_S = 300  # VA-E01
PHOTO_TIME_TOLERANCE_S = 600
PHOTO_DISTANCE_M = 150.0

COMPONENTS = ("geofence", "confirmation", "photo", "duration", "integrity")


@dataclass(frozen=True)
class DeviceIntegrity:
    """FA-028 flags reported by the app at check-in (``visit.device_integrity``)."""

    is_mock: bool = False
    is_rooted: bool = False
    clock_drift_s: int = 0

    @classmethod
    def from_dict(cls, raw: Mapping[str, Any] | None) -> DeviceIntegrity:
        raw = raw or {}
        return cls(
            is_mock=bool(raw.get("is_mock", False)),
            is_rooted=bool(raw.get("is_rooted", False)),
            clock_drift_s=int(raw.get("clock_drift_s", 0) or 0),
        )

    @property
    def ok(self) -> bool:
        return (
            not self.is_mock and not self.is_rooted and abs(self.clock_drift_s) <= MAX_CLOCK_DRIFT_S
        )


@dataclass(frozen=True)
class PhotoEvidence:
    """What the scorer needs of a ``visit_photo``."""

    taken_in_app: bool
    exif_time: datetime | None
    exif_lat: float | None
    exif_lon: float | None

    @classmethod
    def from_row(cls, photo: VisitPhoto) -> PhotoEvidence:
        return cls(
            taken_in_app=photo.taken_in_app,
            exif_time=photo.exif_time,
            exif_lat=photo.exif_lat,
            exif_lon=photo.exif_lon,
        )


@dataclass(frozen=True)
class ScoreResult:
    score: int
    status: VisitStatus
    components: dict[str, int]

    def as_payload(self) -> dict[str, Any]:
        return {"score": self.score, "status": self.status.value, "components": self.components}


def status_for(score: int) -> VisitStatus:
    """VV-005 thresholds: verified >= 70, partial 40-69, unverified < 40."""
    if not 0 <= score <= 100:
        raise ValueError(f"score must be within 0..100, got {score}")
    if score >= VERIFIED_MIN:
        return VisitStatus.VERIFIED
    if score >= PARTIAL_MIN:
        return VisitStatus.PARTIAL
    return VisitStatus.UNVERIFIED


def _geofence_points(result: GeofenceResult | str) -> int:
    match GeofenceResult(result):
        case GeofenceResult.INSIDE | GeofenceResult.MEETING_POINT:
            return GEOFENCE_POINTS
        case GeofenceResult.OVERRIDE:
            return OVERRIDE_POINTS
        case GeofenceResult.OUTSIDE:
            return 0


def photo_matches(
    photo: PhotoEvidence,
    *,
    checkin_at: datetime,
    checkout_at: datetime | None,
    checkin_lat: float,
    checkin_lon: float,
    time_tolerance_s: int = PHOTO_TIME_TOLERANCE_S,
    distance_m: float = PHOTO_DISTANCE_M,
) -> bool:
    """FA-015 / VA-E08: in-app, EXIF time inside the (widened) visit window, EXIF GPS near."""
    if not photo.taken_in_app or photo.exif_time is None:
        return False
    if photo.exif_lat is None or photo.exif_lon is None:
        return False
    tolerance = timedelta(seconds=time_tolerance_s)
    window_end = (checkout_at or checkin_at) + tolerance
    if not (checkin_at - tolerance <= photo.exif_time <= window_end):
        return False
    return haversine_m(checkin_lat, checkin_lon, photo.exif_lat, photo.exif_lon) <= distance_m


def score_visit(
    *,
    geofence_result: GeofenceResult | str,
    confirmed: bool,
    photos: Sequence[PhotoEvidence],
    checkin_at: datetime,
    checkout_at: datetime | None,
    checkin_lat: float,
    checkin_lon: float,
    min_duration_s: int,
    integrity: DeviceIntegrity,
) -> ScoreResult:
    """VV-004 components and the VV-005 status for one visit."""
    duration_ok = (
        checkout_at is not None and (checkout_at - checkin_at).total_seconds() >= min_duration_s
    )
    components = {
        "geofence": _geofence_points(geofence_result),
        "confirmation": CONFIRMATION_POINTS if confirmed else 0,
        "photo": PHOTO_POINTS
        if any(
            photo_matches(
                p,
                checkin_at=checkin_at,
                checkout_at=checkout_at,
                checkin_lat=checkin_lat,
                checkin_lon=checkin_lon,
            )
            for p in photos
        )
        else 0,
        "duration": DURATION_POINTS if duration_ok else 0,
        "integrity": INTEGRITY_POINTS if integrity.ok else 0,
    }
    score = sum(components.values())
    return ScoreResult(score=score, status=status_for(score), components=components)


def score_visit_row(
    visit: Visit, photos: Sequence[VisitPhoto], *, min_duration_s: int
) -> ScoreResult:
    """``score_visit`` over ORM rows (the loaded ``checkin_lat`` / ``checkin_lon`` properties)."""
    return score_visit(
        geofence_result=visit.geofence_result,
        confirmed=visit.confirmed_at is not None,
        photos=[PhotoEvidence.from_row(p) for p in photos],
        checkin_at=visit.checkin_at,
        checkout_at=visit.checkout_at,
        checkin_lat=visit.checkin_lat,
        checkin_lon=visit.checkin_lon,
        min_duration_s=min_duration_s,
        integrity=DeviceIntegrity.from_dict(visit.device_integrity),
    )


__all__ = [
    "COMPONENTS",
    "CONFIRMATION_POINTS",
    "DURATION_POINTS",
    "GEOFENCE_POINTS",
    "INTEGRITY_POINTS",
    "MAX_CLOCK_DRIFT_S",
    "OVERRIDE_POINTS",
    "PARTIAL_MIN",
    "PHOTO_DISTANCE_M",
    "PHOTO_POINTS",
    "PHOTO_TIME_TOLERANCE_S",
    "VERIFIED_MIN",
    "DeviceIntegrity",
    "PhotoEvidence",
    "ScoreResult",
    "photo_matches",
    "score_visit",
    "score_visit_row",
    "status_for",
]
