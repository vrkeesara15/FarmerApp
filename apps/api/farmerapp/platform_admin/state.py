"""Per-process cache of the two tenant facts every request needs (WC-014).

``status`` (may this tenant's users work at all?) and the effective plan limits (may one more
farmer be registered?) are read on hot paths. Reading the ``tenant`` row on every request
would add a round trip to every call in the system, so both are cached per process with the
same TTL the device-status cache uses (``SECURITY_CACHE_TTL_SECONDS``, validated <= 60 s), and
invalidated in-process the moment a platform admin changes them.

Consequence, stated plainly: a suspension or a plan change reaches every Cloud Run instance
within the TTL, not instantly — the same contract as WC-011 revocation (SEC-025, "within
5 min"). A tenant that is *already* suspended is rejected at login too, so a new session can
never be opened for one.

The cache is keyed by tenant id and holds no personal data.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.models.tenant import Tenant
from farmerapp.platform_admin.models import BLOCKED_STATUSES, TenantStatus
from farmerapp.platform_admin.plans import DEFAULT_PLAN, PLANS, PlanLimits, merge_limits
from farmerapp.settings import get_settings


@dataclass(frozen=True)
class TenantState:
    tenant_id: uuid.UUID
    status: str
    plan: str
    limits: PlanLimits

    @property
    def blocked(self) -> bool:
        return self.status in BLOCKED_STATUSES


_CACHE: dict[uuid.UUID, tuple[float, TenantState]] = {}


def _ttl_seconds() -> float:
    return float(get_settings().security_cache_ttl_seconds)


def invalidate(tenant_id: uuid.UUID | None = None) -> None:
    """Drop one tenant (or everything) from this process's cache."""
    if tenant_id is None:
        _CACHE.clear()
    else:
        _CACHE.pop(tenant_id, None)


def state_of(tenant: Tenant) -> TenantState:
    """The state a loaded ``tenant`` row implies (no cache, no query)."""
    plan_name = tenant.plan if tenant.plan in PLANS else DEFAULT_PLAN
    limits = merge_limits(PLANS[plan_name].limits, tenant.plan_limits)
    return TenantState(
        tenant_id=tenant.id,
        status=tenant.status or TenantStatus.ACTIVE,
        plan=plan_name,
        limits=limits,
    )


def remember(state: TenantState) -> None:
    _CACHE[state.tenant_id] = (time.monotonic() + _ttl_seconds(), state)


async def get_tenant_state(session: AsyncSession, tenant_id: uuid.UUID) -> TenantState:
    """Cached status + effective plan limits of ``tenant_id``.

    The session must already be bound to ``tenant_id`` (RLS); an unknown or invisible tenant
    is reported as active on the default plan so a missing row never locks a tenant out of its
    own data — isolation is RLS's job, not this cache's.
    """
    cached = _CACHE.get(tenant_id)
    now = time.monotonic()
    if cached is not None and cached[0] > now:
        return cached[1]
    tenant = (
        await session.execute(select(Tenant).where(Tenant.id == tenant_id))
    ).scalar_one_or_none()
    state = (
        state_of(tenant)
        if tenant is not None
        else TenantState(
            tenant_id=tenant_id,
            status=TenantStatus.ACTIVE,
            plan=DEFAULT_PLAN,
            limits=PLANS[DEFAULT_PLAN].limits,
        )
    )
    remember(state)
    return state


__all__ = ["TenantState", "get_tenant_state", "invalidate", "remember", "state_of"]
