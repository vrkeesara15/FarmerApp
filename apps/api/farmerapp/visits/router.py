"""``/v1/visits`` — read endpoints (M2-KICKOFF). Check-in / capture / confirmation / check-out
writes land with FA-014 .. FA-017.

Row scope is ``farmerapp.auth.scope.visit_filters``: owner / director / tenant_admin /
auditor see the tenant, a cluster head the visits of the officers in their cluster, a store
manager those of their store's officers, a field officer their own, a farmer the visits made
to them. Agronomists and accountants have no visit access (SPEC 2.6).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.scope import visit_filters
from farmerapp.visits.models import Visit, VisitConfirmation, VisitPhoto, VisitStatus
from farmerapp.visits.schemas import VisitDetailOut, VisitOut, VisitPage

router = APIRouter(prefix="/visits", tags=["visits"])

READ_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.FIELD_OFFICER,
    Role.FARMER,
)


async def visible_visit(session: AsyncSession, actor: User, visit_id: uuid.UUID) -> Visit:
    """One visit of the actor's tenant within the actor's 2.6 scope, else 404."""
    stmt = select(Visit).where(
        Visit.id == visit_id, Visit.deleted_at.is_(None), *visit_filters(actor)
    )
    visit = (await session.execute(stmt)).scalar_one_or_none()
    if visit is None:
        raise NotFoundError("Visit not found.")
    return visit


async def visit_detail(session: AsyncSession, visit: Visit) -> VisitDetailOut:
    photos = (
        (
            await session.execute(
                select(VisitPhoto)
                .where(VisitPhoto.visit_id == visit.id, VisitPhoto.deleted_at.is_(None))
                .order_by(VisitPhoto.created_at, VisitPhoto.id)
            )
        )
        .scalars()
        .all()
    )
    confirmations = (
        (
            await session.execute(
                select(VisitConfirmation)
                .where(
                    VisitConfirmation.visit_id == visit.id,
                    VisitConfirmation.deleted_at.is_(None),
                )
                .order_by(VisitConfirmation.confirmed_at, VisitConfirmation.id)
            )
        )
        .scalars()
        .all()
    )
    return VisitDetailOut.from_rows(visit, list(photos), list(confirmations))


@router.get(
    "",
    operation_id="listVisits",
    summary="Visits visible to the caller (tenant, cluster, store, own or to self), oldest first",
    response_model=VisitPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_visits(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    page: Page,
    officer_id: Annotated[uuid.UUID | None, Query(description="Officer user id.")] = None,
    farmer_id: Annotated[uuid.UUID | None, Query()] = None,
    from_: Annotated[
        datetime | None, Query(alias="from", description="Check-in at or after (RFC 3339).")
    ] = None,
    to: Annotated[datetime | None, Query(description="Check-in before (RFC 3339).")] = None,
    status: Annotated[VisitStatus | None, Query()] = None,
) -> VisitPage:
    stmt = select(Visit).where(Visit.deleted_at.is_(None), *visit_filters(actor))
    if officer_id is not None:
        stmt = stmt.where(Visit.officer_id == officer_id)
    if farmer_id is not None:
        stmt = stmt.where(Visit.farmer_id == farmer_id)
    if from_ is not None:
        stmt = stmt.where(Visit.checkin_at >= from_)
    if to is not None:
        stmt = stmt.where(Visit.checkin_at < to)
    if status is not None:
        stmt = stmt.where(Visit.status == status.value)
    after = page.after(Visit.created_at, Visit.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(Visit.created_at, Visit.id).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    return VisitPage(items=[VisitOut.from_row(v) for v in items], next_cursor=next_cursor)


@router.get(
    "/{id}",
    operation_id="getVisit",
    summary="One visit with photos, farmer confirmation and VV-004 score components",
    response_model=VisitDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_visit(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
) -> VisitDetailOut:
    visit = await visible_visit(session, actor, id)
    return await visit_detail(session, visit)


__all__ = ["READ_ROLES", "router", "visible_visit", "visit_detail"]
