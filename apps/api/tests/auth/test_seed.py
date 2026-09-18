"""``python -m farmerapp.jobs seed`` upserts the demo tenant and one user per role."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.db.models import Tenant
from farmerapp.jobs.seed import DEMO_USERS, seed_demo


async def test_seed_is_idempotent(db_session: AsyncSession) -> None:
    first = await seed_demo(db_session)
    assert first.tenant_slug == "fcc"
    assert first.users_created == len(DEMO_USERS) == 6
    second = await seed_demo(db_session)
    assert second.users_created == 0 and second.tenant_id == first.tenant_id

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
        "+919000000010": "farmer",
    }
