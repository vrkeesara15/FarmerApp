"""M7 farmer P1: crop calendar, outbreak alerts, evaluation runs, model releases, re-embedding

Revision ID: 0032
Revises: 0029
Create Date: 2026-09-19 23:30:00 UTC

SPEC 2.4 / 3 / 5.1 (M7: FM-007, FM-009, DX-011, DX-012, DX-013):

* ``crop_task_template`` — FM-007 agronomist-maintained calendar per crop (and season).
* ``crop_plot_task`` — FM-007 the calendar generated for one crop plot from its sowing date
  (sync entity ``crop_plot_task``; reminders as notification rows).
* ``outbreak_alert`` — DX-013 / FM-009 district x crop x problem x ISO week clusters.
* ``evaluation_run`` — DX-011 nightly evaluation results.
* ``model_release`` — DX-012 on-device model approval gate.
* ``corpus_embedding`` — DX-012 staged / previous encoder vectors of corpus images.
* ``encoder_activation`` — DX-012 append-only history of active-encoder flips.

Every new table under RLS (``encoder_activation`` append-only). Expand-only (new tables);
downgrade drops them. Branch label ``farmer_p1`` (parallel M7 branches: 0030 field_p1,
0031 growth; the parent merges the heads).
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op
from pgvector.sqlalchemy import Vector
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0032"
down_revision: str | Sequence[str] | None = "0029"
branch_labels: str | Sequence[str] | None = ("farmer_p1",)
depends_on: str | Sequence[str] | None = None

# Drop order (children first).
_TABLES = (
    "encoder_activation",
    "corpus_embedding",
    "model_release",
    "evaluation_run",
    "outbreak_alert",
    "crop_plot_task",
    "crop_task_template",
)

_TASK_TYPES = "'sow', 'irrigate', 'fertilise', 'spray', 'harvest'"
_SEASONS = "'kharif', 'rabi', 'zaid'"
_STAGES = "'sown', 'vegetative', 'flowering', 'fruiting', 'maturity', 'harvested'"
_CATEGORIES = (
    "'seed', 'fertiliser', 'pesticide', 'fungicide', 'herbicide', 'growth', 'tool', 'other'"
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


def _lean() -> list[sa.Column[Any]]:
    return [
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    ]


def _fk(table: str, column: str, target: str, ondelete: str) -> sa.ForeignKeyConstraint:
    return sa.ForeignKeyConstraint(
        [column],
        [f"{target}.id"],
        name=f"fk_{table}_{column}_{target}",
        ondelete=ondelete,
    )


def upgrade() -> None:
    # ------------------------------------------------------------------ crop_task_template
    op.create_table(
        "crop_task_template",
        *_base(),
        sa.Column("crop_id", sa.Uuid(), nullable=False),
        sa.Column("season", sa.String(8), nullable=True),
        sa.Column("task_key", sa.String(64), nullable=False),
        sa.Column("task_type", sa.String(16), nullable=False),
        sa.Column("day_offset", sa.Integer(), nullable=False),
        sa.Column("duration_days", sa.Integer(), server_default="1", nullable=False),
        sa.Column("stage", sa.String(16), nullable=True),
        sa.Column("titles", postgresql.JSONB(), nullable=False),
        sa.Column("instructions", postgresql.JSONB(), nullable=False),
        sa.Column("product_category", sa.String(16), nullable=True),
        sa.Column("sort_order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("source", sa.String(200), nullable=True),
        sa.Column("updated_by", sa.Uuid(), nullable=True),
        sa.CheckConstraint(
            f"task_type IN ({_TASK_TYPES})", name=op.f("ck_crop_task_template_task_type")
        ),
        sa.CheckConstraint(
            f"season IS NULL OR season IN ({_SEASONS})", name=op.f("ck_crop_task_template_season")
        ),
        sa.CheckConstraint(
            f"stage IS NULL OR stage IN ({_STAGES})", name=op.f("ck_crop_task_template_stage")
        ),
        sa.CheckConstraint(
            f"product_category IS NULL OR product_category IN ({_CATEGORIES})",
            name=op.f("ck_crop_task_template_product_category"),
        ),
        sa.CheckConstraint(
            "day_offset BETWEEN -60 AND 400", name=op.f("ck_crop_task_template_day_offset")
        ),
        sa.CheckConstraint(
            "duration_days BETWEEN 1 AND 60", name=op.f("ck_crop_task_template_duration_days")
        ),
        sa.CheckConstraint(
            "task_key ~ '^[a-z0-9_.-]{2,64}$'", name=op.f("ck_crop_task_template_task_key")
        ),
        _fk("crop_task_template", "crop_id", "crop", "RESTRICT"),
        _fk("crop_task_template", "updated_by", "user", "SET NULL"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_crop_task_template")),
    )
    op.create_index("ix_crop_task_template_tenant_id", "crop_task_template", ["tenant_id"])
    op.create_index("ix_crop_task_template_crop", "crop_task_template", ["tenant_id", "crop_id"])
    op.create_index(
        "uq_crop_task_template_key",
        "crop_task_template",
        ["tenant_id", "crop_id", sa.text("coalesce(season, '')"), "task_key"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    enable_rls("crop_task_template")

    # ------------------------------------------------------------------ crop_plot_task
    op.create_table(
        "crop_plot_task",
        *_base(),
        sa.Column("crop_plot_id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("template_id", sa.Uuid(), nullable=True),
        sa.Column("task_key", sa.String(64), nullable=False),
        sa.Column("task_type", sa.String(16), nullable=False),
        sa.Column("stage", sa.String(16), nullable=True),
        sa.Column("due_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=False),
        sa.Column("titles", postgresql.JSONB(), nullable=False),
        sa.Column("instructions", postgresql.JSONB(), nullable=False),
        sa.Column("product_category", sa.String(16), nullable=True),
        sa.Column("sort_order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("status", sa.String(8), server_default=sa.text("'pending'"), nullable=False),
        sa.Column("done_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("done_by", sa.Uuid(), nullable=True),
        sa.Column("reminder_enabled", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("reminded_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("basis_sowing_date", sa.Date(), nullable=False),
        sa.Column("basis_crop_id", sa.Uuid(), nullable=False),
        sa.Column("basis_hash", sa.String(16), nullable=False),
        sa.CheckConstraint(
            f"task_type IN ({_TASK_TYPES})", name=op.f("ck_crop_plot_task_task_type")
        ),
        sa.CheckConstraint("status IN ('pending', 'done')", name=op.f("ck_crop_plot_task_status")),
        sa.CheckConstraint(
            "status <> 'done' OR done_at IS NOT NULL", name=op.f("ck_crop_plot_task_done_at")
        ),
        sa.CheckConstraint("end_date >= due_date", name=op.f("ck_crop_plot_task_dates")),
        _fk("crop_plot_task", "crop_plot_id", "crop_plot", "CASCADE"),
        _fk("crop_plot_task", "farmer_id", "farmer", "CASCADE"),
        _fk("crop_plot_task", "template_id", "crop_task_template", "SET NULL"),
        _fk("crop_plot_task", "done_by", "user", "SET NULL"),
        _fk("crop_plot_task", "basis_crop_id", "crop", "RESTRICT"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_crop_plot_task")),
    )
    op.create_index("ix_crop_plot_task_tenant_id", "crop_plot_task", ["tenant_id"])
    op.create_index("ix_crop_plot_task_crop_plot_id", "crop_plot_task", ["crop_plot_id"])
    op.create_index(
        "ix_crop_plot_task_farmer_due", "crop_plot_task", ["tenant_id", "farmer_id", "due_date"]
    )
    op.create_index(
        "ix_crop_plot_task_reminder_due",
        "crop_plot_task",
        ["tenant_id", "due_date"],
        postgresql_where=sa.text(
            "deleted_at IS NULL AND status = 'pending' AND reminder_enabled AND reminded_at IS NULL"
        ),
    )
    op.create_index(
        "uq_crop_plot_task_key",
        "crop_plot_task",
        ["crop_plot_id", "task_key"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    enable_rls("crop_plot_task")

    # ------------------------------------------------------------------ outbreak_alert
    op.create_table(
        "outbreak_alert",
        *_base(),
        sa.Column("district", sa.String(80), nullable=False),
        sa.Column("crop_id", sa.Uuid(), nullable=False),
        sa.Column("problem_id", sa.Uuid(), nullable=False),
        sa.Column("week_start", sa.Date(), nullable=False),
        sa.Column("iso_year", sa.Integer(), nullable=False),
        sa.Column("iso_week", sa.Integer(), nullable=False),
        sa.Column("case_count", sa.Integer(), nullable=False),
        sa.Column("farmers_affected", sa.Integer(), nullable=False),
        sa.Column("baseline_mean", sa.Numeric(8, 2), nullable=False),
        sa.Column("rule", postgresql.JSONB(), nullable=False),
        sa.Column("status", sa.String(8), server_default=sa.text("'active'"), nullable=False),
        sa.Column("notified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("notified", postgresql.JSONB(), nullable=False),
        sa.CheckConstraint("status IN ('active', 'closed')", name=op.f("ck_outbreak_alert_status")),
        sa.CheckConstraint("case_count >= 0", name=op.f("ck_outbreak_alert_case_count")),
        _fk("outbreak_alert", "crop_id", "crop", "RESTRICT"),
        _fk("outbreak_alert", "problem_id", "corpus_problem", "RESTRICT"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_outbreak_alert")),
    )
    op.create_index("ix_outbreak_alert_tenant_id", "outbreak_alert", ["tenant_id"])
    op.create_index(
        "ix_outbreak_alert_district_week",
        "outbreak_alert",
        ["tenant_id", "district", "week_start"],
    )
    op.create_index(
        "uq_outbreak_alert_cell",
        "outbreak_alert",
        ["tenant_id", "district", "crop_id", "problem_id", "week_start"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    enable_rls("outbreak_alert")

    # ------------------------------------------------------------------ evaluation_run
    op.create_table(
        "evaluation_run",
        *_base(),
        sa.Column("manifest", sa.String(512), nullable=False),
        sa.Column("status", sa.String(8), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("encoder", sa.String(100), nullable=True),
        sa.Column("llm", sa.String(64), nullable=True),
        sa.Column("corpus_version", sa.Integer(), nullable=True),
        sa.Column("cases", sa.Integer(), nullable=False),
        sa.Column("top1_accuracy", sa.Float(), nullable=True),
        sa.Column("corpus_answer_share", sa.Float(), nullable=True),
        sa.Column("escalation_rate", sa.Float(), nullable=True),
        sa.Column("hallucinated_out_of_scope", sa.Integer(), nullable=False),
        sa.Column("summary", postgresql.JSONB(), nullable=False),
        sa.Column("per_crop", postgresql.JSONB(), nullable=False),
        sa.Column("per_problem", postgresql.JSONB(), nullable=False),
        sa.Column("previous_run_id", sa.Uuid(), nullable=True),
        sa.Column("top1_delta_points", sa.Float(), nullable=True),
        sa.Column("alerted", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("error", sa.Text(), nullable=True),
        sa.CheckConstraint("status IN ('ok', 'failed')", name=op.f("ck_evaluation_run_status")),
        _fk("evaluation_run", "previous_run_id", "evaluation_run", "SET NULL"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_evaluation_run")),
    )
    op.create_index("ix_evaluation_run_tenant_id", "evaluation_run", ["tenant_id"])
    op.create_index(
        "ix_evaluation_run_tenant_started", "evaluation_run", ["tenant_id", "started_at"]
    )
    enable_rls("evaluation_run")

    # ------------------------------------------------------------------ model_release
    op.create_table(
        "model_release",
        *_base(),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("model_name", sa.String(100), nullable=False),
        sa.Column("model_version", sa.String(64), nullable=False),
        sa.Column("artifact_uri", sa.String(512), nullable=False),
        sa.Column("sha256", sa.String(64), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False),
        sa.Column("metadata", postgresql.JSONB(), nullable=False),
        sa.Column("evaluation", postgresql.JSONB(), nullable=False),
        sa.Column("training_manifest_uri", sa.String(512), nullable=True),
        sa.Column("pipeline_run", sa.String(256), nullable=True),
        sa.Column("status", sa.String(16), server_default=sa.text("'candidate'"), nullable=False),
        sa.Column("decided_by", sa.Uuid(), nullable=True),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("decision_note", sa.Text(), nullable=True),
        sa.CheckConstraint("kind IN ('on_device')", name=op.f("ck_model_release_kind")),
        sa.CheckConstraint(
            "status IN ('candidate', 'approved', 'rejected', 'retired')",
            name=op.f("ck_model_release_status"),
        ),
        sa.CheckConstraint("char_length(sha256) = 64", name=op.f("ck_model_release_sha256")),
        sa.CheckConstraint(
            "status NOT IN ('approved', 'rejected', 'retired') OR decided_at IS NOT NULL",
            name=op.f("ck_model_release_decided_at"),
        ),
        _fk("model_release", "decided_by", "user", "SET NULL"),
        sa.UniqueConstraint(
            "tenant_id", "kind", "model_version", name=op.f("uq_model_release_tenant_id")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_model_release")),
    )
    op.create_index("ix_model_release_tenant_id", "model_release", ["tenant_id"])
    op.create_index(
        "ix_model_release_kind_status", "model_release", ["tenant_id", "kind", "status"]
    )
    enable_rls("model_release")

    # ------------------------------------------------------------------ corpus_embedding
    op.create_table(
        "corpus_embedding",
        *_lean(),
        sa.Column("corpus_image_id", sa.Uuid(), nullable=False),
        sa.Column("encoder_name", sa.String(64), nullable=False),
        sa.Column("encoder_version", sa.String(32), nullable=False),
        sa.Column("embedding", Vector(768), nullable=False),
        _fk("corpus_embedding", "corpus_image_id", "corpus_image", "CASCADE"),
        sa.UniqueConstraint(
            "corpus_image_id",
            "encoder_name",
            "encoder_version",
            name=op.f("uq_corpus_embedding_corpus_image_id"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_corpus_embedding")),
    )
    op.create_index(
        "ix_corpus_embedding_encoder",
        "corpus_embedding",
        ["tenant_id", "encoder_name", "encoder_version"],
    )
    op.create_index(
        "ix_corpus_embedding_hnsw",
        "corpus_embedding",
        ["embedding"],
        postgresql_using="hnsw",
        postgresql_with={"m": 16, "ef_construction": 64},
        postgresql_ops={"embedding": "vector_cosine_ops"},
    )
    enable_rls("corpus_embedding")

    # ------------------------------------------------------------------ encoder_activation
    op.create_table(
        "encoder_activation",
        *_lean(),
        sa.Column("encoder_name", sa.String(64), nullable=False),
        sa.Column("encoder_version", sa.String(32), nullable=False),
        sa.Column("previous_name", sa.String(64), nullable=True),
        sa.Column("previous_version", sa.String(32), nullable=True),
        sa.Column("images", sa.Integer(), nullable=False),
        sa.Column("activated_by", sa.Uuid(), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        _fk("encoder_activation", "activated_by", "user", "SET NULL"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_encoder_activation")),
    )
    op.create_index(
        "ix_encoder_activation_tenant_created",
        "encoder_activation",
        ["tenant_id", "created_at"],
    )
    enable_rls("encoder_activation", append_only=True)


def downgrade() -> None:
    for table in _TABLES:
        disable_rls(table)
        op.drop_table(table)
