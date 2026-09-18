"""The ``order`` sync op (FA-020 offline capture by a field officer; FA-025).

``create`` only: the payload is ``OrderCreate`` and ``entity_id`` becomes the order id, so a
replayed op with a new ``op_id`` cannot place the order twice (the second one is a
``conflict`` carrying the server's order). Prices are recomputed exactly as on
``POST /v1/orders``: a device total that differs is rejected (``amount_mismatch``), short
stock is ``insufficient_stock``, a credit sale beyond the limit is ``credit_limit_exceeded``
(status 402) with the approval request id in ``error.errors[0]`` — the op is rejected but
the approval request is kept (it is returned, not raised, inside the op's savepoint).
Orders are ``server_wins`` and immutable from a device: updates and deletes stay
``unsupported_action``.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import date
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError
from farmerapp.auth.models import User
from farmerapp.auth.scope import order_filters
from farmerapp.khata.credit import CreditDecision
from farmerapp.orders.models import Order
from farmerapp.orders.schemas import OrderCreate, OrderDetailOut
from farmerapp.orders.service import order_detail, place_order


@dataclass(frozen=True)
class OrderSyncOutcome:
    out: OrderDetailOut | None = None
    conflict: bool = False
    blocked: CreditDecision | None = None


async def create(
    session: AsyncSession,
    actor: User,
    entity_id: uuid.UUID,
    payload: dict[str, Any],
    *,
    today: date,
) -> OrderSyncOutcome:
    if await session.get(Order, entity_id) is not None:
        existing = (
            await session.execute(select(Order).where(Order.id == entity_id, *order_filters(actor)))
        ).scalar_one_or_none()
        if existing is None:
            raise NotFoundError("Order not found.")
        return OrderSyncOutcome(out=await order_detail(session, existing), conflict=True)
    body = OrderCreate.model_validate({**payload, "id": str(entity_id)})
    result = await place_order(session, actor, body, today=today)
    if result.blocked is not None:
        return OrderSyncOutcome(blocked=result.blocked)
    return OrderSyncOutcome(out=result.order)


__all__ = ["OrderSyncOutcome", "create"]
