"""FM-013 problem codes (RFC 9457, SPEC 8.3)."""

from __future__ import annotations

from farmerapp.api.errors import AppError


class ReferralCodeUnknownError(AppError):
    status = 422
    code = "referral_code_unknown"


class ReferralSelfError(AppError):
    """A farmer may not refer themself (FM-013 duplicate / self-referral prevention)."""

    status = 422
    code = "referral_self"


class ReferralAlreadyAttributedError(AppError):
    """This farmer was already credited to a referrer; a referral is attributed once."""

    status = 409
    code = "referral_already_attributed"


class ReferralWindowClosedError(AppError):
    """The claim window (``tenant.settings.referral.claim_window_days``) has passed."""

    status = 422
    code = "referral_window_closed"


class ReferralDisabledError(AppError):
    status = 422
    code = "referral_disabled"


class ReferralNotAttributedError(AppError):
    """Only an attributed referral can be rewarded."""

    status = 409
    code = "referral_not_attributed"


__all__ = [
    "ReferralAlreadyAttributedError",
    "ReferralCodeUnknownError",
    "ReferralDisabledError",
    "ReferralNotAttributedError",
    "ReferralSelfError",
    "ReferralWindowClosedError",
]
