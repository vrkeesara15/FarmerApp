"""Stock ledger helpers (ST-003): stock on hand is the sum of movements; the batch quantity
is a cache written in the same transaction.

``apply_movement`` is the only way a write path should touch stock: it appends the
``stock_movement`` row *and* adjusts ``stock_batch.qty`` together, refusing to take a batch
below zero (``InsufficientStockError``). ``stock_on_hand`` / ``stock_on_hand_by_sku`` /
``stock_on_hand_by_batch`` read the ledger, never the cache, so a test can prove the two
agree (``tests/orders/test_models.py``).
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import datetime
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError
from farmerapp.stock.models import (
    INBOUND_KINDS,
    OUTBOUND_KINDS,
    QTY_SCALE,
    MovementKind,
    ReservationStatus,
    StockBatch,
    StockMovement,
    StockReservation,
)


class InsufficientStockError(AppError):
    status = 409
    code = "insufficient_stock"


class InvalidMovementError(AppError):
    status = 422
    code = "invalid_stock_movement"


def _quantize(qty: Decimal) -> Decimal:
    return Decimal(qty).quantize(QTY_SCALE)


def check_sign(kind: MovementKind, qty: Decimal) -> None:
    """The CHECK constraint's rule, raised as a problem before the database sees it."""
    if qty == 0:
        raise InvalidMovementError("A stock movement needs a non-zero quantity.")
    if kind in INBOUND_KINDS and qty < 0:
        raise InvalidMovementError(f"A {kind} movement must be positive.")
    if kind in OUTBOUND_KINDS and qty > 0:
        raise InvalidMovementError(f"A {kind} movement must be negative.")


async def apply_movement(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    store_id: uuid.UUID,
    sku_id: uuid.UUID,
    kind: MovementKind,
    qty: Decimal,
    batch: StockBatch | None = None,
    ref_type: str | None = None,
    ref_id: uuid.UUID | None = None,
    note: str | None = None,
    created_by: uuid.UUID | None = None,
    at: datetime | None = None,
    reason: str | None = None,
    photo_uri: str | None = None,
) -> StockMovement:
    """Append a movement and update the batch cache in the same flush.

    ``batch`` must belong to ``store_id`` / ``sku_id``; a batch never goes negative.
    """
    qty = _quantize(qty)
    check_sign(kind, qty)
    if batch is not None:
        if batch.store_id != store_id or batch.sku_id != sku_id:
            raise InvalidMovementError("The batch belongs to another store or SKU.")
        new_qty = _quantize(batch.qty + qty)
        if new_qty < 0:
            raise InsufficientStockError(
                f"Batch {batch.batch_no} has {batch.qty} on hand; cannot move {qty}."
            )
        batch.qty = new_qty
    movement = StockMovement(
        tenant_id=tenant_id,
        store_id=store_id,
        sku_id=sku_id,
        batch_id=batch.id if batch is not None else None,
        kind=kind,
        qty=qty,
        ref_type=ref_type,
        ref_id=ref_id,
        note=note,
        created_by=created_by,
        reason=reason,
        photo_uri=photo_uri,
        **({"created_at": at} if at is not None else {}),
    )
    session.add(movement)
    await session.flush()
    return movement


async def stock_on_hand(session: AsyncSession, store_id: uuid.UUID, sku_id: uuid.UUID) -> Decimal:
    """``sum(qty)`` of the ledger for one SKU in one store (ST-003 acceptance)."""
    total = await session.scalar(
        select(func.coalesce(func.sum(StockMovement.qty), 0)).where(
            StockMovement.store_id == store_id, StockMovement.sku_id == sku_id
        )
    )
    return _quantize(Decimal(total or 0))


async def stock_on_hand_by_sku(
    session: AsyncSession, store_id: uuid.UUID, sku_ids: Sequence[uuid.UUID] | None = None
) -> dict[uuid.UUID, Decimal]:
    """``sku_id -> on hand`` for a store (all SKUs with movements, or the given ones)."""
    stmt = (
        select(StockMovement.sku_id, func.sum(StockMovement.qty))
        .where(StockMovement.store_id == store_id)
        .group_by(StockMovement.sku_id)
    )
    if sku_ids is not None:
        if not sku_ids:
            return {}
        stmt = stmt.where(StockMovement.sku_id.in_(list(sku_ids)))
    rows = await session.execute(stmt)
    return {sku_id: _quantize(Decimal(total)) for sku_id, total in rows}


async def stock_on_hand_by_batch(
    session: AsyncSession, store_id: uuid.UUID
) -> dict[uuid.UUID, Decimal]:
    """``batch_id -> on hand`` from the ledger (to check against ``stock_batch.qty``)."""
    rows = await session.execute(
        select(StockMovement.batch_id, func.sum(StockMovement.qty))
        .where(StockMovement.store_id == store_id, StockMovement.batch_id.is_not(None))
        .group_by(StockMovement.batch_id)
    )
    return {batch_id: _quantize(Decimal(total)) for batch_id, total in rows}


async def reserved_by_batch(
    session: AsyncSession, batch_ids: Sequence[uuid.UUID]
) -> dict[uuid.UUID, Decimal]:
    """``batch_id -> qty`` held by active reservations (FA-020); absent = nothing reserved."""
    if not batch_ids:
        return {}
    rows = await session.execute(
        select(StockReservation.batch_id, func.sum(StockReservation.qty))
        .where(
            StockReservation.batch_id.in_(list(batch_ids)),
            StockReservation.status == ReservationStatus.ACTIVE.value,
        )
        .group_by(StockReservation.batch_id)
    )
    return {batch_id: _quantize(Decimal(total)) for batch_id, total in rows}


async def reserved_by_sku(
    session: AsyncSession, store_id: uuid.UUID, sku_ids: Sequence[uuid.UUID]
) -> dict[uuid.UUID, Decimal]:
    """``sku_id -> qty`` held by active reservations in a store."""
    if not sku_ids:
        return {}
    rows = await session.execute(
        select(StockReservation.sku_id, func.sum(StockReservation.qty))
        .where(
            StockReservation.store_id == store_id,
            StockReservation.sku_id.in_(list(sku_ids)),
            StockReservation.status == ReservationStatus.ACTIVE.value,
        )
        .group_by(StockReservation.sku_id)
    )
    return {sku_id: _quantize(Decimal(total)) for sku_id, total in rows}


__all__ = [
    "InsufficientStockError",
    "InvalidMovementError",
    "apply_movement",
    "check_sign",
    "reserved_by_batch",
    "reserved_by_sku",
    "stock_on_hand",
    "stock_on_hand_by_batch",
    "stock_on_hand_by_sku",
]
