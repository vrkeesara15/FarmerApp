"""VA-F10 — credit risk: a khata debit overdue more than ``max_overdue_days``, or a new credit
sale (a debit) written while the farmer already had an overdue debit at that store.

Ageing is FA-022's (``farmerapp.khata.aging``): credits settle the oldest due debits first;
a debit without a due date falls back to its harvest month, else ``created_at`` plus the
tenant's ``credit_due_days``. Days are IST calendar days.

* ``overdue_90`` — one flag per farmer, store and oldest overdue debit (key
  ``overdue:<store>:<entry>``): paying that debit and falling behind again is a new question.
* ``credit_while_overdue`` — a debit written in the last ``lookback_days`` when, counting
  only the entries before it, an open debit was at least ``min_overdue_days_for_new_credit``
  days overdue. One flag per new debit (key ``credit:<entry>``).

Batch (nightly), for the store manager of the farmer's village store.
"""

from __future__ import annotations

import uuid
from datetime import timedelta

from sqlalchemy import select

from farmerapp.khata.aging import open_debits
from farmerapp.khata.models import EntryType, KhataEntry
from farmerapp.rules.checks.common import ist_day
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject
from farmerapp.tenants.settings import get_tenant_settings


@rule("VA-F10")
async def check(ctx: RuleContext) -> list[Finding]:
    max_overdue = int(ctx.param("max_overdue_days"))
    min_overdue = int(ctx.param("min_overdue_days_for_new_credit"))
    since = ctx.now - timedelta(days=int(ctx.param("lookback_days")))
    due_days = (await get_tenant_settings(ctx.session, ctx.tenant_id)).credit_due_days
    today = ist_day(ctx.now)
    stmt = (
        select(KhataEntry)
        .where(KhataEntry.tenant_id == ctx.tenant_id, KhataEntry.created_at <= ctx.now)
        .order_by(KhataEntry.farmer_id, KhataEntry.store_id, KhataEntry.created_at, KhataEntry.id)
    )
    if ctx.subject_ids is not None:
        stmt = stmt.where(KhataEntry.farmer_id.in_(ctx.subject_ids))
    books: dict[tuple[uuid.UUID, uuid.UUID], list[KhataEntry]] = {}
    for entry in (await ctx.session.execute(stmt)).scalars():
        books.setdefault((entry.farmer_id, entry.store_id), []).append(entry)
    findings: list[Finding] = []
    for (farmer_id, store_id), entries in sorted(books.items(), key=lambda kv: str(kv[0])):
        late = [d for d in open_debits(entries, today, due_days) if d.days_overdue > max_overdue]
        if late:
            oldest = max(late, key=lambda d: d.days_overdue)
            findings.append(
                Finding(
                    subject_type=Subject.FARMER,
                    subject_id=farmer_id,
                    key=f"overdue:{store_id}:{oldest.entry_id}",
                    title=f"Khata debit overdue {oldest.days_overdue} days",
                    evidence=Evidence(
                        records=[record("farmer", farmer_id), record("store", store_id)]
                        + [record("khata_entry", d.entry_id) for d in late],
                        metrics={
                            "reason": "overdue_90",
                            "max_days_overdue": oldest.days_overdue,
                            "overdue_paise": sum(d.open_paise for d in late),
                            "max_overdue_days": max_overdue,
                            "due_date": oldest.due_date.isoformat(),
                        },
                    ),
                )
            )
        for entry in entries:
            if entry.type != EntryType.DEBIT or entry.created_at < since:
                continue
            before = [
                e for e in entries if (e.created_at, str(e.id)) < (entry.created_at, str(entry.id))
            ]
            written = ist_day(entry.created_at)
            overdue = [
                d for d in open_debits(before, written, due_days) if d.days_overdue >= min_overdue
            ]
            if not overdue:
                continue
            worst = max(overdue, key=lambda d: d.days_overdue)
            findings.append(
                Finding(
                    subject_type=Subject.FARMER,
                    subject_id=farmer_id,
                    key=f"credit:{entry.id}",
                    title=f"New credit while a debit was {worst.days_overdue} days overdue",
                    evidence=Evidence(
                        records=[
                            record("farmer", farmer_id),
                            record("store", store_id),
                            record("khata_entry", entry.id),
                        ]
                        + [record("khata_entry", d.entry_id) for d in overdue],
                        metrics={
                            "reason": "credit_while_overdue",
                            "new_credit_paise": entry.amount_paise,
                            "written_on": written.isoformat(),
                            "overdue_paise": sum(d.open_paise for d in overdue),
                            "max_days_overdue": worst.days_overdue,
                        },
                    ),
                )
            )
    return findings
