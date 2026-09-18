"""FA-021 fixtures: the seeded world with fake payment services installed on the app."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import pytest
from fastapi import FastAPI
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.payments.events import CashVarianceDetected, PaymentCaptured, bus
from tests.authz.conftest import Bearer, World, bearer, world  # noqa: F401  (re-exported)
from tests.payments.helpers import PayWorld, make_pay_world


@pytest.fixture
async def pw(
    app: FastAPI,
    db_session: AsyncSession,
    world: World,  # noqa: F811
    bearer: Bearer,  # noqa: F811
) -> PayWorld:
    return await make_pay_world(app, db_session, world, bearer)


@pytest.fixture
def events() -> Iterator[list[Any]]:
    """Every ``PaymentCaptured`` / ``CashVarianceDetected`` published during the test."""
    seen: list[Any] = []
    bus.subscribe(PaymentCaptured, seen.append)
    bus.subscribe(CashVarianceDetected, seen.append)
    try:
        yield seen
    finally:
        bus.unsubscribe(PaymentCaptured, seen.append)
        bus.unsubscribe(CashVarianceDetected, seen.append)
