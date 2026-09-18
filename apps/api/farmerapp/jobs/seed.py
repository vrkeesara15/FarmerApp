"""Demo seed: two tenants with one user per role each (FA-001, FA-002, FA-003 fixtures).

* "Future Crop Care" (``fcc``, phones ``+91900000000{1..10}``) — the pilot tenant.
* "Green Fields" (``gfl``, phones ``+91910000000{1..10}``) — a second tenant so cross-tenant
  authorisation (SEC-006) and RLS (FA-003) tests have data on both sides.

M1-KICKOFF extends this with stores, officers and farmers. Idempotent: re-running updates
names/roles in place and never duplicates rows. Phones are reserved test numbers.

Runs as the app role under RLS (FA-003): every demo tenant has a fixed id (uuid5 of its slug)
and is seeded inside its own ``tenant_scope``; no bypass is needed or available. Writes are
attributed to the system actor in the audit trail (FA-006): ``tenant.create`` /
``user.create`` rows with ``before`` null.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db import audit
from farmerapp.db.models import Tenant
from farmerapp.db.session import get_session_factory, tenant_scope

DemoUser = tuple[str, str, UserRole, str]  # (phone, name, role, language)


TENANT_NAMESPACE = uuid.UUID("6f5b3d1e-0c2a-4b8e-9a7d-2f1e3c4b5a60")  # farmerapp demo tenants


def demo_tenant_id(slug: str) -> uuid.UUID:
    """Stable id per demo tenant so the seed can bind its scope before the row exists."""
    return uuid.uuid5(TENANT_NAMESPACE, slug)


@dataclass(frozen=True)
class DemoTenant:
    name: str
    slug: str
    users: tuple[DemoUser, ...]

    @property
    def id(self) -> uuid.UUID:
        return demo_tenant_id(self.slug)


DEMO_TENANT_NAME = "Future Crop Care"
DEMO_TENANT_SLUG = "fcc"

DEMO_USERS: tuple[DemoUser, ...] = (
    ("+919000000001", "Suresh Reddy", UserRole.OWNER, "en"),
    ("+919000000002", "Lakshmi Devi", UserRole.CLUSTER_HEAD, "te"),
    ("+919000000003", "Venkat Rao", UserRole.STORE_MANAGER, "te"),
    ("+919000000004", "Ramesh Kumar", UserRole.FIELD_OFFICER, "te"),
    ("+919000000005", "Dr. Anitha", UserRole.AGRONOMIST, "en"),
    ("+919000000006", "Prakash Reddy", UserRole.DIRECTOR, "en"),
    ("+919000000007", "Kavitha Rao", UserRole.AUDITOR, "en"),
    ("+919000000008", "Srinivas", UserRole.ACCOUNTANT, "te"),
    ("+919000000009", "Admin FCC", UserRole.TENANT_ADMIN, "en"),
    ("+919000000010", "Mallesh", UserRole.FARMER, "te"),
)

GREEN_FIELDS_USERS: tuple[DemoUser, ...] = (
    ("+919100000001", "Manjunath Gowda", UserRole.OWNER, "en"),
    ("+919100000002", "Shanta Kumari", UserRole.CLUSTER_HEAD, "kn"),
    ("+919100000003", "Basavaraj", UserRole.STORE_MANAGER, "kn"),
    ("+919100000004", "Ravi Naik", UserRole.FIELD_OFFICER, "kn"),
    ("+919100000005", "Dr. Deepa", UserRole.AGRONOMIST, "en"),
    ("+919100000006", "Girish Gowda", UserRole.DIRECTOR, "en"),
    ("+919100000007", "Nagaraj", UserRole.AUDITOR, "en"),
    ("+919100000008", "Sunitha", UserRole.ACCOUNTANT, "kn"),
    ("+919100000009", "Admin GFL", UserRole.TENANT_ADMIN, "en"),
    ("+919100000010", "Siddappa", UserRole.FARMER, "kn"),
)

DEMO_TENANTS: tuple[DemoTenant, ...] = (
    DemoTenant(name=DEMO_TENANT_NAME, slug=DEMO_TENANT_SLUG, users=DEMO_USERS),
    DemoTenant(name="Green Fields", slug="gfl", users=GREEN_FIELDS_USERS),
)


@dataclass(frozen=True)
class SeedResult:
    tenant_id: uuid.UUID  # the primary demo tenant (fcc)
    tenant_slug: str
    users_created: int  # across all demo tenants
    tenants: tuple[tuple[str, uuid.UUID], ...] = field(default_factory=tuple)


async def _seed_tenant(session: AsyncSession, demo: DemoTenant) -> tuple[Tenant, int]:
    tenant = await session.get(Tenant, demo.id)
    if tenant is None:
        tenant = Tenant(id=demo.id, name=demo.name, slug=demo.slug)
        session.add(tenant)
        await session.flush()
    elif tenant.name != demo.name:
        tenant.name = demo.name

    existing = {
        u.phone: u
        for u in (await session.execute(select(User).where(User.tenant_id == tenant.id))).scalars()
    }
    created = 0
    for phone, name, role, language in demo.users:
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
    return tenant, created


async def seed_demo(session: AsyncSession) -> SeedResult:
    seeded: list[tuple[str, uuid.UUID]] = []
    created = 0
    for demo in DEMO_TENANTS:
        with audit.actor_scope(audit.system_actor(demo.id)):
            async with tenant_scope(session, demo.id):
                tenant, n = await _seed_tenant(session, demo)
        seeded.append((demo.slug, tenant.id))
        created += n
    primary = dict(seeded)[DEMO_TENANT_SLUG]
    return SeedResult(
        tenant_id=primary,
        tenant_slug=DEMO_TENANT_SLUG,
        users_created=created,
        tenants=tuple(seeded),
    )


async def run_seed() -> SeedResult:
    factory = get_session_factory()
    async with factory() as session, session.begin():
        return await seed_demo(session)
