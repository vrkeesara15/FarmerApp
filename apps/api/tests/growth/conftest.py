"""M7 growth fixtures: the hand-built ``Mini`` tenant (tests/analytics/builders.py), tokens,
step-up headers and consent helpers."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.farmers.models import ConsentRecord, Farmer
from tests.analytics.builders import Mini
from tests.authz.conftest import Bearer, bearer, step_up, world  # noqa: F401  (re-exported)

T0 = datetime(2026, 9, 1, 4, 30, tzinfo=UTC)


@pytest.fixture
async def mini(db_session: AsyncSession) -> Mini:
    return await Mini.create(db_session)


async def consent(
    m: Mini, farmer: Farmer, *, granted: bool, at: datetime, purpose: str = "marketing"
) -> ConsentRecord:
    row = ConsentRecord(
        tenant_id=m.tid,
        subject_type="farmer",
        subject_id=farmer.id,
        purpose=purpose,
        version="2026-09-v1",
        channel="officer",
        granted_at=at if granted else None,
        withdrawn_at=None if granted else at,
        created_at=at,
    )
    await m.add(row)
    return row


async def consented_world(m: Mini) -> None:
    """f1, f2 consented; f3 granted then withdrew; f4 (N1, O1) never asked."""
    await m.farmer("f4", "N1", "o1", None)
    for key in ("f1", "f2", "f3"):
        await consent(m, m.farmers[key], granted=True, at=T0 - timedelta(days=30))
    await consent(m, m.farmers["f3"], granted=False, at=T0 - timedelta(days=10))


def headers(mint: Bearer, user: User, stepper: Bearer | None = None) -> dict[str, Any]:
    out = dict(mint(user))
    if stepper is not None:
        out.update(stepper(user))
    return out
