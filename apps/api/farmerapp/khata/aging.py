"""Khata ageing (FA-022, SPEC 5.2 "Credit overdue"): which debits are still open, when each
is due, and the overdue buckets 0-30 / 31-60 / 61-90 / 90+ days.

Credits settle debits **first due, first paid** (FIFO by due date, then by entry time): the
open part of a debit is what the credits so far did not cover. A debit's due date is its
``due_date``; rows written without one fall back to the end of their ``harvest_month``,
else ``created_at + credit_due_days``. A debit is overdue from the day after its due date;
``days_overdue`` 1-30 falls in ``0_30`` (the SPEC's first bucket), 31-60 in ``31_60`` and so
on. When every debit carries a due date (all write paths set one) the bucket total equals
``farmerapp.khata.models.overdue_paise``.

Pure functions over loaded rows so the API, the seed checks and tests share them.
"""

from __future__ import annotations

import calendar
import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date, timedelta

from farmerapp.khata.models import EntryType, KhataEntry

BUCKETS: tuple[tuple[str, int, int | None], ...] = (
    ("0_30", 1, 30),
    ("31_60", 31, 60),
    ("61_90", 61, 90),
    ("90_plus", 91, None),
)


@dataclass(frozen=True)
class OpenDebit:
    entry_id: uuid.UUID
    store_id: uuid.UUID
    amount_paise: int
    open_paise: int
    due_date: date
    days_overdue: int
    bucket: str | None


def bucket_for(days_overdue: int) -> str | None:
    for name, low, high in BUCKETS:
        if days_overdue >= low and (high is None or days_overdue <= high):
            return name
    return None


def effective_due_date(entry: KhataEntry, default_due_days: int) -> date:
    if entry.due_date is not None:
        return entry.due_date
    if entry.harvest_month is not None:
        month = entry.harvest_month
        last = calendar.monthrange(month.year, month.month)[1]
        return month.replace(day=last)
    return entry.created_at.date() + timedelta(days=default_due_days)


def open_debits(
    entries: Sequence[KhataEntry], today: date, default_due_days: int
) -> list[OpenDebit]:
    """The debits not yet covered by credits, oldest due first, with their ageing."""
    credits = sum(e.amount_paise for e in entries if e.type == EntryType.CREDIT)
    debits = sorted(
        (e for e in entries if e.type == EntryType.DEBIT),
        key=lambda e: (effective_due_date(e, default_due_days), e.created_at, e.id),
    )
    out: list[OpenDebit] = []
    for debit in debits:
        paid = min(credits, debit.amount_paise)
        credits -= paid
        remaining = debit.amount_paise - paid
        if remaining <= 0:
            continue
        due = effective_due_date(debit, default_due_days)
        days = max((today - due).days, 0)
        out.append(
            OpenDebit(
                entry_id=debit.id,
                store_id=debit.store_id,
                amount_paise=debit.amount_paise,
                open_paise=remaining,
                due_date=due,
                days_overdue=days,
                bucket=bucket_for(days),
            )
        )
    return out


def overdue_buckets(debits: Sequence[OpenDebit]) -> dict[str, int]:
    """``{"0_30": paise, "31_60": ..., "61_90": ..., "90_plus": ...}`` over open debits."""
    totals = {name: 0 for name, _, _ in BUCKETS}
    for debit in debits:
        if debit.bucket is not None:
            totals[debit.bucket] += debit.open_paise
    return totals


__all__ = [
    "BUCKETS",
    "OpenDebit",
    "bucket_for",
    "effective_due_date",
    "open_debits",
    "overdue_buckets",
]
