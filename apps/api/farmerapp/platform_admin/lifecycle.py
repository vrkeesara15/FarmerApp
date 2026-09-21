"""WC-014 tenant lifecycle: suspend, resume, archive.

    active  --suspend-->  suspended  --resume-->  active
    active / suspended  --archive-->  archived   (terminal)

What each means, precisely:

**suspend** — the tenant stops working, its data stays. Every live session is revoked in the
    same transaction (one bulk ``UPDATE`` per table, not a loop over users: a tenant at the
    NF-007 target has 100 officers and a suspension must not load them into memory) and
    ``tenant.status`` blocks new logins and new requests. Reversible.

**resume** — back to ``active``. Sessions are *not* restored: everyone logs in again, which is
    the honest outcome of having revoked them.

**archive** — terminal. Access is gone for good; the rows stay, because NF-012 retention and
    the eight-year financial floor outlive the commercial relationship (docs/retention.md).
    Deleting a tenant's data is a separate, human-gated act and is deliberately not an API.

Both ``tenant.status`` (read on every request through the cached tenant state) and
``platform_tenant.status`` (the registry the platform console lists) are written in the same
transaction, so the two can never disagree; ``tests/platform/test_lifecycle.py`` asserts it.

Enforcement lives in ``farmerapp.auth.deps`` (a bearer token of a blocked tenant is refused)
and ``farmerapp.auth.otp`` (a blocked tenant sends no login code). A suspension reaches other
API instances within the tenant-state TTL (<= 60 s); the instance that made the change drops
its own cache entry at once.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import RefreshToken, RevokeReason, User
from farmerapp.db import audit
from farmerapp.db.models.tenant import Tenant
from farmerapp.db.session import tenant_scope
from farmerapp.logging import get_logger
from farmerapp.platform_admin.errors import InvalidTenantStateError
from farmerapp.platform_admin.models import PLATFORM_TENANT_ID, PlatformTenant, TenantStatus
from farmerapp.platform_admin.state import invalidate

log = get_logger("farmerapp.platform_admin.lifecycle")

#: status -> statuses reachable from it.
TRANSITIONS: dict[str, frozenset[str]] = {
    TenantStatus.ACTIVE: frozenset({TenantStatus.SUSPENDED, TenantStatus.ARCHIVED}),
    TenantStatus.SUSPENDED: frozenset({TenantStatus.ACTIVE, TenantStatus.ARCHIVED}),
    TenantStatus.ARCHIVED: frozenset(),
}


async def _registry(session: AsyncSession, tenant_id: uuid.UUID) -> PlatformTenant | None:
    return (
        await session.execute(
            select(PlatformTenant).where(
                PlatformTenant.tenant_id == PLATFORM_TENANT_ID,
                PlatformTenant.subject_tenant_id == tenant_id,
                PlatformTenant.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()


async def revoke_tenant_sessions(
    session: AsyncSession, tenant_id: uuid.UUID, *, now: datetime, reason: RevokeReason
) -> int:
    """Kill every session of the tenant with two bulk statements (no per-user loop)."""
    await session.execute(
        update(User)
        .where(User.tenant_id == tenant_id)
        .values(tokens_valid_after=now)
        .execution_options(synchronize_session=False)
    )
    result = await session.execute(
        update(RefreshToken)
        .where(RefreshToken.tenant_id == tenant_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now, revoked_reason=reason.value)
        .execution_options(synchronize_session=False)
    )
    return int(getattr(result, "rowcount", 0) or 0)


async def set_status(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    target: TenantStatus,
    *,
    actor_id: uuid.UUID | None = None,
    reason: str | None = None,
    now: datetime | None = None,
) -> PlatformTenant:
    """Move a tenant to ``target``, revoking sessions when access is withdrawn.

    The caller's session must be bound to the platform tenant (a ``platform_admin`` request or
    the ``tenant-lifecycle`` job).
    """
    moment = now or datetime.now(UTC)
    registry = await _registry(session, tenant_id)
    if registry is None:
        raise InvalidTenantStateError(f"Tenant {tenant_id} is not in the platform registry.")
    if registry.status == target:
        return registry
    if target not in TRANSITIONS[TenantStatus(registry.status)]:
        raise InvalidTenantStateError(f"A {registry.status} tenant cannot become {target}.")

    revoked = 0
    async with tenant_scope(session, tenant_id):
        tenant = await session.get(Tenant, tenant_id)
        if tenant is None:  # pragma: no cover - registry without a tenant row
            raise InvalidTenantStateError(f"Tenant {tenant_id} no longer exists.")
        tenant.status = target
        if target in (TenantStatus.SUSPENDED, TenantStatus.ARCHIVED):
            revoked = await revoke_tenant_sessions(
                session,
                tenant_id,
                now=moment,
                reason=RevokeReason.USER_DISABLED,
            )
        await session.flush()

    registry.status = target
    registry.suspended_at = moment if target == TenantStatus.SUSPENDED else None
    if target == TenantStatus.ARCHIVED:
        registry.archived_at = moment
    await session.flush()
    invalidate(tenant_id)
    audit.record(
        session,
        action=f"tenant.{target}",
        entity="tenant",
        entity_id=tenant_id,
        tenant_id=PLATFORM_TENANT_ID,
        after={
            "subject_tenant_id": str(tenant_id),
            "slug": registry.slug,
            "status": str(target),
            "sessions_revoked": revoked,
            "reason": reason,
            "actor_id": str(actor_id) if actor_id else None,
        },
    )
    await session.flush()  # the audit row belongs to the platform tenant, bound right now
    log.info(
        "tenant_status_changed",
        tenant_id=str(tenant_id),
        slug=registry.slug,
        status=str(target),
        sessions_revoked=revoked,
    )
    return registry


__all__ = ["TRANSITIONS", "revoke_tenant_sessions", "set_status"]
