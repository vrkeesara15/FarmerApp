"""FM-008 weather: Open-Meteo parsing and the privacy of the call (grid-cell coordinates only),
the per-cell 3 h cache, spray windows (rain / wind thresholds hide a window; heat and humidity
are cautions) on fixture forecasts, and ``GET /v1/farms/{id}/weather``."""

from __future__ import annotations

import json
from datetime import UTC, date, datetime, timedelta

import httpx
import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.advisory.weather import (
    FakeWeatherProvider,
    Forecast,
    ForecastCache,
    HourForecast,
    OpenMeteoProvider,
    WeatherService,
    WeatherUnavailableError,
    daily_from_hours,
    grid_cell,
    parse_open_meteo,
    spray_windows,
)
from farmerapp.auth.models import UserRole
from farmerapp.db.models import Tenant
from farmerapp.payments.config import IST
from farmerapp.tenants.settings import WeatherSettings
from tests.advisory.conftest import FarmerLogin
from tests.authz.conftest import Bearer, World

T0 = datetime(2026, 9, 21, 6, 0, tzinfo=IST)  # 06:00 IST


def _hour(
    t: datetime,
    *,
    prob: int = 5,
    rain: float = 0.0,
    wind: float = 5.0,
    temp: float = 28.0,
    rh: int = 60,
) -> HourForecast:
    return HourForecast(
        time=t,
        temperature_c=temp,
        relative_humidity_pct=rh,
        precipitation_probability_pct=prob,
        precipitation_mm=rain,
        wind_kmh=wind,
        wind_gust_kmh=wind * 1.5,
    )


def _fixture_hours(start: datetime = T0) -> list[HourForecast]:
    """72 h from 06:00 IST: 09-12 rainy (prob 40 %), 12-15 windy (20 km/h), 15-18 hot and dry,
    21-24 humid, everything else calm."""
    hours: list[HourForecast] = []
    for i in range(80):
        t = start + timedelta(hours=i)
        h = t.hour
        if t.date() == start.date() and 9 <= h < 12:
            hours.append(_hour(t, prob=40 if h == 10 else 10))
        elif t.date() == start.date() and 12 <= h < 15:
            hours.append(_hour(t, wind=20.0 if h == 13 else 8.0))
        elif t.date() == start.date() and 15 <= h < 18:
            hours.append(_hour(t, temp=37.0, rh=25))
        elif t.date() == start.date() and 21 <= h < 24:
            hours.append(_hour(t, rh=95))
        else:
            hours.append(_hour(t))
    return hours


def test_spray_windows_hide_rain_and_wind_and_caution_heat_and_humidity() -> None:
    windows = spray_windows(_fixture_hours(), WeatherSettings(), now=T0 + timedelta(minutes=30))
    assert windows[0].start == T0  # the current window, aligned on 06:00 IST
    assert all((w.start.astimezone(IST).hour % 3) == 0 for w in windows)
    assert all(w.end - w.start == timedelta(hours=3) for w in windows)
    by_start = {w.start.astimezone(IST).hour: w for w in windows if w.start.date() == T0.date()}
    assert by_start[9].advice == "avoid" and by_start[9].reasons == ("rain_likely",)
    assert by_start[12].advice == "avoid" and by_start[12].reasons == ("wind_high",)
    assert by_start[15].advice == "good" and set(by_start[15].cautions) == {"heat", "humidity_low"}
    assert by_start[21].advice == "good" and by_start[21].cautions == ("humidity_high",)
    assert by_start[6].advice == "good" and by_start[6].cautions == ()
    # 72 h horizon
    assert windows[-1].start < T0 + timedelta(hours=72, minutes=30)
    assert len(windows) == 25


def test_thresholds_come_from_the_tenant_setting() -> None:
    lenient = WeatherSettings(spray_max_rain_probability_pct=50, spray_max_wind_kmh=25)
    windows = spray_windows(_fixture_hours(), lenient, now=T0)
    assert all(w.advice == "good" for w in windows)
    strict = WeatherSettings(spray_max_wind_kmh=5)  # 5 km/h calm hours reach it
    assert all(w.advice == "avoid" for w in spray_windows(_fixture_hours(), strict, now=T0))


def test_rain_amount_alone_hides_a_window() -> None:
    hours = [_hour(T0 + timedelta(hours=i), prob=10, rain=0.4) for i in range(3)]
    (window,) = spray_windows(hours, WeatherSettings(), now=T0, horizon_hours=3)
    assert window.advice == "avoid" and window.reasons == ("rain",)
    assert window.precipitation_mm == pytest.approx(1.2)


def test_past_windows_are_skipped() -> None:
    windows = spray_windows(_fixture_hours(), WeatherSettings(), now=T0 + timedelta(hours=7))
    assert windows[0].start == T0 + timedelta(hours=6)  # 12:00 window (now 13:00 IST)


# ------------------------------------------------------------------ provider
OPEN_METEO_FIXTURE = {
    "latitude": 18.0,
    "longitude": 79.6,
    "timezone": "Asia/Kolkata",
    "hourly": {
        "time": ["2026-09-21T00:00", "2026-09-21T01:00"],
        "temperature_2m": [24.1, 23.8],
        "relative_humidity_2m": [88, 90],
        "precipitation_probability": [20, 35],
        "precipitation": [0.0, 0.2],
        "wind_speed_10m": [6.5, None],
        "wind_gusts_10m": [12.0, 14.0],
    },
    "daily": {
        "time": ["2026-09-21"],
        "weather_code": [61],
        "temperature_2m_max": [31.2],
        "temperature_2m_min": [22.9],
        "precipitation_sum": [3.4],
        "precipitation_probability_max": [70],
        "wind_speed_10m_max": [18.5],
    },
}


def test_parse_open_meteo() -> None:
    forecast = parse_open_meteo(OPEN_METEO_FIXTURE, fetched_at=T0)
    assert forecast.hours[0].time == datetime(2026, 9, 21, 0, 0, tzinfo=IST)
    assert forecast.hours[1].wind_kmh is None and forecast.hours[1].precipitation_mm == 0.2
    assert forecast.days[0].date == date(2026, 9, 21)
    assert (
        forecast.days[0].weather_code == 61 and forecast.days[0].precipitation_probability_pct == 70
    )


async def test_open_meteo_call_sends_only_the_grid_cell() -> None:
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json=OPEN_METEO_FIXTURE)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    provider = OpenMeteoProvider("https://open-meteo.test", client=client, clock=lambda: T0)
    lat, lon = grid_cell(18.0234567, 79.5876543)
    forecast = await provider.forecast(lat, lon)
    assert forecast.provider == "open_meteo" and len(forecast.hours) == 2
    (request,) = seen
    assert request.url.host == "open-meteo.test" and request.url.path == "/v1/forecast"
    params = dict(request.url.params)
    assert params["latitude"] == "18.0" and params["longitude"] == "79.6"
    assert set(params) == {
        "latitude",
        "longitude",
        "hourly",
        "daily",
        "forecast_days",
        "wind_speed_unit",
        "timezone",
    }
    assert "authorization" not in {k.lower() for k in request.headers}
    await client.aclose()


async def test_open_meteo_failure_is_weather_unavailable() -> None:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _r: httpx.Response(502, text="bad gateway"))
    )
    provider = OpenMeteoProvider("https://open-meteo.test", client=client)
    with pytest.raises(WeatherUnavailableError):
        await provider.forecast(18.0, 79.6)
    await client.aclose()


async def test_cache_is_per_grid_cell_and_expires() -> None:
    ticks = [0.0]
    cache = ForecastCache(ttl_s=10_800, monotonic=lambda: ticks[0])
    provider = FakeWeatherProvider(clock=lambda: T0)
    a, cached = await cache.get(provider, 18.02, 79.58)
    assert not cached and provider.calls == [(18.0, 79.6)]
    b, cached = await cache.get(provider, 18.04, 79.61)  # same 0.1-degree cell
    assert cached and b is a and len(provider.calls) == 1
    await cache.get(provider, 18.2, 79.6)  # another cell
    assert len(provider.calls) == 2
    ticks[0] = 10_801
    _, cached = await cache.get(provider, 18.02, 79.58)
    assert not cached and len(provider.calls) == 3


def test_daily_from_hours() -> None:
    days = daily_from_hours(_fixture_hours())
    assert days[0].date == T0.date() and days[0].temperature_max_c == 37.0
    assert days[0].precipitation_probability_pct == 40


def test_grid_cell_rounds_to_a_tenth() -> None:
    assert grid_cell(17.96, 79.54) == (18.0, 79.5)
    assert grid_cell(-0.04, 0.06) == (-0.0, 0.1)


# ------------------------------------------------------------------ API
class FixtureProvider:
    name = "fixture"

    def __init__(self, hours: list[HourForecast]) -> None:
        self.hours = hours
        self.calls: list[tuple[float, float]] = []

    async def forecast(self, latitude: float, longitude: float) -> Forecast:
        self.calls.append((latitude, longitude))
        return Forecast(
            latitude=latitude,
            longitude=longitude,
            provider=self.name,
            fetched_at=datetime.now(UTC),
            days=daily_from_hours(self.hours),
            hours=tuple(self.hours),
        )


class BrokenProvider:
    name = "broken"

    async def forecast(self, latitude: float, longitude: float) -> Forecast:
        raise WeatherUnavailableError("down")


def _now_aligned_hours() -> list[HourForecast]:
    start = datetime.now(UTC).astimezone(IST).replace(minute=0, second=0, microsecond=0)
    start -= timedelta(hours=start.hour % 3)
    hours = []
    for i in range(80):
        t = start + timedelta(hours=i)
        # every other window rainy
        rainy = (i // 3) % 2 == 1
        hours.append(_hour(t, prob=60 if rainy else 5))
    return hours


async def test_farm_weather_endpoint(
    app: FastAPI,
    client: AsyncClient,
    bearer: Bearer,
    login: FarmerLogin,
    db_session: AsyncSession,
) -> None:
    provider = FixtureProvider(_now_aligned_hours())
    app.state.weather = WeatherService(provider=provider, cache=ForecastCache(ttl_s=10_800))
    resp = await client.get(f"/v1/farms/{login.farm.id}/weather", headers=bearer(login.user))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["farm_id"] == str(login.farm.id) and body["provider"] == "fixture"
    assert body["location_source"] in ("farm", "village") and body["cached"] is False
    (lat, lon) = provider.calls[0]
    assert (body["latitude"], body["longitude"]) == (lat, lon)
    assert round(lat, 1) == lat and round(lon, 1) == lon  # only the grid cell leaves
    assert len(body["daily"]) >= 3 and len(body["hourly"]) == 72
    spray = body["spray"]
    assert spray["windows"] and spray["avoided"]
    assert all(w["advice"] == "good" for w in spray["windows"])
    assert all(w["reasons"] == ["rain_likely"] for w in spray["avoided"])
    assert spray["thresholds"]["max_rain_probability_pct"] == 30
    assert spray["thresholds"]["max_wind_kmh"] == 15
    again = await client.get(f"/v1/farms/{login.farm.id}/weather", headers=bearer(login.user))
    assert again.json()["cached"] is True and len(provider.calls) == 1
    # a lenient tenant threshold shows every window
    tenant = await db_session.get_one(Tenant, login.user.tenant_id)
    tenant.settings = {**(tenant.settings or {}), "weather": {"spray_max_rain_probability_pct": 80}}
    await db_session.flush()
    lenient = await client.get(f"/v1/farms/{login.farm.id}/weather", headers=bearer(login.user))
    assert lenient.json()["spray"]["avoided"] == []


async def test_farm_weather_scope_and_outage(
    app: FastAPI, client: AsyncClient, bearer: Bearer, login: FarmerLogin, world: World
) -> None:
    other = world.b.user(UserRole.OWNER)
    resp = await client.get(f"/v1/farms/{login.farm.id}/weather", headers=bearer(other))
    assert resp.status_code == 404
    app.state.weather = WeatherService(provider=BrokenProvider(), cache=ForecastCache(ttl_s=0))
    resp = await client.get(f"/v1/farms/{login.farm.id}/weather", headers=bearer(login.user))
    assert resp.status_code == 503 and resp.json()["code"] == "weather_unavailable"


async def test_default_service_is_the_fake_in_tests(
    client: AsyncClient, bearer: Bearer, login: FarmerLogin
) -> None:
    resp = await client.get(f"/v1/farms/{login.farm.id}/weather", headers=bearer(login.user))
    assert resp.status_code == 200 and resp.json()["provider"] == "fake"
    json.dumps(resp.json())
