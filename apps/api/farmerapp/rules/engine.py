"""The rules engine: run the enabled rules of one mode and turn findings into flags (SPEC 6.1).

Three runners share ``run_rules``:

* **inline** — ``run_inline(session, tenant_id, subject, ids)`` from API write paths, in the
  request transaction (FA-012 registration and farm edits call it for VA-F01 / F02 / F03).
* **event** — ``emit(session, tenant_id, topic, subject, id)`` for rules whose ``triggers``
  include the topic: called in-process (write paths and bus subscribers,
  ``farmerapp.rules.events``) and by the Pub/Sub worker for ``visit.created`` /
  ``farmer.registered`` / ``payment.webhook``.
* **batch** — ``run_batch(session, tenant_id)`` over the whole tenant; the nightly job
  (``python -m farmerapp.jobs run-rules --mode batch``) calls it per tenant at 02:00 IST.
  Idempotent: an unresolved flag with the same dedupe key is never raised twice.

Every rule runs in its own savepoint: a failing rule is logged (``rule_failed``) and rolled
back while the others — and the caller's write — carry on. A validation agent never blocks
the business transaction it observes.
"""

from __future__ import annotations

import uuid
from collections import Counter
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.models.tenant import Tenant
from farmerapp.flags.service import raise_flag
from farmerapp.logging import get_logger
from farmerapp.rules.loader import RuleSet, get_rule_set
from farmerapp.rules.registry import RuleContext, implementations
from farmerapp.rules.schema import Mode, RuleConfig, Subject

log = get_logger("farmerapp.rules")


@dataclass
class RunReport:
    tenant_id: uuid.UUID
    mode: Mode
    rules_run: list[str] = field(default_factory=list)
    findings: Counter[str] = field(default_factory=Counter)
    raised: Counter[str] = field(default_factory=Counter)
    failed: list[str] = field(default_factory=list)
    flag_ids: list[uuid.UUID] = field(default_factory=list)

    @property
    def total_raised(self) -> int:
        return sum(self.raised.values())


async def _tenant_slug(session: AsyncSession, tenant_id: uuid.UUID) -> str | None:
    return await session.scalar(select(Tenant.slug).where(Tenant.id == tenant_id))


async def run_rules(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    mode: Mode,
    *,
    subject: Subject | None = None,
    subject_ids: Iterable[uuid.UUID] | None = None,
    trigger: str | None = None,
    rule_ids: Iterable[str] | None = None,
    payload: dict[str, Any] | None = None,
    now: datetime | None = None,
    rule_set: RuleSet | None = None,
) -> RunReport:
    """Run the enabled rules of ``mode`` (optionally for one ``subject`` / ``trigger`` /
    subset of ``rule_ids``) and raise their findings as flags."""
    now = now or datetime.now(UTC)
    rule_set = rule_set or get_rule_set()
    impls = implementations()
    slug = await _tenant_slug(session, tenant_id)
    wanted = set(rule_ids) if rule_ids is not None else None
    ids = tuple(subject_ids) if subject_ids is not None else None
    report = RunReport(tenant_id=tenant_id, mode=mode)
    candidates: list[RuleConfig] = rule_set.for_mode(mode, trigger=trigger)
    for config in candidates:
        if wanted is not None and config.id not in wanted:
            continue
        if subject is not None and config.subject != subject and trigger is None:
            continue
        if not config.enabled_for(slug):
            continue
        impl = impls.get(config.id)
        if impl is None:
            log.error("rule_not_implemented", rule_id=config.id)
            report.failed.append(config.id)
            continue
        ctx = RuleContext(
            session=session,
            tenant_id=tenant_id,
            rule=config,
            params=config.params_for(slug),
            mode=mode,
            now=now,
            subject_ids=ids,
            payload=dict(payload or {}),
        )
        try:
            async with session.begin_nested():
                findings = await impl(ctx)
                for finding in findings:
                    flag = await raise_flag(
                        session,
                        tenant_id=tenant_id,
                        rule=config,
                        finding=finding,
                        mode=mode,
                        now=now,
                    )
                    if flag is not None:
                        report.raised[config.id] += 1
                        report.flag_ids.append(flag.id)
        except Exception:
            log.exception("rule_failed", rule_id=config.id, mode=mode.value)
            report.failed.append(config.id)
            continue
        report.rules_run.append(config.id)
        report.findings[config.id] += len(findings)
    log.info(
        "rules_run",
        tenant_id=str(tenant_id),
        mode=mode.value,
        trigger=trigger,
        rules=report.rules_run,
        findings=dict(report.findings),
        raised=dict(report.raised),
        failed=report.failed,
    )
    return report


async def run_inline(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    subject: Subject,
    subject_ids: Iterable[uuid.UUID],
    *,
    now: datetime | None = None,
) -> RunReport:
    """Inline rules for records a write path just flushed (same transaction)."""
    return await run_rules(
        session, tenant_id, Mode.INLINE, subject=subject, subject_ids=subject_ids, now=now
    )


async def emit(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    topic: str,
    subject_ids: Iterable[uuid.UUID],
    *,
    payload: dict[str, Any] | None = None,
    now: datetime | None = None,
) -> RunReport:
    """Event rules subscribed to ``topic``; ``subject_ids`` are the records the event is
    about (a farmer for ``farmer.registered``, a visit for ``visit.created``)."""
    return await run_rules(
        session,
        tenant_id,
        Mode.EVENT,
        trigger=topic,
        subject_ids=subject_ids,
        payload=payload,
        now=now,
    )


async def run_batch(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    rule_ids: Iterable[str] | None = None,
    now: datetime | None = None,
    rule_set: RuleSet | None = None,
) -> RunReport:
    return await run_rules(
        session, tenant_id, Mode.BATCH, rule_ids=rule_ids, now=now, rule_set=rule_set
    )


__all__ = ["RunReport", "emit", "run_batch", "run_inline", "run_rules"]
