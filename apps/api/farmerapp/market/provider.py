"""FM-012: the ``MandiPriceProvider`` port, the public-source adapter and a fake.

The port
--------
``MandiPriceProvider.prices(state, district, commodity, since) -> tuple[PriceQuote, ...]``.
Quotes are returned exactly as published (rupees converted to paise per quintal); mapping a
commodity name to a tenant crop, deduplication and storage are the caller's job
(:mod:`farmerapp.market.service`).

The public source (human gate: key and terms)
---------------------------------------------
``DataGovInProvider`` reads the **Open Government Data (OGD) Platform India** resource

    "Current Daily Price of Various Commodities from Various Markets (Mandi)"
    resource id ``9ef84268-d588-465a-a308-a864a43d0070``
    https://data.gov.in/resource/current-daily-price-various-commodities-various-markets-mandi

published by the Directorate of Marketing & Inspection (DMI), Ministry of Agriculture &
Farmers Welfare — the same figures as **Agmarknet** (agmarknet.gov.in).

* **Terms**: the resource is published under the *Government Open Data Licence — India*
  (GODL, https://data.gov.in/government-open-data-license-india), which permits commercial
  re-use with attribution and without implying endorsement. FarmerApp attributes it on every
  screen ("Agmarknet (data.gov.in)", with the price date) and states that prices are
  indicative. The licence disclaims accuracy, which is exactly why the apps never present a
  mandi price as a FarmerApp quote.
* **Key**: ``https://api.data.gov.in`` needs a free per-account API key
  (``MANDI_API_KEY``, from Secret Manager in stg / prd). Registering the account and
  accepting the licence is a **human gate** (docs/prs/M8-market-referral-nlq.md); with no key
  the provider is ``off`` and the job does nothing.
* **What is sent**: the state, district and commodity name only — no farmer, no id, no
  coordinate (``farmerapp/privacy/egress.py``).

Request::

    GET https://api.data.gov.in/resource/9ef84268-d588-465a-a308-a864a43d0070
        ?api-key=<key>&format=json&limit=500&offset=0
        &filters[state.keyword]=Telangana&filters[district]=Warangal
        &filters[commodity]=Paddy(Dhan)(Common)

Response records carry ``state``, ``district``, ``market``, ``commodity``, ``variety``,
``grade``, ``arrival_date`` (``DD/MM/YYYY``) and ``min_price`` / ``modal_price`` /
``max_price`` in **rupees per quintal** as strings.
"""

from __future__ import annotations

import hashlib
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any, Protocol

import httpx

from farmerapp.api.errors import AppError
from farmerapp.logging import get_logger
from farmerapp.market.models import SOURCE_NAMES, SOURCE_URLS, PriceSource

log = get_logger("farmerapp.market.provider")

#: The OGD resource that carries the daily mandi prices (see the module docstring).
DATA_GOV_IN_RESOURCE = "9ef84268-d588-465a-a308-a864a43d0070"
DATA_GOV_IN_BASE_URL = "https://api.data.gov.in"
#: One call may not ask for more records than this (the platform's own cap).
MAX_PAGE = 1000


class MandiPriceUnavailableError(AppError):
    status = 503
    code = "mandi_prices_unavailable"


@dataclass(frozen=True)
class PriceQuote:
    """One published figure, already in paise per quintal."""

    state: str
    district: str
    market: str
    commodity: str
    variety: str
    grade: str
    price_date: date
    min_price_paise: int
    modal_price_paise: int
    max_price_paise: int

    @property
    def key(self) -> tuple[str, str, str, str, date]:
        return (self.market, self.commodity, self.variety, self.grade, self.price_date)


class MandiPriceProvider(Protocol):
    name: str
    #: What the apps display as the source of every row this provider returns.
    source_name: str
    source_url: str

    async def prices(
        self, *, state: str, district: str, commodity: str, since: date
    ) -> tuple[PriceQuote, ...]:
        """Published figures for one commodity in one district, not older than ``since``."""
        ...


# --------------------------------------------------------------------------- parsing
def _rupees_to_paise(value: Any) -> int | None:
    """``"2150"`` / ``"2150.50"`` rupees per quintal -> paise. ``None`` when unusable."""
    if value is None:
        return None
    text = str(value).strip().replace(",", "")
    if not text:
        return None
    try:
        rupees = float(text)
    except ValueError:
        return None
    if rupees < 0:
        return None
    return round(rupees * 100)


def _parse_date(value: Any) -> date | None:
    text = str(value or "").strip()
    for fmt in ("%d/%m/%Y", "%Y-%m-%d", "%d-%m-%Y"):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    return None


def parse_records(payload: Any, *, since: date) -> tuple[PriceQuote, ...]:
    """The ``records`` of a data.gov.in response as quotes; unusable rows are dropped."""
    records = (payload or {}).get("records") if isinstance(payload, dict) else None
    out: list[PriceQuote] = []
    for record in records or []:
        if not isinstance(record, dict):
            continue
        when = _parse_date(record.get("arrival_date") or record.get("Arrival_Date"))
        if when is None or when < since:
            continue
        low = _rupees_to_paise(record.get("min_price") or record.get("Min_Price"))
        modal = _rupees_to_paise(record.get("modal_price") or record.get("Modal_Price"))
        high = _rupees_to_paise(record.get("max_price") or record.get("Max_Price"))
        if modal is None:
            continue
        low = modal if low is None else low
        high = modal if high is None else high
        if high < low:
            low, high = high, low
        market = str(record.get("market") or record.get("Market") or "").strip()
        commodity = str(record.get("commodity") or record.get("Commodity") or "").strip()
        if not market or not commodity:
            continue
        out.append(
            PriceQuote(
                state=str(record.get("state") or record.get("State") or "").strip(),
                district=str(record.get("district") or record.get("District") or "").strip(),
                market=market[:120],
                commodity=commodity[:80],
                variety=str(record.get("variety") or record.get("Variety") or "").strip()[:80],
                grade=str(record.get("grade") or record.get("Grade") or "").strip()[:40],
                price_date=when,
                min_price_paise=low,
                modal_price_paise=modal,
                max_price_paise=high,
            )
        )
    return tuple(out)


# --------------------------------------------------------------------------- data.gov.in
class DataGovInProvider:
    """The OGD India daily mandi price resource (Agmarknet figures)."""

    name = PriceSource.AGMARKNET.value
    source_name = SOURCE_NAMES[PriceSource.AGMARKNET]
    source_url = SOURCE_URLS[PriceSource.AGMARKNET]

    def __init__(
        self,
        api_key: str,
        *,
        base_url: str = DATA_GOV_IN_BASE_URL,
        page_size: int = 500,
        timeout: float = 10.0,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._api_key = api_key
        self._url = f"{base_url.rstrip('/')}/resource/{DATA_GOV_IN_RESOURCE}"
        self._page_size = min(page_size, MAX_PAGE)
        self._timeout = timeout
        self._client = client

    def params(self, *, state: str, district: str, commodity: str) -> dict[str, str]:
        """Exactly what leaves the process (NF-011: place and commodity, nothing personal)."""
        return {
            "api-key": self._api_key,
            "format": "json",
            "limit": str(self._page_size),
            "offset": "0",
            "filters[state.keyword]": state,
            "filters[district]": district,
            "filters[commodity]": commodity,
        }

    async def prices(
        self, *, state: str, district: str, commodity: str, since: date
    ) -> tuple[PriceQuote, ...]:
        params = self.params(state=state, district=district, commodity=commodity)
        try:
            if self._client is not None:
                resp = await self._client.get(self._url, params=params, timeout=self._timeout)
            else:  # pragma: no cover - network
                async with httpx.AsyncClient(timeout=self._timeout) as client:
                    resp = await client.get(self._url, params=params)
            resp.raise_for_status()
            payload = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            log.warning("mandi_provider_failed", provider=self.name, error=type(exc).__name__)
            raise MandiPriceUnavailableError("Mandi prices are unavailable.") from exc
        return parse_records(payload, since=since)


# --------------------------------------------------------------------------- fake
class FakeMandiPriceProvider:
    """Deterministic stand-in (``MANDI_PROVIDER=fake``: tests, CI, offline development).

    Two markets per district, one quote per day for the last three days, derived from a hash
    of district and commodity so a run is reproducible. The ``source_name`` says plainly that
    this is sample data, so a fake price can never be mistaken for a published one.
    """

    name = PriceSource.FAKE.value
    source_name = SOURCE_NAMES[PriceSource.FAKE]
    source_url = SOURCE_URLS[PriceSource.FAKE]

    def __init__(
        self,
        *,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
        days: int = 3,
        markets: Sequence[str] = ("Main Yard", "New Market"),
    ) -> None:
        self._clock = clock
        self._days = days
        self._markets = tuple(markets)
        self.calls: list[tuple[str, str, str]] = []

    async def prices(
        self, *, state: str, district: str, commodity: str, since: date
    ) -> tuple[PriceQuote, ...]:
        self.calls.append((state, district, commodity))
        today = self._clock().date()
        seed = int(hashlib.sha256(f"{district}|{commodity}".encode()).hexdigest()[:6], 16)
        base = 150_000 + (seed % 120) * 1_000  # 1500 - 2700 rupees per quintal, in paise
        out: list[PriceQuote] = []
        for index, market in enumerate(self._markets):
            for day in range(self._days):
                when = today - timedelta(days=day)
                if when < since:
                    continue
                modal = base + index * 5_000 - day * 2_000
                out.append(
                    PriceQuote(
                        state=state,
                        district=district,
                        market=f"{district} {market}",
                        commodity=commodity,
                        variety="Common",
                        grade="FAQ",
                        price_date=when,
                        min_price_paise=modal - 8_000,
                        modal_price_paise=modal,
                        max_price_paise=modal + 9_000,
                    )
                )
        return tuple(out)


class DisabledMandiPriceProvider:
    """``MANDI_PROVIDER=off`` (the default until the data.gov.in key exists): no calls, no rows."""

    name = "off"
    source_name = ""
    source_url = ""

    async def prices(
        self, *, state: str, district: str, commodity: str, since: date
    ) -> tuple[PriceQuote, ...]:
        return ()


def build_provider(settings: Any) -> MandiPriceProvider:
    """The provider the API and the daily job use (``MANDI_PROVIDER``).

    ``data_gov_in`` without a key degrades to ``off`` rather than failing a process start:
    the key is a human gate (see the module docstring) and everything else must keep working
    until it lands.
    """
    choice = getattr(settings, "mandi_provider", "off")
    if choice == "fake":
        return FakeMandiPriceProvider()
    if choice == "data_gov_in":
        key = getattr(settings, "mandi_api_key", "")
        if not key:
            log.warning("mandi_provider_disabled", reason="no_api_key")
            return DisabledMandiPriceProvider()
        return DataGovInProvider(
            key,
            base_url=settings.mandi_base_url,
            page_size=settings.mandi_page_size,
            timeout=settings.mandi_timeout_s,
        )
    return DisabledMandiPriceProvider()


__all__ = [
    "DATA_GOV_IN_BASE_URL",
    "DATA_GOV_IN_RESOURCE",
    "DataGovInProvider",
    "DisabledMandiPriceProvider",
    "FakeMandiPriceProvider",
    "MandiPriceProvider",
    "MandiPriceUnavailableError",
    "PriceQuote",
    "build_provider",
    "parse_records",
]
