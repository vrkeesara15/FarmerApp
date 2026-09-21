"""WC-014 platform tables: the tenant registry, usage counters and billing statements.

Everything here is still an ordinary tenant table with ``tenant_id`` and RLS (SPEC 0.2 /
1.4): there is no table outside the isolation model, and ``tests/rls/test_meta.py`` checks it.
The trick is *which* tenant owns each row.

``platform_tenant`` — the registry, one row per tenant, owned by the **platform tenant**
    (``PLATFORM_TENANT_ID``). Only a session bound to the platform tenant can see it, which is
    exactly the set of sessions a ``platform_admin`` gets, so a tenant admin cannot even read
    the list of tenants, let alone another tenant's plan. ``subject_tenant_id`` points at the
    ``tenant`` row it describes.

``usage_counter`` — owned by the **subject tenant**, so the hot creation paths increment it on
    the connection they already have, inside the tenant binding they already hold. One row per
    (metric, period): ``period`` is ``total`` for standing head counts (officers, farmers,
    stores) and ``YYYY-MM`` for monthly ones (photos, campaigns, LLM calls). Increments are
    ``INSERT ... ON CONFLICT DO UPDATE SET count = count + :delta`` — O(1), never a
    ``SELECT count(*)`` over the tenant (NF-007: a full count of 40,000 farmers per
    registration is the thing this design exists to avoid). ``__audit__ = False``: a counter
    bump is not a business event and one audit row per photo would double the write volume.

``billing_statement`` — owned by the subject tenant, one row per (tenant, period). The lines
    are a frozen snapshot of the counters at generation time plus the plan's overage pricing,
    so re-reading a statement never re-derives a changed number. Money is integer paise.

``status`` lives on the ``tenant`` row (``farmerapp.db.models.tenant``) because every request
  has to check it cheaply inside the tenant's own binding; ``platform_tenant.status`` mirrors it
  and both are written in the same transaction (``farmerapp.platform_admin.lifecycle``), which
  ``tests/platform/test_lifecycle.py`` asserts.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    Index,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns

#: The tenant that owns the registry. Fixed so a fresh database, the seed and the tests agree.
PLATFORM_TENANT_NAMESPACE = uuid.UUID("6f0a4c5e-3f1d-4a6b-9b2e-2a4d7c1e0f00")
PLATFORM_TENANT_ID = uuid.uuid5(PLATFORM_TENANT_NAMESPACE, "platform")
PLATFORM_TENANT_SLUG = "platform"
PLATFORM_TENANT_NAME = "FarmerApp Platform"


class TenantStatus(StrEnum):
    """WC-014 lifecycle. ``archived`` is terminal: data is kept for retention, access is gone."""

    ACTIVE = "active"
    SUSPENDED = "suspended"
    ARCHIVED = "archived"


#: Statuses whose users may not authenticate (``farmerapp.platform_admin.lifecycle``).
BLOCKED_STATUSES: frozenset[str] = frozenset({TenantStatus.SUSPENDED, TenantStatus.ARCHIVED})


def _in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


TENANT_STATUS_CHECK = f"status IN ({_in(TenantStatus)})"


class PlatformTenant(Base, BaseColumns):
    """Registry row for one tenant, owned by the platform tenant."""

    __tablename__ = "platform_tenant"
    __table_args__ = (
        UniqueConstraint("tenant_id", "subject_tenant_id", name="uq_platform_tenant_subject"),
        UniqueConstraint("tenant_id", "slug", name="uq_platform_tenant_slug"),
        CheckConstraint(TENANT_STATUS_CHECK, name="status"),
        Index("ix_platform_tenant_status", "tenant_id", "status"),
    )

    #: The ``tenant.id`` this row describes (no FK: the tenant row is in another RLS scope).
    subject_tenant_id: Mapped[uuid.UUID] = mapped_column(nullable=False)
    slug: Mapped[str] = mapped_column(String(50), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    plan: Mapped[str] = mapped_column(String(50), nullable=False)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'active'"), default=TenantStatus.ACTIVE
    )
    region: Mapped[str] = mapped_column(
        String(32), nullable=False, server_default=text("'asia-south1'")
    )
    #: The first tenant_admin created with the tenant (WC-014 "primary contact").
    primary_contact_user_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    primary_contact_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    #: Sparse overrides merged over the catalogue plan (``platform_admin.plans.merge_limits``).
    plan_limits: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, server_default=text("'{}'::jsonb"), default=dict
    )
    #: What ``provision_tenant`` created, for the "usable in under 30 minutes" evidence.
    provisioned: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, server_default=text("'{}'::jsonb"), default=dict
    )
    provisioned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    suspended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    notes: Mapped[str | None] = mapped_column(String(1000), nullable=True)


class UsageCounter(Base, BaseColumns):
    """One (metric, period) counter of one tenant, maintained incrementally."""

    __tablename__ = "usage_counter"
    __table_args__ = (
        UniqueConstraint("tenant_id", "metric", "period", name="uq_usage_counter_key"),
        CheckConstraint("count >= 0", name="count_not_negative"),
    )
    #: A counter bump is bookkeeping, not a business event (see the module docstring).
    __audit__ = False

    metric: Mapped[str] = mapped_column(String(32), nullable=False)
    #: ``total`` for head counts, ``YYYY-MM`` for monthly metrics.
    period: Mapped[str] = mapped_column(String(7), nullable=False)
    count: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default=text("0"))


class BillingStatement(Base, BaseColumns):
    """WC-014 monthly usage statement: counts and overage, frozen at generation time."""

    __tablename__ = "billing_statement"
    __table_args__ = (UniqueConstraint("tenant_id", "period", name="uq_billing_statement_period"),)

    #: Billing month, ``YYYY-MM``.
    period: Mapped[str] = mapped_column(String(7), nullable=False)
    plan: Mapped[str] = mapped_column(String(50), nullable=False)
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    #: ``[{metric, used, included, overage, unit_price_paise, amount_paise}, ...]``
    lines: Mapped[list[dict[str, Any]]] = mapped_column(
        JSONB, nullable=False, server_default=text("'[]'::jsonb"), default=list
    )
    base_price_paise: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    overage_paise: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    total_paise: Mapped[int] = mapped_column(BigInteger, nullable=False, server_default="0")
    #: Set by the payment port when one is wired (``platform_admin.billing``); NULL = unbilled.
    external_invoice_ref: Mapped[str | None] = mapped_column(String(120), nullable=True)


__all__ = [
    "BLOCKED_STATUSES",
    "PLATFORM_TENANT_ID",
    "PLATFORM_TENANT_NAME",
    "PLATFORM_TENANT_SLUG",
    "TENANT_STATUS_CHECK",
    "BillingStatement",
    "PlatformTenant",
    "TenantStatus",
    "UsageCounter",
]
