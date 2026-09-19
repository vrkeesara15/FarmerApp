"""M7 growth: campaigns, targets and incentives, exports and scheduled reports, reorder levels

Revision ID: 0031
Revises: 0028
Create Date: 2026-09-19 22:00:00 UTC

Branch label ``growth`` (parallel to 0029 ``rules_m7`` and 0030 ``field_p1``; the parent
merges the heads).

* WC-008 / AN-008: ``campaign`` (segment, messages per language, channel, schedule,
  attribution window, holdout share) and ``campaign_recipient`` (frozen audience, arm,
  per-recipient delivery status, provider reference, DLT template id, push notification).
* WC-009: ``sales_target`` (monthly per officer / store), ``incentive_rule_set`` (versioned
  declarative rules, one active per tenant) and ``incentive_payout`` (frozen monthly close).
* WC-013 / AN-015 / ST-008 / NF-013: ``export_job``, ``report_schedule`` (cron in IST) and
  ``report_run`` (one delivery per dedupe key).
* ST-004: ``reorder_level`` per store and SKU.

Every table under RLS (``enable_rls``). Expand-only: new tables; downgrade drops them.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0031"
down_revision: str | Sequence[str] | None = "0028"
branch_labels: str | Sequence[str] | None = ("growth",)
depends_on: str | Sequence[str] | None = None

_TABLES = (
    "reorder_level",
    "report_run",
    "report_schedule",
    "export_job",
    "incentive_payout",
    "incentive_rule_set",
    "sales_target",
    "campaign_recipient",
    "campaign",
)


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
        [column],
        [f"{target}.id"],
        name=op.f(f"fk_{table}_{column}_{target}"),
        ondelete=ondelete,
    )


def _tenant_index(table: str) -> None:
    op.create_index(op.f(f"ix_{table}_tenant_id"), table, ["tenant_id"])


def upgrade() -> None:
    ts = sa.DateTime(timezone=True)

    # ------------------------------------------------------------------ campaigns
    op.create_table(
        "campaign",
        *_base(),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("channel", sa.String(16), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("segment", postgresql.JSONB(), nullable=False),
        sa.Column("messages", postgresql.JSONB(), nullable=False),
        sa.Column("template_key", sa.String(64), nullable=True),
        sa.Column("scheduled_at", ts, nullable=True),
        sa.Column("started_at", ts, nullable=True),
        sa.Column("finished_at", ts, nullable=True),
        sa.Column("attribution_days", sa.Integer(), nullable=False),
        sa.Column("holdout_pct", sa.Integer(), nullable=False),
        sa.Column("audience_size", sa.Integer(), nullable=True),
        sa.Column("created_by", sa.Uuid(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.CheckConstraint(
            "channel IN ('sms', 'whatsapp', 'push')", name=op.f("ck_campaign_channel")
        ),
        sa.CheckConstraint(
            "status IN ('draft', 'scheduled', 'sending', 'sent', 'cancelled')",
            name=op.f("ck_campaign_status"),
        ),
        sa.CheckConstraint(
            "holdout_pct >= 0 AND holdout_pct <= 50", name=op.f("ck_campaign_holdout_pct")
        ),
        sa.CheckConstraint(
            "attribution_days >= 1 AND attribution_days <= 90",
            name=op.f("ck_campaign_attribution"),
        ),
        sa.CheckConstraint("char_length(name) > 0", name=op.f("ck_campaign_name")),
        _fk("campaign", "created_by", "user", "SET NULL"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_campaign")),
    )
    _tenant_index("campaign")
    op.create_index(
        "ix_campaign_tenant_status", "campaign", ["tenant_id", "status", "scheduled_at"]
    )
    enable_rls("campaign")

    op.create_table(
        "campaign_recipient",
        *_base(),
        sa.Column("campaign_id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("arm", sa.String(8), nullable=False),
        sa.Column("language", sa.String(8), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("skip_reason", sa.String(32), nullable=True),
        sa.Column("provider_ref", sa.String(64), nullable=True),
        sa.Column("dlt_template_id", sa.String(64), nullable=True),
        sa.Column("notification_id", sa.Uuid(), nullable=True),
        sa.Column("sent_at", ts, nullable=True),
        sa.Column("delivered_at", ts, nullable=True),
        sa.Column("opened_at", ts, nullable=True),
        sa.Column("error", sa.String(200), nullable=True),
        sa.CheckConstraint("arm IN ('target', 'holdout')", name=op.f("ck_campaign_recipient_arm")),
        sa.CheckConstraint(
            "status IN ('pending', 'sent', 'delivered', 'failed', 'skipped', 'holdout')",
            name=op.f("ck_campaign_recipient_status"),
        ),
        sa.CheckConstraint(
            "skip_reason IS NULL OR skip_reason IN "
            "('consent_withdrawn', 'no_app', 'farmer_deleted', 'campaign_cancelled')",
            name=op.f("ck_campaign_recipient_skip_reason"),
        ),
        _fk("campaign_recipient", "campaign_id", "campaign", "CASCADE"),
        _fk("campaign_recipient", "farmer_id", "farmer", "CASCADE"),
        sa.UniqueConstraint(
            "tenant_id",
            "campaign_id",
            "farmer_id",
            name=op.f("uq_campaign_recipient_tenant_id"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_campaign_recipient")),
    )
    _tenant_index("campaign_recipient")
    op.create_index(
        "ix_campaign_recipient_campaign_status",
        "campaign_recipient",
        ["tenant_id", "campaign_id", "status"],
    )
    op.create_index(
        "ix_campaign_recipient_farmer", "campaign_recipient", ["tenant_id", "farmer_id", "sent_at"]
    )
    enable_rls("campaign_recipient")

    # ------------------------------------------------------------------ targets / incentives
    op.create_table(
        "sales_target",
        *_base(),
        sa.Column("month", sa.Date(), nullable=False),
        sa.Column("subject_type", sa.String(8), nullable=False),
        sa.Column("subject_id", sa.Uuid(), nullable=False),
        sa.Column("visits_verified", sa.Integer(), nullable=True),
        sa.Column("new_farmers", sa.Integer(), nullable=True),
        sa.Column("sales_paise", sa.BigInteger(), nullable=True),
        sa.Column("collections_paise", sa.BigInteger(), nullable=True),
        sa.Column("own_brand_share_bp", sa.Integer(), nullable=True),
        sa.Column("set_by", sa.Uuid(), nullable=True),
        sa.CheckConstraint(
            "subject_type IN ('officer', 'store')", name=op.f("ck_sales_target_subject_type")
        ),
        sa.CheckConstraint("extract(day FROM month) = 1", name=op.f("ck_sales_target_month")),
        sa.CheckConstraint(
            "(visits_verified IS NULL OR visits_verified >= 0) AND "
            "(new_farmers IS NULL OR new_farmers >= 0) AND "
            "(sales_paise IS NULL OR sales_paise >= 0) AND "
            "(collections_paise IS NULL OR collections_paise >= 0) AND "
            "(own_brand_share_bp IS NULL OR own_brand_share_bp BETWEEN 0 AND 10000)",
            name=op.f("ck_sales_target_values"),
        ),
        _fk("sales_target", "set_by", "user", "SET NULL"),
        sa.UniqueConstraint(
            "tenant_id",
            "month",
            "subject_type",
            "subject_id",
            name=op.f("uq_sales_target_tenant_id"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_sales_target")),
    )
    _tenant_index("sales_target")
    op.create_index(
        "ix_sales_target_subject",
        "sales_target",
        ["tenant_id", "subject_type", "subject_id", "month"],
    )
    enable_rls("sales_target")

    op.create_table(
        "incentive_rule_set",
        *_base(),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("version_no", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("definition", postgresql.JSONB(), nullable=False),
        sa.Column("created_by", sa.Uuid(), nullable=True),
        sa.Column("activated_at", ts, nullable=True),
        sa.Column("activated_by", sa.Uuid(), nullable=True),
        sa.CheckConstraint(
            "status IN ('draft', 'active', 'retired')", name=op.f("ck_incentive_rule_set_status")
        ),
        sa.CheckConstraint("version_no > 0", name=op.f("ck_incentive_rule_set_version_no")),
        _fk("incentive_rule_set", "created_by", "user", "SET NULL"),
        sa.UniqueConstraint(
            "tenant_id", "version_no", name=op.f("uq_incentive_rule_set_tenant_id")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_incentive_rule_set")),
    )
    _tenant_index("incentive_rule_set")
    op.create_index(
        "uq_incentive_rule_set_active",
        "incentive_rule_set",
        ["tenant_id"],
        unique=True,
        postgresql_where=sa.text("status = 'active' AND deleted_at IS NULL"),
    )
    enable_rls("incentive_rule_set")

    op.create_table(
        "incentive_payout",
        *_base(),
        sa.Column("officer_id", sa.Uuid(), nullable=False),
        sa.Column("month", sa.Date(), nullable=False),
        sa.Column("rule_set_id", sa.Uuid(), nullable=True),
        sa.Column("rule_version", sa.Integer(), nullable=True),
        sa.Column("eligible", sa.Boolean(), nullable=False),
        sa.Column("metrics", postgresql.JSONB(), nullable=False),
        sa.Column("lines", postgresql.JSONB(), nullable=False),
        sa.Column("gross_paise", sa.BigInteger(), nullable=False),
        sa.Column("clawback_paise", sa.BigInteger(), nullable=False),
        sa.Column("amount_paise", sa.BigInteger(), nullable=False),
        sa.Column("closed_at", ts, nullable=False),
        sa.Column("closed_by", sa.Uuid(), nullable=True),
        sa.CheckConstraint("extract(day FROM month) = 1", name=op.f("ck_incentive_payout_month")),
        sa.CheckConstraint(
            "gross_paise >= 0 AND clawback_paise >= 0", name=op.f("ck_incentive_payout_amounts")
        ),
        _fk("incentive_payout", "officer_id", "user", "RESTRICT"),
        _fk("incentive_payout", "rule_set_id", "incentive_rule_set", "SET NULL"),
        sa.UniqueConstraint(
            "tenant_id", "officer_id", "month", name=op.f("uq_incentive_payout_tenant_id")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_incentive_payout")),
    )
    _tenant_index("incentive_payout")
    op.create_index("ix_incentive_payout_month", "incentive_payout", ["tenant_id", "month"])
    enable_rls("incentive_payout")

    # ------------------------------------------------------------------ exports / reports
    op.create_table(
        "export_job",
        *_base(),
        sa.Column("resource", sa.String(32), nullable=False),
        sa.Column("format", sa.String(8), nullable=False),
        sa.Column("filters", postgresql.JSONB(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("rows", sa.Integer(), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("blob_uri", sa.String(512), nullable=True),
        sa.Column("filename", sa.String(200), nullable=True),
        sa.Column("requested_by", sa.Uuid(), nullable=True),
        sa.Column("schedule_id", sa.Uuid(), nullable=True),
        sa.Column("error", sa.String(200), nullable=True),
        sa.CheckConstraint("format IN ('csv', 'xlsx', 'xml')", name=op.f("ck_export_job_format")),
        sa.CheckConstraint("status IN ('done', 'failed')", name=op.f("ck_export_job_status")),
        sa.CheckConstraint("rows >= 0", name=op.f("ck_export_job_rows")),
        _fk("export_job", "requested_by", "user", "SET NULL"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_export_job")),
    )
    _tenant_index("export_job")
    op.create_index(
        "ix_export_job_requested", "export_job", ["tenant_id", "requested_by", "created_at"]
    )
    enable_rls("export_job")

    op.create_table(
        "report_schedule",
        *_base(),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("resource", sa.String(32), nullable=False),
        sa.Column("format", sa.String(8), nullable=False),
        sa.Column("filters", postgresql.JSONB(), nullable=False),
        sa.Column("recipients", postgresql.JSONB(), nullable=False),
        sa.Column("cron", sa.String(64), nullable=False),
        sa.Column("active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("next_run_at", ts, nullable=True),
        sa.Column("last_run_at", ts, nullable=True),
        sa.Column("last_status", sa.String(16), nullable=True),
        sa.CheckConstraint(
            "format IN ('csv', 'xlsx', 'xml')", name=op.f("ck_report_schedule_format")
        ),
        sa.CheckConstraint(
            "char_length(name) > 0 AND char_length(cron) > 0", name=op.f("ck_report_schedule_names")
        ),
        _fk("report_schedule", "owner_id", "user", "CASCADE"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_report_schedule")),
    )
    _tenant_index("report_schedule")
    op.create_index(
        "ix_report_schedule_due", "report_schedule", ["tenant_id", "active", "next_run_at"]
    )
    enable_rls("report_schedule")

    op.create_table(
        "report_run",
        *_base(),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("dedupe_key", sa.String(160), nullable=False),
        sa.Column("period", sa.String(32), nullable=False),
        sa.Column("schedule_id", sa.Uuid(), nullable=True),
        sa.Column("store_id", sa.Uuid(), nullable=True),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("blob_uris", postgresql.JSONB(), nullable=False),
        sa.Column("recipients", sa.Integer(), nullable=False),
        sa.Column("error", sa.String(200), nullable=True),
        sa.CheckConstraint(
            "kind IN ('schedule', 'weekly_owner', 'accounting')", name=op.f("ck_report_run_kind")
        ),
        sa.CheckConstraint(
            "status IN ('sent', 'failed', 'no_recipients')", name=op.f("ck_report_run_status")
        ),
        sa.UniqueConstraint("tenant_id", "dedupe_key", name=op.f("uq_report_run_tenant_id")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_report_run")),
    )
    _tenant_index("report_run")
    op.create_index("ix_report_run_kind_created", "report_run", ["tenant_id", "kind", "created_at"])
    enable_rls("report_run")

    # ------------------------------------------------------------------ ST-004
    op.create_table(
        "reorder_level",
        *_base(),
        sa.Column("store_id", sa.Uuid(), nullable=False),
        sa.Column("sku_id", sa.Uuid(), nullable=False),
        sa.Column("reorder_level", sa.Numeric(12, 3), nullable=False),
        sa.CheckConstraint("reorder_level >= 0", name=op.f("ck_reorder_level_reorder_level")),
        _fk("reorder_level", "store_id", "store", "CASCADE"),
        _fk("reorder_level", "sku_id", "sku", "CASCADE"),
        sa.UniqueConstraint(
            "tenant_id", "store_id", "sku_id", name=op.f("uq_reorder_level_tenant_id")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reorder_level")),
    )
    _tenant_index("reorder_level")
    enable_rls("reorder_level")


def downgrade() -> None:
    for table in _TABLES:
        disable_rls(table)
        op.drop_table(table)
