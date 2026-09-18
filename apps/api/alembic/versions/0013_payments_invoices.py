"""Payments, webhooks, day close and GST invoices (FA-021, SEC-023, ST-001, ST-002, ST-006)

Revision ID: 0013
Revises: 0011
Create Date: 2026-09-18 23:59:00 UTC

Branch label ``payments`` (the orders branch adds its own revision on top of 0011; the merge
revision joins the heads). Expand-only, backward compatible:

* ``payment``: ``status`` widened to 24 characters and ``pending_reconciliation`` added (cash
  waits for the day close); the target CHECK relaxed so a khata dues payment can exist
  before its credit entry (``farmer_id`` set, ``order_id`` / ``khata_entry_id`` NULL);
  new nullable columns ``provider_order_id`` (Razorpay QR / payment link id),
  ``qr_payload``, ``short_url``, ``expires_at``, ``day_close_id`` (the close that
  reconciled a cash payment), ``failure_reason``.
* ``webhook_event``: ``status`` gains ``flagged`` (amount mismatch) and ``rejected`` (bad
  signature).
* ``day_close``: ``status`` (closed / reopened), ``reopened_by`` / ``reopened_at`` /
  ``reopen_reason`` and ``variance_flagged``.
* New ``invoice`` (ST-001 GST invoice snapshot, one per order, number unique per tenant)
  and ``invoice_counter`` (gapless number per store and financial year, locked FOR UPDATE).
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

# Constraint names are complete (``op.f``); the f-string SQL below only interpolates the
# module constants.

revision: str = "0013"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = ("payments",)
depends_on: str | Sequence[str] | None = None

_OLD_PAYMENT_STATUS = "status IN ('created', 'pending', 'paid', 'failed', 'refunded', 'reconciled')"
_NEW_PAYMENT_STATUS = (
    "status IN ('created', 'pending', 'pending_reconciliation', 'paid', 'failed', 'refunded', "
    "'reconciled')"
)
_OLD_TARGET = "order_id IS NOT NULL OR khata_entry_id IS NOT NULL"
_NEW_TARGET = "order_id IS NOT NULL OR khata_entry_id IS NOT NULL OR farmer_id IS NOT NULL"
_OLD_WEBHOOK_STATUS = "status IN ('received', 'processed', 'ignored', 'failed')"
_NEW_WEBHOOK_STATUS = (
    "status IN ('received', 'processed', 'ignored', 'failed', 'flagged', 'rejected')"
)


def upgrade() -> None:
    # ---------------------------------------------------------------- payment
    op.alter_column(
        "payment", "status", type_=sa.String(length=24), existing_type=sa.String(length=16)
    )
    op.drop_constraint(op.f("ck_payment_status"), "payment", type_="check")
    op.create_check_constraint(op.f("ck_payment_status"), "payment", _NEW_PAYMENT_STATUS)
    op.drop_constraint(op.f("ck_payment_target"), "payment", type_="check")
    op.create_check_constraint(op.f("ck_payment_target"), "payment", _NEW_TARGET)
    op.add_column("payment", sa.Column("provider_order_id", sa.String(length=64), nullable=True))
    op.add_column("payment", sa.Column("qr_payload", sa.Text(), nullable=True))
    op.add_column("payment", sa.Column("short_url", sa.String(length=512), nullable=True))
    op.add_column("payment", sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("payment", sa.Column("day_close_id", sa.Uuid(), nullable=True))
    op.add_column("payment", sa.Column("failure_reason", sa.String(length=64), nullable=True))
    op.create_foreign_key(
        op.f("fk_payment_day_close_id_day_close"),
        "payment",
        "day_close",
        ["day_close_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_payment_provider_order_id", "payment", ["tenant_id", "provider_order_id"], unique=False
    )
    op.create_index("ix_payment_day_close_id", "payment", ["day_close_id"], unique=False)

    # ---------------------------------------------------------------- webhook_event
    op.drop_constraint(op.f("ck_webhook_event_status"), "webhook_event", type_="check")
    op.create_check_constraint(
        op.f("ck_webhook_event_status"), "webhook_event", _NEW_WEBHOOK_STATUS
    )

    # ---------------------------------------------------------------- day_close
    op.add_column(
        "day_close",
        sa.Column(
            "status", sa.String(length=16), server_default=sa.text("'closed'"), nullable=False
        ),
    )
    op.add_column("day_close", sa.Column("reopened_by", sa.Uuid(), nullable=True))
    op.add_column("day_close", sa.Column("reopened_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("day_close", sa.Column("reopen_reason", sa.Text(), nullable=True))
    op.add_column(
        "day_close",
        sa.Column(
            "variance_flagged", sa.Boolean(), server_default=sa.text("false"), nullable=False
        ),
    )
    op.create_foreign_key(
        op.f("fk_day_close_reopened_by_user"),
        "day_close",
        "user",
        ["reopened_by"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_check_constraint(
        op.f("ck_day_close_status"), "day_close", "status IN ('closed', 'reopened')"
    )

    # ---------------------------------------------------------------- invoice_counter
    op.create_table(
        "invoice_counter",
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("financial_year", sa.String(length=7), nullable=False),
        sa.Column("last_seq", sa.Integer(), server_default="0", nullable=False),
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), server_default="1", nullable=False),
        sa.CheckConstraint("last_seq >= 0", name=op.f("ck_invoice_counter_last_seq")),
        sa.ForeignKeyConstraint(
            ["store_id"],
            ["store.id"],
            name=op.f("fk_invoice_counter_store_id_store"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_invoice_counter")),
        sa.UniqueConstraint(
            "tenant_id", "store_id", "financial_year", name=op.f("uq_invoice_counter_tenant_id")
        ),
    )
    op.create_index(
        op.f("ix_invoice_counter_tenant_id"), "invoice_counter", ["tenant_id"], unique=False
    )
    enable_rls("invoice_counter")

    # ---------------------------------------------------------------- invoice
    op.create_table(
        "invoice",
        sa.Column("order_id", sa.Uuid(), nullable=False),
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=True),
        sa.Column("invoice_no", sa.String(length=32), nullable=False),
        sa.Column("financial_year", sa.String(length=7), nullable=False),
        sa.Column("seq", sa.Integer(), nullable=False),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("seller_name", sa.String(length=200), nullable=False),
        sa.Column("seller_gstin", sa.String(length=15), nullable=False),
        sa.Column("seller_address", sa.String(length=300), nullable=False),
        sa.Column("seller_state", sa.String(length=80), nullable=False),
        sa.Column("seller_state_code", sa.String(length=2), nullable=False),
        sa.Column("buyer_name", sa.String(length=200), nullable=False),
        sa.Column("buyer_phone", sa.String(length=16), nullable=True),
        sa.Column("buyer_gstin", sa.String(length=15), nullable=True),
        sa.Column("buyer_state", sa.String(length=80), nullable=False),
        sa.Column("place_of_supply", sa.String(length=90), nullable=False),
        sa.Column("supply_type", sa.String(length=8), nullable=False),
        sa.Column("taxable_paise", sa.BigInteger(), nullable=False),
        sa.Column("cgst_paise", sa.BigInteger(), nullable=False),
        sa.Column("sgst_paise", sa.BigInteger(), nullable=False),
        sa.Column("igst_paise", sa.BigInteger(), nullable=False),
        sa.Column("round_off_paise", sa.BigInteger(), nullable=False),
        sa.Column("total_paise", sa.BigInteger(), nullable=False),
        sa.Column("amount_in_words", sa.Text(), nullable=False),
        sa.Column("lines", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("pdf_uri", sa.String(length=512), nullable=True),
        sa.Column("created_by", sa.Uuid(), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("version", sa.Integer(), server_default="1", nullable=False),
        sa.CheckConstraint(
            "supply_type IN ('intra', 'inter')", name=op.f("ck_invoice_supply_type")
        ),
        sa.CheckConstraint(
            "taxable_paise >= 0 AND cgst_paise >= 0 AND sgst_paise >= 0 AND igst_paise >= 0 "
            "AND total_paise >= 0",
            name=op.f("ck_invoice_amounts"),
        ),
        sa.CheckConstraint(
            "total_paise = taxable_paise + cgst_paise + sgst_paise + igst_paise + round_off_paise",
            name=op.f("ck_invoice_total"),
        ),
        sa.CheckConstraint(
            "(supply_type = 'intra' AND igst_paise = 0) OR "
            "(supply_type = 'inter' AND cgst_paise = 0 AND sgst_paise = 0)",
            name=op.f("ck_invoice_tax_split"),
        ),
        sa.CheckConstraint("seq > 0", name=op.f("ck_invoice_seq")),
        sa.ForeignKeyConstraint(
            ["order_id"], ["order.id"], name=op.f("fk_invoice_order_id_order"), ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["store_id"], ["store.id"], name=op.f("fk_invoice_store_id_store"), ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"],
            ["farmer.id"],
            name=op.f("fk_invoice_farmer_id_farmer"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_invoice")),
        sa.UniqueConstraint("tenant_id", "invoice_no", name="uq_invoice_invoice_no"),
        sa.UniqueConstraint("tenant_id", "order_id", name="uq_invoice_order_id"),
        sa.UniqueConstraint(
            "tenant_id", "store_id", "financial_year", "seq", name="uq_invoice_store_fy_seq"
        ),
    )
    op.create_index(op.f("ix_invoice_tenant_id"), "invoice", ["tenant_id"], unique=False)
    op.create_index(
        "ix_invoice_store_issued", "invoice", ["tenant_id", "store_id", "issued_at"], unique=False
    )
    enable_rls("invoice")


def downgrade() -> None:
    disable_rls("invoice")
    op.drop_index("ix_invoice_store_issued", table_name="invoice")
    op.drop_index(op.f("ix_invoice_tenant_id"), table_name="invoice")
    op.drop_table("invoice")
    disable_rls("invoice_counter")
    op.drop_index(op.f("ix_invoice_counter_tenant_id"), table_name="invoice_counter")
    op.drop_table("invoice_counter")

    op.drop_constraint(op.f("ck_day_close_status"), "day_close", type_="check")
    op.drop_constraint(op.f("fk_day_close_reopened_by_user"), "day_close", type_="foreignkey")
    for column in ("variance_flagged", "reopen_reason", "reopened_at", "reopened_by", "status"):
        op.drop_column("day_close", column)

    op.drop_constraint(op.f("ck_webhook_event_status"), "webhook_event", type_="check")
    op.execute("UPDATE webhook_event SET status = 'failed' WHERE status IN ('flagged', 'rejected')")
    op.create_check_constraint(
        op.f("ck_webhook_event_status"), "webhook_event", _OLD_WEBHOOK_STATUS
    )

    op.drop_index("ix_payment_day_close_id", table_name="payment")
    op.drop_index("ix_payment_provider_order_id", table_name="payment")
    op.drop_constraint(op.f("fk_payment_day_close_id_day_close"), "payment", type_="foreignkey")
    for column in (
        "failure_reason",
        "day_close_id",
        "expires_at",
        "short_url",
        "qr_payload",
        "provider_order_id",
    ):
        op.drop_column("payment", column)
    op.drop_constraint(op.f("ck_payment_target"), "payment", type_="check")
    # Dues payments made while 0013 was live keep existing: the old CHECK comes back NOT VALID
    # (enforced for new rows only) instead of deleting money records.
    op.execute(
        f"ALTER TABLE payment ADD CONSTRAINT ck_payment_target CHECK ({_OLD_TARGET}) NOT VALID"
    )
    op.drop_constraint(op.f("ck_payment_status"), "payment", type_="check")
    op.execute("UPDATE payment SET status = 'paid' WHERE status = 'pending_reconciliation'")
    op.create_check_constraint(op.f("ck_payment_status"), "payment", _OLD_PAYMENT_STATUS)
    op.alter_column(
        "payment", "status", type_=sa.String(length=16), existing_type=sa.String(length=24)
    )
