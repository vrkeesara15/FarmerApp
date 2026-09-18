"""``python -m farmerapp.jobs seed`` upserts both demo tenants and one user per role each."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.db.models import Tenant
from farmerapp.jobs.seed import DEMO_TENANTS, DEMO_USERS, seed_demo


async def test_seed_is_idempotent(db_session: AsyncSession) -> None:
    first = await seed_demo(db_session)
    assert first.tenant_slug == "fcc"
    assert len(DEMO_USERS) == 10
    assert first.users_created == sum(len(t.users) for t in DEMO_TENANTS) == 20
    assert [slug for slug, _ in first.tenants] == ["fcc", "gfl"]
    second = await seed_demo(db_session)
    assert second.users_created == 0 and second.tenant_id == first.tenant_id
    assert second.tenants == first.tenants

    tenant = (await db_session.execute(select(Tenant).where(Tenant.slug == "fcc"))).scalar_one()
    assert tenant.name == "Future Crop Care"
    users = (
        (await db_session.execute(select(User).where(User.tenant_id == tenant.id))).scalars().all()
    )
    by_phone = {u.phone: u.role for u in users}
    assert by_phone == {
        "+919000000001": "owner",
        "+919000000002": "cluster_head",
        "+919000000003": "store_manager",
        "+919000000004": "field_officer",
        "+919000000005": "agronomist",
        "+919000000006": "director",
        "+919000000007": "auditor",
        "+919000000008": "accountant",
        "+919000000009": "tenant_admin",
        "+919000000010": "farmer",
    }


async def test_second_tenant_has_every_role(db_session: AsyncSession) -> None:
    result = await seed_demo(db_session)
    gfl_id = dict(result.tenants)["gfl"]
    assert gfl_id != result.tenant_id
    tenant = await db_session.get(Tenant, gfl_id)
    assert tenant is not None and tenant.name == "Green Fields" and tenant.slug == "gfl"
    users = (await db_session.execute(select(User).where(User.tenant_id == gfl_id))).scalars().all()
    assert {u.role for u in users} == {r.value for r in UserRole}
    assert all(u.phone.startswith("+9191") for u in users)
