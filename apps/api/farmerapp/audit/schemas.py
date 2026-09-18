"""Response models for ``/v1/audit-logs``."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict

from farmerapp.api.pagination import PageOut
from farmerapp.db.models import AuditLog


class AuditLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    actor_id: uuid.UUID | None
    actor_role: str
    action: str
    entity: str
    entity_id: uuid.UUID
    before: dict[str, Any] | None
    after: dict[str, Any] | None
    ip: str | None
    device_id: str | None
    user_agent: str | None
    trace_id: str | None
    created_at: datetime

    @classmethod
    def from_row(cls, row: AuditLog) -> AuditLogOut:
        return cls.model_validate(row)


AuditLogPage = PageOut[AuditLogOut]

__all__ = ["AuditLogOut", "AuditLogPage"]
