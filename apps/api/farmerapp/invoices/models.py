"""GST tax invoices (ST-001; migration 0013).

* ``invoice`` — the immutable snapshot of a tax invoice for one order: number, seller
  (legal name, GSTIN, address, state + GST state code), buyer, place of supply, whether the
  supply is intra-state (CGST + SGST, each half the rate) or inter-state (IGST), totals in
  paise with the round-off to the rupee, the amount in words and the per-line breakdown
  (``lines`` JSONB: HSN, quantity, rate, taxable value, tax rate and amounts). The PDF is
  rendered into the blob store (``pdf_uri``). CHECKs keep the totals and the tax split
  consistent.
* ``invoice_counter`` — the last number used per store and financial year. The next number
  is taken with ``SELECT ... FOR UPDATE`` inside the sale's transaction, so numbering is
  gapless: a rolled-back sale gives its number back (``farmerapp.invoices.numbering``).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import sql_in
from farmerapp.db.base import Base, BaseColumns


class SupplyType(StrEnum):
    INTRA = "intra"  # CGST + SGST
    INTER = "inter"  # IGST


class InvoiceCounter(Base, BaseColumns):
    __tablename__ = "invoice_counter"
    __table_args__ = (
        UniqueConstraint("tenant_id", "store_id", "financial_year"),
        CheckConstraint("last_seq >= 0", name="last_seq"),
    )
    __audit__ = False  # a counter; the invoice it numbers is audited

    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("store.id", ondelete="CASCADE"), nullable=False
    )
    financial_year: Mapped[str] = mapped_column(String(7), nullable=False)  # 2026-27
    last_seq: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")


class Invoice(Base, BaseColumns):
    __tablename__ = "invoice"
    __table_args__ = (
        UniqueConstraint("tenant_id", "invoice_no", name="uq_invoice_invoice_no"),
        UniqueConstraint("tenant_id", "order_id", name="uq_invoice_order_id"),
        UniqueConstraint(
            "tenant_id", "store_id", "financial_year", "seq", name="uq_invoice_store_fy_seq"
        ),
        CheckConstraint(f"supply_type IN ({sql_in(SupplyType)})", name="supply_type"),
        CheckConstraint(
            "taxable_paise >= 0 AND cgst_paise >= 0 AND sgst_paise >= 0 AND igst_paise >= 0 "
            "AND total_paise >= 0",
            name="amounts",
        ),
        CheckConstraint(
            "total_paise = taxable_paise + cgst_paise + sgst_paise + igst_paise + round_off_paise",
            name="total",
        ),
        CheckConstraint(
            "(supply_type = 'intra' AND igst_paise = 0) OR "
            "(supply_type = 'inter' AND cgst_paise = 0 AND sgst_paise = 0)",
            name="tax_split",
        ),
        CheckConstraint("seq > 0", name="seq"),
        Index("ix_invoice_store_issued", "tenant_id", "store_id", "issued_at"),
    )

    order_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("order.id", ondelete="RESTRICT"), nullable=False
    )
    store_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("store.id", ondelete="RESTRICT"), nullable=False
    )
    farmer_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("farmer.id", ondelete="SET NULL"), nullable=True
    )
    invoice_no: Mapped[str] = mapped_column(String(32), nullable=False)
    financial_year: Mapped[str] = mapped_column(String(7), nullable=False)
    seq: Mapped[int] = mapped_column(Integer, nullable=False)
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    seller_name: Mapped[str] = mapped_column(String(200), nullable=False)
    seller_gstin: Mapped[str] = mapped_column(String(15), nullable=False)
    seller_address: Mapped[str] = mapped_column(String(300), nullable=False)
    seller_state: Mapped[str] = mapped_column(String(80), nullable=False)
    seller_state_code: Mapped[str] = mapped_column(String(2), nullable=False)
    buyer_name: Mapped[str] = mapped_column(String(200), nullable=False)
    buyer_phone: Mapped[str | None] = mapped_column(String(16), nullable=True)
    buyer_gstin: Mapped[str | None] = mapped_column(String(15), nullable=True)
    buyer_state: Mapped[str] = mapped_column(String(80), nullable=False)
    place_of_supply: Mapped[str] = mapped_column(String(90), nullable=False)
    supply_type: Mapped[str] = mapped_column(String(8), nullable=False)
    taxable_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    cgst_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    sgst_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    igst_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    round_off_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    total_paise: Mapped[int] = mapped_column(BigInteger, nullable=False)
    amount_in_words: Mapped[str] = mapped_column(Text, nullable=False)
    lines: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, nullable=False)
    pdf_uri: Mapped[str | None] = mapped_column(String(512), nullable=True)
    created_by: Mapped[uuid.UUID | None] = mapped_column(Uuid, nullable=True)


__all__ = ["Invoice", "InvoiceCounter", "SupplyType"]
