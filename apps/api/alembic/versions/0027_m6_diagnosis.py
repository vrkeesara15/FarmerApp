"""M6: diagnosis corpus, diagnoses, review history, thresholds, LLM call log, data requests

Revision ID: 0027
Revises: 0026
Create Date: 2026-09-19 20:00:00 UTC

SPEC 3 / 8.2 (M6-KICKOFF, DX-002 .. DX-010, WC-006, WC-007, FM-015):

* ``corpus_problem`` (references ``pest_or_disease`` + ``crop``; names / symptoms / cultural
  practices per language; status draft | reviewed | approved | retired; provenance; source
  internal | public), ``corpus_image`` (blob, sha256, ``embedding vector(768)`` with an
  **HNSW** index ``vector_cosine_ops`` (m 16, ef_construction 64), encoder name + version,
  stage / part / severity / region / season / source / status), ``corpus_version``
  (append-only, monotonic per tenant).
* ``diagnosis`` (lifecycle, result, provenance), ``diagnosis_review`` (append-only),
  ``diagnosis_threshold`` (versioned per crop), ``llm_call_log`` (append-only, one year).
* ``data_request`` (FM-015 deletion, NF-013 access / correction tickets).
* ``upload_session.purpose`` gains ``corpus`` (WC-007 image uploads).

Every table under RLS (``enable_rls``; the three append-only ones with ``append_only=True``).
Expand-only: new tables, a widened CHECK; downgrade drops them and restores the CHECK.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op
from pgvector.sqlalchemy import Vector
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0027"
down_revision: str | Sequence[str] | None = "0026"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_CORPUS_STATUS = "'draft', 'reviewed', 'approved', 'retired'"
_SOURCE = "'internal', 'public'"
_OLD_PURPOSES = "'farm_photo', 'visit_photo', 'receipt', 'diagnosis', 'profile'"
_NEW_PURPOSES = _OLD_PURPOSES + ", 'corpus'"
_TABLES = (
    "data_request",
    "llm_call_log",
    "diagnosis_threshold",
    "diagnosis_review",
    "corpus_image",
    "diagnosis",
    "corpus_version",
    "corpus_problem",
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


def _user_fk(table: str, column: str) -> sa.ForeignKeyConstraint:
    return sa.ForeignKeyConstraint(
        [column], ["user.id"], name=f"fk_{table}_{column}_user", ondelete="SET NULL"
    )


def upgrade() -> None:
    # ------------------------------------------------------------------ corpus_problem
    op.create_table(
        "corpus_problem",
        *_base(),
        sa.Column("pest_or_disease_id", sa.Uuid(), nullable=False),
        sa.Column("crop_id", sa.Uuid(), nullable=False),
        sa.Column("problem_type", sa.String(16), nullable=False),
        sa.Column("names", postgresql.JSONB(), nullable=False),
        sa.Column("symptoms", postgresql.JSONB(), nullable=False),
        sa.Column("cultural_practices", postgresql.JSONB(), nullable=False),
        sa.Column("status", sa.String(16), server_default=sa.text("'draft'"), nullable=False),
        sa.Column("source", sa.String(16), server_default=sa.text("'internal'"), nullable=False),
        sa.Column("labelled_by", sa.Uuid(), nullable=True),
        sa.Column("reviewed_by", sa.Uuid(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("approved_by", sa.Uuid(), nullable=True),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("retired_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("approved_in_version", sa.Integer(), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.CheckConstraint(f"status IN ({_CORPUS_STATUS})", name=op.f("ck_corpus_problem_status")),
        sa.CheckConstraint(f"source IN ({_SOURCE})", name=op.f("ck_corpus_problem_source")),
        sa.CheckConstraint(
            "problem_type IN ('disease', 'pest', 'nutrient', 'abiotic')",
            name=op.f("ck_corpus_problem_problem_type"),
        ),
        sa.CheckConstraint(
            "status <> 'approved' OR approved_at IS NOT NULL",
            name=op.f("ck_corpus_problem_approved_at"),
        ),
        sa.ForeignKeyConstraint(
            ["pest_or_disease_id"],
            ["pest_or_disease.id"],
            name=op.f("fk_corpus_problem_pest_or_disease_id_pest_or_disease"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["crop_id"],
            ["crop.id"],
            name=op.f("fk_corpus_problem_crop_id_crop"),
            ondelete="RESTRICT",
        ),
        _user_fk("corpus_problem", "labelled_by"),
        _user_fk("corpus_problem", "reviewed_by"),
        _user_fk("corpus_problem", "approved_by"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_corpus_problem")),
    )
    op.create_index("ix_corpus_problem_tenant_id", "corpus_problem", ["tenant_id"])
    op.create_index(
        "uq_corpus_problem_crop_pest",
        "corpus_problem",
        ["tenant_id", "crop_id", "pest_or_disease_id"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL AND status <> 'retired'"),
    )
    op.create_index(
        "ix_corpus_problem_crop_status", "corpus_problem", ["tenant_id", "crop_id", "status"]
    )
    op.create_index(
        "ix_corpus_problem_pest_or_disease_id", "corpus_problem", ["pest_or_disease_id"]
    )
    enable_rls("corpus_problem")

    # ------------------------------------------------------------------ corpus_version
    op.create_table(
        "corpus_version",
        *_lean(),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("approved_by", sa.Uuid(), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("changes", postgresql.JSONB(), nullable=False),
        sa.CheckConstraint("version >= 1", name=op.f("ck_corpus_version_version")),
        _user_fk("corpus_version", "approved_by"),
        sa.UniqueConstraint("tenant_id", "version", name=op.f("uq_corpus_version_tenant_id")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_corpus_version")),
    )
    enable_rls("corpus_version", append_only=True)

    # ------------------------------------------------------------------ diagnosis
    op.create_table(
        "diagnosis",
        *_base(),
        sa.Column("subject", sa.String(8), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("crop_plot_id", sa.Uuid(), nullable=True),
        sa.Column("requested_by", sa.Uuid(), nullable=True),
        sa.Column("images", postgresql.JSONB(), nullable=False),
        sa.Column("crop_id", sa.Uuid(), nullable=True),
        sa.Column("crop_detected_on_device", postgresql.JSONB(), nullable=True),
        sa.Column("district", sa.String(80), nullable=True),
        sa.Column("season", sa.String(8), nullable=True),
        sa.Column("crop_stage", sa.String(16), nullable=True),
        sa.Column("language", sa.String(8), server_default="en", nullable=False),
        sa.Column("status", sa.String(16), server_default=sa.text("'queued'"), nullable=False),
        sa.Column("result", postgresql.JSONB(), nullable=True),
        sa.Column("source", sa.String(16), nullable=True),
        sa.Column("confidence", sa.String(8), nullable=True),
        sa.Column("model_versions", postgresql.JSONB(), nullable=False),
        sa.Column("corpus_version", sa.Integer(), nullable=True),
        sa.Column("scores", postgresql.JSONB(), nullable=True),
        sa.Column("final_problem_id", sa.Uuid(), nullable=True),
        sa.Column("out_of_scope_reason", sa.String(32), nullable=True),
        sa.Column("llm_used", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("flagged", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("attempts", sa.Integer(), server_default="0", nullable=False),
        sa.Column("captured_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("answered_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reviewed_by", sa.Uuid(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("notified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("age_alerted_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint("subject IN ('farmer', 'officer')", name=op.f("ck_diagnosis_subject")),
        sa.CheckConstraint(
            "status IN ('queued', 'answered', 'provisional', 'confirmed', 'corrected', "
            "'out_of_scope')",
            name=op.f("ck_diagnosis_status"),
        ),
        sa.CheckConstraint(
            "source IS NULL OR source IN ('corpus', 'llm', 'agronomist')",
            name=op.f("ck_diagnosis_source"),
        ),
        sa.CheckConstraint(
            "confidence IS NULL OR confidence IN ('high', 'medium', 'low')",
            name=op.f("ck_diagnosis_confidence"),
        ),
        sa.CheckConstraint("attempts >= 0", name=op.f("ck_diagnosis_attempts")),
        sa.ForeignKeyConstraint(
            ["farmer_id"],
            ["farmer.id"],
            name=op.f("fk_diagnosis_farmer_id_farmer"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["crop_plot_id"],
            ["crop_plot.id"],
            name=op.f("fk_diagnosis_crop_plot_id_crop_plot"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["crop_id"], ["crop.id"], name=op.f("fk_diagnosis_crop_id_crop"), ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["final_problem_id"],
            ["corpus_problem.id"],
            name=op.f("fk_diagnosis_final_problem_id_corpus_problem"),
            ondelete="SET NULL",
        ),
        _user_fk("diagnosis", "requested_by"),
        _user_fk("diagnosis", "reviewed_by"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_diagnosis")),
    )
    op.create_index("ix_diagnosis_tenant_id", "diagnosis", ["tenant_id"])
    op.create_index(
        "ix_diagnosis_farmer_created", "diagnosis", ["tenant_id", "farmer_id", "created_at"]
    )
    op.create_index(
        "ix_diagnosis_status_created", "diagnosis", ["tenant_id", "status", "created_at"]
    )
    op.create_index("ix_diagnosis_requested_by", "diagnosis", ["requested_by"])
    op.create_index("ix_diagnosis_crop_plot_id", "diagnosis", ["crop_plot_id"])
    enable_rls("diagnosis")

    # ------------------------------------------------------------------ corpus_image
    op.create_table(
        "corpus_image",
        *_base(),
        sa.Column("problem_id", sa.Uuid(), nullable=False),
        sa.Column("crop_id", sa.Uuid(), nullable=False),
        sa.Column("blob_uri", sa.String(512), nullable=False),
        sa.Column("sha256", sa.String(64), nullable=False),
        sa.Column("embedding", Vector(768), nullable=False),
        sa.Column("encoder_name", sa.String(64), nullable=False),
        sa.Column("encoder_version", sa.String(32), nullable=False),
        sa.Column("stage", sa.String(16), nullable=True),
        sa.Column("part", sa.String(8), nullable=True),
        sa.Column("severity", sa.String(8), nullable=True),
        sa.Column("region", sa.String(80), nullable=True),
        sa.Column("season", sa.String(8), nullable=True),
        sa.Column("source", sa.String(16), server_default=sa.text("'internal'"), nullable=False),
        sa.Column("status", sa.String(16), server_default=sa.text("'draft'"), nullable=False),
        sa.Column("labelled_by", sa.Uuid(), nullable=True),
        sa.Column("approved_by", sa.Uuid(), nullable=True),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("approved_in_version", sa.Integer(), nullable=True),
        sa.Column("from_diagnosis_id", sa.Uuid(), nullable=True),
        sa.CheckConstraint(f"status IN ({_CORPUS_STATUS})", name=op.f("ck_corpus_image_status")),
        sa.CheckConstraint(f"source IN ({_SOURCE})", name=op.f("ck_corpus_image_source")),
        sa.CheckConstraint(
            "part IS NULL OR part IN ('leaf', 'stem', 'fruit', 'whole')",
            name=op.f("ck_corpus_image_part"),
        ),
        sa.CheckConstraint(
            "severity IS NULL OR severity IN ('low', 'medium', 'high')",
            name=op.f("ck_corpus_image_severity"),
        ),
        sa.CheckConstraint("char_length(sha256) = 64", name=op.f("ck_corpus_image_sha256")),
        sa.CheckConstraint(
            "status <> 'approved' OR approved_at IS NOT NULL",
            name=op.f("ck_corpus_image_approved_at"),
        ),
        sa.ForeignKeyConstraint(
            ["problem_id"],
            ["corpus_problem.id"],
            name=op.f("fk_corpus_image_problem_id_corpus_problem"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["crop_id"], ["crop.id"], name=op.f("fk_corpus_image_crop_id_crop"), ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["from_diagnosis_id"],
            ["diagnosis.id"],
            name=op.f("fk_corpus_image_from_diagnosis_id_diagnosis"),
            ondelete="SET NULL",
        ),
        _user_fk("corpus_image", "labelled_by"),
        _user_fk("corpus_image", "approved_by"),
        sa.UniqueConstraint(
            "tenant_id", "problem_id", "sha256", name=op.f("uq_corpus_image_tenant_id")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_corpus_image")),
    )
    op.create_index("ix_corpus_image_tenant_id", "corpus_image", ["tenant_id"])
    op.create_index(
        "ix_corpus_image_embedding_hnsw",
        "corpus_image",
        ["embedding"],
        postgresql_using="hnsw",
        postgresql_with={"m": 16, "ef_construction": 64},
        postgresql_ops={"embedding": "vector_cosine_ops"},
    )
    op.create_index(
        "ix_corpus_image_crop_status", "corpus_image", ["tenant_id", "crop_id", "status"]
    )
    op.create_index("ix_corpus_image_problem_id", "corpus_image", ["problem_id"])
    enable_rls("corpus_image")

    # ------------------------------------------------------------------ diagnosis_review
    op.create_table(
        "diagnosis_review",
        *_lean(),
        sa.Column("diagnosis_id", sa.Uuid(), nullable=False),
        sa.Column("actor_id", sa.Uuid(), nullable=True),
        sa.Column("action", sa.String(16), nullable=False),
        sa.Column("from_status", sa.String(16), nullable=False),
        sa.Column("to_status", sa.String(16), nullable=False),
        sa.Column("from_problem_id", sa.Uuid(), nullable=True),
        sa.Column("to_problem_id", sa.Uuid(), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("add_to_corpus", sa.Boolean(), nullable=False),
        sa.Column("corpus_image_ids", postgresql.ARRAY(sa.Uuid()), nullable=False),
        sa.CheckConstraint(
            "action IN ('confirm', 'correct', 'not_diagnosable')",
            name=op.f("ck_diagnosis_review_action"),
        ),
        sa.ForeignKeyConstraint(
            ["diagnosis_id"],
            ["diagnosis.id"],
            name=op.f("fk_diagnosis_review_diagnosis_id_diagnosis"),
            ondelete="CASCADE",
        ),
        _user_fk("diagnosis_review", "actor_id"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_diagnosis_review")),
    )
    op.create_index("ix_diagnosis_review_diagnosis_id", "diagnosis_review", ["diagnosis_id"])
    enable_rls("diagnosis_review", append_only=True)

    # ------------------------------------------------------------------ diagnosis_threshold
    op.create_table(
        "diagnosis_threshold",
        *_base(),
        sa.Column("crop_id", sa.Uuid(), nullable=True),
        sa.Column("t1", sa.Float(), nullable=False),
        sa.Column("agreement", sa.Float(), nullable=False),
        sa.Column("min_similarity", sa.Float(), nullable=False),
        sa.Column("config_version", sa.Integer(), nullable=False),
        sa.Column("set_by", sa.Uuid(), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.CheckConstraint("t1 > 0 AND t1 <= 1", name=op.f("ck_diagnosis_threshold_t1")),
        sa.CheckConstraint(
            "agreement > 0 AND agreement <= 1", name=op.f("ck_diagnosis_threshold_agreement")
        ),
        sa.CheckConstraint(
            "min_similarity >= 0 AND min_similarity <= t1",
            name=op.f("ck_diagnosis_threshold_min_similarity"),
        ),
        sa.CheckConstraint(
            "config_version >= 1", name=op.f("ck_diagnosis_threshold_config_version")
        ),
        sa.ForeignKeyConstraint(
            ["crop_id"],
            ["crop.id"],
            name=op.f("fk_diagnosis_threshold_crop_id_crop"),
            ondelete="RESTRICT",
        ),
        _user_fk("diagnosis_threshold", "set_by"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_diagnosis_threshold")),
    )
    op.create_index("ix_diagnosis_threshold_tenant_id", "diagnosis_threshold", ["tenant_id"])
    op.create_index(
        "uq_diagnosis_threshold_crop_version",
        "diagnosis_threshold",
        [
            "tenant_id",
            sa.text("coalesce(crop_id, '00000000-0000-0000-0000-000000000000'::uuid)"),
            "config_version",
        ],
        unique=True,
    )
    enable_rls("diagnosis_threshold")

    # ------------------------------------------------------------------ llm_call_log
    op.create_table(
        "llm_call_log",
        *_lean(),
        sa.Column("diagnosis_id", sa.Uuid(), nullable=True),
        sa.Column("provider", sa.String(32), nullable=False),
        sa.Column("model", sa.String(64), nullable=False),
        sa.Column("attempt", sa.Integer(), nullable=False),
        sa.Column("prompt", postgresql.JSONB(), nullable=False),
        sa.Column("raw_output", sa.Text(), nullable=True),
        sa.Column("parsed", postgresql.JSONB(), nullable=True),
        sa.Column("outcome", sa.String(16), nullable=False),
        sa.Column("stop_reason", sa.String(32), nullable=True),
        sa.Column("stop_details", postgresql.JSONB(), nullable=True),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("input_tokens", sa.Integer(), nullable=True),
        sa.Column("output_tokens", sa.Integer(), nullable=True),
        sa.Column("latency_ms", sa.Integer(), nullable=False),
        sa.Column("retain_until", sa.Date(), nullable=False),
        sa.ForeignKeyConstraint(
            ["diagnosis_id"],
            ["diagnosis.id"],
            name=op.f("fk_llm_call_log_diagnosis_id_diagnosis"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_llm_call_log")),
    )
    op.create_index("ix_llm_call_log_diagnosis_id", "llm_call_log", ["diagnosis_id"])
    op.create_index("ix_llm_call_log_tenant_created", "llm_call_log", ["tenant_id", "created_at"])
    enable_rls("llm_call_log", append_only=True)

    # ------------------------------------------------------------------ data_request
    op.create_table(
        "data_request",
        *_base(),
        sa.Column("type", sa.String(16), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=True),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("status", sa.String(16), server_default=sa.text("'received'"), nullable=False),
        sa.Column("due_by", sa.DateTime(timezone=True), nullable=False),
        sa.Column("handled_by", sa.Uuid(), nullable=True),
        sa.Column("handled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("resolution_note", sa.Text(), nullable=True),
        sa.CheckConstraint(
            "type IN ('deletion', 'access', 'correction')", name=op.f("ck_data_request_type")
        ),
        sa.CheckConstraint(
            "status IN ('received', 'in_progress', 'completed', 'rejected')",
            name=op.f("ck_data_request_status"),
        ),
        sa.CheckConstraint(
            "(status IN ('completed', 'rejected')) = (handled_at IS NOT NULL)",
            name=op.f("ck_data_request_handled_at"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["user.id"], name=op.f("fk_data_request_user_id_user"), ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"],
            ["farmer.id"],
            name=op.f("fk_data_request_farmer_id_farmer"),
            ondelete="SET NULL",
        ),
        _user_fk("data_request", "handled_by"),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_data_request")),
    )
    op.create_index("ix_data_request_tenant_id", "data_request", ["tenant_id"])
    op.create_index(
        "ix_data_request_user_created", "data_request", ["tenant_id", "user_id", "created_at"]
    )
    op.create_index("ix_data_request_status_due", "data_request", ["tenant_id", "status", "due_by"])
    enable_rls("data_request")

    # ------------------------------------------------------------------ uploads
    op.drop_constraint(op.f("ck_upload_session_purpose"), "upload_session", type_="check")
    op.create_check_constraint(
        op.f("ck_upload_session_purpose"), "upload_session", f"purpose IN ({_NEW_PURPOSES})"
    )


def downgrade() -> None:
    op.drop_constraint(op.f("ck_upload_session_purpose"), "upload_session", type_="check")
    op.create_check_constraint(
        op.f("ck_upload_session_purpose"), "upload_session", f"purpose IN ({_OLD_PURPOSES})"
    )
    for table in _TABLES:
        disable_rls(table)
        op.drop_table(table)
