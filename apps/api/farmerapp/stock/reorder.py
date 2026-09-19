"""ST-004 reorder levels: ``reorder_level`` per SKU per store (migration 0031_growth).

A store's SKU is **low** when its on-hand quantity (the ledger sum over the store's batches of
the SKU) is below its level. A SKU without a row uses the tenant default
``TenantSettings.stock_alerts.default_reorder_level``. Levels are set with
``PUT /v1/stores/{id}/reorder-levels`` (store managers and above) and read with
``GET /v1/stores/{id}/reorder-levels``.
"""

from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy import CheckConstraint, ForeignKey, Numeric, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns


class ReorderLevel(Base, BaseColumns):
    __tablename__ = "reorder_level"
    __table_args__ = (
        UniqueConstraint("tenant_id", "store_id", "sku_id"),
        CheckConstraint("reorder_level >= 0", name="reorder_level"),
    )

    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("store.id", ondelete="CASCADE"), nullable=False
    )
    sku_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("sku.id", ondelete="CASCADE"), nullable=False
    )
    reorder_level: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)


__all__ = ["ReorderLevel"]
