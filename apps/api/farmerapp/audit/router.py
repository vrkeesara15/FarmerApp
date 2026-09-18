"""``GET /v1/audit-logs`` — the caller's tenant's trail, newest first (FA-006, WC-103 later).

Read-only by construction (the app role cannot update or delete audit rows). Roles: owner,
director, auditor, tenant_admin. Filters: ``entity``, ``entity_id``, ``actor_id``,
``action``, ``from`` / ``to`` (inclusive, UTC); cursor pagination over ``(created_at, id)``
descending.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import select

from farmerapp.api.errors import problem_responses
from farmerapp.api.pagination import Page
from farmerapp.audit.schemas import AuditLogOut, AuditLogPage
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.db.models import AuditLog

router = APIRouter(prefix="/audit-logs", tags=["audit"])

READ_ROLES = (Role.OWNER, Role.DIRECTOR, Role.AUDITOR, Role.TENANT_ADMIN)


@router.get(
    "",
    operation_id="listAuditLogs",
    summary="Audit trail of the caller's tenant, newest first",
    response_model=AuditLogPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_audit_logs(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    page: Page,
    entity: Annotated[str | None, Query(max_length=64, description="Table name.")] = None,
    entity_id: Annotated[uuid.UUID | None, Query()] = None,
    actor_id: Annotated[uuid.UUID | None, Query()] = None,
    action: Annotated[str | None, Query(max_length=64, description="e.g. `user.update`.")] = None,
    from_: Annotated[
        datetime | None, Query(alias="from", description="Rows at or after this instant.")
    ] = None,
    to: Annotated[datetime | None, Query(description="Rows at or before this instant.")] = None,
) -> AuditLogPage:
    stmt = select(AuditLog).where(AuditLog.tenant_id == actor.tenant_id)
    if entity is not None:
        stmt = stmt.where(AuditLog.entity == entity)
    if entity_id is not None:
        stmt = stmt.where(AuditLog.entity_id == entity_id)
    if actor_id is not None:
        stmt = stmt.where(AuditLog.actor_id == actor_id)
    if action is not None:
        stmt = stmt.where(AuditLog.action == action)
    if from_ is not None:
        stmt = stmt.where(AuditLog.created_at >= from_)
    if to is not None:
        stmt = stmt.where(AuditLog.created_at <= to)
    before = page.before(AuditLog.created_at, AuditLog.id)
    if before is not None:
        stmt = stmt.where(before)
    stmt = stmt.order_by(AuditLog.created_at.desc(), AuditLog.id.desc()).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    return AuditLogPage(items=[AuditLogOut.from_row(r) for r in items], next_cursor=next_cursor)
