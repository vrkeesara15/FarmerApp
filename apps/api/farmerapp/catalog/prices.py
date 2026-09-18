"""Price-list maintenance (WC-005 "price lists by store").

``upsert_price_list`` applies a batch for one store (or the tenant default, ``store_id``
NULL), all or nothing:

* a row is matched by ``(sku, store, effective_from)`` and updated (price, ``effective_to``),
  otherwise inserted;
* every price must be <= the SKU's MRP (``422 price_above_mrp``);
* after the batch, no two live rows of the same SKU and store may have overlapping effective
  ranges (``409 price_overlap``). The check runs on the *resulting* set, so closing an open
  row and opening the next one in the same batch is fine. The ``price_list`` exclusion
  constraint (0014) is the database backstop.

Both errors carry ``rows: [{index, sku_id, code, conflicting_id?}]`` so the console marks the
offending lines. ``farmerapp.catalog.pricing`` resolves the price that applies on a day.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date
from typing import Any

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError
from farmerapp.auth.models import User
from farmerapp.catalog.errors import PriceAboveMrpError, PriceOverlapError
from farmerapp.catalog.models import PriceList, Sku
from farmerapp.catalog.write_schemas import PriceListOut, PriceListPut
from farmerapp.tenants.models import Store


@dataclass
class _Range:
    index: int | None  # position in the request (None = existing row left untouched)
    id: uuid.UUID | None
    sku_id: uuid.UUID
    effective_from: date
    effective_to: date | None


def overlaps(a_from: date, a_to: date | None, b_from: date, b_to: date | None) -> bool:
    """Closed ranges; ``None`` = open ended."""
    return (b_to is None or a_from <= b_to) and (a_to is None or b_from <= a_to)


def price_out(row: PriceList, mrp_paise: int) -> PriceListOut:
    return PriceListOut(
        id=row.id,
        sku_id=row.sku_id,
        store_id=row.store_id,
        price_paise=row.price_paise,
        effective_from=row.effective_from,
        effective_to=row.effective_to,
        mrp_paise=mrp_paise,
        version=row.version,
    )


async def store_or_404(session: AsyncSession, tenant_id: uuid.UUID, store_id: uuid.UUID) -> Store:
    store = await session.scalar(
        select(Store).where(
            Store.id == store_id, Store.tenant_id == tenant_id, Store.deleted_at.is_(None)
        )
    )
    if store is None:
        raise NotFoundError("Store not found.")
    return store


async def list_prices(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    store_id: uuid.UUID | None,
    at: date | None,
    sku_id: uuid.UUID | None,
) -> list[PriceListOut]:
    stmt = (
        select(PriceList, Sku.mrp_paise)
        .join(Sku, Sku.id == PriceList.sku_id)
        .where(PriceList.tenant_id == tenant_id, PriceList.deleted_at.is_(None))
    )
    if store_id is None:
        stmt = stmt.where(PriceList.store_id.is_(None))
    else:
        stmt = stmt.where(PriceList.store_id == store_id)
    if at is not None:
        stmt = stmt.where(
            PriceList.effective_from <= at,
            or_(PriceList.effective_to.is_(None), PriceList.effective_to >= at),
        )
    if sku_id is not None:
        stmt = stmt.where(PriceList.sku_id == sku_id)
    stmt = stmt.order_by(PriceList.sku_id, PriceList.effective_from.desc(), PriceList.id)
    return [price_out(row, mrp) for row, mrp in (await session.execute(stmt)).tuples()]


async def upsert_price_list(
    session: AsyncSession, actor: User, body: PriceListPut
) -> list[PriceListOut]:
    tenant_id = actor.tenant_id
    if body.store_id is not None:
        await store_or_404(session, tenant_id, body.store_id)
    sku_ids = {item.sku_id for item in body.items}
    skus = {
        s.id: s
        for s in (
            await session.execute(
                select(Sku).where(
                    Sku.id.in_(sku_ids), Sku.tenant_id == tenant_id, Sku.deleted_at.is_(None)
                )
            )
        ).scalars()
    }
    missing = sku_ids - set(skus)
    if missing:
        raise NotFoundError("SKU not found.", extra={"sku_ids": sorted(str(m) for m in missing)})

    above: list[dict[str, Any]] = [
        {"index": i, "sku_id": str(item.sku_id), "code": "price_above_mrp"}
        for i, item in enumerate(body.items)
        if item.price_paise > skus[item.sku_id].mrp_paise
    ]
    if above:
        raise PriceAboveMrpError(
            "A price may not exceed the SKU's MRP.",
            extra={"rows": above},
        )

    store_clause = (
        PriceList.store_id.is_(None)
        if body.store_id is None
        else PriceList.store_id == body.store_id
    )
    existing = (
        (
            await session.execute(
                select(PriceList).where(
                    PriceList.tenant_id == tenant_id,
                    PriceList.sku_id.in_(sku_ids),
                    PriceList.deleted_at.is_(None),
                    store_clause,
                )
            )
        )
        .scalars()
        .all()
    )
    by_key = {(r.sku_id, r.effective_from): r for r in existing}

    # The resulting ranges per SKU: untouched existing rows + the batch (which may replace
    # an existing row with the same effective_from).
    touched: set[tuple[uuid.UUID, date]] = set()
    ranges: dict[uuid.UUID, list[_Range]] = {}
    for i, item in enumerate(body.items):
        key = (item.sku_id, item.effective_from)
        row = by_key.get(key)
        ranges.setdefault(item.sku_id, []).append(
            _Range(i, row.id if row else None, item.sku_id, item.effective_from, item.effective_to)
        )
        touched.add(key)
    for row in existing:
        if (row.sku_id, row.effective_from) not in touched:
            ranges.setdefault(row.sku_id, []).append(
                _Range(None, row.id, row.sku_id, row.effective_from, row.effective_to)
            )

    conflicts: list[dict[str, Any]] = []
    for group in ranges.values():
        for a_pos, a in enumerate(group):
            if a.index is None:
                continue
            for b_pos, b in enumerate(group):
                if a_pos == b_pos:
                    continue
                if overlaps(a.effective_from, a.effective_to, b.effective_from, b.effective_to):
                    entry: dict[str, Any] = {
                        "index": a.index,
                        "sku_id": str(a.sku_id),
                        "code": "price_overlap",
                    }
                    if b.id is not None:
                        entry["conflicting_id"] = str(b.id)
                    elif b.index is not None:
                        entry["conflicting_index"] = b.index
                    conflicts.append(entry)
                    break
    if conflicts:
        raise PriceOverlapError(
            "Effective ranges of one SKU and store may not overlap.",
            extra={"rows": conflicts},
        )

    # Updates first (they may shorten a range), then inserts, so the exclusion constraint
    # never sees an intermediate overlap.
    written: list[PriceList] = []
    seen: set[tuple[uuid.UUID, date]] = set()
    inserts: list[PriceList] = []
    for item in body.items:
        key = (item.sku_id, item.effective_from)
        if key in seen:  # same key twice in one batch: the overlap check caught it already
            continue
        seen.add(key)
        row = by_key.get(key)
        if row is not None:
            if row.price_paise != item.price_paise:
                row.price_paise = item.price_paise
            if row.effective_to != item.effective_to:
                row.effective_to = item.effective_to
            written.append(row)
        else:
            new = PriceList(
                tenant_id=tenant_id,
                store_id=body.store_id,
                sku_id=item.sku_id,
                price_paise=item.price_paise,
                effective_from=item.effective_from,
                effective_to=item.effective_to,
            )
            inserts.append(new)
            written.append(new)
    await session.flush()
    session.add_all(inserts)
    await session.flush()
    for row in written:
        await session.refresh(row)
    return [price_out(row, skus[row.sku_id].mrp_paise) for row in written]


__all__ = ["list_prices", "overlaps", "price_out", "store_or_404", "upsert_price_list"]
