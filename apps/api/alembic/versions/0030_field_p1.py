"""M7 field P1: push tokens + delivery state, track gaps, travel claims, beat plans, demo
plots, farmer meetings

Revision ID: 0030
Revises: 0028
Create Date: 2026-09-19 21:00:00 UTC

FA-007 / VV-006 / VV-008 / FA-023 / FA-018 / FA-026 / FA-027 (docs/prs/M7-field-p1-api.md):

* ``push_token`` (FCM registration tokens per user / device; bookkeeping, not audited);
  ``notification`` gains ``delivery_status`` (``pending | delivered | failed | no_device |
  skipped``; rows that existed before are ``skipped`` so the first delivery run never pushes
  an old backlog), ``attempts``, ``next_attempt_at``, ``delivered_at``, ``last_error`` and a
  partial index of the pending rows.
* ``duty_session`` gains ``km_raw``, ``km_source``, ``processed_at`` (VV-006);
  ``track_gap`` (gaps > 30 min while on duty, deterministic ids, VV-008 reason + note).
* ``travel_claim`` (FA-023 expense claims, integer paise), ``beat_plan`` (FA-018),
  ``demo_plot`` / ``demo_observation`` (FA-026), ``farmer_meeting`` / ``meeting_attendance``
  (FA-027).
* ``upload_session.purpose`` gains ``demo_plot`` (FA-026 stage photos).

Every new table is under RLS (``enable_rls``). Expand-only: new tables, nullable or defaulted
columns and a widened CHECK; downgrade drops them and restores the CHECK. Branch label
``field_p1`` (the parent merges the M7 heads).
"""

from __future__ import annotations

from collections.abc import Sequence

import geoalchemy2
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0030"
down_revision: str | Sequence[str] | None = "0028"
branch_labels: str | Sequence[str] | None = ("field_p1",)
depends_on: str | Sequence[str] | None = None

_OLD_PURPOSES = "'farm_photo', 'visit_photo', 'receipt', 'diagnosis', 'profile', 'corpus'"
_NEW_PURPOSES = _OLD_PURPOSES + ", 'demo_plot'"
_TABLES = (
    "demo_observation",
    "demo_plot",
    "meeting_attendance",
    "farmer_meeting",
    "track_gap",
    "travel_claim",
    "push_token",
    "beat_plan",
)


def upgrade() -> None:
    op.create_table(
        "beat_plan",
        sa.Column("officer_id", sa.Uuid(), nullable=False),
        sa.Column("plan_date", sa.Date(), nullable=False),
        sa.Column(
            "status", sa.String(length=12), server_default=sa.text("'generated'"), nullable=False
        ),
        sa.Column("target", sa.Integer(), nullable=False),
        sa.Column(
            "items",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'[]'::jsonb"),
            nullable=False,
        ),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("edited_at", sa.DateTime(timezone=True), nullable=True),
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
        sa.CheckConstraint("status IN ('generated', 'edited')", name=op.f("ck_beat_plan_status")),
        sa.CheckConstraint("target > 0", name=op.f("ck_beat_plan_target")),
        sa.ForeignKeyConstraint(
            ["officer_id"],
            ["user.id"],
            name=op.f("fk_beat_plan_officer_id_user"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_beat_plan")),
        sa.UniqueConstraint(
            "tenant_id", "officer_id", "plan_date", name=op.f("uq_beat_plan_tenant_id")
        ),
    )
    op.create_index(op.f("ix_beat_plan_tenant_id"), "beat_plan", ["tenant_id"], unique=False)
    op.create_table(
        "push_token",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("token", sa.String(length=4096), nullable=False),
        sa.Column("platform", sa.String(length=8), nullable=False),
        sa.Column("device_id", sa.String(length=128), nullable=True),
        sa.Column("app_version", sa.String(length=32), nullable=True),
        sa.Column("last_registered_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("disabled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("disabled_reason", sa.String(length=32), nullable=True),
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
            "platform IN ('android', 'ios', 'web')", name=op.f("ck_push_token_platform")
        ),
        sa.CheckConstraint("char_length(token) >= 16", name=op.f("ck_push_token_token")),
        sa.ForeignKeyConstraint(
            ["user_id"], ["user.id"], name=op.f("fk_push_token_user_id_user"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_push_token")),
        sa.UniqueConstraint("tenant_id", "token", name=op.f("uq_push_token_tenant_id")),
    )
    op.create_index(op.f("ix_push_token_tenant_id"), "push_token", ["tenant_id"], unique=False)
    op.create_index("ix_push_token_user_id", "push_token", ["tenant_id", "user_id"], unique=False)
    op.create_table(
        "travel_claim",
        sa.Column("officer_id", sa.Uuid(), nullable=False),
        sa.Column("claim_date", sa.Date(), nullable=False),
        sa.Column("type", sa.String(length=8), nullable=False),
        sa.Column("amount_paise", sa.BigInteger(), nullable=False),
        sa.Column("receipt_uri", sa.String(length=512), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("km_computed", sa.Numeric(precision=8, scale=2), nullable=True),
        sa.Column(
            "status", sa.String(length=12), server_default=sa.text("'submitted'"), nullable=False
        ),
        sa.Column("decided_by", sa.Uuid(), nullable=True),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("decision_note", sa.Text(), nullable=True),
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
            "(status = 'submitted') = (decided_by IS NULL AND decided_at IS NULL)",
            name=op.f("ck_travel_claim_decision"),
        ),
        sa.CheckConstraint(
            "status IN ('submitted', 'approved', 'rejected')", name=op.f("ck_travel_claim_status")
        ),
        sa.CheckConstraint("type IN ('fuel', 'bus', 'other')", name=op.f("ck_travel_claim_type")),
        sa.CheckConstraint("amount_paise > 0", name=op.f("ck_travel_claim_amount")),
        sa.ForeignKeyConstraint(
            ["decided_by"],
            ["user.id"],
            name=op.f("fk_travel_claim_decided_by_user"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["officer_id"],
            ["user.id"],
            name=op.f("fk_travel_claim_officer_id_user"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_travel_claim")),
    )
    op.create_index(
        "ix_travel_claim_officer_date",
        "travel_claim",
        ["tenant_id", "officer_id", "claim_date"],
        unique=False,
    )
    op.create_index(
        "ix_travel_claim_status",
        "travel_claim",
        ["tenant_id", "status", "created_at"],
        unique=False,
    )
    op.create_index(op.f("ix_travel_claim_tenant_id"), "travel_claim", ["tenant_id"], unique=False)
    op.create_table(
        "track_gap",
        sa.Column("duty_session_id", sa.Uuid(), nullable=False),
        sa.Column("officer_id", sa.Uuid(), nullable=False),
        sa.Column("start_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("end_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("duration_s", sa.Integer(), nullable=False),
        sa.Column("reason", sa.String(length=16), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("reason_at", sa.DateTime(timezone=True), nullable=True),
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
            "reason IS NULL OR reason IN ('network', 'personal_break', 'vehicle', 'other')",
            name=op.f("ck_track_gap_reason"),
        ),
        sa.CheckConstraint(
            "(reason IS NULL) = (reason_at IS NULL)", name=op.f("ck_track_gap_reason_at")
        ),
        sa.CheckConstraint("end_at > start_at", name=op.f("ck_track_gap_span")),
        sa.ForeignKeyConstraint(
            ["duty_session_id"],
            ["duty_session.id"],
            name=op.f("fk_track_gap_duty_session_id_duty_session"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["officer_id"],
            ["user.id"],
            name=op.f("fk_track_gap_officer_id_user"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_track_gap")),
    )
    op.create_index("ix_track_gap_duty_session_id", "track_gap", ["duty_session_id"], unique=False)
    op.create_index(
        "ix_track_gap_officer_start",
        "track_gap",
        ["tenant_id", "officer_id", "start_at"],
        unique=False,
    )
    op.create_index(op.f("ix_track_gap_tenant_id"), "track_gap", ["tenant_id"], unique=False)
    op.create_table(
        "farmer_meeting",
        sa.Column("officer_id", sa.Uuid(), nullable=False),
        sa.Column("village_id", sa.Uuid(), nullable=False),
        sa.Column("topic", sa.String(length=200), nullable=False),
        sa.Column("held_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "checkin_point",
            geoalchemy2.types.Geography(
                geometry_type="POINT",
                srid=4326,
                dimension=2,
                spatial_index=False,
                from_text="ST_GeogFromText",
                name="geography",
                nullable=False,
            ),
            nullable=False,
        ),
        sa.Column("checkin_accuracy_m", sa.Float(), nullable=True),
        sa.Column("geofence_result", sa.String(length=16), nullable=False),
        sa.Column("distance_m", sa.Float(), nullable=True),
        sa.Column("status", sa.String(length=8), server_default=sa.text("'open'"), nullable=False),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True),
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
            "(status = 'closed') = (closed_at IS NOT NULL)",
            name=op.f("ck_farmer_meeting_closed_at"),
        ),
        sa.CheckConstraint("status IN ('open', 'closed')", name=op.f("ck_farmer_meeting_status")),
        sa.ForeignKeyConstraint(
            ["officer_id"],
            ["user.id"],
            name=op.f("fk_farmer_meeting_officer_id_user"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["village_id"],
            ["village.id"],
            name=op.f("fk_farmer_meeting_village_id_village"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_farmer_meeting")),
    )
    op.create_index(
        "ix_farmer_meeting_officer_held",
        "farmer_meeting",
        ["tenant_id", "officer_id", "held_at"],
        unique=False,
    )
    op.create_index(
        op.f("ix_farmer_meeting_tenant_id"), "farmer_meeting", ["tenant_id"], unique=False
    )
    op.create_index("ix_farmer_meeting_village_id", "farmer_meeting", ["village_id"], unique=False)
    op.create_table(
        "meeting_attendance",
        sa.Column("meeting_id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("method", sa.String(length=8), nullable=False),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("recorded_by", sa.Uuid(), nullable=False),
        sa.Column("otp_challenge_id", sa.Uuid(), nullable=True),
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
        sa.CheckConstraint("method IN ('otp', 'qr')", name=op.f("ck_meeting_attendance_method")),
        sa.ForeignKeyConstraint(
            ["farmer_id"],
            ["farmer.id"],
            name=op.f("fk_meeting_attendance_farmer_id_farmer"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["meeting_id"],
            ["farmer_meeting.id"],
            name=op.f("fk_meeting_attendance_meeting_id_farmer_meeting"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["recorded_by"],
            ["user.id"],
            name=op.f("fk_meeting_attendance_recorded_by_user"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_meeting_attendance")),
        sa.UniqueConstraint(
            "meeting_id", "farmer_id", name=op.f("uq_meeting_attendance_meeting_id")
        ),
    )
    op.create_index(
        "ix_meeting_attendance_farmer_id", "meeting_attendance", ["farmer_id"], unique=False
    )
    op.create_index(
        op.f("ix_meeting_attendance_tenant_id"), "meeting_attendance", ["tenant_id"], unique=False
    )
    op.create_table(
        "demo_plot",
        sa.Column("officer_id", sa.Uuid(), nullable=False),
        sa.Column("farmer_id", sa.Uuid(), nullable=False),
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column("crop_plot_id", sa.Uuid(), nullable=False),
        sa.Column("baseline", sa.String(length=16), nullable=False),
        sa.Column("comparison_crop_plot_id", sa.Uuid(), nullable=True),
        sa.Column("product_id", sa.Uuid(), nullable=True),
        sa.Column("treatment", sa.Text(), nullable=False),
        sa.Column(
            "status", sa.String(length=12), server_default=sa.text("'created'"), nullable=False
        ),
        sa.Column("stage", sa.String(length=16), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("harvested_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reported_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_observed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("demo_yield_kg_per_acre", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column("practice_yield_kg_per_acre", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column("yield_note", sa.Text(), nullable=True),
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
            "(baseline = 'comparison_plot') = (comparison_crop_plot_id IS NOT NULL)",
            name=op.f("ck_demo_plot_comparison"),
        ),
        sa.CheckConstraint(
            "baseline IN ('farmer_practice', 'comparison_plot')", name=op.f("ck_demo_plot_baseline")
        ),
        sa.CheckConstraint(
            "status IN ('created', 'active', 'harvested', 'reported')",
            name=op.f("ck_demo_plot_status"),
        ),
        sa.CheckConstraint(
            "status NOT IN ('harvested', 'reported') OR demo_yield_kg_per_acre IS NOT NULL",
            name=op.f("ck_demo_plot_yield_when_harvested"),
        ),
        sa.CheckConstraint(
            "demo_yield_kg_per_acre IS NULL OR demo_yield_kg_per_acre >= 0",
            name=op.f("ck_demo_plot_demo_yield"),
        ),
        sa.CheckConstraint(
            "practice_yield_kg_per_acre IS NULL OR practice_yield_kg_per_acre >= 0",
            name=op.f("ck_demo_plot_practice_yield"),
        ),
        sa.ForeignKeyConstraint(
            ["comparison_crop_plot_id"],
            ["crop_plot.id"],
            name=op.f("fk_demo_plot_comparison_crop_plot_id_crop_plot"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["crop_plot_id"],
            ["crop_plot.id"],
            name=op.f("fk_demo_plot_crop_plot_id_crop_plot"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["farm_id"], ["farm.id"], name=op.f("fk_demo_plot_farm_id_farm"), ondelete="RESTRICT"
        ),
        sa.ForeignKeyConstraint(
            ["farmer_id"],
            ["farmer.id"],
            name=op.f("fk_demo_plot_farmer_id_farmer"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["officer_id"],
            ["user.id"],
            name=op.f("fk_demo_plot_officer_id_user"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["product_id"],
            ["product.id"],
            name=op.f("fk_demo_plot_product_id_product"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_demo_plot")),
    )
    op.create_index("ix_demo_plot_farmer_id", "demo_plot", ["farmer_id"], unique=False)
    op.create_index(
        "ix_demo_plot_officer", "demo_plot", ["tenant_id", "officer_id", "status"], unique=False
    )
    op.create_index(op.f("ix_demo_plot_tenant_id"), "demo_plot", ["tenant_id"], unique=False)
    op.create_table(
        "demo_observation",
        sa.Column("demo_plot_id", sa.Uuid(), nullable=False),
        sa.Column("officer_id", sa.Uuid(), nullable=False),
        sa.Column("stage", sa.String(length=16), nullable=False),
        sa.Column("side", sa.String(length=8), server_default=sa.text("'demo'"), nullable=False),
        sa.Column("observed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column(
            "photo_uris",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'[]'::jsonb"),
            nullable=False,
        ),
        sa.Column(
            "data",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
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
        sa.CheckConstraint(
            "side IN ('demo', 'practice', 'both')", name=op.f("ck_demo_observation_side")
        ),
        sa.CheckConstraint(
            "stage IN ('sown', 'vegetative', 'flowering', 'fruiting', 'maturity', 'harvest')",
            name=op.f("ck_demo_observation_stage"),
        ),
        sa.ForeignKeyConstraint(
            ["demo_plot_id"],
            ["demo_plot.id"],
            name=op.f("fk_demo_observation_demo_plot_id_demo_plot"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["officer_id"],
            ["user.id"],
            name=op.f("fk_demo_observation_officer_id_user"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_demo_observation")),
    )
    op.create_index(
        "ix_demo_observation_plot",
        "demo_observation",
        ["demo_plot_id", "observed_at"],
        unique=False,
    )
    op.create_index(
        op.f("ix_demo_observation_tenant_id"), "demo_observation", ["tenant_id"], unique=False
    )
    op.add_column(
        "duty_session", sa.Column("km_raw", sa.Numeric(precision=8, scale=2), nullable=True)
    )
    op.add_column("duty_session", sa.Column("km_source", sa.String(length=16), nullable=True))
    op.add_column(
        "duty_session", sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True)
    )
    # Rows written before FA-007 delivery existed are never pushed (``skipped``); new rows
    # start ``pending``.
    op.add_column(
        "notification",
        sa.Column(
            "delivery_status",
            sa.String(length=16),
            server_default=sa.text("'skipped'"),
            nullable=False,
        ),
    )
    op.alter_column("notification", "delivery_status", server_default=sa.text("'pending'"))
    op.create_check_constraint(
        op.f("ck_notification_delivery_status"),
        "notification",
        "delivery_status IN ('pending', 'delivered', 'failed', 'no_device', 'skipped')",
    )
    op.add_column(
        "notification", sa.Column("attempts", sa.Integer(), server_default="0", nullable=False)
    )
    op.add_column(
        "notification", sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "notification", sa.Column("delivered_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column("notification", sa.Column("last_error", sa.String(length=200), nullable=True))
    op.create_index(
        "ix_notification_pending",
        "notification",
        ["tenant_id", "next_attempt_at"],
        unique=False,
        postgresql_where=sa.text("delivery_status = 'pending'"),
    )

    for table in _TABLES:
        enable_rls(table)

    op.drop_constraint(op.f("ck_upload_session_purpose"), "upload_session", type_="check")
    op.create_check_constraint(
        op.f("ck_upload_session_purpose"), "upload_session", f"purpose IN ({_NEW_PURPOSES})"
    )


def downgrade() -> None:
    op.drop_constraint(op.f("ck_upload_session_purpose"), "upload_session", type_="check")
    op.create_check_constraint(
        op.f("ck_upload_session_purpose"), "upload_session", f"purpose IN ({_OLD_PURPOSES})"
    )
    op.drop_index("ix_notification_pending", table_name="notification")
    op.drop_constraint(op.f("ck_notification_delivery_status"), "notification", type_="check")
    for column in ("last_error", "delivered_at", "next_attempt_at", "attempts", "delivery_status"):
        op.drop_column("notification", column)
    for column in ("processed_at", "km_source", "km_raw"):
        op.drop_column("duty_session", column)
    for table in _TABLES:
        disable_rls(table)
        op.drop_table(table)
