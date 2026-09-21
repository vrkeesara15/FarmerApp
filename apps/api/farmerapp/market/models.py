"""FM-012 data model (Alembic ``0043_m8_market_referral_nlq``).

``mandi_price`` — one row per (market, crop, variety, grade, price date) as published by the
public source. Prices are **integer paise per quintal** (CLAUDE.md: money is integer paise);
the source publishes rupees per quintal, so the adapter multiplies by 100.

The row records where the figure came from (``source`` = the dataset key, ``source_name`` =
what the apps display, ``source_url``) and when we fetched it (``fetched_at``), so every
screen can show "as of <price_date> — <source_name>" (the FM-012 acceptance criterion).

Prices are **indicative**: they are a public reference feed, not a quote from any store, and
both apps say so next to the figure.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from enum import StrEnum

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns


class PriceSource(StrEnum):
    """Where a ``mandi_price`` row came from."""

    #: data.gov.in resource 9ef84268-d588-465a-a308-a864a43d0070 (Agmarknet daily mandi prices).
    AGMARKNET = "agmarknet"
    #: The deterministic offline stand-in (tests, local development, CI).
    FAKE = "fake"


#: Display names, shown verbatim in both apps next to the "as of" date (FM-012 acceptance).
SOURCE_NAMES: dict[str, str] = {
    PriceSource.AGMARKNET: "Agmarknet (data.gov.in)",
    PriceSource.FAKE: "Sample data (not a real price)",
}

SOURCE_URLS: dict[str, str] = {
    PriceSource.AGMARKNET: (
        "https://data.gov.in/resource/current-daily-price-various-commodities-various-markets-mandi"
    ),
    PriceSource.FAKE: "",
}


def sql_in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


class MandiPrice(Base, BaseColumns):
    __tablename__ = "mandi_price"
    __table_args__ = (
        UniqueConstraint(
            "tenant_id",
            "source",
            "market",
            "crop_id",
            "variety",
            "grade",
            "price_date",
            name="uq_mandi_price_reading",
        ),
        CheckConstraint(f"source IN ({sql_in(PriceSource)})", name="source"),
        CheckConstraint("min_price_paise >= 0", name="min_price_paise"),
        CheckConstraint("modal_price_paise >= 0", name="modal_price_paise"),
        CheckConstraint("max_price_paise >= 0", name="max_price_paise"),
        CheckConstraint("max_price_paise >= min_price_paise", name="price_range"),
        Index("ix_mandi_price_lookup", "tenant_id", "crop_id", "district", "price_date"),
        Index("ix_mandi_price_date", "tenant_id", "price_date"),
    )

    crop_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("crop.id", ondelete="CASCADE"), nullable=False
    )
    #: As published by the source, so the farmer recognises the mandi name.
    market: Mapped[str] = mapped_column(String(120), nullable=False)
    district: Mapped[str] = mapped_column(String(80), nullable=False)
    state: Mapped[str] = mapped_column(String(80), nullable=False)
    #: "" when the source does not break the commodity down (part of the unique key).
    variety: Mapped[str] = mapped_column(String(80), nullable=False, default="")
    grade: Mapped[str] = mapped_column(String(40), nullable=False, default="")
    #: The arrival / publication date of the figure (what "as of" shows). IST, from the source.
    price_date: Mapped[date] = mapped_column(Date, nullable=False)
    min_price_paise: Mapped[int] = mapped_column(Integer, nullable=False)
    modal_price_paise: Mapped[int] = mapped_column(Integer, nullable=False)
    max_price_paise: Mapped[int] = mapped_column(Integer, nullable=False)
    #: ``PriceSource``; ``source_name`` is what the apps display.
    source: Mapped[str] = mapped_column(String(24), nullable=False)
    source_name: Mapped[str] = mapped_column(String(120), nullable=False)
    source_url: Mapped[str | None] = mapped_column(String(300), nullable=True)
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


__all__ = ["SOURCE_NAMES", "SOURCE_URLS", "MandiPrice", "PriceSource"]
