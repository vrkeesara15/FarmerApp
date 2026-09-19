"""SEC-026 step 2 (migrate): encrypt the PII of rows written before Alembic 0025.

``python -m farmerapp.jobs pii-backfill --tenant <id|slug> [--batch-size 500]
[--clear-plaintext | --restore-plaintext]``

* default (**encrypt**): for ``user.phone``, ``farmer.phone`` and ``farmer.landmark`` rows
  that have a plain value and no ciphertext, write ``*_enc`` (tenant data key) and
  ``phone_hash``. The plain column is kept, so a rollback to the previous release still reads
  every row.
* ``--clear-plaintext``: set the plain columns of rows that are already encrypted to NULL
  (run once the new release is stable and ``PII_PLAINTEXT_WRITES`` is off everywhere; the
  job refuses while it is on). Required before the contract migration.
* ``--restore-plaintext``: the rollback aid — decrypt into empty plain columns (before a
  downgrade of Alembic 0025 or a rollback to a release without SEC-026).

Batches of ``--batch-size`` rows by id, **one transaction per batch**: an interrupted run
resumes where it stopped, and a second run finds nothing to do (idempotent: every update is
guarded by the same predicate that selected the row). Core ``UPDATE`` statements: encryption
is a storage change, not a data change, so rows keep their ``version`` (no sync feed churn) and
the audit trail gets one ``pii.backfill`` event per tenant and run instead of one per row. Two
legacy rows of one tenant with the same normalised phone cannot both take the hash (unique
per tenant): the second is left as is, counted in ``conflicts`` and caught by VA-F02.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable, Sequence
from contextlib import AbstractAsyncContextManager
from dataclasses import dataclass, field
from typing import Any, Literal, cast

from sqlalchemy import ColumnElement, Table, and_, func, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.farmers.models import Farmer
from farmerapp.logging import get_logger
from farmerapp.pii.crypto import get_cipher, phone_hash
from farmerapp.settings import get_settings

log = get_logger("farmerapp.pii.backfill")

Mode = Literal["encrypt", "clear", "restore"]
DEFAULT_BATCH_SIZE = 500
#: A transaction bound to a tenant (default ``job_session``; tests pass savepoints).
Sessions = Callable[[uuid.UUID], AbstractAsyncContextManager[AsyncSession]]


@dataclass(frozen=True)
class Target:
    table: str
    model: Any
    #: (logical column, plain SQL column, ciphertext column, hash column or None)
    fields: tuple[tuple[str, str, str, str | None], ...]

    @property
    def sql(self) -> Table:
        return cast(Table, self.model.__table__)


TARGETS: tuple[Target, ...] = (
    Target("user", User, (("phone", "phone", "phone_enc", "phone_hash"),)),
    Target(
        "farmer",
        Farmer,
        (
            ("phone", "phone", "phone_enc", "phone_hash"),
            ("landmark", "landmark", "landmark_enc", None),
        ),
    ),
)


@dataclass
class TableReport:
    scanned: int = 0
    changed: int = 0
    conflicts: int = 0
    remaining: int = 0


@dataclass
class BackfillReport:
    tenant_id: uuid.UUID
    mode: Mode
    tables: dict[str, TableReport] = field(default_factory=dict)

    @property
    def changed(self) -> int:
        return sum(t.changed for t in self.tables.values())

    @property
    def remaining(self) -> int:
        return sum(t.remaining for t in self.tables.values())


def _needs(target: Target, mode: Mode) -> ColumnElement[bool]:
    c = target.sql.c
    parts: list[ColumnElement[bool]] = []
    for _, plain, enc, _ in target.fields:
        if mode == "encrypt":
            parts.append(and_(c[enc].is_(None), c[plain].is_not(None)))
        elif mode == "clear":
            parts.append(and_(c[enc].is_not(None), c[plain].is_not(None)))
        else:
            parts.append(and_(c[enc].is_not(None), c[plain].is_(None)))
    return or_(*parts)


def _values(target: Target, mode: Mode, tenant_id: uuid.UUID, row: Any) -> dict[str, Any]:
    cipher = get_cipher()
    values: dict[str, Any] = {}
    for logical, plain, enc, hashed in target.fields:
        plain_value, enc_value = row._mapping[plain], row._mapping[enc]
        if mode == "encrypt" and enc_value is None and plain_value is not None:
            values[enc] = cipher.encrypt(tenant_id, target.table, logical, plain_value)
            if hashed is not None:
                values[hashed] = phone_hash(plain_value)
        elif mode == "clear" and enc_value is not None and plain_value is not None:
            values[plain] = None
        elif mode == "restore" and enc_value is not None and plain_value is None:
            values[plain] = cipher.decrypt(tenant_id, target.table, logical, bytes(enc_value))
    return values


async def _batch(
    session: AsyncSession,
    target: Target,
    mode: Mode,
    tenant_id: uuid.UUID,
    after: uuid.UUID | None,
    size: int,
    report: TableReport,
) -> uuid.UUID | None:
    c = target.sql.c
    columns = [c.id]
    for _, plain, enc, _ in target.fields:
        columns += [c[plain], c[enc]]
    stmt = select(*columns).where(c.tenant_id == tenant_id, _needs(target, mode))
    if after is not None:
        stmt = stmt.where(c.id > after)
    rows = (await session.execute(stmt.order_by(c.id).limit(size))).all()
    for row in rows:
        report.scanned += 1
        values = _values(target, mode, tenant_id, row)
        if not values:
            continue
        guard = update(target.sql).where(c.id == row.id, _needs(target, mode)).values(**values)
        try:
            async with session.begin_nested():
                result = await session.execute(guard)
        except IntegrityError:  # the same normalised phone twice in one tenant (legacy)
            report.conflicts += 1
            log.warning("pii_backfill_conflict", table=target.table, row_id=str(row.id))
            continue
        report.changed += cast(Any, result).rowcount or 0
    return rows[-1].id if len(rows) == size else None


async def backfill_tenant(
    tenant_id: uuid.UUID,
    *,
    mode: Mode = "encrypt",
    batch_size: int = DEFAULT_BATCH_SIZE,
    sessions: Sessions = job_session,
) -> BackfillReport:
    if mode == "clear" and get_settings().pii_plaintext_writes:
        raise ValueError("PII_PLAINTEXT_WRITES is on: plain columns would be written again")
    report = BackfillReport(tenant_id=tenant_id, mode=mode)
    with audit.actor_scope(audit.system_actor(tenant_id)):
        for target in TARGETS:
            table_report = report.tables.setdefault(target.table, TableReport())
            after: uuid.UUID | None = None
            while True:
                async with sessions(tenant_id) as session:  # one transaction per batch
                    after = await _batch(
                        session, target, mode, tenant_id, after, batch_size, table_report
                    )
                if after is None:
                    break
            async with sessions(tenant_id) as session:
                c = target.sql.c
                table_report.remaining = int(
                    await session.scalar(
                        select(func.count())
                        .select_from(target.sql)
                        .where(c.tenant_id == tenant_id, _needs(target, mode))
                    )
                    or 0
                )
        async with sessions(tenant_id) as session:
            audit.record(
                session,
                action="pii.backfill",
                entity="tenant",
                entity_id=tenant_id,
                tenant_id=tenant_id,
                after={
                    "mode": mode,
                    **{
                        f"{name}_{k}": v
                        for name, t in report.tables.items()
                        for k, v in vars(t).items()
                    },
                },
            )
    log.info(
        "pii_backfill",
        tenant_id=str(tenant_id),
        mode=mode,
        changed=report.changed,
        remaining=report.remaining,
        conflicts=sum(t.conflicts for t in report.tables.values()),
    )
    return report


async def run_backfill(
    tenant_ids: Sequence[uuid.UUID], *, mode: Mode = "encrypt", batch_size: int = DEFAULT_BATCH_SIZE
) -> list[BackfillReport]:
    return [await backfill_tenant(t, mode=mode, batch_size=batch_size) for t in tenant_ids]


__all__ = [
    "DEFAULT_BATCH_SIZE",
    "TARGETS",
    "BackfillReport",
    "TableReport",
    "backfill_tenant",
    "run_backfill",
]
