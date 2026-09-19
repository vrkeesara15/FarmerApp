"""Analytics fixtures: the seeded world (SMALL), tokens and the hand-built ``Mini`` tenant."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient, Response
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from tests.analytics.builders import Mini
from tests.authz.conftest import Bearer, bearer, world  # noqa: F401  (fixtures re-exported)


@pytest.fixture
async def mini(db_session: AsyncSession) -> Mini:
    return await Mini.create(db_session)


async def get(client: AsyncClient, mint: Bearer, user: User, path: str, **params: Any) -> Response:
    """``GET /v1/analytics<path>`` as ``user``; ``from_=`` becomes ``from``."""
    query = {("from" if k == "from_" else k): str(v) for k, v in params.items() if v is not None}
    return await client.get(f"/v1/analytics{path}", params=query, headers=mint(user))
