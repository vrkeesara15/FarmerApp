"""Problem codes of the flag API (WC-010)."""

from __future__ import annotations

from farmerapp.api.errors import AppError, ConflictError


class InvalidTransitionError(ConflictError):
    """The SPEC 6.1 state machine does not allow this move (or the flag is resolved)."""

    code = "invalid_transition"


class FlagClosedError(ConflictError):
    """Comments and assignments need an unresolved flag."""

    code = "flag_resolved"


class AssigneeInvalidError(AppError):
    status = 422
    code = "assignee_invalid"


__all__ = ["AssigneeInvalidError", "FlagClosedError", "InvalidTransitionError"]
