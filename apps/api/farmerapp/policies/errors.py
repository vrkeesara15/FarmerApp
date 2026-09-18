"""Problem codes of the policy acceptance and duty write paths (FA-011, VV-010)."""

from __future__ import annotations

from farmerapp.api.errors import AppError


class PolicyVersionStaleError(AppError):
    """The version / text hash sent is not the tenant's current policy: fetch it again."""

    status = 422
    code = "policy_version_stale"


class PolicyNotAcceptedError(AppError):
    """Duty cannot start until the current ``location_policy_version`` is accepted."""

    status = 422
    code = "policy_not_accepted"
