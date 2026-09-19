"""OPS-008 finance tickets and SEC-024 Play Integrity verdicts in the audit trail

Revision ID: 0024
Revises: 0023
Create Date: 2026-09-19 14:00:00 UTC

Expand-only:

* ``flag.subject_type`` gains ``tenant`` (CHECK widened): OPS monitors raise flags about the
  whole tenant — the OPS-008 payment reconciliation finance ticket (rule id ``OPS-008``, one
  per tenant and business day).
* ``audit_log.integrity`` (jsonb, nullable): the Play Integrity verdict of the request that
  wrote the row (login and sensitive actions); VA-E01 reads failed verdicts from it.

Downgrade deletes ``tenant`` flags (system tickets only, re-created by the next job run)
before narrowing the CHECK, and drops the column.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "0024"
down_revision: str | Sequence[str] | None = "0023"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_OLD_SUBJECTS = "('farmer', 'employee', 'visit', 'store')"
_NEW_SUBJECTS = "('farmer', 'employee', 'visit', 'store', 'tenant')"


def upgrade() -> None:
    op.drop_constraint(op.f("ck_flag_subject_type"), "flag", type_="check")
    op.create_check_constraint(
        op.f("ck_flag_subject_type"), "flag", f"subject_type IN {_NEW_SUBJECTS}"
    )
    op.add_column("audit_log", sa.Column("integrity", JSONB(), nullable=True))


def downgrade() -> None:
    op.drop_column("audit_log", "integrity")
    op.execute("DELETE FROM flag WHERE subject_type = 'tenant'")
    op.drop_constraint(op.f("ck_flag_subject_type"), "flag", type_="check")
    op.create_check_constraint(
        op.f("ck_flag_subject_type"), "flag", f"subject_type IN {_OLD_SUBJECTS}"
    )
