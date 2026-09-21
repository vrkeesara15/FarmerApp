from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import CheckConstraint, String, event, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns


class Tenant(Base, BaseColumns):
    """SPEC 8.2: tenant(name, plan, branding jsonb, settings jsonb).

    A tenant is its own tenant: ``tenant_id == id`` (kept so RLS policies are uniform).

    WC-014 adds the two columns the *runtime* needs inside the tenant's own binding:
    ``status`` (a suspended or archived tenant cannot authenticate —
    ``farmerapp.platform_admin.lifecycle``) and ``plan_limits`` (the sparse overrides merged
    over the catalogue plan named by ``plan`` — ``farmerapp.platform_admin.plans``). The
    platform-level registry that mirrors them lives in ``platform_tenant``, which only a
    ``platform_admin`` session can see.
    """

    __tablename__ = "tenant"
    __table_args__ = (
        CheckConstraint("status IN ('active', 'suspended', 'archived')", name="status"),
    )

    name: Mapped[str] = mapped_column(String(200), nullable=False)
    slug: Mapped[str | None] = mapped_column(String(50), nullable=True, unique=True)
    plan: Mapped[str] = mapped_column(String(50), nullable=False, server_default=text("'pilot'"))
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'active'"), default="active"
    )
    plan_limits: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, server_default=text("'{}'::jsonb"), default=dict
    )
    branding: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, server_default=text("'{}'::jsonb")
    )
    settings: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, server_default=text("'{}'::jsonb")
    )


@event.listens_for(Tenant, "before_insert")
def _self_tenant(_mapper: Any, _connection: Any, target: Tenant) -> None:
    tenant_id: uuid.UUID | None = target.tenant_id
    if tenant_id is None:
        current_id: uuid.UUID | None = target.id
        target.id = current_id or uuid.uuid4()
        target.tenant_id = target.id
