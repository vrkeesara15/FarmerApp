"""M3: catalogue, label claims, stock ledger, orders, payments, khata, credit limits,
webhook events and day close

Revision ID: 0011
Revises: 0010
Create Date: 2026-09-18 23:30:00 UTC

M3-KICKOFF (SPEC 14.4): the SPEC 8.2 entities for catalogue, store mode, orders, payments and
khata — thirteen new tables, nothing existing changed (backward compatible):

* ``product``, ``sku``, ``price_list`` (WC-005; money as integer paise, GST in basis points),
  ``pest_or_disease`` (problem master shared with the M6 corpus), ``label_claim`` (DX-007 —
  the only path to recommend a SKU; ``status`` draft / approved / retired).
* ``stock_batch`` (qty cache) and the **append-only** ``stock_movement`` ledger (ST-003).
* ``order`` / ``order_line`` (FA-020, ST-001, ST-005; ``total = subtotal - discount + tax``
  CHECK; ``label_claim_id`` = why a line was recommended).
* ``payment`` (FA-021, ST-002; ``provider_event_id`` unique per tenant and provider),
  ``webhook_event`` (SEC-023 idempotency by provider event id, signature result, payload),
  ``day_close`` (ST-006; one per store and business date, variance CHECK).
* **append-only** ``khata_entry`` (FA-022: balance = sum of entries) and ``credit_limit``
  (ST-007).

Every table gets the base columns, ``enable_rls`` (SELECT + INSERT only for the two
append-only ledgers) and FK / lookup indexes. Enumerations are CHECK constraints on short
strings (expand-only).
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import enable_rls

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "product",
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("brand", sa.String(length=120), nullable=False),
        sa.Column("own_brand", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("category", sa.String(length=16), nullable=False),
        sa.Column("hsn", sa.String(length=8), nullable=True),
        sa.Column("gst_rate_bp", sa.Integer(), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("active_ingredient", sa.Text(), nullable=True),
        sa.Column("formulation", sa.String(length=64), nullable=True),
        sa.Column(
            "names",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.Column("image_uri", sa.String(length=512), nullable=True),
        sa.Column("active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
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
            "category IN ('seed', 'fertiliser', 'pesticide', 'fungicide', 'herbicide', "
            "'growth', 'tool', 'other')",
            name=op.f("ck_product_category"),
        ),
        sa.CheckConstraint(
            "char_length(name) > 0 AND char_length(brand) > 0", name=op.f("ck_product_names")
        ),
        sa.CheckConstraint(
            "gst_rate_bp >= 0 AND gst_rate_bp <= 10000", name=op.f("ck_product_gst_rate_bp")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_product")),
        sa.UniqueConstraint("tenant_id", "brand", "name", name=op.f("uq_product_tenant_id")),
    )
    op.create_index(
        "ix_product_name_trgm",
        "product",
        ["name"],
        unique=False,
        postgresql_using="gin",
        postgresql_ops={"name": "gin_trgm_ops"},
    )
    op.create_index(
        "ix_product_tenant_category", "product", ["tenant_id", "category"], unique=False
    )
    op.create_index(op.f("ix_product_tenant_id"), "product", ["tenant_id"], unique=False)
    op.create_index(
        "ix_product_tenant_own_brand", "product", ["tenant_id", "own_brand"], unique=False
    )
    enable_rls("product")
    op.create_table(
        "webhook_event",
        sa.Column("provider", sa.String(length=16), nullable=False),
        sa.Column("event_id", sa.String(length=128), nullable=False),
        sa.Column("event_type", sa.String(length=64), nullable=True),
        sa.Column("signature_ok", sa.Boolean(), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column(
            "received_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("error", sa.Text(), nullable=True),
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
            "status IN ('received', 'processed', 'ignored', 'failed')",
            name=op.f("ck_webhook_event_status"),
        ),
        sa.CheckConstraint("char_length(event_id) > 0", name=op.f("ck_webhook_event_event_id")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_webhook_event")),
        sa.UniqueConstraint(
            "tenant_id", "provider", "event_id", name=op.f("uq_webhook_event_tenant_id")
        ),
    )
    op.create_index(
        "ix_webhook_event_received", "webhook_event", ["tenant_id", "received_at"], unique=False
    )
    op.create_index(
        op.f("ix_webhook_event_tenant_id"), "webhook_event", ["tenant_id"], unique=False
    )
    enable_rls("webhook_event")
    op.create_table(
        "pest_or_disease",
        sa.Column("code", sa.String(length=48), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column(
            "names",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.Column("type", sa.String(length=16), nullable=False),
        sa.Column("crop_id", sa.Uuid(), nullable=True),
        sa.Column("scientific_name", sa.String(length=160), nullable=True),
        sa.Column("symptoms", sa.Text(), nullable=True),
        sa.Column("active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
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
            "type IN ('disease', 'pest', 'nutrient', 'abiotic')",
            name=op.f("ck_pest_or_disease_type"),
        ),
        sa.ForeignKeyConstraint(
            ["crop_id"],
            ["crop.id"],
            name=op.f("fk_pest_or_disease_crop_id_crop"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_pest_or_disease")),
        sa.UniqueConstraint("tenant_id", "code", name=op.f("uq_pest_or_disease_tenant_id")),
    )
    op.create_index("ix_pest_or_disease_crop_id", "pest_or_disease", ["crop_id"], unique=False)
    op.create_index(
        op.f("ix_pest_or_disease_tenant_id"), "pest_or_disease", ["tenant_id"], unique=False
    )
    enable_rls("pest_or_disease")
    op.create_table(
        "sku",
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("pack_size_value", sa.Numeric(precision=10, scale=3), nullable=False),
        sa.Column("pack_size_unit", sa.String(length=8), nullable=False),
        sa.Column("barcode", sa.String(length=64), nullable=True),
        sa.Column("mrp_paise", sa.BigInteger(), nullable=False),
        sa.Column("active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
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
            "pack_size_unit IN ('ml', 'l', 'g', 'kg', 'pcs')", name=op.f("ck_sku_pack_size_unit")
        ),
        sa.CheckConstraint("mrp_paise >= 0", name=op.f("ck_sku_mrp_paise")),
        sa.CheckConstraint("pack_size_value > 0", name=op.f("ck_sku_pack_size_value")),
        sa.ForeignKeyConstraint(
            ["product_id"],
            ["product.id"],
            name=op.f("fk_sku_product_id_product"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_sku")),
        sa.UniqueConstraint("tenant_id", "barcode", name=op.f("uq_sku_tenant_id")),
    )
    op.create_index("ix_sku_product_id", "sku", ["product_id"], unique=False)
    op.create_index(op.f("ix_sku_tenant_id"), "sku", ["tenant_id"], unique=False)
    enable_rls("sku")
    op.create_table(
        "day_close",
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("business_date", sa.Date(), nullable=False),
        sa.Column("cash_expected_paise", sa.BigInteger(), nullable=False),
        sa.Column("cash_counted_paise", sa.BigInteger(), nullable=False),
        sa.Column("variance_paise", sa.BigInteger(), nullable=False),
        sa.Column("deposit_slip_uri", sa.String(length=512), nullable=True),
        sa.Column("closed_by", sa.Uuid(), nullable=False),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
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
            "cash_expected_paise >= 0 AND cash_counted_paise >= 0",
            name=op.f("ck_day_close_cash_amounts"),
        ),
        sa.CheckConstraint(
            "variance_paise = cash_counted_paise - cash_expected_paise",
            name=op.f("ck_day_close_variance"),
        ),
        sa.ForeignKeyConstraint(
            ["closed_by"],
            ["user.id"],
            name=op.f("fk_day_close_closed_by_user"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["store_id"], ["store.id"], name=op.f("fk_day_close_store_id_store"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_day_close")),
        sa.UniqueConstraint(
            "tenant_id", "store_id", "business_date", name=op.f("uq_day_close_tenant_id")
        ),
    )
    op.create_index(op.f("ix_day_close_tenant_id"), "day_close", ["tenant_id"], unique=False)
    enable_rls("day_close")
    op.create_table(
        "label_claim",
        sa.Column("sku_id", sa.Uuid(), nullable=False),
        sa.Column("crop_id", sa.Uuid(), nullable=False),
        sa.Column("pest_or_disease_id", sa.Uuid(), nullable=False),
        sa.Column("dose_per_acre", sa.String(length=120), nullable=False),
        sa.Column("dose_value", sa.Numeric(precision=10, scale=3), nullable=True),
        sa.Column("dose_unit", sa.String(length=8), nullable=True),
        sa.Column("dose_per_tank_15l", sa.String(length=64), nullable=True),
        sa.Column("phi_days", sa.Integer(), nullable=True),
        sa.Column("ppe_text", sa.Text(), nullable=True),
        sa.Column("safety_text", sa.Text(), nullable=True),
        sa.Column("source_ref", sa.String(length=200), nullable=False),
        sa.Column("efficacy_tier", sa.Integer(), nullable=True),
        sa.Column(
            "status", sa.String(length=16), server_default=sa.text("'draft'"), nullable=False
        ),
        sa.Column("approved_by", sa.Uuid(), nullable=True),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
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
            "dose_unit IS NULL OR dose_unit IN ('ml', 'g', 'l', 'kg')",
            name=op.f("ck_label_claim_dose_unit"),
        ),
        sa.CheckConstraint(
            "status <> 'approved' OR approved_at IS NOT NULL",
            name=op.f("ck_label_claim_approved_at"),
        ),
        sa.CheckConstraint(
            "status IN ('draft', 'approved', 'retired')", name=op.f("ck_label_claim_status")
        ),
        sa.CheckConstraint("char_length(source_ref) > 0", name=op.f("ck_label_claim_source_ref")),
        sa.CheckConstraint(
            "dose_value IS NULL OR dose_value > 0", name=op.f("ck_label_claim_dose_value")
        ),
        sa.CheckConstraint(
            "efficacy_tier IS NULL OR efficacy_tier BETWEEN 1 AND 3",
            name=op.f("ck_label_claim_efficacy_tier"),
        ),
        sa.CheckConstraint(
            "phi_days IS NULL OR phi_days >= 0", name=op.f("ck_label_claim_phi_days")
        ),
        sa.ForeignKeyConstraint(
            ["approved_by"],
            ["user.id"],
            name=op.f("fk_label_claim_approved_by_user"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["crop_id"], ["crop.id"], name=op.f("fk_label_claim_crop_id_crop"), ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["pest_or_disease_id"],
            ["pest_or_disease.id"],
            name=op.f("fk_label_claim_pest_or_disease_id_pest_or_disease"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["sku_id"], ["sku.id"], name=op.f("fk_label_claim_sku_id_sku"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_label_claim")),
        sa.UniqueConstraint(
            "tenant_id",
            "sku_id",
            "crop_id",
            "pest_or_disease_id",
            name=op.f("uq_label_claim_tenant_id"),
        ),
    )
    op.create_index(
        "ix_label_claim_crop_pest",
        "label_claim",
        ["tenant_id", "crop_id", "pest_or_disease_id", "status"],
        unique=False,
    )
    op.create_index(
        "ix_label_claim_pest_or_disease_id", "label_claim", ["pest_or_disease_id"], unique=False
    )
    op.create_index(op.f("ix_label_claim_tenant_id"), "label_claim", ["tenant_id"], unique=False)
    enable_rls("label_claim")
    op.create_table(
        "price_list",
        sa.Column("store_id", sa.Uuid(), nullable=True),
        sa.Column("sku_id", sa.Uuid(), nullable=False),
        sa.Column("price_paise", sa.BigInteger(), nullable=False),
        sa.Column("effective_from", sa.Date(), nullable=False),
        sa.Column("effective_to", sa.Date(), nullable=True),
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
            "effective_to IS NULL OR effective_to >= effective_from",
            name=op.f("ck_price_list_effective_range"),
        ),
        sa.CheckConstraint("price_paise >= 0", name=op.f("ck_price_list_price_paise")),
        sa.ForeignKeyConstraint(
            ["sku_id"], ["sku.id"], name=op.f("fk_price_list_sku_id_sku"), ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["store_id"],
            ["store.id"],
            name=op.f("fk_price_list_store_id_store"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_price_list")),
    )
    op.create_index(
        "ix_price_list_sku_store_from",
        "price_list",
        ["tenant_id", "sku_id", "store_id", "effective_from"],
        unique=False,
        postgresql_ops={"effective_from": "DESC"},
    )
    op.create_index(op.f("ix_price_list_tenant_id"), "price_list", ["tenant_id"], unique=False)
    enable_rls("price_list")
    op.create_table(
        "stock_batch",
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("sku_id", sa.Uuid(), nullable=False),
        sa.Column("batch_no", sa.String(length=64), nullable=False),
        sa.Column("expiry", sa.Date(), nullable=True),
        sa.Column("qty", sa.Numeric(precision=12, scale=3), server_default="0", nullable=False),
        sa.Column("cost_paise", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column(
            "received_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
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
        sa.CheckConstraint("char_length(batch_no) > 0", name=op.f("ck_stock_batch_batch_no")),
        sa.CheckConstraint("cost_paise >= 0", name=op.f("ck_stock_batch_cost_paise")),
        sa.CheckConstraint("qty >= 0", name=op.f("ck_stock_batch_qty")),
        sa.ForeignKeyConstraint(
            ["sku_id"], ["sku.id"], name=op.f("fk_stock_batch_sku_id_sku"), ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["store_id"],
            ["store.id"],
            name=op.f("fk_stock_batch_store_id_store"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_stock_batch")),
        sa.UniqueConstraint(
            "tenant_id", "store_id", "sku_id", "batch_no", name=op.f("uq_stock_batch_tenant_id")
        ),
    )
    op.create_index("ix_stock_batch_expiry", "stock_batch", ["tenant_id", "expiry"], unique=False)
    op.create_index(
        "ix_stock_batch_store_sku", "stock_batch", ["tenant_id", "store_id", "sku_id"], unique=False
    )
    op.create_index(op.f("ix_stock_batch_tenant_id"), "stock_batch", ["tenant_id"], unique=False)
    enable_rls("stock_batch")
    op.create_table(
        "stock_movement",
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("sku_id", sa.Uuid(), nullable=False),
        sa.Column("batch_id", sa.Uuid(), nullable=True),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("qty", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("ref_type", sa.String(length=32), nullable=True),
        sa.Column("ref_id", sa.Uuid(), nullable=True),
        sa.Column("note", sa.String(length=500), nullable=True),
        sa.Column("created_by", sa.Uuid(), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.CheckConstraint(
            "(kind IN ('receipt', 'transfer_in') AND qty > 0) OR "
            "(kind IN ('sale', 'transfer_out', 'damage') AND qty < 0) OR "
            "(kind = 'adjust' AND qty <> 0)",
            name=op.f("ck_stock_movement_qty_sign"),
        ),
        sa.CheckConstraint(
            "kind IN ('receipt', 'sale', 'transfer_out', 'transfer_in', 'damage', 'adjust')",
            name=op.f("ck_stock_movement_kind"),
        ),
        sa.ForeignKeyConstraint(
            ["batch_id"],
            ["stock_batch.id"],
            name=op.f("fk_stock_movement_batch_id_stock_batch"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["sku_id"], ["sku.id"], name=op.f("fk_stock_movement_sku_id_sku"), ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["store_id"],
            ["store.id"],
            name=op.f("fk_stock_movement_store_id_store"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_stock_movement")),
    )
    op.create_index("ix_stock_movement_batch_id", "stock_movement", ["batch_id"], unique=False)
    op.create_index(
        "ix_stock_movement_ref", "stock_movement", ["tenant_id", "ref_type", "ref_id"], unique=False
    )
    op.create_index(
        "ix_stock_movement_store_sku",
        "stock_movement",
        ["tenant_id", "store_id", "sku_id", "created_at"],
        unique=False,
    )
    enable_rls("stock_movement", append_only=True)
    op.create_table(
        "credit_limit",
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("limit_paise", sa.BigInteger(), nullable=False),
        sa.Column("set_by", sa.Uuid(), nullable=False),
        sa.Column("approved_by", sa.Uuid(), nullable=True),
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
        sa.CheckConstraint("limit_paise >= 0", name=op.f("ck_credit_limit_limit_paise")),
        sa.ForeignKeyConstraint(
            ["approved_by"],
            ["user.id"],
            name=op.f("fk_credit_limit_approved_by_user"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"],
            ["farmer.id"],
            name=op.f("fk_credit_limit_farmer_id_farmer"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["set_by"], ["user.id"], name=op.f("fk_credit_limit_set_by_user"), ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["store_id"],
            ["store.id"],
            name=op.f("fk_credit_limit_store_id_store"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_credit_limit")),
        sa.UniqueConstraint(
            "tenant_id", "farmer_id", "store_id", name=op.f("uq_credit_limit_tenant_id")
        ),
    )
    op.create_index(op.f("ix_credit_limit_tenant_id"), "credit_limit", ["tenant_id"], unique=False)
    enable_rls("credit_limit")
    op.create_table(
        "khata_entry",
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("type", sa.String(length=8), nullable=False),
        sa.Column("amount_paise", sa.BigInteger(), nullable=False),
        sa.Column("due_date", sa.Date(), nullable=True),
        sa.Column("ref_type", sa.String(length=16), nullable=False),
        sa.Column("ref_id", sa.Uuid(), nullable=True),
        sa.Column("note", sa.String(length=500), nullable=True),
        sa.Column("harvest_month", sa.Date(), nullable=True),
        sa.Column("created_by", sa.Uuid(), nullable=True),
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.CheckConstraint(
            "ref_type IN ('order', 'payment', 'adjustment')", name=op.f("ck_khata_entry_ref_type")
        ),
        sa.CheckConstraint("type IN ('debit', 'credit')", name=op.f("ck_khata_entry_type")),
        sa.CheckConstraint("amount_paise > 0", name=op.f("ck_khata_entry_amount_paise")),
        sa.CheckConstraint(
            "harvest_month IS NULL OR extract(day FROM harvest_month) = 1",
            name=op.f("ck_khata_entry_harvest_month"),
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"],
            ["farmer.id"],
            name=op.f("fk_khata_entry_farmer_id_farmer"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["store_id"],
            ["store.id"],
            name=op.f("fk_khata_entry_store_id_store"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_khata_entry")),
    )
    op.create_index(
        "ix_khata_entry_due_date", "khata_entry", ["tenant_id", "due_date"], unique=False
    )
    op.create_index(
        "ix_khata_entry_farmer_store",
        "khata_entry",
        ["tenant_id", "farmer_id", "store_id", "created_at"],
        unique=False,
    )
    op.create_index(
        "ix_khata_entry_ref", "khata_entry", ["tenant_id", "ref_type", "ref_id"], unique=False
    )
    enable_rls("khata_entry", append_only=True)
    op.create_table(
        "order",
        sa.Column("farmer_id", sa.Uuid(), nullable=True),
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("channel", sa.String(length=16), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("fulfilment", sa.String(length=16), nullable=False),
        sa.Column("subtotal_paise", sa.BigInteger(), nullable=False),
        sa.Column("discount_paise", sa.BigInteger(), nullable=False),
        sa.Column("tax_paise", sa.BigInteger(), nullable=False),
        sa.Column("total_paise", sa.BigInteger(), nullable=False),
        sa.Column("placed_by", sa.Uuid(), nullable=True),
        sa.Column("placed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("invoice_no", sa.String(length=32), nullable=True),
        sa.Column("client_order_id", sa.Uuid(), nullable=True),
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
            "channel IN ('officer', 'farmer_app', 'pos')", name=op.f("ck_order_channel")
        ),
        sa.CheckConstraint(
            "fulfilment IN ('pickup', 'delivery')", name=op.f("ck_order_fulfilment")
        ),
        sa.CheckConstraint(
            "status IN ('draft', 'placed', 'reserved', 'packed', 'ready', 'handed_over', "
            "'delivered', 'cancelled')",
            name=op.f("ck_order_status"),
        ),
        sa.CheckConstraint(
            "subtotal_paise >= 0 AND discount_paise >= 0 AND tax_paise >= 0 AND total_paise >= 0",
            name=op.f("ck_order_amounts"),
        ),
        sa.CheckConstraint(
            "total_paise = subtotal_paise - discount_paise + tax_paise", name=op.f("ck_order_total")
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"],
            ["farmer.id"],
            name=op.f("fk_order_farmer_id_farmer"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["placed_by"], ["user.id"], name=op.f("fk_order_placed_by_user"), ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["store_id"], ["store.id"], name=op.f("fk_order_store_id_store"), ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_order")),
        sa.UniqueConstraint("tenant_id", "client_order_id", name="uq_order_client_order_id"),
        sa.UniqueConstraint("tenant_id", "invoice_no", name="uq_order_invoice_no"),
    )
    op.create_index("ix_order_farmer_id", "order", ["farmer_id"], unique=False)
    op.create_index("ix_order_placed_by", "order", ["placed_by"], unique=False)
    op.create_index(
        "ix_order_store_status", "order", ["tenant_id", "store_id", "status"], unique=False
    )
    op.create_index(op.f("ix_order_tenant_id"), "order", ["tenant_id"], unique=False)
    enable_rls("order")
    op.create_table(
        "order_line",
        sa.Column("order_id", sa.Uuid(), nullable=False),
        sa.Column("sku_id", sa.Uuid(), nullable=False),
        sa.Column("batch_id", sa.Uuid(), nullable=True),
        sa.Column("qty", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("unit_price_paise", sa.BigInteger(), nullable=False),
        sa.Column("gst_rate_bp", sa.Integer(), nullable=False),
        sa.Column("line_total_paise", sa.BigInteger(), nullable=False),
        sa.Column("label_claim_id", sa.Uuid(), nullable=True),
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
            "gst_rate_bp >= 0 AND gst_rate_bp <= 10000", name=op.f("ck_order_line_gst_rate_bp")
        ),
        sa.CheckConstraint("qty > 0", name=op.f("ck_order_line_qty")),
        sa.CheckConstraint(
            "unit_price_paise >= 0 AND line_total_paise >= 0", name=op.f("ck_order_line_amounts")
        ),
        sa.ForeignKeyConstraint(
            ["batch_id"],
            ["stock_batch.id"],
            name=op.f("fk_order_line_batch_id_stock_batch"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["label_claim_id"],
            ["label_claim.id"],
            name=op.f("fk_order_line_label_claim_id_label_claim"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["order_id"],
            ["order.id"],
            name=op.f("fk_order_line_order_id_order"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["sku_id"], ["sku.id"], name=op.f("fk_order_line_sku_id_sku"), ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_order_line")),
    )
    op.create_index("ix_order_line_order_id", "order_line", ["order_id"], unique=False)
    op.create_index("ix_order_line_sku_id", "order_line", ["sku_id"], unique=False)
    op.create_index(op.f("ix_order_line_tenant_id"), "order_line", ["tenant_id"], unique=False)
    enable_rls("order_line")
    op.create_table(
        "payment",
        sa.Column("order_id", sa.Uuid(), nullable=True),
        sa.Column("khata_entry_id", sa.Uuid(), nullable=True),
        sa.Column("farmer_id", sa.Uuid(), nullable=True),
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("mode", sa.String(length=16), nullable=False),
        sa.Column("amount_paise", sa.BigInteger(), nullable=False),
        sa.Column("provider", sa.String(length=16), nullable=False),
        sa.Column("provider_ref", sa.String(length=64), nullable=True),
        sa.Column("provider_event_id", sa.String(length=64), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("receipt_uri", sa.String(length=512), nullable=True),
        sa.Column("collected_by", sa.Uuid(), nullable=True),
        sa.Column("reference_note", sa.String(length=200), nullable=True),
        sa.Column("paid_at", sa.DateTime(timezone=True), nullable=True),
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
            "(mode IN ('upi_qr', 'payment_link')) = (provider <> 'none')",
            name=op.f("ck_payment_provider_mode"),
        ),
        sa.CheckConstraint(
            "mode IN ('upi_qr', 'payment_link', 'cash', 'card_terminal', 'credit')",
            name=op.f("ck_payment_mode"),
        ),
        sa.CheckConstraint(
            "provider IN ('razorpay', 'cashfree', 'none')", name=op.f("ck_payment_provider")
        ),
        sa.CheckConstraint(
            "status IN ('created', 'pending', 'paid', 'failed', 'refunded', 'reconciled')",
            name=op.f("ck_payment_status"),
        ),
        sa.CheckConstraint("amount_paise > 0", name=op.f("ck_payment_amount_paise")),
        sa.CheckConstraint(
            "order_id IS NOT NULL OR khata_entry_id IS NOT NULL", name=op.f("ck_payment_target")
        ),
        sa.ForeignKeyConstraint(
            ["collected_by"],
            ["user.id"],
            name=op.f("fk_payment_collected_by_user"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"],
            ["farmer.id"],
            name=op.f("fk_payment_farmer_id_farmer"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["khata_entry_id"],
            ["khata_entry.id"],
            name=op.f("fk_payment_khata_entry_id_khata_entry"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["order_id"], ["order.id"], name=op.f("fk_payment_order_id_order"), ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["store_id"], ["store.id"], name=op.f("fk_payment_store_id_store"), ondelete="RESTRICT"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_payment")),
        sa.UniqueConstraint(
            "tenant_id", "provider", "provider_event_id", name=op.f("uq_payment_tenant_id")
        ),
    )
    op.create_index("ix_payment_collected_by", "payment", ["collected_by"], unique=False)
    op.create_index("ix_payment_farmer_id", "payment", ["farmer_id"], unique=False)
    op.create_index("ix_payment_order_id", "payment", ["order_id"], unique=False)
    op.create_index(
        "ix_payment_store_created", "payment", ["tenant_id", "store_id", "created_at"], unique=False
    )
    op.create_index(op.f("ix_payment_tenant_id"), "payment", ["tenant_id"], unique=False)

    enable_rls("payment")


def downgrade() -> None:
    op.drop_index(op.f("ix_payment_tenant_id"), table_name="payment")
    op.drop_index("ix_payment_store_created", table_name="payment")
    op.drop_index("ix_payment_order_id", table_name="payment")
    op.drop_index("ix_payment_farmer_id", table_name="payment")
    op.drop_index("ix_payment_collected_by", table_name="payment")
    op.drop_table("payment")
    op.drop_index(op.f("ix_order_line_tenant_id"), table_name="order_line")
    op.drop_index("ix_order_line_sku_id", table_name="order_line")
    op.drop_index("ix_order_line_order_id", table_name="order_line")
    op.drop_table("order_line")
    op.drop_index(op.f("ix_order_tenant_id"), table_name="order")
    op.drop_index("ix_order_store_status", table_name="order")
    op.drop_index("ix_order_placed_by", table_name="order")
    op.drop_index("ix_order_farmer_id", table_name="order")
    op.drop_table("order")
    op.drop_index("ix_khata_entry_ref", table_name="khata_entry")
    op.drop_index("ix_khata_entry_farmer_store", table_name="khata_entry")
    op.drop_index("ix_khata_entry_due_date", table_name="khata_entry")
    op.drop_table("khata_entry")
    op.drop_index(op.f("ix_credit_limit_tenant_id"), table_name="credit_limit")
    op.drop_table("credit_limit")
    op.drop_index("ix_stock_movement_store_sku", table_name="stock_movement")
    op.drop_index("ix_stock_movement_ref", table_name="stock_movement")
    op.drop_index("ix_stock_movement_batch_id", table_name="stock_movement")
    op.drop_table("stock_movement")
    op.drop_index(op.f("ix_stock_batch_tenant_id"), table_name="stock_batch")
    op.drop_index("ix_stock_batch_store_sku", table_name="stock_batch")
    op.drop_index("ix_stock_batch_expiry", table_name="stock_batch")
    op.drop_table("stock_batch")
    op.drop_index(op.f("ix_price_list_tenant_id"), table_name="price_list")
    op.drop_index(
        "ix_price_list_sku_store_from",
        table_name="price_list",
        postgresql_ops={"effective_from": "DESC"},
    )
    op.drop_table("price_list")
    op.drop_index(op.f("ix_label_claim_tenant_id"), table_name="label_claim")
    op.drop_index("ix_label_claim_pest_or_disease_id", table_name="label_claim")
    op.drop_index("ix_label_claim_crop_pest", table_name="label_claim")
    op.drop_table("label_claim")
    op.drop_index(op.f("ix_day_close_tenant_id"), table_name="day_close")
    op.drop_table("day_close")
    op.drop_index(op.f("ix_sku_tenant_id"), table_name="sku")
    op.drop_index("ix_sku_product_id", table_name="sku")
    op.drop_table("sku")
    op.drop_index(op.f("ix_pest_or_disease_tenant_id"), table_name="pest_or_disease")
    op.drop_index("ix_pest_or_disease_crop_id", table_name="pest_or_disease")
    op.drop_table("pest_or_disease")
    op.drop_index(op.f("ix_webhook_event_tenant_id"), table_name="webhook_event")
    op.drop_index("ix_webhook_event_received", table_name="webhook_event")
    op.drop_table("webhook_event")
    op.drop_index("ix_product_tenant_own_brand", table_name="product")
    op.drop_index(op.f("ix_product_tenant_id"), table_name="product")
    op.drop_index("ix_product_tenant_category", table_name="product")
    op.drop_index(
        "ix_product_name_trgm",
        table_name="product",
        postgresql_using="gin",
        postgresql_ops={"name": "gin_trgm_ops"},
    )
    op.drop_table("product")
