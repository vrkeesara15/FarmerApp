"""FM-008 weather: a ``WeatherProvider`` port, the Open-Meteo adapter, a fake, a grid-cell
cache and the spray-window advice.

Data residency / privacy: the server alone calls the provider (the apps never do), and it
sends **only the coordinates of the 0.1-degree grid cell** the farm falls in (about 11 km;
never the farm polygon, the farmer, a phone or an id). Open-Meteo needs no key and receives
nothing else. Forecasts are cached per grid cell for ``WEATHER_CACHE_TTL_SECONDS`` (3 h) per
API instance, so a village of farmers costs one call.

Spray advice (``spray_advice``): the next 72 hours in 3-hour windows aligned on IST clock
hours 00, 03, ... 21. A window is **avoid** (hidden from the farmer's list) when its highest
rain probability reaches ``weather.spray_max_rain_probability_pct`` (30 %), its rain reaches
``spray_max_rain_mm`` or its highest wind speed reaches ``spray_max_wind_kmh`` (15 km/h);
heat (``caution_max_temperature_c``) and very high / low humidity only add cautions.
"""

from __future__ import annotations

import asyncio
import math
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from typing import Any, Protocol

import httpx

from farmerapp.api.errors import AppError
from farmerapp.logging import get_logger
from farmerapp.payments.config import IST
from farmerapp.settings import Settings
from farmerapp.tenants.settings import WeatherSettings

log = get_logger("farmerapp.advisory.weather")

GRID_DEG = 0.1
WINDOW_HOURS = 3
ADVICE_HOURS = 72
FORECAST_DAYS = 7


class WeatherUnavailableError(AppError):
    status = 503
    code = "weather_unavailable"


@dataclass(frozen=True)
class HourForecast:
    time: datetime  # aware
    temperature_c: float | None
    relative_humidity_pct: int | None
    precipitation_probability_pct: int | None
    precipitation_mm: float | None
    wind_kmh: float | None
    wind_gust_kmh: float | None


@dataclass(frozen=True)
class DayForecast:
    date: date
    temperature_max_c: float | None
    temperature_min_c: float | None
    precipitation_mm: float | None
    precipitation_probability_pct: int | None
    wind_max_kmh: float | None
    weather_code: int | None


@dataclass(frozen=True)
class Forecast:
    latitude: float
    longitude: float
    provider: str
    fetched_at: datetime
    days: tuple[DayForecast, ...]
    hours: tuple[HourForecast, ...]


class WeatherProvider(Protocol):
    name: str

    async def forecast(self, latitude: float, longitude: float) -> Forecast:
        """7-day daily and hourly forecast for a point (IST day boundaries)."""
        ...


def grid_cell(latitude: float, longitude: float) -> tuple[float, float]:
    """The 0.1-degree cell centre-ish point sent to the provider (rounded coordinates)."""
    return round(round(latitude / GRID_DEG) * GRID_DEG, 1), round(
        round(longitude / GRID_DEG) * GRID_DEG, 1
    )


# --------------------------------------------------------------------------- Open-Meteo
_HOURLY = (
    "temperature_2m",
    "relative_humidity_2m",
    "precipitation_probability",
    "precipitation",
    "wind_speed_10m",
    "wind_gusts_10m",
)
_DAILY = (
    "weather_code",
    "temperature_2m_max",
    "temperature_2m_min",
    "precipitation_sum",
    "precipitation_probability_max",
    "wind_speed_10m_max",
)


def _num(values: Sequence[Any] | None, i: int) -> float | None:
    if values is None or i >= len(values) or values[i] is None:
        return None
    return float(values[i])


def _int(values: Sequence[Any] | None, i: int) -> int | None:
    value = _num(values, i)
    return None if value is None else round(value)


def parse_open_meteo(
    payload: dict[str, Any], *, provider: str = "open_meteo", fetched_at: datetime
) -> Forecast:
    """An Open-Meteo ``/v1/forecast`` response (``timezone=Asia/Kolkata``) as a Forecast."""
    hourly, daily = payload.get("hourly") or {}, payload.get("daily") or {}
    hours = tuple(
        HourForecast(
            time=datetime.fromisoformat(stamp).replace(tzinfo=IST),
            temperature_c=_num(hourly.get("temperature_2m"), i),
            relative_humidity_pct=_int(hourly.get("relative_humidity_2m"), i),
            precipitation_probability_pct=_int(hourly.get("precipitation_probability"), i),
            precipitation_mm=_num(hourly.get("precipitation"), i),
            wind_kmh=_num(hourly.get("wind_speed_10m"), i),
            wind_gust_kmh=_num(hourly.get("wind_gusts_10m"), i),
        )
        for i, stamp in enumerate(hourly.get("time") or [])
    )
    days = tuple(
        DayForecast(
            date=date.fromisoformat(stamp),
            temperature_max_c=_num(daily.get("temperature_2m_max"), i),
            temperature_min_c=_num(daily.get("temperature_2m_min"), i),
            precipitation_mm=_num(daily.get("precipitation_sum"), i),
            precipitation_probability_pct=_int(daily.get("precipitation_probability_max"), i),
            wind_max_kmh=_num(daily.get("wind_speed_10m_max"), i),
            weather_code=_int(daily.get("weather_code"), i),
        )
        for i, stamp in enumerate(daily.get("time") or [])
    )
    return Forecast(
        latitude=float(payload.get("latitude", 0.0)),
        longitude=float(payload.get("longitude", 0.0)),
        provider=provider,
        fetched_at=fetched_at,
        days=days,
        hours=hours,
    )


class OpenMeteoProvider:
    """Open-Meteo forecast API (free, no key). Only ``latitude`` / ``longitude`` (already
    rounded to the grid cell by the caller) and the variable lists are sent."""

    name = "open_meteo"

    def __init__(
        self,
        base_url: str = "https://api.open-meteo.com",
        *,
        timeout: float = 8.0,
        client: httpx.AsyncClient | None = None,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        self._url = base_url.rstrip("/") + "/v1/forecast"
        self._timeout = timeout
        self._client = client
        self._clock = clock

    def params(self, latitude: float, longitude: float) -> dict[str, str]:
        return {
            "latitude": f"{latitude:.1f}",
            "longitude": f"{longitude:.1f}",
            "hourly": ",".join(_HOURLY),
            "daily": ",".join(_DAILY),
            "forecast_days": str(FORECAST_DAYS),
            "wind_speed_unit": "kmh",
            "timezone": "Asia/Kolkata",
        }

    async def forecast(self, latitude: float, longitude: float) -> Forecast:
        params = self.params(latitude, longitude)
        try:
            if self._client is not None:
                resp = await self._client.get(self._url, params=params, timeout=self._timeout)
            else:  # pragma: no cover - network
                async with httpx.AsyncClient(timeout=self._timeout) as client:
                    resp = await client.get(self._url, params=params)
            resp.raise_for_status()
            payload = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            log.warning("weather_provider_failed", provider=self.name, error=type(exc).__name__)
            raise WeatherUnavailableError("The weather forecast is unavailable.") from exc
        return parse_open_meteo(payload, provider=self.name, fetched_at=self._clock())


class FakeWeatherProvider:
    """Deterministic forecast derived from the coordinates and the clock (tests, offline dev):
    dry mornings, a wet and windy afternoon every third day."""

    name = "fake"

    def __init__(self, clock: Callable[[], datetime] = lambda: datetime.now(UTC)) -> None:
        self._clock = clock
        self.calls: list[tuple[float, float]] = []

    async def forecast(self, latitude: float, longitude: float) -> Forecast:
        self.calls.append((latitude, longitude))
        now = self._clock()
        start = datetime.combine(now.astimezone(IST).date(), datetime.min.time(), tzinfo=IST)
        seed = abs(math.sin(latitude * 12.9898 + longitude * 78.233))
        hours: list[HourForecast] = []
        for i in range(FORECAST_DAYS * 24):
            t = start + timedelta(hours=i)
            wet = (t.day % 3 == 0) and 13 <= t.hour < 19
            hours.append(
                HourForecast(
                    time=t,
                    temperature_c=round(24 + 8 * math.sin((t.hour - 9) / 24 * 2 * math.pi), 1),
                    relative_humidity_pct=round(60 + 25 * math.cos(t.hour / 24 * 2 * math.pi)),
                    precipitation_probability_pct=70 if wet else round(5 + 10 * seed),
                    precipitation_mm=2.0 if wet else 0.0,
                    wind_kmh=18.0 if wet else round(6 + 4 * seed, 1),
                    wind_gust_kmh=28.0 if wet else 12.0,
                )
            )
        return Forecast(
            latitude=latitude,
            longitude=longitude,
            provider=self.name,
            fetched_at=now,
            days=daily_from_hours(hours),
            hours=tuple(hours),
        )


def daily_from_hours(hours: Sequence[HourForecast]) -> tuple[DayForecast, ...]:
    by_day: dict[date, list[HourForecast]] = {}
    for h in hours:
        by_day.setdefault(h.time.astimezone(IST).date(), []).append(h)
    out: list[DayForecast] = []
    for day, items in sorted(by_day.items()):
        temps = [h.temperature_c for h in items if h.temperature_c is not None]
        probs = [
            h.precipitation_probability_pct
            for h in items
            if h.precipitation_probability_pct is not None
        ]
        winds = [h.wind_kmh for h in items if h.wind_kmh is not None]
        out.append(
            DayForecast(
                date=day,
                temperature_max_c=max(temps) if temps else None,
                temperature_min_c=min(temps) if temps else None,
                precipitation_mm=round(sum(h.precipitation_mm or 0.0 for h in items), 1),
                precipitation_probability_pct=max(probs) if probs else None,
                wind_max_kmh=max(winds) if winds else None,
                weather_code=None,
            )
        )
    return tuple(out)


# --------------------------------------------------------------------------- cache
@dataclass
class _Entry:
    forecast: Forecast
    stored: float


@dataclass
class ForecastCache:
    """Per-instance TTL cache keyed by (provider, grid cell)."""

    ttl_s: float
    monotonic: Callable[[], float] = time.monotonic
    max_entries: int = 5000
    _entries: dict[tuple[str, float, float], _Entry] = field(default_factory=dict)
    _locks: dict[tuple[str, float, float], asyncio.Lock] = field(default_factory=dict)

    async def get(
        self, provider: WeatherProvider, latitude: float, longitude: float
    ) -> tuple[Forecast, bool]:
        lat, lon = grid_cell(latitude, longitude)
        key = (provider.name, lat, lon)
        lock = self._locks.setdefault(key, asyncio.Lock())
        async with lock:
            entry = self._entries.get(key)
            if entry is not None and self.monotonic() - entry.stored < self.ttl_s:
                return entry.forecast, True
            forecast = await provider.forecast(lat, lon)
            if len(self._entries) >= self.max_entries:
                oldest = min(self._entries, key=lambda k: self._entries[k].stored)
                self._entries.pop(oldest, None)
                self._locks.pop(oldest, None)
            self._entries[key] = _Entry(forecast=forecast, stored=self.monotonic())
            return forecast, False


@dataclass
class WeatherService:
    provider: WeatherProvider
    cache: ForecastCache


def build_weather_service(settings: Settings) -> WeatherService:
    provider: WeatherProvider
    if settings.weather_provider == "fake":
        provider = FakeWeatherProvider()
    else:
        provider = OpenMeteoProvider(settings.weather_base_url, timeout=settings.weather_timeout_s)
    return WeatherService(
        provider=provider, cache=ForecastCache(settings.weather_cache_ttl_seconds)
    )


# --------------------------------------------------------------------------- spray advice
@dataclass(frozen=True)
class SprayWindow:
    start: datetime
    end: datetime
    advice: str  # good | avoid
    reasons: tuple[str, ...]
    cautions: tuple[str, ...]
    max_precipitation_probability_pct: int | None
    precipitation_mm: float | None
    max_wind_kmh: float | None
    max_temperature_c: float | None
    min_relative_humidity_pct: int | None
    max_relative_humidity_pct: int | None


def _max(values: Sequence[float | int | None]) -> Any:
    present = [v for v in values if v is not None]
    return max(present) if present else None


def _min(values: Sequence[float | int | None]) -> Any:
    present = [v for v in values if v is not None]
    return min(present) if present else None


def spray_windows(
    hours: Sequence[HourForecast],
    thresholds: WeatherSettings,
    *,
    now: datetime,
    horizon_hours: int = ADVICE_HOURS,
) -> list[SprayWindow]:
    """Every 3-hour window from the current one to ``now + horizon`` with its advice."""
    local = now.astimezone(IST)
    first = local.replace(minute=0, second=0, microsecond=0) - timedelta(
        hours=local.hour % WINDOW_HOURS
    )
    until = now + timedelta(hours=horizon_hours)
    out: list[SprayWindow] = []
    start = first
    while start < until:
        end = start + timedelta(hours=WINDOW_HOURS)
        items = [h for h in hours if start <= h.time < end]
        start_next = end
        if not items or end <= now:
            start = start_next
            continue
        prob = _max([h.precipitation_probability_pct for h in items])
        rain = round(sum(h.precipitation_mm or 0.0 for h in items), 1)
        wind = _max([h.wind_kmh for h in items])
        temp = _max([h.temperature_c for h in items])
        rh_min = _min([h.relative_humidity_pct for h in items])
        rh_max = _max([h.relative_humidity_pct for h in items])
        reasons: list[str] = []
        if prob is not None and prob >= thresholds.spray_max_rain_probability_pct:
            reasons.append("rain_likely")
        if rain > 0 and rain >= thresholds.spray_max_rain_mm:
            reasons.append("rain")
        if wind is not None and wind >= thresholds.spray_max_wind_kmh:
            reasons.append("wind_high")
        cautions: list[str] = []
        if temp is not None and temp >= thresholds.caution_max_temperature_c:
            cautions.append("heat")
        if rh_max is not None and rh_max >= thresholds.caution_max_humidity_pct:
            cautions.append("humidity_high")
        if rh_min is not None and rh_min <= thresholds.caution_min_humidity_pct:
            cautions.append("humidity_low")
        out.append(
            SprayWindow(
                start=start,
                end=end,
                advice="avoid" if reasons else "good",
                reasons=tuple(reasons),
                cautions=tuple(cautions),
                max_precipitation_probability_pct=prob,
                precipitation_mm=rain,
                max_wind_kmh=wind,
                max_temperature_c=temp,
                min_relative_humidity_pct=rh_min,
                max_relative_humidity_pct=rh_max,
            )
        )
        start = start_next
    return out


__all__ = [
    "ADVICE_HOURS",
    "GRID_DEG",
    "DayForecast",
    "FakeWeatherProvider",
    "Forecast",
    "ForecastCache",
    "HourForecast",
    "OpenMeteoProvider",
    "SprayWindow",
    "WeatherProvider",
    "WeatherService",
    "WeatherUnavailableError",
    "build_weather_service",
    "daily_from_hours",
    "grid_cell",
    "parse_open_meteo",
    "spray_windows",
]
