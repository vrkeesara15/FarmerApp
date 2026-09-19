"""FA-024 acceptance: "numbers match console for the same officer and period"."""

from __future__ import annotations

import uuid
from datetime import date, timedelta

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.performance.ports import NullIncentives
from tests.analytics.builders import Mini, ist
from tests.authz.conftest import Bearer
from tests.field_tokens import mint_bearer


@pytest.fixture
def bearer(app: FastAPI) -> Bearer:
    return mint_bearer(app)


FROM, TO = date(2026, 8, 1), date(2026, 8, 31)


@pytest.fixture
async def mini(db_session: AsyncSession) -> Mini:
    m = await Mini.create(db_session)
    d = date(2026, 8, 10)
    await m.duty("o1", ist(d, 9), ist(d, 17), km="32.50")
    await m.duty("o1", ist(d + timedelta(days=1), 9), ist(d + timedelta(days=1), 16), km="18.00")
    await m.visit("o1", "f1", ist(d, 10), score=85, confirmed=True)
    await m.visit("o1", "f2", ist(d, 12), score=55)
    await m.visit("o1", "f1", ist(d + timedelta(days=1), 10), score=90, confirmed=True)
    await m.visit("o1", "f2", ist(d - timedelta(days=20), 10), score=95)  # July: outside
    await m.visit("o2", "f3", ist(d, 11), score=80)  # another officer
    await m.farmer("f5", "N1", "o1", None, created_at=ist(d, 15))  # registered in August
    await m.sale("N1", "f1", ist(d + timedelta(days=2), 12), [("own", 2, 1000)], placed_by="o1")
    await m.sale("N1", "f2", ist(d + timedelta(days=3), 12), [("multi", 1, 800)], placed_by="o1")
    await m.sale("N1", "f2", ist(d + timedelta(days=4), 12), [("multi", 5, 800)])  # POS
    await m.payment("N1", "f1", "o1", 1_500, ist(d + timedelta(days=2), 13))
    await m.payment("S1", "f3", "o2", 9_999, ist(d, 13))
    return m


async def test_numbers_match_the_console(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    o1 = mini.user("o1")
    params = {"from": str(FROM), "to": str(TO)}
    mine = await client.get("/v1/me/performance", params=params, headers=bearer(o1))
    assert mine.status_code == 200, mine.text
    perf = mine.json()

    for viewer in ("owner", "cluster_head", "o1"):
        console = await client.get(
            f"/v1/analytics/officers/{o1.id}", params=params, headers=bearer(mini.user(viewer))
        )
        assert console.status_code == 200, console.text
        profile = console.json()
        card = profile["scorecard"]
        assert perf["visits"] == card["visits"], viewer
        assert perf["verified_visits"] == card["verified_visits"], viewer
        assert perf["unique_farmers_reached"] == card["unique_farmers_reached"], viewer
        assert perf["farmers_added"] == card["new_registrations"], viewer
        assert perf["confirmation_rate"] == card["confirmation_rate"], viewer
        assert perf["collections_paise"] == card["collections_paise"], viewer
        assert perf["duty_days"] == card["duty_days"], viewer
        assert perf["time_on_farm_s"] == card["time_on_farm_s"], viewer
        assert perf["conversion_rate"] == card["conversion_rate"], viewer
        assert perf["sales_net_paise"] == profile["sales_net_paise"], viewer
        assert perf["sales_orders"] == profile["sales_orders"], viewer

    # And the values are the SPEC 5.2 ones for this data.
    assert perf["visits"] == 3 and perf["verified_visits"] == 2
    assert perf["confirmation_rate"] == pytest.approx(2 / 3, abs=1e-4)
    assert perf["farmers_added"] == 1
    assert perf["sales_net_paise"] == 2 * 1000 + 800 and perf["sales_orders"] == 2
    assert perf["collections_paise"] == 1_500
    assert perf["duty_days"] == 2 and perf["km_per_day"] == pytest.approx(25.25)
    assert perf["incentive_earned_paise"] is None  # WC-009 not configured yet
    assert perf["from"] == str(FROM) and perf["filters"]["scope"] == "own"


async def test_incentive_comes_from_the_port(
    app: FastAPI, client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    class Fixed(NullIncentives):
        async def earned_paise(
            self, session: object, tenant_id: uuid.UUID, officer_id: uuid.UUID, *_: object
        ) -> int | None:
            return 123_400 if officer_id == mini.user("o1").id else None

    app.state.incentives = Fixed()
    resp = await client.get(
        "/v1/me/performance",
        params={"from": str(FROM), "to": str(TO)},
        headers=bearer(mini.user("o1")),
    )
    assert resp.json()["incentive_earned_paise"] == 123_400


async def test_range_validation_and_roles(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    o1 = bearer(mini.user("o1"))
    bad = await client.get(
        "/v1/me/performance", params={"from": "2026-09-02", "to": "2026-09-01"}, headers=o1
    )
    assert bad.status_code == 422 and bad.json()["code"] == "invalid_date_range"
    default = await client.get("/v1/me/performance", headers=o1)
    assert default.status_code == 200 and default.json()["filters"]["days"] == 30
    for role in ("cluster_head", "owner", "store_manager"):
        resp = await client.get("/v1/me/performance", headers=bearer(mini.user(role)))
        assert resp.status_code == 403, role
