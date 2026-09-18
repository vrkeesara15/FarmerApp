"""Gapless invoice numbers per store and financial year (ST-001, GST rule 46).

``FCC/KND/2026-27/000123`` = tenant prefix / store code / financial year (April - March,
IST) / six-digit sequence. ``next_seq`` takes the store's ``invoice_counter`` row with
``SELECT ... FOR UPDATE`` inside the sale's transaction: a concurrent sale at the same store
waits for the lock, and a rolled-back sale releases its number with the rollback, so the
sequence never has gaps or duplicates (tested with two sessions).
"""

from __future__ import annotations

import uuid
from datetime import date

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.invoices.models import InvoiceCounter

SEQ_WIDTH = 6


def financial_year(day: date) -> str:
    """``2026-09-18`` -> ``"2026-27"``; ``2027-03-31`` -> ``"2026-27"``; April starts a year."""
    start = day.year if day.month >= 4 else day.year - 1
    return f"{start}-{(start + 1) % 100:02d}"


def format_invoice_no(prefix: str, store_code: str, fy: str, seq: int) -> str:
    return f"{prefix}/{store_code}/{fy}/{seq:0{SEQ_WIDTH}d}"


async def next_seq(
    session: AsyncSession, *, tenant_id: uuid.UUID, store_id: uuid.UUID, fy: str
) -> int:
    await session.execute(
        insert(InvoiceCounter)
        .values(
            id=uuid.uuid4(), tenant_id=tenant_id, store_id=store_id, financial_year=fy, last_seq=0
        )
        .on_conflict_do_nothing(index_elements=["tenant_id", "store_id", "financial_year"])
    )
    row = (
        await session.execute(
            select(InvoiceCounter.id, InvoiceCounter.last_seq)
            .where(
                InvoiceCounter.tenant_id == tenant_id,
                InvoiceCounter.store_id == store_id,
                InvoiceCounter.financial_year == fy,
            )
            .with_for_update()
        )
    ).one()
    seq = int(row.last_seq) + 1
    await session.execute(
        update(InvoiceCounter)
        .where(InvoiceCounter.id == row.id)
        .values(last_seq=seq, version=InvoiceCounter.version + 1)
        .execution_options(synchronize_session=False)
    )
    return seq


__all__ = ["SEQ_WIDTH", "financial_year", "format_invoice_no", "next_seq"]
