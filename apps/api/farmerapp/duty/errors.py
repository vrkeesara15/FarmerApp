"""Problem codes of the duty write path (FA-010)."""

from __future__ import annotations

from farmerapp.api.errors import AppError


class DutyAlreadyActiveError(AppError):
    """Another session of the officer is open (and younger than 24 h)."""

    status = 409
    code = "duty_already_active"


class NoActiveDutyError(AppError):
    """Nothing to end: the officer has no open session."""

    status = 409
    code = "no_active_duty"
