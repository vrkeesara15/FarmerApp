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
