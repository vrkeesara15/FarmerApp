"""VV-004 visit score (geofence 30, confirmation 30, in-app photo with matching EXIF 20,
duration 10, device integrity 10) and VV-005 status (verified >= 70, partial 40-69,
unverified < 40) on fixtures, including the boundary values 70 and 40."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from farmerapp.db.geo import haversine_m, offset
from farmerapp.visits.models import GeofenceResult, VisitStatus
from farmerapp.visits.scoring import (
    CONFIRMATION_POINTS,
    DURATION_POINTS,
    GEOFENCE_POINTS,
    INTEGRITY_POINTS,
    MAX_CLOCK_DRIFT_S,
    OVERRIDE_POINTS,
    PARTIAL_MIN,
    PHOTO_POINTS,
    VERIFIED_MIN,
    DeviceIntegrity,
    PhotoEvidence,
    ScoreResult,
    score_visit,
    status_for,
)

T0 = datetime(2026, 9, 18, 5, 0, tzinfo=UTC)  # 10:30 IST
LON, LAT = 79.55, 18.02
CLEAN = DeviceIntegrity(is_mock=False, is_rooted=False, clock_drift_s=12)


def photo(
    *,
    minutes: float = 5,
    metres: float = 10,
    in_app: bool = True,
    exif_time: bool = True,
    exif_point: bool = True,
) -> PhotoEvidence:
    lon, lat = offset(LON, LAT, metres, 0)
    return PhotoEvidence(
        taken_in_app=in_app,
        exif_time=T0 + timedelta(minutes=minutes) if exif_time else None,
        exif_lat=lat if exif_point else None,
        exif_lon=lon if exif_point else None,
    )


def score(**overrides: object) -> ScoreResult:
    kwargs: dict[str, object] = {
        "geofence_result": GeofenceResult.INSIDE,
        "confirmed": True,
        "photos": [photo()],
        "checkin_at": T0,
        "checkout_at": T0 + timedelta(minutes=20),
        "checkin_lat": LAT,
        "checkin_lon": LON,
        "min_duration_s": 300,
        "integrity": CLEAN,
    }
    kwargs.update(overrides)
    return score_visit(**kwargs)  # type: ignore[arg-type]


def test_weights_add_up_to_100() -> None:
    assert (
        GEOFENCE_POINTS + CONFIRMATION_POINTS + PHOTO_POINTS + DURATION_POINTS + INTEGRITY_POINTS
        == 100
    )
    assert (GEOFENCE_POINTS, CONFIRMATION_POINTS, PHOTO_POINTS) == (30, 30, 20)
    assert (DURATION_POINTS, INTEGRITY_POINTS) == (10, 10)
    assert (VERIFIED_MIN, PARTIAL_MIN) == (70, 40)
    assert 0 < OVERRIDE_POINTS < GEOFENCE_POINTS


def test_perfect_visit_scores_100_and_is_verified() -> None:
    result = score()
    assert result.score == 100
    assert result.status == VisitStatus.VERIFIED
    assert result.components == {
        "geofence": 30,
        "confirmation": 30,
        "photo": 20,
        "duration": 10,
        "integrity": 10,
    }
    assert sum(result.components.values()) == result.score


def test_nothing_scores_zero_and_is_unverified() -> None:
    result = score(
        geofence_result=GeofenceResult.OUTSIDE,
        confirmed=False,
        photos=[],
        checkout_at=None,
        integrity=DeviceIntegrity(is_mock=True, is_rooted=True, clock_drift_s=0),
    )
    assert result.score == 0 and result.status == VisitStatus.UNVERIFIED
    assert set(result.components.values()) == {0}


@pytest.mark.parametrize(
    ("geofence", "points"),
    [
        (GeofenceResult.INSIDE, GEOFENCE_POINTS),
        (GeofenceResult.MEETING_POINT, GEOFENCE_POINTS),
        (GeofenceResult.OVERRIDE, OVERRIDE_POINTS),
        (GeofenceResult.OUTSIDE, 0),
    ],
)
def test_geofence_component(geofence: GeofenceResult, points: int) -> None:
    assert score(geofence_result=geofence).components["geofence"] == points


def test_confirmation_component() -> None:
    assert score(confirmed=False).components["confirmation"] == 0
    assert score(confirmed=True).components["confirmation"] == CONFIRMATION_POINTS


@pytest.mark.parametrize(
    ("photos", "points"),
    [
        ([photo()], PHOTO_POINTS),
        ([photo(minutes=19, metres=140)], PHOTO_POINTS),  # inside the window and the radius
        ([photo(metres=400)], 0),  # EXIF GPS too far from the check-in point (VA-E08)
        ([photo(minutes=90)], 0),  # EXIF time outside the visit window
        ([photo(minutes=-15)], 0),  # before check-in beyond the tolerance
        ([photo(in_app=False)], 0),  # gallery photo (FA-015)
        ([photo(exif_time=False)], 0),
        ([photo(exif_point=False)], 0),
        ([photo(metres=400), photo(in_app=False), photo()], PHOTO_POINTS),  # one good is enough
        ([], 0),
    ],
)
def test_photo_component(photos: list[PhotoEvidence], points: int) -> None:
    assert score(photos=photos).components["photo"] == points


def test_photo_window_is_tolerant_around_checkin_and_checkout() -> None:
    # Up to 10 min before check-in and after check-out counts (clock skew, retakes).
    assert score(photos=[photo(minutes=-9)]).components["photo"] == PHOTO_POINTS
    assert score(photos=[photo(minutes=29)]).components["photo"] == PHOTO_POINTS
    assert score(photos=[photo(minutes=31)]).components["photo"] == 0
    # No check-out yet: the window is check-in plus the tolerance only.
    assert score(checkout_at=None, photos=[photo(minutes=5)]).components["photo"] == PHOTO_POINTS
    assert score(checkout_at=None, photos=[photo(minutes=25)]).components["photo"] == 0


@pytest.mark.parametrize(
    ("minutes", "points"),
    [(20, DURATION_POINTS), (5, DURATION_POINTS), (4.98, 0), (0, 0)],
)
def test_duration_component(minutes: float, points: int) -> None:
    result = score(checkout_at=T0 + timedelta(minutes=minutes))
    assert result.components["duration"] == points


def test_duration_needs_a_checkout() -> None:
    assert score(checkout_at=None).components["duration"] == 0


@pytest.mark.parametrize(
    ("integrity", "points"),
    [
        (CLEAN, INTEGRITY_POINTS),
        (DeviceIntegrity(is_mock=True, is_rooted=False, clock_drift_s=0), 0),
        (DeviceIntegrity(is_mock=False, is_rooted=True, clock_drift_s=0), 0),
        (DeviceIntegrity(is_mock=False, is_rooted=False, clock_drift_s=MAX_CLOCK_DRIFT_S), 10),
        (DeviceIntegrity(is_mock=False, is_rooted=False, clock_drift_s=-MAX_CLOCK_DRIFT_S), 10),
        (DeviceIntegrity(is_mock=False, is_rooted=False, clock_drift_s=MAX_CLOCK_DRIFT_S + 1), 0),
    ],
)
def test_integrity_component(integrity: DeviceIntegrity, points: int) -> None:
    assert MAX_CLOCK_DRIFT_S == 300  # VA-E01: clock drift > 5 min
    assert score(integrity=integrity).components["integrity"] == points


def test_integrity_from_dict_tolerates_missing_keys() -> None:
    assert DeviceIntegrity.from_dict({}) == CLEAN.__class__(
        is_mock=False, is_rooted=False, clock_drift_s=0
    )
    assert DeviceIntegrity.from_dict({"is_mock": True, "clock_drift_s": "400"}) == DeviceIntegrity(
        is_mock=True, is_rooted=False, clock_drift_s=400
    )
    assert DeviceIntegrity.from_dict(None).is_mock is False


# ------------------------------------------------------------------ VV-005 boundaries
def test_exactly_70_is_verified() -> None:
    # geofence 30 + confirmation 30 + duration 10, no photo, tampered device -> 70
    result = score(photos=[], integrity=DeviceIntegrity(True, False, 0))
    assert result.score == 70 == VERIFIED_MIN
    assert result.status == VisitStatus.VERIFIED


def test_69_is_partial() -> None:
    # 70 minus... cannot be built from the weights; take the closest: outside + everything = 70,
    # so drop integrity too: outside(0) + 30 + 20 + 10 + 0 = 60 -> partial. And 65 via override.
    result = score(geofence_result=GeofenceResult.OVERRIDE, photos=[], checkout_at=None)
    assert result.score == OVERRIDE_POINTS + CONFIRMATION_POINTS + INTEGRITY_POINTS == 55
    assert result.status == VisitStatus.PARTIAL
    assert status_for(69) == VisitStatus.PARTIAL


def test_exactly_40_is_partial() -> None:
    # geofence 30 + duration 10 -> 40
    result = score(confirmed=False, photos=[], integrity=DeviceIntegrity(True, False, 0))
    assert result.score == 40 == PARTIAL_MIN
    assert result.status == VisitStatus.PARTIAL


def test_39_and_below_is_unverified() -> None:
    assert status_for(39) == VisitStatus.UNVERIFIED
    # photo 20 + duration 10 + integrity 10 = 40 is partial; without integrity 30 is unverified.
    result = score(
        geofence_result=GeofenceResult.OUTSIDE,
        confirmed=False,
        integrity=DeviceIntegrity(False, True, 0),
    )
    assert result.score == 30 and result.status == VisitStatus.UNVERIFIED


@pytest.mark.parametrize(
    ("value", "status"),
    [
        (100, VisitStatus.VERIFIED),
        (70, VisitStatus.VERIFIED),
        (69, VisitStatus.PARTIAL),
        (40, VisitStatus.PARTIAL),
        (39, VisitStatus.UNVERIFIED),
        (0, VisitStatus.UNVERIFIED),
    ],
)
def test_status_for(value: int, status: VisitStatus) -> None:
    assert status_for(value) == status


def test_status_for_rejects_out_of_range() -> None:
    with pytest.raises(ValueError):
        status_for(101)
    with pytest.raises(ValueError):
        status_for(-1)


def test_result_is_json_ready() -> None:
    result = score()
    payload = result.as_payload()
    assert payload == {"score": 100, "status": "verified", "components": result.components}


def test_haversine_matches_offset_helper() -> None:
    lon, lat = offset(LON, LAT, 300, 400)
    assert abs(haversine_m(LAT, LON, lat, lon) - 500) < 2
    assert haversine_m(LAT, LON, LAT, LON) == 0
