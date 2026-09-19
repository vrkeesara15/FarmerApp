"""SEC-026 PII field encryption — the expand step

Revision ID: 0025
Revises: 0024
Create Date: 2026-09-19 15:00:00 UTC

Expand -> migrate -> contract (SPEC 10.2), step 1 of 3:

* ``tenant_data_key`` — wrapped per-tenant data keys (append-only, RLS).
* ``user``: ``phone_enc`` (bytea), ``phone_hash`` (HMAC-SHA256 hex), unique
  ``(tenant_id, phone_hash)``, index on ``phone_hash`` (login); ``phone`` becomes nullable.
* ``farmer``: ``phone_enc``, ``phone_hash`` (unique per tenant), ``landmark_enc``; ``phone``
  becomes nullable.
* ``auth_find_user_by_phone_hash(hash, phone)`` — the login lookup by hash (SECURITY DEFINER,
  owned by ``farmerapp_auth`` like ``auth_find_user_by_phone``, which stays until the contract
  step). A row not yet backfilled (no hash) still matches on its plain phone.

Backward compatible: the previous release keeps reading and writing the plain columns (new
columns are nullable, the old unique constraint stays). Step 2 (migrate) is the job
``python -m farmerapp.jobs pii-backfill --tenant …``; step 3 (contract, dropping the plain
columns) is ``alembic/manual/pii_contract.py``, applied by hand once the backfill reports
nothing left in every environment (docs/runbooks/pii-encryption.md).

Downgrade drops the new columns, function and table; it refuses while rows exist whose phone
is only encrypted (their plain column is NULL): re-enable ``PII_PLAINTEXT_WRITES`` and run the
backfill's ``--restore-plaintext`` first.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

from farmerapp.db.rls import APP_ROLE, AUTH_ROLE, disable_rls, enable_rls

revision: str = "0025"
down_revision: str | Sequence[str] | None = "0024"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

HASH_LOOKUP = "auth_find_user_by_phone_hash(text, text)"


def upgrade() -> None:
    op.create_table(
        "tenant_data_key",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("key_version", sa.Integer(), nullable=False),
        sa.Column("wrapped_key", sa.LargeBinary(), nullable=False),
        sa.Column("kek_backend", sa.String(8), nullable=False),
        sa.Column("kek_name", sa.String(300), nullable=False),
        sa.CheckConstraint("key_version >= 1", name=op.f("ck_tenant_data_key_key_version")),
        sa.CheckConstraint(
            "kek_backend IN ('kms', 'local')", name=op.f("ck_tenant_data_key_kek_backend")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_tenant_data_key")),
        sa.UniqueConstraint("tenant_id", "key_version", name=op.f("uq_tenant_data_key_tenant_id")),
    )
    enable_rls("tenant_data_key", append_only=True)

    for table in ("user", "farmer"):
        op.add_column(table, sa.Column("phone_enc", sa.LargeBinary(), nullable=True))
        op.add_column(table, sa.Column("phone_hash", sa.String(64), nullable=True))
        op.alter_column(table, "phone", existing_type=sa.String(16), nullable=True)
        op.create_unique_constraint(
            f"uq_{table}_tenant_id_phone_hash", table, ["tenant_id", "phone_hash"]
        )
    op.add_column("farmer", sa.Column("landmark_enc", sa.LargeBinary(), nullable=True))
    op.create_index("ix_user_phone_hash", "user", ["phone_hash"])

    op.execute(f'GRANT SELECT (phone_hash) ON "user" TO {AUTH_ROLE}')
    op.execute(
        """
CREATE OR REPLACE FUNCTION public.auth_find_user_by_phone_hash(p_hash text, p_phone text)
RETURNS TABLE (user_id uuid, tenant_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT u.id, u.tenant_id
    FROM public."user" u
    WHERE u.phone_hash = p_hash OR (u.phone_hash IS NULL AND u.phone = p_phone)
    ORDER BY (u.deleted_at IS NOT NULL), u.created_at, u.id
$$
""".strip()
    )
    op.execute(f"GRANT CREATE ON SCHEMA public TO {AUTH_ROLE}")
    op.execute(f"ALTER FUNCTION public.{HASH_LOOKUP} OWNER TO {AUTH_ROLE}")
    op.execute(f"REVOKE CREATE ON SCHEMA public FROM {AUTH_ROLE}")
    op.execute(f"REVOKE ALL ON FUNCTION public.{HASH_LOOKUP} FROM PUBLIC")
    op.execute(f"GRANT EXECUTE ON FUNCTION public.{HASH_LOOKUP} TO {APP_ROLE}")


def downgrade() -> None:
    for table in ("user", "farmer"):
        op.execute(
            f"""
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public."{table}" WHERE phone IS NULL) THEN
        RAISE EXCEPTION '{table} rows with an encrypted-only phone: restore plaintext first';
    END IF;
END
$$
"""
        )
    op.execute(f"DROP FUNCTION IF EXISTS public.{HASH_LOOKUP}")
    op.execute(f'REVOKE SELECT (phone_hash) ON "user" FROM {AUTH_ROLE}')
    op.drop_index("ix_user_phone_hash", table_name="user")
    op.drop_column("farmer", "landmark_enc")
    for table in ("user", "farmer"):
        op.drop_constraint(f"uq_{table}_tenant_id_phone_hash", table, type_="unique")
        op.alter_column(table, "phone", existing_type=sa.String(16), nullable=False)
        op.drop_column(table, "phone_hash")
        op.drop_column(table, "phone_enc")
    disable_rls("tenant_data_key")
    op.drop_table("tenant_data_key")
