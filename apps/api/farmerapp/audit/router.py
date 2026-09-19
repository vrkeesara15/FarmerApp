"""``/v1/audit-logs`` — the caller's tenant's trail, newest first (FA-006, WC-103 / C103).

Read-only by construction (the app role cannot update or delete audit rows). Roles: owner,
director, auditor, tenant_admin. Filters (all optional, combined with AND): ``entity``,
``entity_id``, ``actor_id``, ``actor_role``, ``action`` (exact, or a prefix ending in ``.``
such as ``user.``), ``from`` / ``to`` (inclusive, UTC) and ``q`` (free text: an entity id or
its leading characters). Cursor pagination over ``(created_at, id)`` descending.

``GET /v1/audit-logs/export`` streams the same filtered rows as CSV (at most
``EXPORT_MAX_ROWS``), needs a step-up token (SEC-028) and is itself audited
(``audit_log.export`` with the filters and the row count). Cells that a spreadsheet would
read as a formula are prefixed with ``'``.
"""

from __future__ import annotations

import csv
import io
import json
import uuid
from collections.abc import Iterator
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse
from sqlalchemy import Select, String, cast, select

from farmerapp.api.errors import problem_responses
from farmerapp.api.pagination import Page
from farmerapp.audit.schemas import AuditLogOut, AuditLogPage
from farmerapp.auth.deps import DbSession
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.stepup import STEP_UP_OPENAPI, StepUp
from farmerapp.db import audit
from farmerapp.db.models import AuditLog

router = APIRouter(prefix="/audit-logs", tags=["audit"])

READ_ROLES = (Role.OWNER, Role.DIRECTOR, Role.AUDITOR, Role.TENANT_ADMIN)
EXPORT_MAX_ROWS = 50_000
EXPORT_COLUMNS = (
    "created_at",
    "action",
    "entity",
    "entity_id",
    "actor_id",
    "actor_role",
    "ip",
    "device_id",
    "user_agent",
    "trace_id",
    "before",
    "after",
    "id",
)
_FORMULA_PREFIXES = ("=", "+", "-", "@", "\t", "\r")


@dataclass(frozen=True)
class AuditFilters:
    entity: str | None
    entity_id: uuid.UUID | None
    actor_id: uuid.UUID | None
    actor_role: str | None
    action: str | None
    from_: datetime | None
    to: datetime | None
    q: str | None

    def apply(self, stmt: Select[Any], tenant_id: uuid.UUID) -> Select[Any]:
        stmt = stmt.where(AuditLog.tenant_id == tenant_id)
        if self.entity is not None:
            stmt = stmt.where(AuditLog.entity == self.entity)
        if self.entity_id is not None:
            stmt = stmt.where(AuditLog.entity_id == self.entity_id)
        if self.actor_id is not None:
            stmt = stmt.where(AuditLog.actor_id == self.actor_id)
        if self.actor_role is not None:
            stmt = stmt.where(AuditLog.actor_role == self.actor_role)
        if self.action is not None:
            if self.action.endswith("."):
                stmt = stmt.where(AuditLog.action.startswith(self.action, autoescape=True))
            else:
                stmt = stmt.where(AuditLog.action == self.action)
        if self.from_ is not None:
            stmt = stmt.where(AuditLog.created_at >= self.from_)
        if self.to is not None:
            stmt = stmt.where(AuditLog.created_at <= self.to)
        if self.q:
            stmt = stmt.where(
                cast(AuditLog.entity_id, String).startswith(self.q.lower(), autoescape=True)
            )
        return stmt

    def as_json(self) -> dict[str, Any]:
        return {k.rstrip("_"): v for k, v in asdict(self).items() if v is not None}


def audit_filters(
    entity: Annotated[str | None, Query(max_length=64, description="Table name.")] = None,
    entity_id: Annotated[uuid.UUID | None, Query()] = None,
    actor_id: Annotated[uuid.UUID | None, Query()] = None,
    actor_role: Annotated[str | None, Query(max_length=32, description="e.g. `owner`.")] = None,
    action: Annotated[
        str | None,
        Query(max_length=64, description="`user.update`, or a prefix ending in `.` (`user.`)."),
    ] = None,
    from_: Annotated[
        datetime | None, Query(alias="from", description="Rows at or after this instant.")
    ] = None,
    to: Annotated[datetime | None, Query(description="Rows at or before this instant.")] = None,
    q: Annotated[
        str | None,
        Query(
            max_length=36,
            pattern=r"^[0-9A-Fa-f-]+$",
            description="Free text: an entity id or its first characters.",
        ),
    ] = None,
) -> AuditFilters:
    return AuditFilters(entity, entity_id, actor_id, actor_role, action, from_, to, q)


Filters = Annotated[AuditFilters, Depends(audit_filters)]


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
    filters: Filters,
) -> AuditLogPage:
    stmt = filters.apply(select(AuditLog), actor.tenant_id)
    before = page.before(AuditLog.created_at, AuditLog.id)
    if before is not None:
        stmt = stmt.where(before)
    stmt = stmt.order_by(AuditLog.created_at.desc(), AuditLog.id.desc()).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    items, next_cursor = page.slice(rows)
    return AuditLogPage(items=[AuditLogOut.from_row(r) for r in items], next_cursor=next_cursor)


def _cell(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, dict | list):
        text = json.dumps(value, sort_keys=True, ensure_ascii=False)
    elif isinstance(value, datetime):
        text = value.isoformat()
    else:
        text = str(value)
    return "'" + text if text.startswith(_FORMULA_PREFIXES) else text


def _csv(rows: list[AuditLog]) -> Iterator[bytes]:
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(EXPORT_COLUMNS)
    yield buf.getvalue().encode("utf-8")
    for row in rows:
        buf.seek(0)
        buf.truncate()
        writer.writerow([_cell(getattr(row, col)) for col in EXPORT_COLUMNS])
        yield buf.getvalue().encode("utf-8")


@router.get(
    "/export",
    operation_id="exportAuditLogs",
    summary="CSV of the filtered audit trail (step-up required; audited)",
    response_class=StreamingResponse,
    openapi_extra=STEP_UP_OPENAPI,
    responses={
        200: {"content": {"text/csv": {}}, "description": "CSV file."},
        **problem_responses((401, "step_up_required")),
    },
)
async def export_audit_logs(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    filters: Filters,
) -> StreamingResponse:
    stmt = (
        filters.apply(select(AuditLog), actor.tenant_id)
        .order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        .limit(EXPORT_MAX_ROWS)
    )
    rows = list((await session.execute(stmt)).scalars().all())
    audit.record(
        session,
        action="audit_log.export",
        entity="audit_log",
        entity_id=actor.tenant_id,
        after={"filters": filters.as_json(), "rows": len(rows)},
    )
    await session.flush()
    return StreamingResponse(
        _csv(rows),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="audit-log.csv"'},
    )
