"""Problem codes for the auth module (RFC 9457 ``code`` values are the client contract)."""

from __future__ import annotations

from farmerapp.api.errors import AppError


class UserNotFoundError(AppError):
    status = 404
    code = "user_not_found"


class UserDisabledError(AppError):
    status = 403
    code = "user_disabled"


class OtpNotFoundError(AppError):
    status = 404
    code = "otp_not_found"


class OtpInvalidError(AppError):
    status = 401
    code = "otp_invalid"


class OtpExpiredError(AppError):
    status = 401
    code = "otp_expired"


class OtpLockedError(AppError):
    status = 423
    code = "otp_locked"
    title = "Locked"


class OtpRateLimitedError(AppError):
    status = 429
    code = "otp_rate_limited"


class RefreshInvalidError(AppError):
    status = 401
    code = "refresh_invalid"


class RefreshExpiredError(AppError):
    status = 401
    code = "refresh_expired"


class RefreshReusedError(AppError):
    status = 401
    code = "refresh_reused"


class RefreshDeviceMismatchError(AppError):
    status = 401
    code = "refresh_device_mismatch"


class TokenExpiredError(AppError):
    status = 401
    code = "token_expired"


class SessionRevokedError(AppError):
    """WC-011: an admin forced a logout (or unbound the device); sign in again."""

    status = 401
    code = "session_revoked"


class DeviceWipeRequiredError(AppError):
    """SEC-025: the account is disabled or this device was reported lost. The app must wipe
    its local data (database, files, tokens) and return to the login screen."""

    status = 401
    code = "device_wipe_required"


class DeviceNotBoundError(AppError):
    """SEC-020: a field officer is bound to another device; an admin must bind this one."""

    status = 409
    code = "device_not_bound"


class DeviceIdRequiredError(AppError):
    """SEC-020: field officers must sign in with the app's device id."""

    status = 422
    code = "device_id_required"


class StepUpRequiredError(AppError):
    """SEC-028: the action needs a fresh OTP (``POST /v1/auth/step-up``)."""

    status = 401
    code = "step_up_required"
