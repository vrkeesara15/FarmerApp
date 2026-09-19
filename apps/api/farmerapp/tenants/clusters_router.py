"""``GET /v1/clusters`` — clusters with their names and stores (console filters and pickers).

Any staff role may call it; the rows follow SPEC 2.6 (``farmerapp.auth.scope``):

* owner / director / tenant_admin / auditor / accountant — every cluster of the tenant with
  all of its stores;
* cluster_head — their own cluster;
* store_manager / field_officer — the cluster of their own store, listing only that store;
* agronomist — nothing (no store-scoped screens), an empty list.

Stores without a cluster are not listed; soft-deleted clusters and stores are left out.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter
from pydantic import BaseModel, Field
from sqlalchemy import select

from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import DEFAULT_VISIBILITY, Visibility
from farmerapp.tenants.models import Cluster, Store

router = APIRouter(prefix="/clusters", tags=["tenants"])

STAFF_ROLES = tuple(r for r in Role if r != Role.FARMER)


class ClusterOut(BaseModel):
    id: uuid.UUID
    name: str
    district: str | None
    state: str
    store_ids: list[uuid.UUID] = Field(description="Stores of the cluster the caller may see.")


class ClusterList(BaseModel):
    items: list[ClusterOut]


@router.get(
    "",
    operation_id="listClusters",
    summary="Clusters with names, district and store ids (scoped per SPEC 2.6)",
    response_model=ClusterList,
)
async def list_clusters(
    actor: Annotated[User, require_roles(*STAFF_ROLES)], session: DbSession
) -> ClusterList:
    clusters = select(Cluster).where(
        Cluster.tenant_id == actor.tenant_id, Cluster.deleted_at.is_(None)
    )
    stores = select(Store.id, Store.cluster_id).where(
        Store.tenant_id == actor.tenant_id,
        Store.deleted_at.is_(None),
        Store.cluster_id.is_not(None),
    )
    match DEFAULT_VISIBILITY[UserRole(actor.role)]:
        case Visibility.ALL:
            pass
        case Visibility.CLUSTER:
            clusters = clusters.where(Cluster.id == actor.cluster_id)
            stores = stores.where(Store.cluster_id == actor.cluster_id)
        case Visibility.STORE | Visibility.OWN:
            # Own store (store manager) / the store an officer works from.
            own_cluster = select(Store.cluster_id).where(
                Store.id == actor.store_id, Store.tenant_id == actor.tenant_id
            )
            clusters = clusters.where(Cluster.id.in_(own_cluster))
            stores = stores.where(Store.id == actor.store_id)
        case Visibility.NONE:
            return ClusterList(items=[])

    store_rows = (await session.execute(stores.order_by(Store.code))).all()
    by_cluster: dict[uuid.UUID, list[uuid.UUID]] = {}
    for store_id, cluster_id in store_rows:
        by_cluster.setdefault(cluster_id, []).append(store_id)
    rows = (await session.execute(clusters.order_by(Cluster.name))).scalars().all()
    return ClusterList(
        items=[
            ClusterOut(
                id=c.id,
                name=c.name,
                district=c.district,
                state=c.state,
                store_ids=by_cluster.get(c.id, []),
            )
            for c in rows
        ]
    )
