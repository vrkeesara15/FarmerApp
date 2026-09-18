"""Where a store may send stock (ST-003 transfers).

``GET /v1/catalog/stores`` stays scoped to what the caller may *see* (a store manager: their
own store), so the transfer screen asks here for the destinations instead:

* **origin** — the store the stock leaves: a store manager's own store (always); for the
  other roles the optional ``from_store_id`` (must be a store they may see), else their own
  store when they have one, else none (distances are then ``null``).
* **destinations** — the other live (not deleted) stores of the tenant that the origin may
  send to: owner / director / tenant admin every store; everyone else the stores of one
  cluster — the origin's cluster, else the caller's own cluster (cluster head, an accountant
  placed in a cluster). An accountant with neither (a finance user of the whole tenant, SPEC
  2.6 assumption in FA-002) sees every store. A store without a cluster has no
  cluster-mates: fail closed.
* **distance** — metres from the origin (PostGIS ``ST_Distance`` on the geography points),
  nearest first; stores without an origin are ordered by code.

``POST /v1/stock/transfers`` enforces the same set for a store manager: the source must be
their own store (403 ``transfer_source_not_allowed``) and the destination one of these
stores (403 ``transfer_destination_not_allowed``).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from sqlalchemy import ColumnElement, false, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import ForbiddenError, NotFoundError
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.scope import visible_store_filters
from farmerapp.tenants.models import Store

#: Roles whose destinations are every store of the tenant.
TENANT_WIDE_ROLES = frozenset({UserRole.OWNER, UserRole.DIRECTOR, UserRole.TENANT_ADMIN})


class TransferSourceNotAllowedError(ForbiddenError):
    code = "transfer_source_not_allowed"


class TransferDestinationNotAllowedError(ForbiddenError):
    code = "transfer_destination_not_allowed"


@dataclass(frozen=True)
class Destination:
    store: Store
    distance_m: float | None


async def _live_store(
    session: AsyncSession, actor: User, store_id: uuid.UUID, *scope: ColumnElement[bool]
) -> Store:
    store = (
        await session.execute(
            select(Store).where(
                Store.id == store_id,
                Store.tenant_id == actor.tenant_id,
                Store.deleted_at.is_(None),
                *scope,
            )
        )
    ).scalar_one_or_none()
    if store is None:
        raise NotFoundError("Store not found.")
    return store


async def transfer_origin(
    session: AsyncSession, actor: User, from_store_id: uuid.UUID | None
) -> Store | None:
    """The store the stock leaves (see the module doc). A store manager naming another
    store is 403 ``transfer_source_not_allowed``; another role naming a store outside their
    scope is 404."""
    if UserRole(actor.role) == UserRole.STORE_MANAGER:
        if actor.store_id is None or (from_store_id not in (None, actor.store_id)):
            raise TransferSourceNotAllowedError("A store manager transfers from their own store.")
        return await _live_store(session, actor, actor.store_id)
    if from_store_id is not None:
        return await _live_store(session, actor, from_store_id, *visible_store_filters(actor))
    if actor.store_id is None:
        return None
    own: Store | None = await session.scalar(
        select(Store).where(
            Store.id == actor.store_id,
            Store.tenant_id == actor.tenant_id,
            Store.deleted_at.is_(None),
        )
    )
    return own


def destination_filters(actor: User, origin: Store | None) -> list[ColumnElement[bool]]:
    """Filters on ``store`` for the stores ``origin`` may send stock to."""
    filters: list[ColumnElement[bool]] = [
        Store.tenant_id == actor.tenant_id,
        Store.deleted_at.is_(None),
    ]
    if origin is not None:
        filters.append(Store.id != origin.id)
    role = UserRole(actor.role)
    if role in TENANT_WIDE_ROLES:
        return filters
    if role == UserRole.STORE_MANAGER:
        cluster_id = origin.cluster_id if origin is not None else None
    else:
        cluster_id = origin.cluster_id if origin is not None else actor.cluster_id
        if cluster_id is None and origin is None and role == UserRole.ACCOUNTANT:
            return filters  # a tenant-wide finance user without a placement
    filters.append(Store.cluster_id == cluster_id if cluster_id is not None else false())
    return filters


async def transfer_destinations(
    session: AsyncSession, actor: User, origin: Store | None
) -> list[Destination]:
    filters = destination_filters(actor, origin)
    if origin is None:
        stores = (
            (await session.execute(select(Store).where(*filters).order_by(Store.code)))
            .scalars()
            .all()
        )
        return [Destination(store=store, distance_m=None) for store in stores]
    distance = func.ST_Distance(
        Store.location, select(Store.location).where(Store.id == origin.id).scalar_subquery()
    )
    rows = (
        await session.execute(
            select(Store, distance).where(*filters).order_by(distance, Store.code)
        )
    ).all()
    return [Destination(store=store, distance_m=round(float(meters), 1)) for store, meters in rows]


async def check_transfer(session: AsyncSession, actor: User, source: Store, target: Store) -> None:
    """``POST /v1/stock/transfers`` for a store manager: from their own store, to one of
    their transfer destinations (403 otherwise). Other roles keep their store scope."""
    if UserRole(actor.role) != UserRole.STORE_MANAGER:
        return
    origin = await transfer_origin(session, actor, source.id)
    if origin is None or target.id == origin.id:  # the same store: the service's 422
        return
    allowed = await session.scalar(
        select(Store.id).where(Store.id == target.id, *destination_filters(actor, origin))
    )
    if allowed is None:
        raise TransferDestinationNotAllowedError(
            "A store manager transfers to the other stores of their cluster."
        )


__all__ = [
    "TENANT_WIDE_ROLES",
    "Destination",
    "TransferDestinationNotAllowedError",
    "TransferSourceNotAllowedError",
    "check_transfer",
    "destination_filters",
    "transfer_destinations",
    "transfer_origin",
]
