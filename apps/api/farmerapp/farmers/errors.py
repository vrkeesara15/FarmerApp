"""Problem codes of the farmer write endpoints (FA-012, VA-F01, VA-F03)."""

from __future__ import annotations

from farmerapp.api.errors import AppError


class FarmerPhoneExistsError(AppError):
    status = 409
    code = "farmer_phone_exists"


class FarmerPhoneIsStaffError(AppError):
    status = 422
    code = "farmer_phone_is_staff"


class FarmBoundaryInvalidError(AppError):
    status = 422
    code = "farm_boundary_invalid"


class PhoneVerificationInvalidError(AppError):
    status = 422
    code = "phone_verification_invalid"


class VersionConflictError(AppError):
    status = 409
    code = "version_conflict"


class UnsupportedActionError(AppError):
    status = 422
    code = "unsupported_action"
