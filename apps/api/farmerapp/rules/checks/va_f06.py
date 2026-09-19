"""VA-F06 — registration burst: an officer registers more than ``max_registrations`` farmers
within ``window_minutes``, or one device registers farmers for more than
``max_officers_per_device`` officers.

* **Burst**: over the farmers registered in the last ``lookback_hours``, the
  ``max_registrations``-th next registration of the same officer (window function ``lead``)
  is less than ``window_minutes`` away. One flag per officer and IST day. Registrations are
  timed by when the device **captured** them (``farmer.captured_at``, the sync op's
  ``client_ts``), falling back to the server ``created_at`` for online registrations, so
  offline captures synced in one batch are not a burst. The look-back itself is on
  ``created_at`` (arrival), so a burst synced days later is still examined.
* **Shared device**: the audit trail (FA-006) records the ``X-Device-Id`` of every
  ``farmer.create``; a device used by several officers in the look-back suggests one person
  registering under other accounts. One flag per device and IST day, about the officer with
  the most registrations on it.

"Many farmers sharing one phone" cannot happen inside a tenant (``(tenant, phone)`` is
unique; VA-F01 / VA-F02 cover near-duplicates). Event mode runs on ``farmer.registered``
(``ctx.subject_ids`` are the new farmers: only their officers and devices are checked);
the nightly batch checks the whole tenant.

Params: ``max_registrations``, ``window_minutes``, ``max_officers_per_device``,
``lookback_hours``.
"""

from __future__ import annotations

import uuid
from collections import Counter
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import func, select

from farmerapp.db.models.audit_log import AuditLog
from farmerapp.farmers.models import Farmer
from farmerapp.rules.registry import Evidence, Finding, RuleContext, record, rule
from farmerapp.rules.schema import Subject

IST = ZoneInfo("Asia/Kolkata")


async def _bursts(ctx: RuleContext, since: datetime) -> list[Finding]:
    n = int(ctx.param("max_registrations"))
    window = timedelta(minutes=float(ctx.param("window_minutes")))
    at = func.coalesce(Farmer.captured_at, Farmer.created_at)
    base = select(
        Farmer.id,
        Farmer.registered_by,
        at.label("at"),
        func.lead(at, n)
        .over(partition_by=Farmer.registered_by, order_by=(at, Farmer.id))
        .label("nth_next"),
    ).where(
        Farmer.tenant_id == ctx.tenant_id,
        Farmer.deleted_at.is_(None),
        Farmer.registered_by.is_not(None),
        Farmer.created_at >= since,
    )
    if ctx.subject_ids is not None:
        officers = select(Farmer.registered_by).where(Farmer.id.in_(ctx.subject_ids))
        base = base.where(Farmer.registered_by.in_(officers))
    rows: list[tuple[uuid.UUID, uuid.UUID, datetime, datetime | None]] = list(
        (await ctx.session.execute(base)).tuples()
    )
    by_officer: dict[uuid.UUID, list[tuple[uuid.UUID, datetime]]] = {}
    for farmer_id, officer, created_at, _nth in rows:
        by_officer.setdefault(officer, []).append((farmer_id, created_at))
    findings: dict[str, Finding] = {}
    for _farmer_id, officer, start, nth_next in rows:
        if nth_next is None or nth_next - start >= window:
            continue
        day = start.astimezone(IST).date().isoformat()
        key = f"burst:{day}"
        if f"{officer}:{key}" in findings:
            continue
        in_burst = [f for f, at in by_officer[officer] if start <= at <= nth_next]
        minutes = int(window.total_seconds() // 60)
        findings[f"{officer}:{key}"] = Finding(
            subject_type=Subject.EMPLOYEE,
            subject_id=officer,
            key=key,
            title=f"{len(in_burst)} farmers registered within {minutes} minutes",
            evidence=Evidence(
                records=[record("user", officer)] + [record("farmer", f) for f in in_burst],
                metrics={
                    "reason": "registration_burst",
                    "registrations": len(in_burst),
                    "window_minutes": minutes,
                    "first_at": start.isoformat(),
                    "last_at": nth_next.isoformat(),
                },
            ),
        )
    return list(findings.values())


async def _shared_devices(ctx: RuleContext, since: datetime) -> list[Finding]:
    max_officers = int(ctx.param("max_officers_per_device"))
    stmt = (
        select(AuditLog.device_id, AuditLog.actor_id, Farmer.id, Farmer.created_at)
        .join(Farmer, Farmer.id == AuditLog.entity_id)
        .where(
            AuditLog.tenant_id == ctx.tenant_id,
            AuditLog.action == "farmer.create",
            AuditLog.device_id.is_not(None),
            AuditLog.actor_id.is_not(None),
            Farmer.deleted_at.is_(None),
            Farmer.created_at >= since,
        )
    )
    if ctx.subject_ids is not None:
        devices = select(AuditLog.device_id).where(
            AuditLog.tenant_id == ctx.tenant_id,
            AuditLog.action == "farmer.create",
            AuditLog.entity_id.in_(ctx.subject_ids),
        )
        stmt = stmt.where(AuditLog.device_id.in_(devices))
    by_device: dict[str, list[tuple[uuid.UUID, uuid.UUID, datetime]]] = {}
    for device, actor, farmer, at in (await ctx.session.execute(stmt)).tuples():
        if device is not None and actor is not None:  # filtered in SQL; narrows the types
            by_device.setdefault(device, []).append((actor, farmer, at))
    findings: list[Finding] = []
    for device, rows in sorted(by_device.items()):
        officers = Counter(actor for actor, _f, _at in rows)
        if len(officers) <= max_officers:
            continue
        subject = sorted(officers.items(), key=lambda kv: (-kv[1], str(kv[0])))[0][0]
        day = min(at for _a, _f, at in rows).astimezone(IST).date().isoformat()
        findings.append(
            Finding(
                subject_type=Subject.EMPLOYEE,
                subject_id=subject,
                key=f"device:{device}:{day}",
                title=f"One device registered farmers for {len(officers)} officers",
                evidence=Evidence(
                    records=[record("user", o) for o in sorted(officers, key=str)]
                    + [record("farmer", f) for _a, f, _at in rows],
                    metrics={
                        "reason": "shared_device",
                        "device_id": device,
                        "officers": len(officers),
                        "registrations": len(rows),
                    },
                ),
            )
        )
    return findings


@rule("VA-F06")
async def check(ctx: RuleContext) -> list[Finding]:
    since = ctx.now - timedelta(hours=float(ctx.param("lookback_hours")))
    return [*await _bursts(ctx, since), *await _shared_devices(ctx, since)]
