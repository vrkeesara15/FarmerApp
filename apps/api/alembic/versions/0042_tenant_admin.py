"""WC-014 platform tenant administration + NF-007 scale indexes

Revision ID: 0042
Revises: 0036, 0040
Create Date: 2026-09-21 09:00:00 UTC

This revision is also the merge point of the two heads this branch started from (``0036``
analytics segments and ``0040`` security/privacy): ``alembic upgrade head`` must resolve to
one head, so the first migration after a fork rejoins the graph.

Expand-only and backward compatible: every new column has a server default, the widened
``user.role`` check accepts everything it accepted before, and no existing column changes
type or nullability. An older API deployed against this schema keeps working (it simply never
writes ``platform_admin`` and never reads the new tables).

**WC-014**

* ``tenant.status`` (``active`` | ``suspended`` | ``archived``, default ``active``) and
  ``tenant.plan_limits`` (jsonb, default ``{}``) — the two facts the request path reads inside
  the tenant's own RLS binding.
* ``user.role`` check widened with ``platform_admin`` (the platform-level role, which only
  ever exists in the platform tenant).
* ``platform_tenant`` — the registry, owned by the platform tenant.
* ``usage_counter`` — incremental usage per (metric, period), owned by the subject tenant.
* ``billing_statement`` — the frozen monthly statement, owned by the subject tenant.

All three go under RLS like every other tenant table (``tests/rls/test_meta.py``).

**NF-007** — the indexes the scale suite's query plans asked for (docs/perf/NF-007.md). Each
one replaced a sequential scan over a table that grows with tenant size:

* ``ix_farmer_tenant_created_id`` — ``GET /v1/farmers`` orders by ``(created_at, id)`` within
  the tenant and pages with a keyset cursor; at 40,000 farmers the planner was sorting the
  whole tenant to return 50 rows.
* ``ix_visit_tenant_created`` — the owner-home and field-team windows read visits by
  ``created_at`` for the tenant, not by officer, so the officer-leading index did not help.
* ``ix_diagnosis_tenant_created`` — same shape for the diagnosis list and the AN-007 counts.
* ``ix_corpus_image_tenant_status_created`` — the corpus manager pages approved images by age.
* ``ix_order_tenant_created`` — the store day views and AN-003 read orders by age per tenant.
* ``ix_visit_photo_tenant_created`` / ``ix_farm_photo_tenant_created`` — the photo counters'
  recount (and the NF-012 photo sweep) bound by month; without them a recount reads every
  photo row of the tenant.

``location_point`` is already partitioned daily (migration 0010), which is the right answer at
this volume and needs nothing here.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0042"
down_revision: str | Sequence[str] | None = "0041"
branch_labels: str | Sequence[str] | None = ("tenant_admin",)
depends_on: str | Sequence[str] | None = None

_ROLES = (
    "owner",
    "director",
    "cluster_head",
    "auditor",
    "store_manager",
    "accountant",
    "field_officer",
    "agronomist",
    "tenant_admin",
    "farmer",
    "platform_admin",
)
_ROLE_CHECK = "role IN (" + ", ".join(f"'{r}'" for r in _ROLES) + ")"
_OLD_ROLE_CHECK = "role IN (" + ", ".join(f"'{r}'" for r in _ROLES[:-1]) + ")"

_STATUS_CHECK = "status IN ('active', 'suspended', 'archived')"

#: (name, table, columns, where) of the NF-007 indexes.
_SCALE_INDEXES: tuple[tuple[str, str, tuple[str, ...], str | None], ...] = (
    ("ix_farmer_tenant_created_id", "farmer", ("tenant_id", "created_at", "id"), None),
    ("ix_visit_tenant_created", "visit", ("tenant_id", "created_at"), None),
    ("ix_diagnosis_tenant_created", "diagnosis", ("tenant_id", "created_at"), None),
    (
        "ix_corpus_image_tenant_status_created",
        "corpus_image",
        ("tenant_id", "status", "created_at"),
        None,
    ),
    ("ix_order_tenant_created", "order", ("tenant_id", "created_at"), None),
    ("ix_visit_photo_tenant_created", "visit_photo", ("tenant_id", "created_at"), None),
    ("ix_farm_photo_tenant_created", "farm_photo", ("tenant_id", "created_at"), None),
)


def _base_columns() -> list[Any]:
    return [
        sa.Column("id", sa.Uuid(), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
    ]


def upgrade() -> None:
    # ---------------------------------------------------------------- tenant columns
    op.add_column(
        "tenant",
        sa.Column("status", sa.String(16), nullable=False, server_default=sa.text("'active'")),
    )
    op.add_column(
        "tenant",
        sa.Column(
            "plan_limits",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
    )
    op.create_check_constraint(op.f("ck_tenant_status"), "tenant", _STATUS_CHECK)

    # ---------------------------------------------------------------- platform_admin role
    op.drop_constraint(op.f("ck_user_role"), "user", type_="check")
    op.create_check_constraint(op.f("ck_user_role"), "user", _ROLE_CHECK)

    # ---------------------------------------------------------------- platform_tenant
    op.create_table(
        "platform_tenant",
        *_base_columns(),
        sa.Column("subject_tenant_id", sa.Uuid(), nullable=False),
        sa.Column("slug", sa.String(50), nullable=False),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("plan", sa.String(50), nullable=False),
        sa.Column("status", sa.String(16), nullable=False, server_default=sa.text("'active'")),
        sa.Column("region", sa.String(32), nullable=False, server_default=sa.text("'asia-south1'")),
        sa.Column("primary_contact_user_id", sa.Uuid(), nullable=True),
        sa.Column("primary_contact_name", sa.String(200), nullable=True),
        sa.Column(
            "plan_limits",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "provisioned",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("provisioned_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("suspended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("notes", sa.String(1000), nullable=True),
        sa.CheckConstraint(_STATUS_CHECK, name="status"),
        sa.UniqueConstraint("tenant_id", "subject_tenant_id", name="uq_platform_tenant_subject"),
        sa.UniqueConstraint("tenant_id", "slug", name="uq_platform_tenant_slug"),
    )
    op.create_index("ix_platform_tenant_tenant_id", "platform_tenant", ["tenant_id"])
    op.create_index("ix_platform_tenant_status", "platform_tenant", ["tenant_id", "status"])
    enable_rls("platform_tenant")

    # ---------------------------------------------------------------- usage_counter
    op.create_table(
        "usage_counter",
        *_base_columns(),
        sa.Column("metric", sa.String(32), nullable=False),
        sa.Column("period", sa.String(7), nullable=False),
        sa.Column("count", sa.BigInteger(), nullable=False, server_default=sa.text("0")),
        sa.CheckConstraint("count >= 0", name="count_not_negative"),
        sa.UniqueConstraint("tenant_id", "metric", "period", name="uq_usage_counter_key"),
    )
    op.create_index("ix_usage_counter_tenant_id", "usage_counter", ["tenant_id"])
    enable_rls("usage_counter")

    # ---------------------------------------------------------------- billing_statement
    op.create_table(
        "billing_statement",
        *_base_columns(),
        sa.Column("period", sa.String(7), nullable=False),
        sa.Column("plan", sa.String(50), nullable=False),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "lines",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("base_price_paise", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("overage_paise", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("total_paise", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("external_invoice_ref", sa.String(120), nullable=True),
        sa.UniqueConstraint("tenant_id", "period", name="uq_billing_statement_period"),
    )
    op.create_index("ix_billing_statement_tenant_id", "billing_statement", ["tenant_id"])
    enable_rls("billing_statement")

    # ---------------------------------------------------------------- NF-007 indexes
    for name, table, columns, where in _SCALE_INDEXES:
        op.create_index(
            name,
            table,
            list(columns),
            postgresql_where=sa.text(where) if where else None,
        )


def downgrade() -> None:
    for name, table, _columns, _where in reversed(_SCALE_INDEXES):
        op.drop_index(name, table_name=table)
    for table in ("billing_statement", "usage_counter", "platform_tenant"):
        disable_rls(table)
        op.drop_table(table)
    op.drop_constraint(op.f("ck_user_role"), "user", type_="check")
    op.create_check_constraint(op.f("ck_user_role"), "user", _OLD_ROLE_CHECK)
    op.drop_constraint(op.f("ck_tenant_status"), "tenant", type_="check")
    op.drop_column("tenant", "plan_limits")
    op.drop_column("tenant", "status")
