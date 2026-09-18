"""WC-005 catalogue writes: label-claim versions and retirement, no overlapping price ranges

Revision ID: 0014
Revises: 0011
Create Date: 2026-09-18 23:59:00 UTC

WC-005 (branch ``catalog``, developed concurrently with the orders and payments branches on
0011; the merge revision rejoins the heads):

* ``label_claim.supersedes_id`` (the approved claim a draft edits: approved claims are
  immutable, an edit is a new draft version), ``retired_by`` / ``retired_at``.
* The ``(tenant, sku, crop, pest)`` unique constraint becomes a **partial** unique index over
  approved, not-deleted claims: several versions (draft / retired) of one claim may coexist,
  but at most one is approved — the one ``recommendable_skus`` serves (DX-007).
* ``price_list`` gets an exclusion constraint (``btree_gist``): no two live rows of the same
  SKU and store (NULL = tenant default) have overlapping effective ranges. The API checks the
  same rule first to answer ``409 price_overlap`` per row; the constraint is the backstop.

Expand-only (backward compatible): new nullable columns, a looser uniqueness, and a
constraint the existing seed data already satisfies.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0014"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = ("catalog",)
depends_on: str | Sequence[str] | None = None

APPROVED_UNIQUE = "uq_label_claim_approved"
PRICE_NO_OVERLAP = "ex_price_list_no_overlap"


def upgrade() -> None:
    op.add_column("label_claim", sa.Column("supersedes_id", sa.Uuid(), nullable=True))
    op.add_column("label_claim", sa.Column("retired_by", sa.Uuid(), nullable=True))
    op.add_column("label_claim", sa.Column("retired_at", sa.DateTime(timezone=True), nullable=True))
    op.create_foreign_key(
        op.f("fk_label_claim_supersedes_id_label_claim"),
        "label_claim",
        "label_claim",
        ["supersedes_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_foreign_key(
        op.f("fk_label_claim_retired_by_user"),
        "label_claim",
        "user",
        ["retired_by"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_label_claim_supersedes_id", "label_claim", ["supersedes_id"])
    op.drop_constraint(op.f("uq_label_claim_tenant_id"), "label_claim", type_="unique")
    op.create_index(
        APPROVED_UNIQUE,
        "label_claim",
        ["tenant_id", "sku_id", "crop_id", "pest_or_disease_id"],
        unique=True,
        postgresql_where=sa.text("status = 'approved' AND deleted_at IS NULL"),
    )

    op.execute("CREATE EXTENSION IF NOT EXISTS btree_gist")
    op.execute(
        f"""
        ALTER TABLE price_list ADD CONSTRAINT {PRICE_NO_OVERLAP} EXCLUDE USING gist (
            tenant_id WITH =,
            sku_id WITH =,
            (coalesce(store_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =,
            daterange(effective_from, effective_to, '[]') WITH &&
        ) WHERE (deleted_at IS NULL)
        """
    )


def downgrade() -> None:
    op.execute(f"ALTER TABLE price_list DROP CONSTRAINT IF EXISTS {PRICE_NO_OVERLAP}")
    op.drop_index(APPROVED_UNIQUE, table_name="label_claim")
    op.create_unique_constraint(
        op.f("uq_label_claim_tenant_id"),
        "label_claim",
        ["tenant_id", "sku_id", "crop_id", "pest_or_disease_id"],
    )
    op.drop_index("ix_label_claim_supersedes_id", table_name="label_claim")
    op.drop_constraint(op.f("fk_label_claim_retired_by_user"), "label_claim", type_="foreignkey")
    op.drop_constraint(
        op.f("fk_label_claim_supersedes_id_label_claim"), "label_claim", type_="foreignkey"
    )
    op.drop_column("label_claim", "retired_at")
    op.drop_column("label_claim", "retired_by")
    op.drop_column("label_claim", "supersedes_id")
