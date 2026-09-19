"""Who owns a flag (VA-003).

* The subject is resolved to its **scope**: an employee's cluster and store (``user``), a
  farmer's village store and that store's cluster, a visit's officer (then as an employee),
  a store and its cluster.
* The owner follows the rule's ``owner_role`` hint: ``cluster_head`` -> the active cluster
  head of the scope cluster (employee flags), ``store_manager`` -> the active store manager
  of the scope store (farmer-data flags), ``auditor`` -> an active auditor. When nobody holds
  that role the owner falls back up the escalation ladder (cluster head -> auditor -> owner).
* High severity also goes to every active auditor (``watchers``; the owner is never listed
  twice).

The same ladder serves OPS-010: ``next_level`` finds whom an overdue flag escalates to.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.farmers.models import Farmer
from farmerapp.rules.schema import OwnerRole, Severity, Subject
from farmerapp.tenants.models import Store, Village
from farmerapp.visits.models import Visit

#: OPS-010 escalation ladder (index = escalation level of the owner role).
LADDER: tuple[UserRole, ...] = (
    UserRole.STORE_MANAGER,
    UserRole.CLUSTER_HEAD,
    UserRole.AUDITOR,
    UserRole.OWNER,
)


@dataclass(frozen=True)
class Scope:
    cluster_id: uuid.UUID | None = None
    store_id: uuid.UUID | None = None


@dataclass(frozen=True)
class Route:
    owner_id: uuid.UUID | None
    owner_role: str | None
    watchers: list[uuid.UUID] = field(default_factory=list)
    scope: Scope = field(default_factory=Scope)

    @property
    def recipients(self) -> list[uuid.UUID]:
        out = [self.owner_id] if self.owner_id is not None else []
        return out + [w for w in self.watchers if w not in out]


async def _store_scope(session: AsyncSession, store_id: uuid.UUID | None) -> Scope:
    if store_id is None:
        return Scope()
    cluster = await session.scalar(select(Store.cluster_id).where(Store.id == store_id))
    return Scope(cluster_id=cluster, store_id=store_id)


async def _user_scope(session: AsyncSession, user_id: uuid.UUID | None) -> Scope:
    if user_id is None:
        return Scope()
    row = (
        await session.execute(select(User.cluster_id, User.store_id).where(User.id == user_id))
    ).first()
    if row is None:
        return Scope()
    cluster_id, store_id = row
    if cluster_id is None and store_id is not None:
        return await _store_scope(session, store_id)
    return Scope(cluster_id=cluster_id, store_id=store_id)


async def subject_scope(
    session: AsyncSession, subject_type: Subject | str, subject_id: uuid.UUID
) -> Scope:
    match Subject(subject_type):
        case Subject.EMPLOYEE:
            return await _user_scope(session, subject_id)
        case Subject.FARMER:
            store_id = await session.scalar(
                select(Village.store_id)
                .join(Farmer, Farmer.village_id == Village.id)
                .where(Farmer.id == subject_id)
            )
            return await _store_scope(session, store_id)
        case Subject.VISIT:
            officer = await session.scalar(select(Visit.officer_id).where(Visit.id == subject_id))
            return await _user_scope(session, officer)
        case Subject.STORE:
            return await _store_scope(session, subject_id)
        case Subject.TENANT:
            return Scope()  # tenant-wide: auditors and owners on the ladder


async def _holders(
    session: AsyncSession, tenant_id: uuid.UUID, role: UserRole, scope: Scope
) -> list[uuid.UUID]:
    stmt = select(User.id).where(
        User.tenant_id == tenant_id,
        User.role == role.value,
        User.status == UserStatus.ACTIVE.value,
        User.deleted_at.is_(None),
    )
    if role == UserRole.CLUSTER_HEAD:
        if scope.cluster_id is None:
            return []
        stmt = stmt.where(User.cluster_id == scope.cluster_id)
    elif role == UserRole.STORE_MANAGER:
        if scope.store_id is None:
            return []
        stmt = stmt.where(User.store_id == scope.store_id)
    rows = await session.execute(stmt.order_by(User.created_at, User.id))
    return list(rows.scalars())


async def first_holder(
    session: AsyncSession, tenant_id: uuid.UUID, scope: Scope, *, from_level: int
) -> tuple[uuid.UUID, UserRole] | None:
    """The first active user on the ladder at or above ``from_level`` for ``scope``."""
    for role in LADDER[from_level:]:
        holders = await _holders(session, tenant_id, role, scope)
        if holders:
            return holders[0], role
    return None


def ladder_level(role: str | None) -> int:
    try:
        return LADDER.index(UserRole(role)) if role else -1  # unowned: anyone on the ladder
    except ValueError:  # an assignee outside the ladder (director, tenant admin)
        return len(LADDER) - 1


async def route(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    subject_type: Subject | str,
    subject_id: uuid.UUID,
    owner_role: OwnerRole | str,
    severity: Severity | str,
) -> Route:
    scope = await subject_scope(session, subject_type, subject_id)
    hit = await first_holder(
        session, tenant_id, scope, from_level=LADDER.index(UserRole(owner_role))
    )
    owner_id, role = (hit[0], hit[1].value) if hit is not None else (None, None)
    watchers: list[uuid.UUID] = []
    if Severity(severity) == Severity.HIGH:
        auditors = await _holders(session, tenant_id, UserRole.AUDITOR, scope)
        watchers = [a for a in auditors if a != owner_id]
    return Route(owner_id=owner_id, owner_role=role, watchers=watchers, scope=scope)


async def next_level(
    session: AsyncSession, tenant_id: uuid.UUID, scope: Scope, current_role: str | None
) -> tuple[uuid.UUID, UserRole] | None:
    """OPS-010: the next rung above ``current_role`` that has an active holder."""
    level = ladder_level(current_role) + 1
    if level >= len(LADDER):
        return None
    return await first_holder(session, tenant_id, scope, from_level=level)


__all__ = [
    "LADDER",
    "Route",
    "Scope",
    "first_holder",
    "ladder_level",
    "next_level",
    "route",
    "subject_scope",
]
