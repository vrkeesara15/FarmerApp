"""SPEC 8.2 ``audit_log`` (FA-006): who changed what, when, from where.

Append-only: the app role may only INSERT and SELECT (migration 0004 revokes UPDATE/DELETE);
purging past the NF-012 retention (1 year minimum) is the migrate role's job
(``farmerapp.jobs.purge_audit_logs``). Rows are written by ``farmerapp.db.audit`` — the
session listener for ORM mutations and ``audit.record`` for explicit events such as login.
"""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import Index, String, Uuid, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, TenantRow


class AuditLog(Base, TenantRow):
    __tablename__ = "audit_log"
    __table_args__ = (
        # WC-103 viewer: history of one record, newest first.
        Index(
            "ix_audit_log_tenant_entity_created",
            "tenant_id",
            "entity",
            "entity_id",
            "created_at",
            postgresql_ops={"created_at": "DESC"},
        ),
        # GET /v1/audit-logs listing + purge by age.
        Index("ix_audit_log_tenant_created", "tenant_id", "created_at", "id"),
        # VA-F06 shared devices: farmer registrations by device (NF-005; Alembic 0026).
        Index(
            "ix_audit_log_farmer_create_device",
            "tenant_id",
            "device_id",
            postgresql_where=text("action = 'farmer.create'"),
        ),
    )
    __audit__ = False  # the trail does not audit itself

    actor_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)  # NULL = system
    actor_role: Mapped[str] = mapped_column(String(32), nullable=False)
    action: Mapped[str] = mapped_column(String(64), nullable=False)  # "<entity>.<verb>"
    entity: Mapped[str] = mapped_column(String(64), nullable=False)  # table name
    entity_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    before: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    after: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    ip: Mapped[str | None] = mapped_column(String(45), nullable=True)
    device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    user_agent: Mapped[str | None] = mapped_column(String(512), nullable=True)
    trace_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    # SEC-024: Play Integrity verdict of the request that wrote the row (login and sensitive
    # actions; NULL otherwise). ``{status, actions, reasons, package, app_verdict, ...}``.
    integrity: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
