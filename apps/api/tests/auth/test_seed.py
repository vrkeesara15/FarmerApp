"""``python -m farmerapp.jobs seed`` upserts both demo tenants and one user per role each."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import TENANT_ROLES, User
from farmerapp.db.models import Tenant
from farmerapp.db.session import tenant_scope
from farmerapp.jobs.seed import DEMO_TENANTS, DEMO_USERS, SMALL, seed_demo


async def test_seed_is_idempotent(db_session: AsyncSession) -> None:
    first = await seed_demo(db_session, SMALL)
    assert first.tenant_slug == "fcc"
    assert len(DEMO_USERS) == 10
    assert first.users_created == sum(len(t.all_users) for t in DEMO_TENANTS) == 24
    assert [slug for slug, _ in first.tenants] == ["fcc", "gfl"]
    second = await seed_demo(db_session, SMALL)
    assert second.users_created == 0 and second.tenant_id == first.tenant_id
    assert second.tenants == first.tenants

    async with tenant_scope(db_session, first.tenant_id):
        tenant = (await db_session.execute(select(Tenant).where(Tenant.slug == "fcc"))).scalar_one()
        assert tenant.name == "Future Crop Care"
        users = (
            (await db_session.execute(select(User).where(User.tenant_id == tenant.id)))
            .scalars()
            .all()
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
        "+919000000011": "field_officer",
        "+919000000012": "field_officer",
        "+919000000013": "field_officer",
        "+919000000014": "field_officer",
    }
    placed = {u.phone: u for u in users}
    # store manager and officers belong to a store (and its cluster); the head to a cluster
    assert placed["+919000000003"].store_id == placed["+919000000004"].store_id is not None
    assert placed["+919000000003"].cluster_id == placed["+919000000002"].cluster_id is not None
    officers = [u for u in users if u.role == "field_officer"]
    assert len({o.store_id for o in officers}) == 5  # one per store
    assert placed["+919000000001"].store_id is None and placed["+919000000001"].cluster_id is None


async def test_second_tenant_has_every_role(db_session: AsyncSession) -> None:
    result = await seed_demo(db_session, SMALL)
    gfl_id = dict(result.tenants)["gfl"]
    assert gfl_id != result.tenant_id
    async with tenant_scope(db_session, gfl_id):
        tenant = await db_session.get(Tenant, gfl_id)
        assert tenant is not None and tenant.name == "Green Fields" and tenant.slug == "gfl"
        users = (
            (await db_session.execute(select(User).where(User.tenant_id == gfl_id))).scalars().all()
        )
    assert {u.role for u in users} == {r.value for r in TENANT_ROLES}
    assert all(u.phone.startswith("+9191") for u in users)


async def test_seed_tenant_ids_are_stable(db_session: AsyncSession) -> None:
    """Fixed ids let the seed run under RLS (scope per tenant) and stay idempotent."""
    ids = {t.slug: t.id for t in DEMO_TENANTS}
    result = await seed_demo(db_session, SMALL)
    assert dict(result.tenants) == ids
    assert len(set(ids.values())) == len(ids)
