"""SEC-026 PII field encryption — the contract step (MANUAL, not in ``alembic/versions``)

Revision ID: pii_contract
Revises: 0026 (set ``down_revision`` to the head of the day when this file is moved)
Create Date: 2026-09-19 15:30:00 UTC

Step 3 of expand -> migrate -> contract (SPEC 10.2). It drops the plain ``user.phone``,
``farmer.phone`` and ``farmer.landmark`` columns, the old ``(tenant_id, phone)`` unique
constraints / index and ``auth_find_user_by_phone``, and makes ``phone_enc`` / ``phone_hash``
NOT NULL. It lives outside ``alembic/versions`` on purpose so that ``alembic upgrade head``
never drops plain columns on its own. A human applies it, in a release of its own, only
after (docs/runbooks/pii-encryption.md):

1. the release with Alembic 0025 has run in the environment for at least one full release
   cycle with ``PII_PLAINTEXT_WRITES=false``;
2. ``python -m farmerapp.jobs pii-backfill --tenant <every tenant>`` reports
   ``remaining=0`` and ``conflicts=0`` (resolve VA-F02 duplicates first);
3. ``pii-backfill --clear-plaintext`` reports ``remaining=0`` for every tenant;
4. the code of that release no longer maps ``phone_plain`` / ``landmark_plain`` and
   ``farmerapp.pii.lookup`` no longer falls back to them;
5. a backup / PITR point is noted (Cloud SQL) — the downgrade cannot restore the data.

Then move this file to ``alembic/versions/0NNN_pii_contract.py`` with the next revision
number and ``down_revision`` = the current head, and deploy.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "pii_contract"
down_revision: str | Sequence[str] | None = "0026"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    for table in ("user", "farmer"):
        op.execute(
            f"""
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public."{table}"
               WHERE phone_enc IS NULL OR phone_hash IS NULL OR phone IS NOT NULL) THEN
        RAISE EXCEPTION '{table}: run pii-backfill and pii-backfill --clear-plaintext first';
    END IF;
END
$$
"""
        )
    op.execute(
        """
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.farmer WHERE landmark IS NOT NULL) THEN
        RAISE EXCEPTION 'farmer.landmark: run pii-backfill --clear-plaintext first';
    END IF;
END
$$
"""
    )
    op.execute("DROP FUNCTION IF EXISTS public.auth_find_user_by_phone(text)")
    op.drop_index("ix_user_phone", table_name="user")
    op.drop_constraint("uq_user_tenant_id", "user", type_="unique")
    op.drop_constraint("uq_farmer_tenant_id", "farmer", type_="unique")
    for table in ("user", "farmer"):
        op.drop_column(table, "phone")
        op.alter_column(table, "phone_enc", existing_type=sa.LargeBinary(), nullable=False)
        op.alter_column(table, "phone_hash", existing_type=sa.String(64), nullable=False)
    op.drop_column("farmer", "landmark")


def downgrade() -> None:
    """Re-creates the empty plain columns; ``pii-backfill --restore-plaintext`` refills them."""
    op.add_column("farmer", sa.Column("landmark", sa.String(200), nullable=True))
    for table in ("user", "farmer"):
        op.alter_column(table, "phone_hash", existing_type=sa.String(64), nullable=True)
        op.alter_column(table, "phone_enc", existing_type=sa.LargeBinary(), nullable=True)
        op.add_column(table, sa.Column("phone", sa.String(16), nullable=True))
    op.create_unique_constraint("uq_farmer_tenant_id", "farmer", ["tenant_id", "phone"])
    op.create_unique_constraint("uq_user_tenant_id", "user", ["tenant_id", "phone"])
    op.create_index("ix_user_phone", "user", ["phone"])
