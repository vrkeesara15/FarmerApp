"""Location policy: serve the current text, record acceptances, check them (FA-011, VV-010).

Shared by the REST endpoints and the ``policy_acceptance`` sync op, so the rule is in one
place: an acceptance is valid only for the tenant's *current* ``location_policy_version``
with the matching ``text_hash`` (``policy_version_stale`` otherwise), and duty may start
only when the officer has an acceptance of exactly that version (``policy_not_accepted``).
Changing the tenant setting therefore invalidates every earlier acceptance.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.location.models import LOCATION_POLICY_KEY, PolicyAcceptance
from farmerapp.location.schemas import PolicyAcceptanceOut
from farmerapp.logging import get_logger
from farmerapp.policies.errors import PolicyNotAcceptedError, PolicyVersionStaleError
from farmerapp.policies.location_policy import LocationPolicy, policy_for
from farmerapp.policies.schemas import PolicyAcceptIn
from farmerapp.tenants.settings import TenantSettings, get_tenant_settings

log = get_logger("farmerapp.policies")


async def settings_for(session: AsyncSession, tenant_id: uuid.UUID) -> TenantSettings:
    """The typed settings of the bound tenant (a missing row means the defaults)."""
    return await get_tenant_settings(session, tenant_id)


async def current_policy(session: AsyncSession, tenant_id: uuid.UUID) -> LocationPolicy:
    settings = await settings_for(session, tenant_id)
    return policy_for(settings.location_policy_version)


async def latest_acceptance(session: AsyncSession, user: User) -> PolicyAcceptance | None:
    stmt = (
        select(PolicyAcceptance)
        .where(
            PolicyAcceptance.tenant_id == user.tenant_id,
            PolicyAcceptance.user_id == user.id,
            PolicyAcceptance.policy_key == LOCATION_POLICY_KEY,
        )
        .order_by(PolicyAcceptance.accepted_at.desc(), PolicyAcceptance.created_at.desc())
        .limit(1)
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def has_accepted(session: AsyncSession, user: User, version: str) -> bool:
    """Whether the user has an acceptance of exactly ``version`` (rows are append-only, so a
    bumped tenant version simply has none until the user accepts it again)."""
    stmt = (
        select(PolicyAcceptance.id)
        .where(
            PolicyAcceptance.tenant_id == user.tenant_id,
            PolicyAcceptance.user_id == user.id,
            PolicyAcceptance.policy_key == LOCATION_POLICY_KEY,
            PolicyAcceptance.version == version,
        )
        .limit(1)
    )
    return (await session.execute(stmt)).first() is not None


async def require_accepted(session: AsyncSession, user: User, version: str) -> None:
    """Raise ``policy_not_accepted`` unless the user's latest acceptance names ``version``."""
    if not await has_accepted(session, user, version):
        raise PolicyNotAcceptedError(
            f"Location policy {version} must be accepted before duty can start.",
            extra={"required_version": version},
        )


async def accept_policy(
    session: AsyncSession, user: User, body: PolicyAcceptIn, *, now: datetime
) -> PolicyAcceptanceOut:
    """Store an acceptance of the tenant's current policy (append-only row)."""
    policy = await current_policy(session, user.tenant_id)
    if body.version != policy.version or body.text_hash != policy.text_hash:
        raise PolicyVersionStaleError(
            "The policy shown is not the current version; fetch it again.",
            extra={"current_version": policy.version},
        )
    accepted_at = body.accepted_at or now
    if accepted_at > now:
        accepted_at = now  # a device clock ahead of the server never back-dates nothing
    row = PolicyAcceptance(
        id=body.id or uuid.uuid4(),
        tenant_id=user.tenant_id,
        user_id=user.id,
        policy_key=LOCATION_POLICY_KEY,
        version=body.version,
        accepted_at=accepted_at,
        device_id=body.device_id,
        app_version=body.app_version,
        text_hash=body.text_hash,
    )
    session.add(row)
    await session.flush()
    await session.refresh(row)
    log.info(
        "location_policy_accepted",
        actor_id=str(user.id),
        version=body.version,
        device_id=body.device_id,
    )
    return PolicyAcceptanceOut.from_row(row)


__all__ = [
    "accept_policy",
    "current_policy",
    "has_accepted",
    "latest_acceptance",
    "require_accepted",
    "settings_for",
]
