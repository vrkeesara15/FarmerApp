"""Demo seed (FA-001 part): tenant "Future Crop Care" (slug ``fcc``) and one user per role.

M1-KICKOFF extends this with stores, officers and farmers. Idempotent: re-running updates
names/roles in place and never duplicates rows. Phones are reserved test numbers.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db.models import Tenant
from farmerapp.db.session import get_session_factory, set_bypass_rls

DEMO_TENANT_NAME = "Future Crop Care"
DEMO_TENANT_SLUG = "fcc"

# (phone, name, role, language)
DEMO_USERS: tuple[tuple[str, str, UserRole, str], ...] = (
    ("+919000000001", "Suresh Reddy", UserRole.OWNER, "en"),
    ("+919000000002", "Lakshmi Devi", UserRole.CLUSTER_HEAD, "te"),
    ("+919000000003", "Venkat Rao", UserRole.STORE_MANAGER, "te"),
    ("+919000000004", "Ramesh Kumar", UserRole.FIELD_OFFICER, "te"),
    ("+919000000005", "Dr. Anitha", UserRole.AGRONOMIST, "en"),
    ("+919000000010", "Mallesh", UserRole.FARMER, "te"),
)


@dataclass(frozen=True)
class SeedResult:
    tenant_id: uuid.UUID
    tenant_slug: str
    users_created: int


async def seed_demo(session: AsyncSession) -> SeedResult:
    await set_bypass_rls(session)
    tenant = (
        await session.execute(select(Tenant).where(Tenant.slug == DEMO_TENANT_SLUG))
    ).scalar_one_or_none()
    if tenant is None:
        tenant = Tenant(name=DEMO_TENANT_NAME, slug=DEMO_TENANT_SLUG)
        session.add(tenant)
        await session.flush()
    elif tenant.name != DEMO_TENANT_NAME:
        tenant.name = DEMO_TENANT_NAME

    existing = {
        u.phone: u
        for u in (await session.execute(select(User).where(User.tenant_id == tenant.id))).scalars()
    }
    created = 0
    for phone, name, role, language in DEMO_USERS:
        user = existing.get(phone)
        if user is None:
            session.add(
                User(
                    tenant_id=tenant.id,
                    phone=phone,
                    name=name,
                    role=role,
                    language=language,
                    status=UserStatus.ACTIVE,
                )
            )
            created += 1
        else:
            user.name, user.role, user.language = name, role, language
    await session.flush()
    return SeedResult(tenant_id=tenant.id, tenant_slug=DEMO_TENANT_SLUG, users_created=created)


async def run_seed() -> SeedResult:
    factory = get_session_factory()
    async with factory() as session, session.begin():
        return await seed_demo(session)
