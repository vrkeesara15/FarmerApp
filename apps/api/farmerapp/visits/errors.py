"""Problem codes of the visit write endpoints (FA-014 .. FA-017)."""

from __future__ import annotations

from farmerapp.api.errors import AppError


class OutsideGeofenceError(AppError):
    """FA-014: the check-in point is outside every allowed target and no override note came.

    ``extra`` carries ``distance_m`` (to the nearest target), ``target`` (``farm`` /
    ``meeting_point`` / null) and ``radius_m`` so the app can show the reason.
    """

    status = 422
    code = "outside_geofence"


class GalleryNotAllowedError(AppError):
    """FA-015: only photos taken in-app are accepted as visit evidence."""

    status = 422
    code = "gallery_not_allowed"


class PhotoShaMismatchError(AppError):
    status = 422
    code = "photo_sha_mismatch"


class ConfirmationChannelInvalidError(AppError):
    """FA-016: the channel cannot be used this way (e.g. OTP without a code, QR from the
    officer's side, push to a farmer without the app)."""

    status = 422
    code = "confirmation_channel_invalid"


class ConfirmationTokenInvalidError(AppError):
    status = 422
    code = "confirmation_token_invalid"


class ConfirmationNotRequestedError(AppError):
    status = 404
    code = "confirmation_not_requested"


class VisitAlreadyConfirmedError(AppError):
    status = 409
    code = "visit_already_confirmed"


class VisitAlreadyCheckedOutError(AppError):
    status = 409
    code = "visit_already_checked_out"


class OverrideNotPendingError(AppError):
    """No pending override request on the visit (none asked, or already decided)."""

    status = 409
    code = "override_not_pending"


__all__ = [
    "ConfirmationChannelInvalidError",
    "ConfirmationNotRequestedError",
    "ConfirmationTokenInvalidError",
    "GalleryNotAllowedError",
    "OutsideGeofenceError",
    "OverrideNotPendingError",
    "PhotoShaMismatchError",
    "VisitAlreadyCheckedOutError",
    "VisitAlreadyConfirmedError",
]
