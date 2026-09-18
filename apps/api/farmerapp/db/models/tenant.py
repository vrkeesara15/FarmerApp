from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import String, event, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns


class Tenant(Base, BaseColumns):
    """SPEC 8.2: tenant(name, plan, branding jsonb, settings jsonb).

    A tenant is its own tenant: ``tenant_id == id`` (kept so RLS policies are uniform).
    """

    __tablename__ = "tenant"

    name: Mapped[str] = mapped_column(String(200), nullable=False)
    slug: Mapped[str | None] = mapped_column(String(50), nullable=True, unique=True)
    plan: Mapped[str] = mapped_column(String(50), nullable=False, server_default=text("'pilot'"))
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
