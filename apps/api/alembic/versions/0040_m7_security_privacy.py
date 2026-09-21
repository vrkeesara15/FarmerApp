"""M7 security and privacy: OTP abuse controls (SEC-021) and DPDP rights (NF-013)

Revision ID: 0040
Revises: 0035
Create Date: 2026-09-19 00:00:00 UTC

SEC-021 (SMS pumping protection):

* ``otp_challenge.request_ip`` — the client IP a send came from, for the per-IP velocity
  rule; indexed with ``created_at`` so the hourly count is a range scan.
* ``otp_block`` — the abuse block list: a *hashed* phone or IP (``HMAC(otp_pepper, …)``),
  why it was blocked, how many strikes and until when. Under RLS like every tenant table;
  updatable (a strike raises ``strikes`` and extends ``blocked_until``).

NF-013 (data-principal rights, on the existing FM-015 ``data_request`` ticket):

* ``type`` gains ``grievance`` (the DPDP grievance-redressal channel).
* ``subject`` / ``message`` — a grievance's one-line subject and body.
* ``requested_changes`` — a correction request's ``{field: new value}``, applied by staff
  through ``POST /v1/admin/data-requests/{id}/apply-correction``.
* ``erasure_report`` — what an erasure actually did: which fields were anonymised and which
  record classes were retained (financial records, 8 years, NF-012) with the reason.

Backward compatible: every new column is nullable or has a default, and the widened CHECK
constraint accepts every value the previous release wrote. Downgrade drops them (and refuses
nothing: rows of the new type would already violate the narrowed constraint, so the
downgrade deletes grievance tickets — noted here because it is not loss-free).

Revision id 0040 with branch label ``security_privacy``: three M7 branches run in parallel
(analytics, observability, this one) and each takes its own number off 0035, so two agents
never claim the same revision. The parent merges the heads.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from farmerapp.db.rls import disable_rls, enable_rls

revision: str = "0040"
down_revision: str | Sequence[str] | None = "0035"
branch_labels: str | Sequence[str] | None = ("security_privacy",)
depends_on: str | Sequence[str] | None = None

_OLD_REQUEST_TYPES = "'deletion', 'access', 'correction'"
_NEW_REQUEST_TYPES = _OLD_REQUEST_TYPES + ", 'grievance'"


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
    # ------------------------------------------------------------------ SEC-021
    op.add_column("otp_challenge", sa.Column("request_ip", sa.String(45), nullable=True))
    op.create_index(
        "ix_otp_challenge_request_ip_created",
        "otp_challenge",
        ["tenant_id", "request_ip", "created_at"],
    )
    op.create_index("ix_otp_challenge_tenant_created", "otp_challenge", ["tenant_id", "created_at"])

    op.create_table(
        "otp_block",
        *_base(),
        sa.Column("scope", sa.String(8), nullable=False),
        sa.Column("key_hash", sa.String(64), nullable=False),
        sa.Column("reason", sa.String(32), nullable=False),
        sa.Column("strikes", sa.Integer(), server_default="1", nullable=False),
        sa.Column("blocked_until", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("scope IN ('phone', 'ip')", name=op.f("ck_otp_block_scope")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_otp_block")),
        sa.UniqueConstraint("tenant_id", "key_hash", name="uq_otp_block_tenant_id_key_hash"),
    )
    op.create_index("ix_otp_block_tenant_id", "otp_block", ["tenant_id"])
    op.create_index("ix_otp_block_blocked_until", "otp_block", ["tenant_id", "blocked_until"])
    enable_rls("otp_block")

    # ------------------------------------------------------------------ NF-013
    op.drop_constraint(op.f("ck_data_request_type"), "data_request", type_="check")
    op.create_check_constraint(
        op.f("ck_data_request_type"), "data_request", f"type IN ({_NEW_REQUEST_TYPES})"
    )
    op.add_column("data_request", sa.Column("subject", sa.String(200), nullable=True))
    op.add_column("data_request", sa.Column("message", sa.Text(), nullable=True))
    op.add_column("data_request", sa.Column("requested_changes", postgresql.JSONB(), nullable=True))
    op.add_column("data_request", sa.Column("erasure_report", postgresql.JSONB(), nullable=True))


def downgrade() -> None:
    op.execute("DELETE FROM data_request WHERE type = 'grievance'")
    op.drop_column("data_request", "erasure_report")
    op.drop_column("data_request", "requested_changes")
    op.drop_column("data_request", "message")
    op.drop_column("data_request", "subject")
    op.drop_constraint(op.f("ck_data_request_type"), "data_request", type_="check")
    op.create_check_constraint(
        op.f("ck_data_request_type"), "data_request", f"type IN ({_OLD_REQUEST_TYPES})"
    )

    disable_rls("otp_block")
    op.drop_index("ix_otp_block_blocked_until", table_name="otp_block")
    op.drop_index("ix_otp_block_tenant_id", table_name="otp_block")
    op.drop_table("otp_block")

    op.drop_index("ix_otp_challenge_tenant_created", table_name="otp_challenge")
    op.drop_index("ix_otp_challenge_request_ip_created", table_name="otp_challenge")
    op.drop_column("otp_challenge", "request_ip")
