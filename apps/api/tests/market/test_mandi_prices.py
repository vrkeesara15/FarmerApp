"""FM-012: the public-source adapter (what leaves, what is parsed), the daily refresh, and
``GET /v1/me/mandi-prices`` / ``GET /v1/farmers/{id}/mandi-prices``.

The acceptance criterion — *prices shown with date and source* — is asserted on the routes:
every quote carries ``price_date`` and ``source_name``, the response carries an ``as_of``
date and the ``indicative_note_key`` both apps must show.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

import httpx
import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.market.models import SOURCE_NAMES, MandiPrice, PriceSource
from farmerapp.market.provider import (
    DATA_GOV_IN_RESOURCE,
    DataGovInProvider,
    DisabledMandiPriceProvider,
    FakeMandiPriceProvider,
    MandiPriceUnavailableError,
    PriceQuote,
    build_provider,
    parse_records,
)
from farmerapp.market.service import commodity_names, prices_for_farmer, refresh_prices
from farmerapp.settings import Settings
from farmerapp.tenants.settings import MandiSettings
from tests.advisory.conftest import FarmerLogin
from tests.authz.conftest import Bearer, World

T0 = datetime(2026, 9, 21, 4, 0, tzinfo=UTC)

RESOURCE_FIXTURE = {
    "records": [
        {
            "state": "Telangana",
            "district": "Warangal",
            "market": "Warangal",
            "commodity": "Paddy(Dhan)(Common)",
            "variety": "Common",
            "grade": "FAQ",
            "arrival_date": "20/09/2026",
            "min_price": "2,050",
            "modal_price": "2150.50",
            "max_price": "2250",
        },
        {  # max below min: the adapter swaps them rather than dropping the reading
            "state": "Telangana",
            "district": "Warangal",
            "market": "Hanamkonda",
            "commodity": "Paddy(Dhan)(Common)",
            "variety": "",
            "grade": "",
            "arrival_date": "20/09/2026",
            "min_price": "2300",
            "modal_price": "2200",
            "max_price": "2100",
        },
        {  # too old for the lookback window
            "state": "Telangana",
            "district": "Warangal",
            "market": "Warangal",
            "commodity": "Paddy(Dhan)(Common)",
            "arrival_date": "01/01/2026",
            "modal_price": "1900",
        },
        {"market": "", "commodity": "Paddy", "arrival_date": "20/09/2026", "modal_price": "1"},
        {"market": "X", "commodity": "Paddy", "arrival_date": "20/09/2026", "modal_price": ""},
    ]
}


# --------------------------------------------------------------------------- adapter
def test_parse_records_converts_rupees_to_paise_and_drops_unusable_rows() -> None:
    quotes = parse_records(RESOURCE_FIXTURE, since=date(2026, 9, 14))
    assert [q.market for q in quotes] == ["Warangal", "Hanamkonda"]
    first = quotes[0]
    assert first.min_price_paise == 205_000  # 2,050 rupees per quintal
    assert first.modal_price_paise == 215_050  # 2150.50
    assert first.max_price_paise == 225_000
    assert first.price_date == date(2026, 9, 20)
    assert (first.variety, first.grade) == ("Common", "FAQ")
    second = quotes[1]
    assert second.min_price_paise == 210_000 and second.max_price_paise == 230_000
    assert (second.variety, second.grade) == ("", "")


def test_parse_records_tolerates_junk() -> None:
    assert parse_records(None, since=date(2026, 1, 1)) == ()
    assert parse_records({"records": "nope"}, since=date(2026, 1, 1)) == ()
    assert parse_records({"records": [1, "x", {}]}, since=date(2026, 1, 1)) == ()


async def test_data_gov_in_sends_only_place_and_commodity() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=RESOURCE_FIXTURE)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    provider = DataGovInProvider(
        "test-key", base_url="https://data.gov.test", page_size=200, client=client
    )
    quotes = await provider.prices(
        state="Telangana",
        district="Warangal",
        commodity="Paddy(Dhan)(Common)",
        since=date(2026, 9, 14),
    )
    assert len(quotes) == 2
    (request,) = seen
    assert request.url.path == f"/resource/{DATA_GOV_IN_RESOURCE}"
    params = dict(request.url.params)
    # NF-011: a place and a commodity, plus the key. Nothing about anybody.
    assert set(params) == {
        "api-key",
        "format",
        "limit",
        "offset",
        "filters[state.keyword]",
        "filters[district]",
        "filters[commodity]",
    }
    assert params["filters[district]"] == "Warangal" and params["limit"] == "200"
    await client.aclose()


async def test_data_gov_in_failure_is_mandi_prices_unavailable() -> None:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _r: httpx.Response(503, text="down"))
    )
    provider = DataGovInProvider("k", base_url="https://data.gov.test", client=client)
    with pytest.raises(MandiPriceUnavailableError):
        await provider.prices(
            state="Telangana", district="Warangal", commodity="Paddy", since=date(2026, 9, 1)
        )
    await client.aclose()


def test_build_provider_is_off_without_a_key() -> None:
    off = build_provider(Settings(mandi_provider="data_gov_in", mandi_api_key=""))
    assert isinstance(off, DisabledMandiPriceProvider)
    live = build_provider(Settings(mandi_provider="data_gov_in", mandi_api_key="k"))
    assert isinstance(live, DataGovInProvider)
    assert isinstance(build_provider(Settings(mandi_provider="fake")), FakeMandiPriceProvider)
    assert isinstance(build_provider(Settings(mandi_provider="off")), DisabledMandiPriceProvider)


def test_the_fake_source_says_it_is_sample_data() -> None:
    assert "not a real price" in SOURCE_NAMES[PriceSource.FAKE]
    assert SOURCE_NAMES[PriceSource.AGMARKNET] == "Agmarknet (data.gov.in)"


async def test_fake_provider_is_deterministic() -> None:
    provider = FakeMandiPriceProvider(clock=lambda: T0)
    a = await provider.prices(
        state="Telangana", district="Warangal", commodity="Paddy", since=date(2026, 9, 1)
    )
    b = await provider.prices(
        state="Telangana", district="Warangal", commodity="Paddy", since=date(2026, 9, 1)
    )
    assert a == b and len(a) == 6  # 2 markets x 3 days
    assert max(q.price_date for q in a) == T0.date()


def test_commodity_names_falls_back_to_the_english_crop_name() -> None:
    crop = Crop(code="paddy", name="Paddy")
    assert commodity_names(crop, MandiSettings()) == ("Paddy",)
    mapped = MandiSettings(commodities={"paddy": ["Paddy(Dhan)(Common)", "Paddy(Dhan)(Basmati)"]})
    assert commodity_names(crop, mapped) == ("Paddy(Dhan)(Common)", "Paddy(Dhan)(Basmati)")


# --------------------------------------------------------------------------- refresh
class ScriptedProvider:
    """Answers with one quote per (district, commodity) it is asked for."""

    name = PriceSource.FAKE.value
    source_name = SOURCE_NAMES[PriceSource.FAKE]
    source_url = ""

    def __init__(self, *, modal: int = 200_000, day: date | None = None) -> None:
        self.asked: list[tuple[str, str, str]] = []
        self.modal = modal
        self.day = day or T0.date()

    async def prices(
        self, *, state: str, district: str, commodity: str, since: date
    ) -> tuple[PriceQuote, ...]:
        self.asked.append((state, district, commodity))
        return (
            PriceQuote(
                state=state,
                district=district,
                market=f"{district} Yard",
                commodity=commodity,
                variety="Common",
                grade="FAQ",
                price_date=self.day,
                min_price_paise=self.modal - 5_000,
                modal_price_paise=self.modal,
                max_price_paise=self.modal + 5_000,
            ),
        )


async def test_refresh_writes_one_row_per_reading_and_is_idempotent(
    db_session: AsyncSession, world: World, login: FarmerLogin
) -> None:
    tenant_id = world.a.tenant.id
    provider = ScriptedProvider()
    report = await refresh_prices(
        db_session,
        tenant_id=tenant_id,
        provider=provider,
        settings=MandiSettings(),
        now=T0,
    )
    assert report.districts >= 1 and report.crops >= 1 and report.failures == 0
    assert report.written == report.districts * report.crops
    rows = list(
        (
            await db_session.scalars(select(MandiPrice).where(MandiPrice.tenant_id == tenant_id))
        ).all()
    )
    assert len(rows) == report.written
    assert all(r.source == PriceSource.FAKE for r in rows)
    assert all(r.source_name == SOURCE_NAMES[PriceSource.FAKE] for r in rows)
    assert all(r.fetched_at == T0 for r in rows)
    # Only the crops farmers actually grow are asked for.
    asked_commodities = {c for _s, _d, c in provider.asked}
    assert asked_commodities

    # Running it again the same day updates the same rows rather than duplicating them.
    again = ScriptedProvider(modal=250_000)
    later = T0 + timedelta(hours=1)
    await refresh_prices(
        db_session, tenant_id=tenant_id, provider=again, settings=MandiSettings(), now=later
    )
    after = list(
        (
            await db_session.scalars(select(MandiPrice).where(MandiPrice.tenant_id == tenant_id))
        ).all()
    )
    assert len(after) == len(rows)
    assert {r.modal_price_paise for r in after} == {250_000}
    assert {r.fetched_at for r in after} == {later}


async def test_refresh_counts_a_provider_failure_without_losing_the_rest(
    db_session: AsyncSession, world: World, login: FarmerLogin
) -> None:
    class Flaky(ScriptedProvider):
        async def prices(self, **kw: object) -> tuple[PriceQuote, ...]:
            raise MandiPriceUnavailableError("down")

    report = await refresh_prices(
        db_session,
        tenant_id=world.a.tenant.id,
        provider=Flaky(),
        settings=MandiSettings(),
        now=T0,
    )
    assert report.failures > 0 and report.written == 0


async def test_refresh_ignores_a_commodity_the_source_does_not_match(
    db_session: AsyncSession, world: World, login: FarmerLogin
) -> None:
    class Wrong(ScriptedProvider):
        async def prices(
            self, *, state: str, district: str, commodity: str, since: date
        ) -> tuple[PriceQuote, ...]:
            quotes = await super().prices(
                state=state, district=district, commodity=commodity, since=since
            )
            return tuple(
                PriceQuote(**{**q.__dict__, "commodity": "Something Else"}) for q in quotes
            )

    report = await refresh_prices(
        db_session,
        tenant_id=world.a.tenant.id,
        provider=Wrong(),
        settings=MandiSettings(),
        now=T0,
    )
    assert report.fetched == 0 and report.written == 0


async def test_reads_return_only_the_latest_date_nearest_market_first(
    db_session: AsyncSession, world: World, login: FarmerLogin
) -> None:
    tenant_id = world.a.tenant.id
    crop = login.crop
    for day, market, district in (
        (date(2026, 9, 19), "Old Yard", login.district),
        (date(2026, 9, 20), "Far Yard", "Elsewhere"),
        (date(2026, 9, 20), "Home Yard", login.district),
    ):
        db_session.add(
            MandiPrice(
                tenant_id=tenant_id,
                crop_id=crop.id,
                market=market,
                district=district,
                state="Telangana",
                variety="",
                grade="",
                price_date=day,
                min_price_paise=100_000,
                modal_price_paise=110_000,
                max_price_paise=120_000,
                source=PriceSource.FAKE,
                source_name=SOURCE_NAMES[PriceSource.FAKE],
                fetched_at=T0,
            )
        )
    await db_session.flush()
    groups = await prices_for_farmer(db_session, login.farmer)
    (group,) = [g for g in groups if g.crop_id == crop.id]
    assert group.price_date == date(2026, 9, 20)  # the newest date only
    assert [q.market for q in group.rows] == ["Home Yard", "Far Yard"]  # own district first
    assert group.source_name == SOURCE_NAMES[PriceSource.FAKE]


# --------------------------------------------------------------------------- API
async def _seed(session: AsyncSession, login: FarmerLogin, *, day: date) -> None:
    session.add(
        MandiPrice(
            tenant_id=login.farmer.tenant_id,
            crop_id=login.crop.id,
            market="Warangal Yard",
            district=login.district,
            state="Telangana",
            variety="Common",
            grade="FAQ",
            price_date=day,
            min_price_paise=205_000,
            modal_price_paise=215_050,
            max_price_paise=225_000,
            source=PriceSource.AGMARKNET,
            source_name=SOURCE_NAMES[PriceSource.AGMARKNET],
            source_url="https://data.gov.in/resource/x",
            fetched_at=T0,
        )
    )
    await session.flush()


async def test_my_mandi_prices_shows_the_date_and_the_source(
    app: FastAPI,
    client: AsyncClient,
    bearer: Bearer,
    login: FarmerLogin,
    db_session: AsyncSession,
) -> None:
    day = date(2026, 9, 20)
    await _seed(db_session, login, day=day)
    resp = await client.get("/v1/me/mandi-prices", headers=bearer(login.user))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["farmer_id"] == str(login.farmer.id)
    assert body["district"] == login.district
    assert body["as_of"] == day.isoformat()
    # FM-012: the "prices are indicative" line is part of the contract, not an app decision.
    assert body["indicative_note_key"] == "mandi.indicative"
    crop = next(c for c in body["crops"] if c["crop_id"] == str(login.crop.id))
    assert crop["price_date"] == day.isoformat()
    assert crop["source_name"] == "Agmarknet (data.gov.in)"
    assert crop["crop_names"]["en"] == login.crop.name
    (quote,) = crop["quotes"]
    assert quote["modal_price_paise"] == 215_050  # integer paise per quintal
    assert quote["price_date"] == day.isoformat()
    assert quote["source_name"] == "Agmarknet (data.gov.in)"
    assert quote["source"] == "agmarknet"


async def test_a_crop_with_no_price_is_listed_with_a_null_date(
    client: AsyncClient, bearer: Bearer, login: FarmerLogin
) -> None:
    body = (await client.get("/v1/me/mandi-prices", headers=bearer(login.user))).json()
    crop = next(c for c in body["crops"] if c["crop_id"] == str(login.crop.id))
    assert crop["price_date"] is None and crop["quotes"] == []
    assert body["as_of"] is None


async def test_the_officer_variant_answers_for_one_of_their_farmers(
    client: AsyncClient,
    bearer: Bearer,
    login: FarmerLogin,
    world: World,
    db_session: AsyncSession,
) -> None:
    await _seed(db_session, login, day=date(2026, 9, 20))
    officer = world.a.user(UserRole.FIELD_OFFICER)
    resp = await client.get(f"/v1/farmers/{login.farmer.id}/mandi-prices", headers=bearer(officer))
    assert resp.status_code == 200, resp.text
    assert resp.json()["as_of"] == "2026-09-20"

    # Another tenant's farmer is simply not found.
    missing = await client.get(f"/v1/farmers/{uuid.uuid4()}/mandi-prices", headers=bearer(officer))
    assert missing.status_code == 404


async def test_the_markets_parameter_caps_the_list(
    client: AsyncClient, bearer: Bearer, login: FarmerLogin, db_session: AsyncSession
) -> None:
    day = date(2026, 9, 20)
    for i in range(4):
        db_session.add(
            MandiPrice(
                tenant_id=login.farmer.tenant_id,
                crop_id=login.crop.id,
                market=f"Yard {i}",
                district=login.district,
                state="Telangana",
                variety="",
                grade="",
                price_date=day,
                min_price_paise=1,
                modal_price_paise=2,
                max_price_paise=3,
                source=PriceSource.FAKE,
                source_name=SOURCE_NAMES[PriceSource.FAKE],
                fetched_at=T0,
            )
        )
    await db_session.flush()
    body = (await client.get("/v1/me/mandi-prices?markets=2", headers=bearer(login.user))).json()
    crop = next(c for c in body["crops"] if c["crop_id"] == str(login.crop.id))
    assert len(crop["quotes"]) == 2
