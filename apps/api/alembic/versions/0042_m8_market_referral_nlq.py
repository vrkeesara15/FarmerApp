"""M8: mandi prices, farmer referrals, and the AN-016 authorised views + read-only role

Revision ID: 0042
Revises: 0036, 0040
Create Date: 2026-09-21 09:00:00 UTC

SPEC 2.4 (FM-012, FM-013), 5.3 (AN-016), 11.3 (SEC-027).

* ``mandi_price`` — FM-012: one row per market x crop x variety x grade x date from the
  public source, with the source name and the fetch time.
* ``referral`` — FM-013: pending -> attributed -> rewarded, with the referrer, the invited
  farmer and the store credited; ``farmer.referral_code`` is the farmer's own invite code
  (nullable, minted on first use, unique per tenant — no backfill needed).
* AN-016: the five authorised views (``farmerapp.nlq.views``), the ``app_nlq_scope_ok``
  scope function, and the ``farmerapp_readonly`` role that may ``SELECT`` on those views and
  **nothing else**.

Expand-only and backward compatible: two new tables, one nullable column, five views and a
role. Downgrade drops the views, the role grants, the tables and the column.

Branch label ``m8_extras``. ``down_revision`` is **both current heads**: main carried two
(``0036_analytics_segments`` and ``0040_m7_security_privacy``, siblings of ``0035``) with no
merge revision between them, so ``alembic upgrade head`` — which the test harness uses to
build its template database — could not resolve a target. This revision is that merge as well
as the M8 expansion, so the branch has exactly one head again. A parallel M8 branch that
takes ``0041`` from ``0040`` will need its own merge with this one, as the M7 branches did
(``0033``, ``0034``, ``0035``).
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op

from farmerapp.db.rls import APP_ROLE, disable_rls, enable_rls
from farmerapp.nlq import views as nlq_views

revision: str = "0042"
down_revision: str | Sequence[str] | None = ("0036", "0040")
branch_labels: str | Sequence[str] | None = ("m8_extras",)
depends_on: str | Sequence[str] | None = None

_TABLES = ("referral", "mandi_price")

_PRICE_SOURCES = "'agmarknet', 'fake'"
_REFERRAL_STATUSES = "'pending', 'attributed', 'rewarded', 'rejected'"
_REFERRAL_SOURCES = "'farmer_app', 'officer', 'invite'"


def _base() -> list[sa.Column[Any]]:
    return [
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
    ]


def _fk(table: str, column: str, target: str, ondelete: str) -> sa.ForeignKeyConstraint:
    return sa.ForeignKeyConstraint(
        [column], [f"{target}.id"], name=f"fk_{table}_{column}_{target}", ondelete=ondelete
    )


def upgrade() -> None:
    # ------------------------------------------------------------------ FM-012 mandi_price
    op.create_table(
        "mandi_price",
        *_base(),
        sa.Column("crop_id", sa.Uuid(), nullable=False),
        sa.Column("market", sa.String(120), nullable=False),
        sa.Column("district", sa.String(80), nullable=False),
        sa.Column("state", sa.String(80), nullable=False),
        sa.Column("variety", sa.String(80), server_default=sa.text("''"), nullable=False),
        sa.Column("grade", sa.String(40), server_default=sa.text("''"), nullable=False),
        sa.Column("price_date", sa.Date(), nullable=False),
        sa.Column("min_price_paise", sa.Integer(), nullable=False),
        sa.Column("modal_price_paise", sa.Integer(), nullable=False),
        sa.Column("max_price_paise", sa.Integer(), nullable=False),
        sa.Column("source", sa.String(24), nullable=False),
        sa.Column("source_name", sa.String(120), nullable=False),
        sa.Column("source_url", sa.String(300), nullable=True),
        sa.Column("fetched_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(f"source IN ({_PRICE_SOURCES})", name=op.f("ck_mandi_price_source")),
        sa.CheckConstraint("min_price_paise >= 0", name=op.f("ck_mandi_price_min_price_paise")),
        sa.CheckConstraint("modal_price_paise >= 0", name=op.f("ck_mandi_price_modal_price_paise")),
        sa.CheckConstraint("max_price_paise >= 0", name=op.f("ck_mandi_price_max_price_paise")),
        sa.CheckConstraint(
            "max_price_paise >= min_price_paise", name=op.f("ck_mandi_price_price_range")
        ),
        sa.UniqueConstraint(
            "tenant_id",
            "source",
            "market",
            "crop_id",
            "variety",
            "grade",
            "price_date",
            name="uq_mandi_price_reading",
        ),
        _fk("mandi_price", "crop_id", "crop", "CASCADE"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_mandi_price")),
    )
    op.create_index("ix_mandi_price_tenant_id", "mandi_price", ["tenant_id"])
    op.create_index(
        "ix_mandi_price_lookup", "mandi_price", ["tenant_id", "crop_id", "district", "price_date"]
    )
    op.create_index("ix_mandi_price_date", "mandi_price", ["tenant_id", "price_date"])
    enable_rls("mandi_price")

    # ------------------------------------------------------------------ FM-013 referral
    op.add_column("farmer", sa.Column("referral_code", sa.String(16), nullable=True))
    op.create_index(
        "uq_farmer_referral_code",
        "farmer",
        ["tenant_id", "referral_code"],
        unique=True,
        postgresql_where=sa.text("referral_code IS NOT NULL"),
    )

    op.create_table(
        "referral",
        *_base(),
        sa.Column("code", sa.String(16), nullable=False),
        sa.Column("referrer_farmer_id", sa.Uuid(), nullable=False),
        sa.Column("invited_farmer_id", sa.Uuid(), nullable=True),
        sa.Column("invited_phone_hash", sa.String(64), nullable=True),
        sa.Column("invited_phone_last4", sa.String(4), nullable=True),
        sa.Column("store_id", sa.Uuid(), nullable=True),
        sa.Column("status", sa.String(16), server_default=sa.text("'pending'"), nullable=False),
        sa.Column("source", sa.String(16), nullable=False),
        sa.Column("referrer_reward_paise", sa.Integer(), server_default="0", nullable=False),
        sa.Column("store_reward_paise", sa.Integer(), server_default="0", nullable=False),
        sa.Column("reward_note", sa.String(200), nullable=True),
        sa.Column("attributed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("rewarded_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("rewarded_by", sa.Uuid(), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.CheckConstraint(f"status IN ({_REFERRAL_STATUSES})", name=op.f("ck_referral_status")),
        sa.CheckConstraint(f"source IN ({_REFERRAL_SOURCES})", name=op.f("ck_referral_source")),
        sa.CheckConstraint(
            "invited_farmer_id IS NULL OR invited_farmer_id <> referrer_farmer_id",
            name=op.f("ck_referral_not_self"),
        ),
        sa.CheckConstraint(
            "status <> 'attributed' OR "
            "(invited_farmer_id IS NOT NULL AND attributed_at IS NOT NULL)",
            name=op.f("ck_referral_attributed_complete"),
        ),
        sa.CheckConstraint(
            "status <> 'rewarded' OR rewarded_at IS NOT NULL",
            name=op.f("ck_referral_rewarded_complete"),
        ),
        sa.CheckConstraint(
            "referrer_reward_paise >= 0", name=op.f("ck_referral_referrer_reward_paise")
        ),
        sa.CheckConstraint("store_reward_paise >= 0", name=op.f("ck_referral_store_reward_paise")),
        sa.CheckConstraint("char_length(code) BETWEEN 4 AND 16", name=op.f("ck_referral_code")),
        _fk("referral", "referrer_farmer_id", "farmer", "CASCADE"),
        _fk("referral", "invited_farmer_id", "farmer", "CASCADE"),
        _fk("referral", "store_id", "store", "SET NULL"),
        _fk("referral", "rewarded_by", "user", "SET NULL"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_referral")),
    )
    op.create_index("ix_referral_tenant_id", "referral", ["tenant_id"])
    op.create_index("ix_referral_referrer", "referral", ["tenant_id", "referrer_farmer_id"])
    op.create_index("ix_referral_store", "referral", ["tenant_id", "store_id", "status"])
    op.create_index("ix_referral_phone_hash", "referral", ["tenant_id", "invited_phone_hash"])
    op.create_index(
        "uq_referral_invited_farmer",
        "referral",
        ["tenant_id", "invited_farmer_id"],
        unique=True,
        postgresql_where=sa.text("invited_farmer_id IS NOT NULL AND deleted_at IS NULL"),
    )
    op.create_index(
        "uq_referral_pending_phone",
        "referral",
        ["tenant_id", "referrer_farmer_id", "invited_phone_hash"],
        unique=True,
        postgresql_where=sa.text(
            "invited_phone_hash IS NOT NULL AND status = 'pending' AND deleted_at IS NULL"
        ),
    )
    enable_rls("referral")

    # ------------------------------------------------------------------ AN-016
    for statement in (
        *nlq_views.role_statements(),
        *nlq_views.scope_function_statements(),
        *nlq_views.ddl_statements(),
    ):
        op.execute(statement)


def downgrade() -> None:
    for statement in nlq_views.drop_statements():
        op.execute(statement)
    op.execute(f"DROP FUNCTION IF EXISTS public.{nlq_views.SCOPE_FUNCTION}(uuid, uuid)")
    op.execute(f"REVOKE {nlq_views.READONLY_ROLE} FROM {APP_ROLE}")
    for table in _TABLES:
        disable_rls(table)
        op.drop_table(table)
    op.drop_index("uq_farmer_referral_code", table_name="farmer")
    op.drop_column("farmer", "referral_code")
