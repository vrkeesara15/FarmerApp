"""Price resolution (WC-005 "price lists by store"; FA-020 / ST-001 unit prices).

``price_for(session, sku, store, at)`` picks, among the ``price_list`` rows of the SKU that
are in force on ``at`` (``effective_from <= at`` and ``effective_to`` NULL or ``>= at``):

1. the store's own row (``store_id = store``), latest ``effective_from`` first;
2. else the tenant default (``store_id`` NULL), latest first;
3. else ``None`` — callers fall back to ``sku.mrp_paise`` (``resolved_price``).

``resolve`` is the pure-Python rule over loaded rows so the seed, the REST list (one query
for a page of SKUs) and the unit tests share it; ``prices_for`` batches it for many SKUs.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Sequence
from datetime import date
from typing import Protocol

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.models import PriceList


class PriceRow(Protocol):
    sku_id: uuid.UUID
    store_id: uuid.UUID | None
    price_paise: int
    effective_from: date
    effective_to: date | None


def in_force(row: PriceRow, at: date) -> bool:
    return row.effective_from <= at and (row.effective_to is None or row.effective_to >= at)


def resolve(rows: Iterable[PriceRow], store_id: uuid.UUID | None, at: date) -> int | None:
    """The price in paise for one SKU from its rows, or ``None`` when nothing applies."""
    store_rows = [r for r in rows if in_force(r, at)]
    own = [r for r in store_rows if store_id is not None and r.store_id == store_id]
    default = [r for r in store_rows if r.store_id is None]
    for candidates in (own, default):
        if candidates:
            best = max(candidates, key=lambda r: r.effective_from)
            return int(best.price_paise)
    return None


async def prices_for(
    session: AsyncSession,
    sku_ids: Sequence[uuid.UUID],
    store_id: uuid.UUID | None,
    at: date,
) -> dict[uuid.UUID, int]:
    """``sku_id -> price_paise`` for the SKUs that have a price in force (others absent)."""
    if not sku_ids:
        return {}
    stmt = select(PriceList).where(
        PriceList.sku_id.in_(list(sku_ids)),
        PriceList.deleted_at.is_(None),
        PriceList.effective_from <= at,
        or_(PriceList.effective_to.is_(None), PriceList.effective_to >= at),
    )
    if store_id is None:
        stmt = stmt.where(PriceList.store_id.is_(None))
    else:
        stmt = stmt.where(or_(PriceList.store_id.is_(None), PriceList.store_id == store_id))
    by_sku: dict[uuid.UUID, list[PriceList]] = {}
    for row in (await session.execute(stmt)).scalars():
        by_sku.setdefault(row.sku_id, []).append(row)
    out: dict[uuid.UUID, int] = {}
    for sku_id, rows in by_sku.items():
        price = resolve(rows, store_id, at)
        if price is not None:
            out[sku_id] = price
    return out


async def price_for(
    session: AsyncSession, sku_id: uuid.UUID, store_id: uuid.UUID | None, at: date
) -> int | None:
    """The selling price of ``sku_id`` at ``store_id`` on ``at`` (``None`` = no price list)."""
    return (await prices_for(session, [sku_id], store_id, at)).get(sku_id)


def resolved_price(price: int | None, mrp_paise: int) -> int:
    """What the customer pays: the price list, else the MRP."""
    return mrp_paise if price is None else price


__all__ = ["PriceRow", "in_force", "price_for", "prices_for", "resolve", "resolved_price"]
