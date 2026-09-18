"""Stock write paths (ST-003) and order reservations (FA-020, ST-005).

Every quantity change goes through ``farmerapp.stock.ledger.apply_movement`` (append the
movement and update the batch cache in one flush). Batches are locked ``FOR UPDATE`` before
they are read for a decision, so two concurrent writes on one batch serialise and the
"never negative" rule holds under load.

* **Goods receipt** (``receive``): a ``receipt`` movement per line into the batch named by
  ``batch_no`` (created when new; an existing batch with a different expiry is a 409
  ``batch_mismatch``).
* **Transfer** (``transfer``): ``transfer_out`` on the source batch and ``transfer_in`` on
  the destination batch with the same ``batch_no`` / expiry / cost (created when missing),
  in the same transaction — no in-transit state in the pilot.
* **Write-off** (``write_off``): ``damage`` movements with the reason (damage / expiry /
  other) and an optional photo URI.
* **Adjustment** (``adjust``): stock count correction to the counted quantity, ``adjust``
  movement with the reason, plus an explicit ``stock.adjustment`` audit event.

Outbound writes may only take what is **available** (``batch.qty - active reservations``):
more is a 409 ``negative_stock`` listing the batch's available quantity.

Reservations (``stock_reservation``): ``allocate_fefo`` picks unexpired batches of a SKU in
a store earliest expiry first (no-expiry batches last, then oldest receipt) and
``reserve_order`` holds them for an order's lines; not enough is a 409
``insufficient_stock`` with the available quantity per line. ``release_order`` (cancel) and
``consume_order`` (handover / delivery: the reservations become ``sale`` movements) close
them.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import Any

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, ConflictError, NotFoundError
from farmerapp.auth.models import User
from farmerapp.catalog.models import Sku
from farmerapp.db import audit
from farmerapp.stock.ledger import apply_movement, reserved_by_batch
from farmerapp.stock.models import (
    QTY_SCALE,
    MovementKind,
    ReservationStatus,
    StockBatch,
    StockMovement,
    StockReservation,
)
from farmerapp.stock.schemas import (
    AdjustmentIn,
    BatchStateOut,
    ReceiptIn,
    StockMovementOut,
    StockWriteOut,
    TransferIn,
    WriteOffIn,
)
from farmerapp.tenants.models import Store


class NegativeStockError(ConflictError):
    code = "negative_stock"


class InsufficientStockForOrderError(ConflictError):
    code = "insufficient_stock"


class BatchMismatchError(ConflictError):
    code = "batch_mismatch"


class InvalidStockRequestError(AppError):
    status = 422
    code = "invalid_stock_request"


REF_RECEIPT = "receipt"
REF_TRANSFER = "transfer"
REF_WRITE_OFF = "write_off"
REF_ADJUSTMENT = "adjustment"
REF_ORDER = "order"


def _q(qty: Decimal) -> Decimal:
    return Decimal(qty).quantize(QTY_SCALE)


# --------------------------------------------------------------------------- batch helpers
async def lock_batches(
    session: AsyncSession, store_id: uuid.UUID, batch_ids: Iterable[uuid.UUID]
) -> dict[uuid.UUID, StockBatch]:
    """The batches of ``store_id`` locked FOR UPDATE; an unknown id is a 404."""
    wanted = sorted(set(batch_ids))
    rows = (
        (
            await session.execute(
                select(StockBatch)
                .where(
                    StockBatch.id.in_(wanted),
                    StockBatch.store_id == store_id,
                    StockBatch.deleted_at.is_(None),
                )
                .order_by(StockBatch.id)
                .with_for_update()
            )
        )
        .scalars()
        .all()
    )
    found = {b.id: b for b in rows}
    missing = [str(b) for b in wanted if b not in found]
    if missing:
        raise NotFoundError(f"Batch not found in this store: {', '.join(missing)}.")
    return found


async def batch_states(session: AsyncSession, batches: Sequence[StockBatch]) -> list[BatchStateOut]:
    reserved = await reserved_by_batch(session, [b.id for b in batches])
    out: list[BatchStateOut] = []
    for b in batches:
        held = reserved.get(b.id, _q(Decimal(0)))
        out.append(
            BatchStateOut(
                id=b.id,
                store_id=b.store_id,
                sku_id=b.sku_id,
                batch_no=b.batch_no,
                expiry=b.expiry,
                qty=b.qty,
                reserved=held,
                available=b.qty - held,
            )
        )
    return out


def _write_out(
    ref_type: str, ref_id: uuid.UUID, movements: list[StockMovement], states: list[BatchStateOut]
) -> StockWriteOut:
    return StockWriteOut(
        ref_type=ref_type,
        ref_id=ref_id,
        movements=[StockMovementOut.model_validate(m) for m in movements],
        batches=states,
    )


def _unique(batches: Iterable[StockBatch]) -> list[StockBatch]:
    seen: dict[uuid.UUID, StockBatch] = {}
    for b in batches:
        seen.setdefault(b.id, b)
    return list(seen.values())


async def _check_available(
    session: AsyncSession, batches: dict[uuid.UUID, StockBatch], wanted: dict[uuid.UUID, Decimal]
) -> None:
    """``negative_stock`` when any batch would go below its reserved quantity."""
    reserved = await reserved_by_batch(session, list(wanted))
    problems: list[dict[str, Any]] = []
    for batch_id, qty in wanted.items():
        batch = batches[batch_id]
        available = batch.qty - reserved.get(batch_id, Decimal(0))
        if qty > available:
            problems.append(
                {
                    "batch_id": str(batch_id),
                    "batch_no": batch.batch_no,
                    "requested": str(_q(qty)),
                    "available": str(_q(max(available, Decimal(0)))),
                }
            )
    if problems:
        raise NegativeStockError(
            "The movement would take a batch below zero (or below its reserved quantity).",
            extra={"errors": problems},
        )


# --------------------------------------------------------------------------- receipt
async def receive(
    session: AsyncSession, actor: User, store: Store, body: ReceiptIn
) -> StockWriteOut:
    sku_ids = {line.sku_id for line in body.lines}
    skus = set(
        (
            await session.execute(
                select(Sku.id).where(
                    Sku.id.in_(sku_ids),
                    Sku.tenant_id == actor.tenant_id,
                    Sku.deleted_at.is_(None),
                )
            )
        )
        .scalars()
        .all()
    )
    unknown = sorted(str(s) for s in sku_ids - skus)
    if unknown:
        raise InvalidStockRequestError(f"Unknown SKU: {', '.join(unknown)}.")
    receipt_id = uuid.uuid4()
    movements: list[StockMovement] = []
    touched: list[StockBatch] = []
    for line in body.lines:
        batch = (
            await session.execute(
                select(StockBatch)
                .where(
                    StockBatch.store_id == store.id,
                    StockBatch.sku_id == line.sku_id,
                    StockBatch.batch_no == line.batch_no,
                )
                .with_for_update()
            )
        ).scalar_one_or_none()
        if batch is None:
            batch = StockBatch(
                tenant_id=actor.tenant_id,
                store_id=store.id,
                sku_id=line.sku_id,
                batch_no=line.batch_no,
                expiry=line.expiry,
                qty=Decimal(0),
                cost_paise=line.cost_paise,
            )
            session.add(batch)
            await session.flush()
        elif batch.expiry != line.expiry:
            raise BatchMismatchError(
                f"Batch {line.batch_no} already exists with expiry {batch.expiry}.",
                extra={"batch_id": str(batch.id)},
            )
        movements.append(
            await apply_movement(
                session,
                tenant_id=actor.tenant_id,
                store_id=store.id,
                sku_id=line.sku_id,
                kind=MovementKind.RECEIPT,
                qty=line.qty,
                batch=batch,
                ref_type=REF_RECEIPT,
                ref_id=receipt_id,
                note=body.reference,
                created_by=actor.id,
            )
        )
        touched.append(batch)
    return _write_out(
        REF_RECEIPT, receipt_id, movements, await batch_states(session, _unique(touched))
    )


# --------------------------------------------------------------------------- transfer
async def transfer(
    session: AsyncSession, actor: User, source: Store, target: Store, body: TransferIn
) -> StockWriteOut:
    if source.id == target.id:
        raise InvalidStockRequestError("A transfer needs two different stores.")
    batches = await lock_batches(session, source.id, (line.batch_id for line in body.lines))
    wanted: dict[uuid.UUID, Decimal] = {}
    for line in body.lines:
        wanted[line.batch_id] = wanted.get(line.batch_id, Decimal(0)) + line.qty
    await _check_available(session, batches, wanted)
    transfer_id = uuid.uuid4()
    movements: list[StockMovement] = []
    touched: list[StockBatch] = []
    for line in body.lines:
        src = batches[line.batch_id]
        dest = (
            await session.execute(
                select(StockBatch)
                .where(
                    StockBatch.store_id == target.id,
                    StockBatch.sku_id == src.sku_id,
                    StockBatch.batch_no == src.batch_no,
                )
                .with_for_update()
            )
        ).scalar_one_or_none()
        if dest is None:
            dest = StockBatch(
                tenant_id=actor.tenant_id,
                store_id=target.id,
                sku_id=src.sku_id,
                batch_no=src.batch_no,
                expiry=src.expiry,
                qty=Decimal(0),
                cost_paise=src.cost_paise,
            )
            session.add(dest)
            await session.flush()
        elif dest.expiry != src.expiry:
            raise BatchMismatchError(
                f"Batch {src.batch_no} exists at the destination with another expiry.",
                extra={"batch_id": str(dest.id)},
            )
        for store_id, kind, qty, batch in (
            (source.id, MovementKind.TRANSFER_OUT, -line.qty, src),
            (target.id, MovementKind.TRANSFER_IN, line.qty, dest),
        ):
            movements.append(
                await apply_movement(
                    session,
                    tenant_id=actor.tenant_id,
                    store_id=store_id,
                    sku_id=src.sku_id,
                    kind=kind,
                    qty=qty,
                    batch=batch,
                    ref_type=REF_TRANSFER,
                    ref_id=transfer_id,
                    note=body.note,
                    created_by=actor.id,
                )
            )
        touched += [src, dest]
    return _write_out(
        REF_TRANSFER, transfer_id, movements, await batch_states(session, _unique(touched))
    )


# --------------------------------------------------------------------------- write-off
async def write_off(
    session: AsyncSession, actor: User, store: Store, body: WriteOffIn
) -> StockWriteOut:
    batches = await lock_batches(session, store.id, (line.batch_id for line in body.lines))
    wanted: dict[uuid.UUID, Decimal] = {}
    for line in body.lines:
        wanted[line.batch_id] = wanted.get(line.batch_id, Decimal(0)) + line.qty
    await _check_available(session, batches, wanted)
    write_off_id = uuid.uuid4()
    movements: list[StockMovement] = []
    for line in body.lines:
        batch = batches[line.batch_id]
        movements.append(
            await apply_movement(
                session,
                tenant_id=actor.tenant_id,
                store_id=store.id,
                sku_id=batch.sku_id,
                kind=MovementKind.DAMAGE,
                qty=-line.qty,
                batch=batch,
                ref_type=REF_WRITE_OFF,
                ref_id=write_off_id,
                note=body.note,
                created_by=actor.id,
                reason=line.reason.value,
                photo_uri=body.photo_blob_uri,
            )
        )
    return _write_out(
        REF_WRITE_OFF,
        write_off_id,
        movements,
        await batch_states(session, _unique(batches[line.batch_id] for line in body.lines)),
    )


# --------------------------------------------------------------------------- adjustment
async def adjust(
    session: AsyncSession, actor: User, store: Store, body: AdjustmentIn
) -> StockWriteOut:
    ids = [line.batch_id for line in body.lines]
    if len(set(ids)) != len(ids):
        raise InvalidStockRequestError("Count each batch once per adjustment.")
    batches = await lock_batches(session, store.id, ids)
    reserved = await reserved_by_batch(session, ids)
    problems = [
        {
            "batch_id": str(line.batch_id),
            "batch_no": batches[line.batch_id].batch_no,
            "counted": str(_q(line.counted_qty)),
            "reserved": str(reserved[line.batch_id]),
        }
        for line in body.lines
        if line.counted_qty < reserved.get(line.batch_id, Decimal(0))
    ]
    if problems:
        raise NegativeStockError(
            "The counted quantity is below what open orders have reserved; cancel or "
            "fulfil them first.",
            extra={"errors": problems},
        )
    adjustment_id = uuid.uuid4()
    movements: list[StockMovement] = []
    for line in body.lines:
        batch = batches[line.batch_id]
        before = batch.qty
        delta = _q(line.counted_qty) - before
        if delta == 0:
            continue
        movement = await apply_movement(
            session,
            tenant_id=actor.tenant_id,
            store_id=store.id,
            sku_id=batch.sku_id,
            kind=MovementKind.ADJUST,
            qty=delta,
            batch=batch,
            ref_type=REF_ADJUSTMENT,
            ref_id=adjustment_id,
            note=body.reason,
            created_by=actor.id,
            reason="count",
        )
        movements.append(movement)
        audit.record(
            session,
            action="stock.adjustment",
            entity="stock_batch",
            entity_id=batch.id,
            tenant_id=actor.tenant_id,
            before={"qty": before},
            after={"qty": batch.qty, "reason": body.reason, "movement_id": movement.id},
        )
    return _write_out(
        REF_ADJUSTMENT,
        adjustment_id,
        movements,
        await batch_states(session, _unique(batches[i] for i in ids)),
    )


# --------------------------------------------------------------------------- reservations
@dataclass(frozen=True)
class LineDemand:
    """One order line's need: which SKU, how much (``index`` = position in the request)."""

    index: int
    sku_id: uuid.UUID
    qty: Decimal
    line_id: uuid.UUID | None = None


Allocation = list[tuple[StockBatch, Decimal]]


async def allocate_fefo(
    session: AsyncSession,
    store_id: uuid.UUID,
    demands: Sequence[LineDemand],
    today: date,
) -> list[Allocation]:
    """Lock the store's unexpired batches of the demanded SKUs and split every line over
    them earliest expiry first. Raises ``insufficient_stock`` (409) listing, per short
    line, the requested and available quantity; nothing is written."""
    sku_ids = sorted({d.sku_id for d in demands})
    batches = (
        (
            await session.execute(
                select(StockBatch)
                .where(
                    StockBatch.store_id == store_id,
                    StockBatch.sku_id.in_(sku_ids),
                    StockBatch.deleted_at.is_(None),
                    StockBatch.qty > 0,
                    or_(StockBatch.expiry.is_(None), StockBatch.expiry >= today),
                )
                .order_by(
                    StockBatch.expiry.asc().nulls_last(), StockBatch.received_at, StockBatch.id
                )
                .with_for_update()
            )
        )
        .scalars()
        .all()
    )
    reserved = await reserved_by_batch(session, [b.id for b in batches])
    free = {b.id: b.qty - reserved.get(b.id, Decimal(0)) for b in batches}
    by_sku: dict[uuid.UUID, list[StockBatch]] = {}
    for b in batches:
        by_sku.setdefault(b.sku_id, []).append(b)
    allocations: list[Allocation] = []
    short: list[dict[str, Any]] = []
    for demand in demands:
        need = _q(demand.qty)
        available = sum(
            (max(free[b.id], Decimal(0)) for b in by_sku.get(demand.sku_id, [])), Decimal(0)
        )
        picked: Allocation = []
        for b in by_sku.get(demand.sku_id, []):
            if need <= 0:
                break
            take = min(need, free[b.id])
            if take <= 0:
                continue
            picked.append((b, take))
            free[b.id] -= take
            need -= take
        if need > 0:
            short.append(
                {
                    "loc": ["lines", demand.index],
                    "index": demand.index,
                    "sku_id": str(demand.sku_id),
                    "requested": str(_q(demand.qty)),
                    "available": str(_q(available)),
                }
            )
        allocations.append(picked)
    if short:
        raise InsufficientStockForOrderError(
            "Not enough unreserved, unexpired stock at the store.", extra={"errors": short}
        )
    return allocations


async def reserve_order(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    order_id: uuid.UUID,
    store_id: uuid.UUID,
    demands: Sequence[LineDemand],
    today: date,
) -> list[StockReservation]:
    """Hold FEFO batches for every line (``line_id`` required on each demand)."""
    allocations = await allocate_fefo(session, store_id, demands, today)
    return await hold_allocations(
        session,
        tenant_id=tenant_id,
        order_id=order_id,
        store_id=store_id,
        demands=demands,
        allocations=allocations,
    )


async def hold_allocations(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    order_id: uuid.UUID,
    store_id: uuid.UUID,
    demands: Sequence[LineDemand],
    allocations: Sequence[Allocation],
) -> list[StockReservation]:
    """Write the reservations of an ``allocate_fefo`` result (batches still locked)."""
    rows: list[StockReservation] = []
    for demand, allocation in zip(demands, allocations, strict=True):
        if demand.line_id is None:
            raise ValueError("hold_allocations needs line ids")
        for batch, qty in allocation:
            rows.append(
                StockReservation(
                    tenant_id=tenant_id,
                    store_id=store_id,
                    sku_id=demand.sku_id,
                    batch_id=batch.id,
                    order_id=order_id,
                    order_line_id=demand.line_id,
                    qty=_q(qty),
                    status=ReservationStatus.ACTIVE,
                )
            )
    session.add_all(rows)
    await session.flush()
    return rows


async def active_reservations(session: AsyncSession, order_id: uuid.UUID) -> list[StockReservation]:
    return list(
        (
            await session.execute(
                select(StockReservation)
                .where(
                    StockReservation.order_id == order_id,
                    StockReservation.status == ReservationStatus.ACTIVE.value,
                )
                .order_by(StockReservation.created_at, StockReservation.id)
                .with_for_update()
            )
        )
        .scalars()
        .all()
    )


async def release_order(session: AsyncSession, order_id: uuid.UUID) -> int:
    """Cancel: every active reservation of the order is released. Returns how many."""
    rows = await active_reservations(session, order_id)
    for row in rows:
        row.status = ReservationStatus.RELEASED
    await session.flush()
    return len(rows)


async def consume_order(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    order_id: uuid.UUID,
    store_id: uuid.UUID,
    demands: Sequence[LineDemand],
    actor_id: uuid.UUID | None,
    today: date,
) -> list[StockMovement]:
    """Handover / delivery: the reservations become ``sale`` movements on their batches.
    Lines with no active reservation (orders placed before FA-020) are picked FEFO now."""
    rows = await active_reservations(session, order_id)
    batches = await lock_batches(session, store_id, {r.batch_id for r in rows}) if rows else {}
    movements: list[StockMovement] = []
    covered: set[uuid.UUID] = set()
    for row in rows:
        movements.append(
            await apply_movement(
                session,
                tenant_id=tenant_id,
                store_id=store_id,
                sku_id=row.sku_id,
                kind=MovementKind.SALE,
                qty=-row.qty,
                batch=batches[row.batch_id],
                ref_type=REF_ORDER,
                ref_id=order_id,
                created_by=actor_id,
            )
        )
        row.status = ReservationStatus.CONSUMED
        covered.add(row.order_line_id)
    missing = [d for d in demands if d.line_id not in covered]
    if missing:
        allocations = await allocate_fefo(session, store_id, missing, today)
        for demand, allocation in zip(missing, allocations, strict=True):
            for batch, qty in allocation:
                movements.append(
                    await apply_movement(
                        session,
                        tenant_id=tenant_id,
                        store_id=store_id,
                        sku_id=demand.sku_id,
                        kind=MovementKind.SALE,
                        qty=-qty,
                        batch=batch,
                        ref_type=REF_ORDER,
                        ref_id=order_id,
                        created_by=actor_id,
                    )
                )
    await session.flush()
    return movements


__all__ = [
    "REF_ADJUSTMENT",
    "REF_ORDER",
    "REF_RECEIPT",
    "REF_TRANSFER",
    "REF_WRITE_OFF",
    "Allocation",
    "BatchMismatchError",
    "InsufficientStockForOrderError",
    "InvalidStockRequestError",
    "LineDemand",
    "NegativeStockError",
    "active_reservations",
    "adjust",
    "allocate_fefo",
    "batch_states",
    "consume_order",
    "hold_allocations",
    "lock_batches",
    "receive",
    "release_order",
    "reserve_order",
    "transfer",
    "write_off",
]
