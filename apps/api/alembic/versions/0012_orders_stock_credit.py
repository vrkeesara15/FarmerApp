"""FA-020 / ST-003 / ST-005 / ST-007: stock reservations, order status history, credit
approval requests and write-off details

Revision ID: 0012
Revises: 0011
Create Date: 2026-09-18 16:40:00 UTC

Branch ``orders`` (merged with the other M3 heads by the parent). Additive only (backward
compatible):

* ``stock_reservation`` — stock held per batch for an open order (FEFO at placement);
  ``available = on_hand - active reservations``; ``consumed`` at handover (the ``sale``
  movement is written then), ``released`` on cancel.
* **append-only** ``order_status_event`` — one row per ST-005 status change.
* ``credit_approval_request`` — ST-007: a credit sale beyond the farmer's limit waiting for
  the cluster head; approved requests let the same order proceed once (``used_at``).
* ``stock_movement.reason`` / ``photo_uri`` — write-off reason and photo, adjustment reason.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = ("orders",)
depends_on: str | Sequence[str] | None = None

ORDER_STATUSES = (
    "'draft', 'placed', 'reserved', 'packed', 'ready', 'handed_over', 'delivered', 'cancelled'"
)


def upgrade() -> None:
    op.create_table(
        "credit_approval_request",
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("order_id", sa.Uuid(), nullable=True),
        sa.Column("amount_paise", sa.BigInteger(), nullable=False),
        sa.Column("balance_paise", sa.BigInteger(), nullable=False),
        sa.Column("limit_paise", sa.BigInteger(), nullable=False),
        sa.Column("shortfall_paise", sa.BigInteger(), nullable=False),
        sa.Column("requested_by", sa.Uuid(), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("decided_by", sa.Uuid(), nullable=True),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("decision_note", sa.String(length=500), nullable=True),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), server_default="1", nullable=False),
        sa.CheckConstraint(
            "(status = 'pending') = (decided_by IS NULL AND decided_at IS NULL)",
            name=op.f("ck_credit_approval_request_decision"),
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'approved', 'rejected')",
            name=op.f("ck_credit_approval_request_status"),
        ),
        sa.CheckConstraint(
            "used_at IS NULL OR status = 'approved'",
            name=op.f("ck_credit_approval_request_used_at"),
        ),
        sa.CheckConstraint(
            "amount_paise > 0 AND shortfall_paise > 0",
            name=op.f("ck_credit_approval_request_amounts"),
        ),
        sa.ForeignKeyConstraint(
            ["decided_by"],
            ["user.id"],
            name=op.f("fk_credit_approval_request_decided_by_user"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"],
            ["farmer.id"],
            name=op.f("fk_credit_approval_request_farmer_id_farmer"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["requested_by"],
            ["user.id"],
            name=op.f("fk_credit_approval_request_requested_by_user"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["store_id"],
            ["store.id"],
            name=op.f("fk_credit_approval_request_store_id_store"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_credit_approval_request")),
    )
    op.create_index(
        "ix_credit_approval_request_farmer_store",
        "credit_approval_request",
        ["tenant_id", "farmer_id", "store_id"],
        unique=False,
    )
    op.create_index(
        "ix_credit_approval_request_order_id",
        "credit_approval_request",
        ["tenant_id", "order_id"],
        unique=False,
    )
    op.create_index(
        "ix_credit_approval_request_status",
        "credit_approval_request",
        ["tenant_id", "status"],
        unique=False,
    )
    op.create_index(
        op.f("ix_credit_approval_request_tenant_id"),
        "credit_approval_request",
        ["tenant_id"],
        unique=False,
    )
    enable_rls("credit_approval_request")
    op.create_table(
        "order_status_event",
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("order_id", sa.Uuid(), nullable=False),
        sa.Column("from_status", sa.String(length=16), nullable=True),
        sa.Column("to_status", sa.String(length=16), nullable=False),
        sa.Column("note", sa.String(length=500), nullable=True),
        sa.Column("actor_id", sa.Uuid(), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.CheckConstraint(
            f"from_status IS NULL OR from_status IN ({ORDER_STATUSES})",
            name=op.f("ck_order_status_event_from_status"),
        ),
        sa.CheckConstraint(
            f"to_status IN ({ORDER_STATUSES})",
            name=op.f("ck_order_status_event_to_status"),
        ),
        sa.ForeignKeyConstraint(
            ["actor_id"],
            ["user.id"],
            name=op.f("fk_order_status_event_actor_id_user"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["order_id"],
            ["order.id"],
            name=op.f("fk_order_status_event_order_id_order"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_order_status_event")),
    )
    op.create_index(
        "ix_order_status_event_order",
        "order_status_event",
        ["tenant_id", "order_id", "created_at"],
        unique=False,
    )
    enable_rls("order_status_event", append_only=True)
    op.create_table(
        "stock_reservation",
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("sku_id", sa.Uuid(), nullable=False),
        sa.Column("batch_id", sa.Uuid(), nullable=False),
        sa.Column("order_id", sa.Uuid(), nullable=False),
        sa.Column("order_line_id", sa.Uuid(), nullable=False),
        sa.Column("qty", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), server_default="1", nullable=False),
        sa.CheckConstraint(
            "status IN ('active', 'consumed', 'released')", name=op.f("ck_stock_reservation_status")
        ),
        sa.CheckConstraint("qty > 0", name=op.f("ck_stock_reservation_qty")),
        sa.ForeignKeyConstraint(
            ["batch_id"],
            ["stock_batch.id"],
            name=op.f("fk_stock_reservation_batch_id_stock_batch"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["order_id"],
            ["order.id"],
            name=op.f("fk_stock_reservation_order_id_order"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["order_line_id"],
            ["order_line.id"],
            name=op.f("fk_stock_reservation_order_line_id_order_line"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["sku_id"],
            ["sku.id"],
            name=op.f("fk_stock_reservation_sku_id_sku"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["store_id"],
            ["store.id"],
            name=op.f("fk_stock_reservation_store_id_store"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_stock_reservation")),
    )
    op.create_index(
        "ix_stock_reservation_batch_status",
        "stock_reservation",
        ["tenant_id", "batch_id", "status"],
        unique=False,
    )
    op.create_index(
        "ix_stock_reservation_order_id", "stock_reservation", ["order_id"], unique=False
    )
    op.create_index(
        op.f("ix_stock_reservation_tenant_id"), "stock_reservation", ["tenant_id"], unique=False
    )
    enable_rls("stock_reservation")
    op.add_column("stock_movement", sa.Column("reason", sa.String(length=16), nullable=True))
    op.add_column("stock_movement", sa.Column("photo_uri", sa.String(length=512), nullable=True))


def downgrade() -> None:
    op.drop_column("stock_movement", "photo_uri")
    op.drop_column("stock_movement", "reason")
    op.drop_index(op.f("ix_stock_reservation_tenant_id"), table_name="stock_reservation")
    op.drop_index("ix_stock_reservation_order_id", table_name="stock_reservation")
    op.drop_index("ix_stock_reservation_batch_status", table_name="stock_reservation")
    disable_rls("stock_reservation")
    op.drop_table("stock_reservation")
    op.drop_index("ix_order_status_event_order", table_name="order_status_event")
    disable_rls("order_status_event")
    op.drop_table("order_status_event")
    op.drop_index(
        op.f("ix_credit_approval_request_tenant_id"), table_name="credit_approval_request"
    )
    op.drop_index("ix_credit_approval_request_status", table_name="credit_approval_request")
    op.drop_index("ix_credit_approval_request_order_id", table_name="credit_approval_request")
    op.drop_index("ix_credit_approval_request_farmer_store", table_name="credit_approval_request")
    disable_rls("credit_approval_request")
    op.drop_table("credit_approval_request")
