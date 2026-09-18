"""ST-007: an approved credit request is consumed by exactly one sale

Revision ID: 0016
Revises: 0015
Create Date: 2026-09-18 12:00:00 UTC

Approvals used to match only on the ``order_id`` of the attempt that was blocked; the POS
(and an officer app that did not reuse its order id) creates a fresh order id per attempt,
so a sale retried after the cluster head approved it was refused again. Clients now retry
with ``credit_approval_request_id`` and the gate marks the request ``consumed``.

Expand-only:

* ``credit_approval_request.status`` gains ``consumed`` (CHECK widened).
* new nullable ``consumed_at`` and ``consumed_by_order_id`` (no FK: the gate runs before the
  order row is written, like ``order_id``); ``(status = 'consumed') = (consumed_at IS NOT
  NULL)``.
* ``used_at`` may now be set on ``approved`` or ``consumed`` rows; rows an order already used
  under 0012 (``approved`` + ``used_at``) become ``consumed`` (``consumed_at = used_at``).

Downgrade turns ``consumed`` rows back into ``approved`` + ``used_at`` (what 0012 meant by a
used approval) before narrowing the CHECKs; no row is deleted.
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0016"
down_revision: str | Sequence[str] | None = "0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TABLE = "credit_approval_request"
_OLD_STATUS = "status IN ('pending', 'approved', 'rejected')"
_NEW_STATUS = "status IN ('pending', 'approved', 'rejected', 'consumed')"
_OLD_USED_AT = "used_at IS NULL OR status = 'approved'"
_NEW_USED_AT = "used_at IS NULL OR status IN ('approved', 'consumed')"
_CONSUMED = "(status = 'consumed') = (consumed_at IS NOT NULL)"


def upgrade() -> None:
    op.add_column(TABLE, sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column(TABLE, sa.Column("consumed_by_order_id", sa.Uuid(), nullable=True))
    op.drop_constraint(op.f("ck_credit_approval_request_status"), TABLE, type_="check")
    op.create_check_constraint(op.f("ck_credit_approval_request_status"), TABLE, _NEW_STATUS)
    op.drop_constraint(op.f("ck_credit_approval_request_used_at"), TABLE, type_="check")
    op.create_check_constraint(op.f("ck_credit_approval_request_used_at"), TABLE, _NEW_USED_AT)
    op.execute(
        f"UPDATE {TABLE} SET status = 'consumed', consumed_at = used_at, "
        "consumed_by_order_id = order_id WHERE status = 'approved' AND used_at IS NOT NULL"
    )
    op.create_check_constraint(op.f("ck_credit_approval_request_consumed"), TABLE, _CONSUMED)
    op.create_index(
        "ix_credit_approval_request_consumed_by_order_id",
        TABLE,
        ["tenant_id", "consumed_by_order_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_credit_approval_request_consumed_by_order_id", table_name=TABLE)
    op.drop_constraint(op.f("ck_credit_approval_request_consumed"), TABLE, type_="check")
    op.execute(
        f"UPDATE {TABLE} SET status = 'approved', used_at = COALESCE(used_at, consumed_at) "
        "WHERE status = 'consumed'"
    )
    op.drop_constraint(op.f("ck_credit_approval_request_used_at"), TABLE, type_="check")
    op.create_check_constraint(op.f("ck_credit_approval_request_used_at"), TABLE, _OLD_USED_AT)
    op.drop_constraint(op.f("ck_credit_approval_request_status"), TABLE, type_="check")
    op.create_check_constraint(op.f("ck_credit_approval_request_status"), TABLE, _OLD_STATUS)
    op.drop_column(TABLE, "consumed_by_order_id")
    op.drop_column(TABLE, "consumed_at")
