"""WC-014 problem types (SPEC 8.3 RFC 9457 with a stable ``code``)."""

from __future__ import annotations

from farmerapp.api.errors import AppError, ConflictError


class PlanLimitExceededError(AppError):
    """The tenant's plan does not allow one more of something.

    409 rather than 402/403: nothing is wrong with the caller or their credentials, the
    resource simply cannot be created in this state. The problem always carries ``metric``,
    ``limit``, ``current`` and ``plan`` so the console can say "4,999 of 5,000 farmers used"
    without a second request.
    """

    status = 409
    code = "plan_limit_exceeded"

    def __init__(self, *, metric: str, limit: int, current: int, plan: str) -> None:
        super().__init__(
            f"The {plan} plan allows {limit} {metric.replace('_', ' ')}; {current} are in use.",
            extra={"metric": metric, "limit": limit, "current": current, "plan": plan},
        )
        self.metric = metric
        self.limit = limit
        self.current = current
        self.plan = plan


class TenantSuspendedError(AppError):
    """The caller's tenant is suspended or archived (WC-014 lifecycle)."""

    status = 403
    code = "tenant_suspended"


class TenantSlugTakenError(ConflictError):
    code = "tenant_slug_taken"


class InvalidTenantStateError(AppError):
    """The lifecycle transition asked for is not allowed from the current status."""

    status = 409
    code = "invalid_tenant_state"


class UnknownPlanProblemError(AppError):
    status = 422
    code = "unknown_plan"


__all__ = [
    "InvalidTenantStateError",
    "PlanLimitExceededError",
    "TenantSlugTakenError",
    "TenantSuspendedError",
    "UnknownPlanProblemError",
]
