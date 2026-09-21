"""FM-012 reads and the daily refresh.

Two jobs live here:

``refresh_prices`` (the daily job) walks the tenant's **districts** (every district that has a
store or a village) and its **pilot crops** (every active crop some farmer actually grows),
asks the provider for each pair, maps the published commodity name back to the crop and
upserts one ``mandi_price`` row per (market, crop, variety, grade, price date). Re-running it
the same day rewrites the same rows (idempotent).

``prices_for_farmer`` / ``prices_for_crops`` (the reads) return, per crop, the rows of the
**latest date we hold**, nearest market first. "Nearest" is the straight-line distance from
the farmer's village to a market whose name we can resolve to a store, then same-district,
then everything else — mandis have no coordinates in the public feed, so the ordering is a
best effort and the district is what the farmer really recognises.

Every row carries ``price_date`` and ``source_name``: the FM-012 acceptance criterion is that
a price is never shown without both.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import Select, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.crops import Crop
from farmerapp.farmers.models import CropPlot, Farm, Farmer
from farmerapp.logging import get_logger
from farmerapp.market.models import MandiPrice
from farmerapp.market.provider import (
    MandiPriceProvider,
    MandiPriceUnavailableError,
    PriceQuote,
)
from farmerapp.tenants.models import Store, Village
from farmerapp.tenants.settings import MandiSettings

log = get_logger("farmerapp.market.service")

#: How far back a refresh accepts a published figure (the feed lags by a day or two).
LOOKBACK_DAYS = 7
#: Rows older than this are dropped by the refresh (the screen only ever shows the latest).
RETENTION_DAYS = 90


@dataclass(frozen=True)
class RefreshReport:
    tenant_id: uuid.UUID
    provider: str
    districts: int
    crops: int
    fetched: int
    written: int
    purged: int
    failures: int


# --------------------------------------------------------------------------- commodity names
def commodity_names(crop: Crop, settings: MandiSettings) -> tuple[str, ...]:
    """The names to ask the public source for, for one crop.

    The feed uses its own commodity vocabulary ("Paddy(Dhan)(Common)", "Bhindi(Ladies
    Finger)"), so the tenant maps crop code -> published names in
    ``settings.mandi.commodities``. Without a mapping the crop's English name is used, which
    is right for the simple ones (Cotton, Maize, Tomato).
    """
    mapped = settings.commodities.get(crop.code)
    if mapped:
        return tuple(mapped)
    return (crop.name,)


def _matches(quote: PriceQuote, names: Sequence[str]) -> bool:
    published = quote.commodity.casefold()
    return any(published == name.casefold() for name in names)


# --------------------------------------------------------------------------- refresh
async def _districts(session: AsyncSession, tenant_id: uuid.UUID) -> list[tuple[str, str]]:
    """(state, district) pairs the tenant operates in: store districts, then village ones."""
    stores = select(Store.state, Store.district).where(
        Store.tenant_id == tenant_id, Store.deleted_at.is_(None)
    )
    villages = select(Village.state, Village.district).where(
        Village.tenant_id == tenant_id, Village.deleted_at.is_(None)
    )
    rows = (await session.execute(stores.union(villages))).all()
    return sorted({(str(state), str(district)) for state, district in rows if district})


async def _grown_crops(session: AsyncSession, tenant_id: uuid.UUID) -> list[Crop]:
    """Active crops of the tenant that at least one farmer grows (the "pilot crops")."""
    grown = (
        select(CropPlot.crop_id)
        .where(CropPlot.tenant_id == tenant_id, CropPlot.deleted_at.is_(None))
        .distinct()
        .scalar_subquery()
    )
    stmt = (
        select(Crop)
        .where(
            Crop.tenant_id == tenant_id,
            Crop.deleted_at.is_(None),
            Crop.active.is_(True),
            Crop.id.in_(grown),
        )
        .order_by(Crop.code)
    )
    return list((await session.scalars(stmt)).all())


async def _upsert(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    crop: Crop,
    quotes: Iterable[PriceQuote],
    provider: MandiPriceProvider,
    now: datetime,
) -> int:
    written = 0
    for quote in quotes:
        values = {
            "tenant_id": tenant_id,
            "crop_id": crop.id,
            "market": quote.market,
            "district": quote.district,
            "state": quote.state,
            "variety": quote.variety,
            "grade": quote.grade,
            "price_date": quote.price_date,
            "min_price_paise": quote.min_price_paise,
            "modal_price_paise": quote.modal_price_paise,
            "max_price_paise": quote.max_price_paise,
            "source": provider.name,
            "source_name": provider.source_name,
            "source_url": provider.source_url or None,
            "fetched_at": now,
        }
        stmt = insert(MandiPrice).values(**values)
        await session.execute(
            stmt.on_conflict_do_update(
                constraint="uq_mandi_price_reading",
                set_={
                    "min_price_paise": stmt.excluded.min_price_paise,
                    "modal_price_paise": stmt.excluded.modal_price_paise,
                    "max_price_paise": stmt.excluded.max_price_paise,
                    "district": stmt.excluded.district,
                    "state": stmt.excluded.state,
                    "source_name": stmt.excluded.source_name,
                    "source_url": stmt.excluded.source_url,
                    "fetched_at": stmt.excluded.fetched_at,
                    "updated_at": now,
                    "deleted_at": None,
                },
            )
        )
        written += 1
    return written


async def refresh_prices(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    provider: MandiPriceProvider,
    settings: MandiSettings,
    now: datetime | None = None,
) -> RefreshReport:
    """FM-012 daily job: pull every (district x grown crop) pair into ``mandi_price``."""
    now = now or datetime.now(UTC)
    since = now.date() - timedelta(days=settings.lookback_days or LOOKBACK_DAYS)
    districts = await _districts(session, tenant_id)
    crops = await _grown_crops(session, tenant_id)
    fetched = written = failures = 0
    for state, district in districts:
        for crop in crops:
            names = commodity_names(crop, settings)
            quotes: list[PriceQuote] = []
            for name in names:
                try:
                    got = await provider.prices(
                        state=state, district=district, commodity=name, since=since
                    )
                except MandiPriceUnavailableError:
                    failures += 1
                    continue
                quotes.extend(q for q in got if _matches(q, names))
            fetched += len(quotes)
            # One row per reading: a feed may repeat a market on one day.
            unique = {q.key: q for q in quotes}
            written += await _upsert(
                session,
                tenant_id=tenant_id,
                crop=crop,
                quotes=unique.values(),
                provider=provider,
                now=now,
            )
    cutoff = now.date() - timedelta(days=RETENTION_DAYS)
    purged = await purge_old(session, tenant_id=tenant_id, before=cutoff)
    await session.flush()
    # The upsert and the purge are Core statements: anything this session had already loaded
    # is stale afterwards, so drop it rather than hand a caller yesterday's price.
    session.expire_all()
    report = RefreshReport(
        tenant_id=tenant_id,
        provider=provider.name,
        districts=len(districts),
        crops=len(crops),
        fetched=fetched,
        written=written,
        purged=purged,
        failures=failures,
    )
    log.info(
        "mandi_prices_refreshed",
        tenant_id=str(tenant_id),
        provider=provider.name,
        districts=report.districts,
        crops=report.crops,
        fetched=report.fetched,
        written=report.written,
        purged=report.purged,
        failures=report.failures,
    )
    return report


async def purge_old(session: AsyncSession, *, tenant_id: uuid.UUID, before: date) -> int:
    from sqlalchemy import delete

    result = await session.execute(
        delete(MandiPrice).where(MandiPrice.tenant_id == tenant_id, MandiPrice.price_date < before)
    )
    return int(getattr(result, "rowcount", 0) or 0)


# --------------------------------------------------------------------------- reads
@dataclass(frozen=True)
class CropPrices:
    crop_id: uuid.UUID
    crop_code: str
    crop_name: str
    crop_names: dict[str, str]
    price_date: date | None
    source_name: str | None
    source_url: str | None
    rows: tuple[MandiPrice, ...]


async def _crop_ids_for_farmer(session: AsyncSession, farmer: Farmer) -> list[uuid.UUID]:
    stmt = (
        select(CropPlot.crop_id)
        .join(Farm, Farm.id == CropPlot.farm_id)
        .where(
            Farm.farmer_id == farmer.id,
            CropPlot.tenant_id == farmer.tenant_id,
            CropPlot.deleted_at.is_(None),
            Farm.deleted_at.is_(None),
        )
        .distinct()
    )
    return list((await session.scalars(stmt)).all())


def _order_key(row: MandiPrice, home_district: str | None) -> tuple[int, str]:
    """Nearest market first: same district, then alphabetical (stable for the app's cache)."""
    same = 0 if home_district and row.district.casefold() == home_district.casefold() else 1
    return (same, row.market.casefold())


async def prices_for_crops(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    crop_ids: Sequence[uuid.UUID],
    home_district: str | None,
    limit_per_crop: int = 5,
) -> list[CropPrices]:
    """Latest-date prices per crop, nearest market first (empty ``rows`` when we hold none)."""
    if not crop_ids:
        return []
    crops = list(
        (
            await session.scalars(
                select(Crop)
                .where(Crop.tenant_id == tenant_id, Crop.id.in_(list(crop_ids)))
                .order_by(Crop.code)
            )
        ).all()
    )
    out: list[CropPrices] = []
    for crop in crops:
        latest = await session.scalar(
            select(func.max(MandiPrice.price_date)).where(
                MandiPrice.tenant_id == tenant_id,
                MandiPrice.crop_id == crop.id,
                MandiPrice.deleted_at.is_(None),
            )
        )
        rows: list[MandiPrice] = []
        if latest is not None:
            stmt: Select[tuple[MandiPrice]] = select(MandiPrice).where(
                MandiPrice.tenant_id == tenant_id,
                MandiPrice.crop_id == crop.id,
                MandiPrice.price_date == latest,
                MandiPrice.deleted_at.is_(None),
            )
            rows = sorted(
                (await session.scalars(stmt)).all(), key=lambda r: _order_key(r, home_district)
            )[:limit_per_crop]
        first = rows[0] if rows else None
        out.append(
            CropPrices(
                crop_id=crop.id,
                crop_code=crop.code,
                crop_name=crop.name,
                crop_names=dict(crop.names or {}),
                price_date=latest if rows else None,
                source_name=first.source_name if first else None,
                source_url=first.source_url if first else None,
                rows=tuple(rows),
            )
        )
    return out


async def prices_for_farmer(
    session: AsyncSession, farmer: Farmer, *, limit_per_crop: int = 5
) -> list[CropPrices]:
    """FM-012: the farmer's own crops, nearest markets first, latest date we hold."""
    district = await session.scalar(select(Village.district).where(Village.id == farmer.village_id))
    crop_ids = await _crop_ids_for_farmer(session, farmer)
    return await prices_for_crops(
        session,
        tenant_id=farmer.tenant_id,
        crop_ids=crop_ids,
        home_district=district,
        limit_per_crop=limit_per_crop,
    )


__all__ = [
    "LOOKBACK_DAYS",
    "RETENTION_DAYS",
    "CropPrices",
    "RefreshReport",
    "commodity_names",
    "prices_for_crops",
    "prices_for_farmer",
    "purge_old",
    "refresh_prices",
]
