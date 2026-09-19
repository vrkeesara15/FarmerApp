"""``tenant_data_key`` — the wrapped per-tenant data keys of SEC-026 (Alembic 0025).

Append-only (``APPEND_ONLY_TABLES``: the app role may SELECT and INSERT only): a rotation is
a new ``key_version``; old versions stay to decrypt old values. ``wrapped_key`` is the DEK
encrypted by the KEK (``kek_backend`` ``kms`` / ``local``, ``kek_name`` = the KMS key); the
plain DEK exists only in process memory. Not audited (the row holds nothing readable and
its creation is logged as ``pii_data_key_created``).
"""

from __future__ import annotations

from sqlalchemy import CheckConstraint, Integer, LargeBinary, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, TenantRow


class TenantDataKey(Base, TenantRow):
    __tablename__ = "tenant_data_key"
    __table_args__ = (
        UniqueConstraint("tenant_id", "key_version"),
        CheckConstraint("key_version >= 1", name="key_version"),
        CheckConstraint("kek_backend IN ('kms', 'local')", name="kek_backend"),
    )
    __audit__ = False

    key_version: Mapped[int] = mapped_column(Integer, nullable=False)
    wrapped_key: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    kek_backend: Mapped[str] = mapped_column(String(8), nullable=False)
    kek_name: Mapped[str] = mapped_column(String(300), nullable=False)


__all__ = ["TenantDataKey"]
