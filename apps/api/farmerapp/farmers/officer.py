"""FM-011 / F62: the field officer a farmer calls from the farmer app.

Rule (documented in docs/prs/M6-followups.md):

1. the user who registered the farmer (``farmer.registered_by``) while that user is an
   **active field officer** of the tenant (not disabled, not deleted, role unchanged);
2. otherwise the active field officer assigned to the store of the farmer's village
   (``village.store_id``); several officers at one store -> the longest-serving one
   (``user.created_at``, then ``id``) so the answer is stable between reads;
3. otherwise none (``null``; the app shows "your field officer").

The phone is decrypted through the SEC-026 field cipher (``User.phone``) and returned in full
only to the farmer themself, the officer themself and the roles that already read user
profiles with phones (``GET /v1/users``: owner, director, cluster head, auditor, tenant
admin). Every other reader (store manager, other field officers, agronomist) gets it masked.
"""

from __future__ import annotations

import uuid

from sqlalchemy import ColumnElement, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.auth.providers import mask_phone
from farmerapp.auth.schemas import AssignedOfficerOut
from farmerapp.farmers.models import Farmer
from farmerapp.tenants.models import Village

#: Staff roles that read user phones already (``farmerapp.users.router.READ_ROLES``).
PHONE_READER_ROLES = frozenset(
    {
        UserRole.OWNER,
        UserRole.DIRECTOR,
        UserRole.CLUSTER_HEAD,
        UserRole.AUDITOR,
        UserRole.TENANT_ADMIN,
    }
)


def _active_officer(tenant_id: uuid.UUID) -> tuple[ColumnElement[bool], ...]:
    return (
        User.tenant_id == tenant_id,
        User.role == UserRole.FIELD_OFFICER,
        User.status == UserStatus.ACTIVE,
        User.deleted_at.is_(None),
    )


async def assigned_officer(session: AsyncSession, farmer: Farmer) -> User | None:
    """The farmer's field officer by the rule in the module docstring, or ``None``."""
    if farmer.registered_by is not None:
        registrar = (
            await session.execute(
                select(User).where(
                    User.id == farmer.registered_by, *_active_officer(farmer.tenant_id)
                )
            )
        ).scalar_one_or_none()
        if registrar is not None:
            return registrar
    store_id = (
        select(Village.store_id)
        .where(Village.id == farmer.village_id, Village.tenant_id == farmer.tenant_id)
        .scalar_subquery()
    )
    stmt = (
        select(User)
        .where(*_active_officer(farmer.tenant_id), User.store_id == store_id)
        .order_by(User.created_at, User.id)
        .limit(1)
    )
    return (await session.execute(stmt)).scalar_one_or_none()


def may_read_phone(viewer: User, farmer: Farmer, officer: User) -> bool:
    if viewer.id == officer.id:
        return True
    role = UserRole(viewer.role)
    if role == UserRole.FARMER:
        return farmer.user_id is not None and farmer.user_id == viewer.id
    return role in PHONE_READER_ROLES


async def officer_out(
    session: AsyncSession, farmer: Farmer, viewer: User
) -> AssignedOfficerOut | None:
    officer = await assigned_officer(session, farmer)
    if officer is None:
        return None
    phone = officer.phone
    if not may_read_phone(viewer, farmer, officer):
        phone = mask_phone(phone)
    return AssignedOfficerOut(id=officer.id, name=officer.name, phone=phone)


async def own_farmer(session: AsyncSession, user: User) -> Farmer | None:
    """The farmer record of a farmer login (``farmer.user_id``), if any."""
    stmt = (
        select(Farmer)
        .where(
            Farmer.tenant_id == user.tenant_id,
            Farmer.user_id == user.id,
            Farmer.deleted_at.is_(None),
        )
        .order_by(Farmer.created_at, Farmer.id)
        .limit(1)
    )
    return (await session.execute(stmt)).scalar_one_or_none()
