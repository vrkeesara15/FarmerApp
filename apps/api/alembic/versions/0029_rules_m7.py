"""M7 validation rules: crop calendar, flag summaries, rule overrides, LLM log flag link

Revision ID: 0029
Revises: 0028
Create Date: 2026-09-19 22:00:00 UTC

SPEC 6 (M7: VA-F05, VA-004, VA-006):

* ``crop_calendar`` — VA-F05 district crop calendar: the sowing window (``MM-DD`` to
  ``MM-DD``, may wrap the new year) of a crop in a season, per state and optionally per
  district (``district`` NULL = the whole state). Seeded for the six pilot crops in
  Telangana (``farmerapp.rules.reference``).
* ``flag_summary`` — VA-004 review agent output, one row per flag: status
  (``pending | done | refused | invalid | error | disabled``), the three summary lines, the
  suggested action, the cited record ids, model and attempts.
* ``rule_tenant_override`` — VA-006: a tenant's runtime switch of one rule (auto-disabled
  when its precision stays under 30 % over four weeks; re-enabled by an admin), with the
  reason, source, precision and who set it. One row per tenant and rule; every change is
  audited (FA-006 listener + explicit ``rule.*`` audit rows).
* ``llm_call_log.flag_id`` — the flag a VA-004 summary call was about (NULL for DX-004).

Every new table under RLS. Expand-only (new tables, a nullable column); downgrade drops them.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0029"
down_revision: str | Sequence[str] | None = "0028"
branch_labels: str | Sequence[str] | None = ("rules_m7",)
depends_on: str | Sequence[str] | None = None

_TABLES = ("rule_tenant_override", "flag_summary", "crop_calendar")


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


def upgrade() -> None:
    # ------------------------------------------------------------------ crop_calendar
    op.create_table(
        "crop_calendar",
        *_base(),
        sa.Column("state", sa.String(80), nullable=False),
        sa.Column("district", sa.String(80), nullable=True),
        sa.Column("crop_code", sa.String(32), nullable=False),
        sa.Column("season", sa.String(8), nullable=False),
        sa.Column("sow_start", sa.String(5), nullable=False),
        sa.Column("sow_end", sa.String(5), nullable=False),
        sa.Column("source", sa.String(200), nullable=True),
        sa.CheckConstraint(
            "season IN ('kharif', 'rabi', 'zaid')", name=op.f("ck_crop_calendar_season")
        ),
        sa.CheckConstraint(
            "sow_start ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' AND "
            "sow_end ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'",
            name=op.f("ck_crop_calendar_mmdd"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_crop_calendar")),
    )
    op.create_index("ix_crop_calendar_tenant_id", "crop_calendar", ["tenant_id"])
    op.create_index(
        "uq_crop_calendar_window",
        "crop_calendar",
        ["tenant_id", "state", sa.text("coalesce(district, '')"), "crop_code", "season"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    enable_rls("crop_calendar")

    # ------------------------------------------------------------------ flag_summary
    op.create_table(
        "flag_summary",
        *_base(),
        sa.Column("flag_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("summary_lines", postgresql.JSONB(), nullable=True),
        sa.Column("suggested_action", sa.Text(), nullable=True),
        sa.Column(
            "cited_record_ids",
            postgresql.JSONB(),
            server_default=sa.text("'[]'::jsonb"),
            nullable=False,
        ),
        sa.Column("model", sa.String(64), nullable=True),
        sa.Column("attempts", sa.Integer(), server_default="0", nullable=False),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('pending', 'done', 'refused', 'invalid', 'error', 'disabled')",
            name=op.f("ck_flag_summary_status"),
        ),
        sa.ForeignKeyConstraint(
            ["flag_id"], ["flag.id"], name=op.f("fk_flag_summary_flag_id_flag"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_flag_summary")),
        sa.UniqueConstraint("flag_id", name=op.f("uq_flag_summary_flag_id")),
    )
    op.create_index("ix_flag_summary_tenant_id", "flag_summary", ["tenant_id"])
    op.create_index("ix_flag_summary_tenant_status", "flag_summary", ["tenant_id", "status"])
    enable_rls("flag_summary")

    # ------------------------------------------------------------------ rule_tenant_override
    op.create_table(
        "rule_tenant_override",
        *_base(),
        sa.Column("rule_id", sa.String(16), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False),
        sa.Column("source", sa.String(16), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("rule_version", sa.Integer(), nullable=True),
        sa.Column("precision", sa.Numeric(5, 4), nullable=True),
        sa.Column("resolved_count", sa.Integer(), nullable=True),
        sa.Column("set_by", sa.Uuid(), nullable=True),
        sa.Column("set_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "source IN ('auto_precision', 'admin')", name=op.f("ck_rule_tenant_override_source")
        ),
        sa.CheckConstraint("char_length(reason) > 0", name=op.f("ck_rule_tenant_override_reason")),
        sa.ForeignKeyConstraint(
            ["set_by"],
            ["user.id"],
            name=op.f("fk_rule_tenant_override_set_by_user"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_rule_tenant_override")),
        sa.UniqueConstraint("tenant_id", "rule_id", name="uq_rule_tenant_override_rule"),
    )
    op.create_index("ix_rule_tenant_override_tenant_id", "rule_tenant_override", ["tenant_id"])
    enable_rls("rule_tenant_override")

    # ------------------------------------------------------------------ llm_call_log.flag_id
    op.add_column("llm_call_log", sa.Column("flag_id", sa.Uuid(), nullable=True))
    op.create_foreign_key(
        "fk_llm_call_log_flag_id_flag",
        "llm_call_log",
        "flag",
        ["flag_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_llm_call_log_flag_id", "llm_call_log", ["flag_id"])


def downgrade() -> None:
    op.drop_index("ix_llm_call_log_flag_id", table_name="llm_call_log")
    op.drop_constraint("fk_llm_call_log_flag_id_flag", "llm_call_log", type_="foreignkey")
    op.drop_column("llm_call_log", "flag_id")
    for table in _TABLES:
        disable_rls(table)
        op.drop_table(table)
