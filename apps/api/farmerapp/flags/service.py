"""Flag lifecycle (VA-002, VA-003, WC-010, OPS-010).

* ``raise_flag`` — the engine's only way to create a flag: dedupe (an unresolved flag with
  the same key, or any flag with the same key already reviewed under this rule version, means
  "nothing new"), route (``routing.route``), SLA from the rule, a ``created`` event and a
  notification per recipient. The insert runs in a savepoint so a concurrent duplicate that
  hits the partial unique index is a no-op, not an error.
* ``transition`` — the SPEC 6.1 state machine (409 ``invalid_transition`` otherwise);
  resolutions need a note and record the VA-006 label; escalating hands the flag to an
  auditor when the current owner is below that rung.
* ``add_comment`` / ``assign`` — the review thread and manual reassignment.
* ``escalate_overdue`` — OPS-010: every unresolved flag past its SLA moves one rung up the
  ladder (store manager -> cluster head -> auditor -> owner) with a fresh SLA.
* ``raise_system_flag`` — a flag raised by an OPS monitor rather than a validation rule
  (rule id ``OPS-008`` for the payment reconciliation finance ticket): same dedupe, routing,
  SLA, history and notifications, plus extra ``watchers`` (the tenant's accountants).
* ``flag_filters`` — SPEC 2.6-style row scope of the inbox.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import ColumnElement, and_, false, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.flags.errors import (
    AssigneeInvalidError,
    FlagClosedError,
    InvalidTransitionError,
)
from farmerapp.flags.models import (
    LABELS,
    RESOLVED,
    TRANSITIONS,
    UNRESOLVED,
    Flag,
    FlagComment,
    FlagEvent,
    FlagEventKind,
    FlagStatus,
)
from farmerapp.flags.routing import (
    LADDER,
    Route,
    Scope,
    first_holder,
    ladder_level,
    next_level,
    route,
)
from farmerapp.logging import get_logger
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.rules.registry import Finding
from farmerapp.rules.schema import Mode, OwnerRole, RuleConfig, Severity, Subject

log = get_logger("farmerapp.flags")

#: Roles that review flags (WC-010). Field officers only read / explain their own.
REVIEWER_ROLES = frozenset(
    {
        UserRole.OWNER,
        UserRole.DIRECTOR,
        UserRole.AUDITOR,
        UserRole.CLUSTER_HEAD,
        UserRole.STORE_MANAGER,
        UserRole.TENANT_ADMIN,
    }
)
TENANT_WIDE = frozenset(
    {UserRole.OWNER, UserRole.DIRECTOR, UserRole.AUDITOR, UserRole.TENANT_ADMIN}
)
DEFAULT_SLA_HOURS = 24
#: OPS monitors that raise flags (``raise_system_flag``); version 1 until their logic changes.
FINANCE_RULES = frozenset({"OPS-008"})
SYSTEM_RULE_VERSION = 1


def dedupe_key(rule_id: str, finding: Finding) -> str:
    return f"{rule_id}:{finding.subject_type.value}:{finding.subject_id}:{finding.key}"[:255]


# --------------------------------------------------------------------------- notifications
def _notify(
    session: AsyncSession, flag: Flag, user_ids: list[uuid.UUID], kind: NotificationKind
) -> None:
    for user_id in user_ids:
        session.add(
            Notification(
                tenant_id=flag.tenant_id,
                user_id=user_id,
                kind=kind.value,
                title_key=f"notification.{kind.value}.title",
                body_key=f"notification.{kind.value}.body",
                data={
                    "flag_id": str(flag.id),
                    "rule_id": flag.rule_id,
                    "severity": flag.severity,
                    "sla_due_at": flag.sla_due_at.isoformat(),
                },
            )
        )


def _event(
    flag: Flag,
    kind: FlagEventKind,
    *,
    actor_id: uuid.UUID | None,
    now: datetime,
    from_status: str | None = None,
    note: str | None = None,
    from_owner_id: uuid.UUID | None = None,
    label: str | None = None,
) -> FlagEvent:
    return FlagEvent(
        tenant_id=flag.tenant_id,
        created_at=now,
        flag_id=flag.id,
        kind=kind.value,
        actor_id=actor_id,
        from_status=from_status,
        to_status=flag.status,
        from_owner_id=from_owner_id,
        to_owner_id=flag.owner_id,
        label=label,
        note=note,
    )


# --------------------------------------------------------------------------- raise
async def _already_known(
    session: AsyncSession, tenant_id: uuid.UUID, key: str, rule_version: int
) -> bool:
    found = await session.scalar(
        select(Flag.id)
        .where(
            Flag.tenant_id == tenant_id,
            Flag.dedupe_key == key,
            Flag.deleted_at.is_(None),
            or_(
                Flag.status.in_([s.value for s in UNRESOLVED]),
                Flag.rule_version == rule_version,
            ),
        )
        .limit(1)
    )
    return found is not None


async def raise_flag(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    rule: RuleConfig,
    finding: Finding,
    mode: Mode,
    now: datetime,
) -> Flag | None:
    """Create the flag for ``finding`` unless it is already known; ``None`` when deduped."""
    return await _raise(
        session,
        tenant_id=tenant_id,
        rule_id=rule.id,
        rule_version=rule.version,
        severity=rule.severity,
        owner_role=rule.owner_role,
        sla_hours=rule.sla_hours,
        finding=finding,
        mode=mode,
        now=now,
    )


async def raise_system_flag(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    rule_id: str,
    finding: Finding,
    severity: Severity,
    owner_role: OwnerRole,
    sla_hours: int,
    now: datetime,
    watchers: list[uuid.UUID] | None = None,
) -> Flag | None:
    """A flag raised by an OPS monitor job (``rule_id`` like ``OPS-008``), batch mode."""
    return await _raise(
        session,
        tenant_id=tenant_id,
        rule_id=rule_id,
        rule_version=SYSTEM_RULE_VERSION,
        severity=severity,
        owner_role=owner_role,
        sla_hours=sla_hours,
        finding=finding,
        mode=Mode.BATCH,
        now=now,
        extra_watchers=watchers or [],
    )


async def _raise(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    rule_id: str,
    rule_version: int,
    severity: Severity,
    owner_role: OwnerRole,
    sla_hours: int,
    finding: Finding,
    mode: Mode,
    now: datetime,
    extra_watchers: list[uuid.UUID] | None = None,
) -> Flag | None:
    key = dedupe_key(rule_id, finding)
    if await _already_known(session, tenant_id, key, rule_version):
        return None
    target = await route(
        session,
        tenant_id=tenant_id,
        subject_type=finding.subject_type,
        subject_id=finding.subject_id,
        owner_role=owner_role,
        severity=severity,
    )
    watchers = list(target.watchers)
    for extra in extra_watchers or []:
        if extra != target.owner_id and extra not in watchers:
            watchers.append(extra)
    target = Route(
        owner_id=target.owner_id,
        owner_role=target.owner_role,
        watchers=watchers,
        scope=target.scope,
    )
    flag = Flag(
        id=uuid.uuid4(),
        tenant_id=tenant_id,
        created_at=now,
        rule_id=rule_id,
        rule_version=rule_version,
        subject_type=finding.subject_type.value,
        subject_id=finding.subject_id,
        severity=severity.value,
        title=finding.title[:200],
        evidence=finding.evidence.as_json(),
        raised_by_mode=mode.value,
        owner_id=target.owner_id,
        owner_role=target.owner_role,
        watchers=watchers,
        scope_cluster_id=target.scope.cluster_id,
        scope_store_id=target.scope.store_id,
        status=FlagStatus.OPEN.value,
        sla_due_at=now + timedelta(hours=sla_hours),
        dedupe_key=key,
    )
    try:
        async with session.begin_nested():
            session.add(flag)
            await session.flush()
    except IntegrityError:  # a concurrent run raised the same open flag first
        log.info("flag_dedupe_race", rule_id=rule_id, dedupe_key=key)
        return None
    session.add(_event(flag, FlagEventKind.CREATED, actor_id=None, now=now))
    _notify(session, flag, target.recipients, NotificationKind.FLAG_ASSIGNED)
    await session.flush()
    log.info(
        "flag_raised",
        tenant_id=str(tenant_id),
        flag_id=str(flag.id),
        rule_id=rule_id,
        rule_version=rule_version,
        # not ``severity``: that key is Cloud Logging's log severity (farmerapp.logging)
        flag_severity=flag.severity,
        subject_type=flag.subject_type,
        mode=mode.value,
        owner_role=flag.owner_role,
    )
    return flag


# --------------------------------------------------------------------------- scope
def watched_by(user_id: uuid.UUID) -> ColumnElement[bool]:
    """``user_id`` is one of the flag's watchers (auditors on high severity, VA-003)."""
    return Flag.watchers.contains([user_id])


def flag_filters(actor: User) -> list[ColumnElement[bool]]:
    """Which ``flag`` rows ``actor`` may see (WC-010 inbox, VA-005 own flags)."""
    filters: list[ColumnElement[bool]] = [Flag.tenant_id == actor.tenant_id]
    role = UserRole(actor.role)
    mine = or_(Flag.owner_id == actor.id, watched_by(actor.id))
    if role in TENANT_WIDE:
        return filters
    if role == UserRole.CLUSTER_HEAD:
        in_cluster = (
            Flag.scope_cluster_id == actor.cluster_id if actor.cluster_id is not None else false()
        )
        return [*filters, or_(in_cluster, mine)]
    if role == UserRole.STORE_MANAGER:
        farmer_data = (
            and_(Flag.subject_type == Subject.FARMER.value, Flag.scope_store_id == actor.store_id)
            if actor.store_id is not None
            else false()
        )
        return [*filters, or_(farmer_data, mine)]
    if role == UserRole.FIELD_OFFICER:
        return [
            *filters,
            Flag.subject_type == Subject.EMPLOYEE.value,
            Flag.subject_id == actor.id,
        ]
    if role == UserRole.ACCOUNTANT:  # OPS-008 finance tickets they watch
        return [*filters, Flag.rule_id.in_(sorted(FINANCE_RULES)), mine]
    return [*filters, false()]


def is_subject(actor: User, flag: Flag) -> bool:
    return flag.subject_type == Subject.EMPLOYEE.value and flag.subject_id == actor.id


def is_reviewer(actor: User) -> bool:
    return UserRole(actor.role) in REVIEWER_ROLES


async def visible_flag(
    session: AsyncSession, actor: User, flag_id: uuid.UUID, *, for_update: bool = False
) -> Flag:
    stmt = select(Flag).where(Flag.id == flag_id, Flag.deleted_at.is_(None), *flag_filters(actor))
    if for_update:
        stmt = stmt.with_for_update()
    flag = (await session.execute(stmt)).scalar_one_or_none()
    if flag is None:
        raise NotFoundError("Flag not found.")
    return flag


# --------------------------------------------------------------------------- transitions
async def transition(
    session: AsyncSession,
    actor: User,
    flag: Flag,
    to: FlagStatus,
    note: str | None,
    *,
    now: datetime,
) -> Flag:
    current = FlagStatus(flag.status)
    if to not in TRANSITIONS[current]:
        raise InvalidTransitionError(
            f"A flag in '{current.value}' cannot move to '{to.value}'.",
            extra={
                "from": current.value,
                "to": to.value,
                "allowed": sorted(s.value for s in TRANSITIONS[current]),
            },
        )
    if (to in RESOLVED or to == FlagStatus.ESCALATED) and not (note and note.strip()):
        raise InvalidTransitionError(
            "Resolving or escalating a flag needs a note.",
            extra={"from": current.value, "to": to.value, "reason": "note_required"},
        )
    from_owner = flag.owner_id
    flag.status = to.value
    label = LABELS.get(to)
    if to in RESOLVED:
        flag.resolved_at = now
        flag.resolved_by = actor.id
        flag.resolution_note = note
    reassigned = False
    if to == FlagStatus.ESCALATED:
        auditor_level = LADDER.index(UserRole.AUDITOR)
        if ladder_level(flag.owner_role) < auditor_level:
            hit = await first_holder(
                session,
                flag.tenant_id,
                Scope(cluster_id=flag.scope_cluster_id, store_id=flag.scope_store_id),
                from_level=auditor_level,
            )
            if hit is not None:
                flag.owner_id, flag.owner_role = hit[0], hit[1].value
                reassigned = True
    session.add(
        _event(
            flag,
            FlagEventKind.TRANSITION,
            actor_id=actor.id,
            now=now,
            from_status=current.value,
            note=note,
            from_owner_id=from_owner,
            label=label.value if label else None,
        )
    )
    if reassigned and flag.owner_id is not None:
        _notify(session, flag, [flag.owner_id], NotificationKind.FLAG_ESCALATED)
    await session.flush()
    log.info(
        "flag_transition",
        flag_id=str(flag.id),
        rule_id=flag.rule_id,
        from_status=current.value,
        to_status=to.value,
        label=label.value if label else None,
    )
    return flag


def _require_unresolved(flag: Flag) -> None:
    if FlagStatus(flag.status) in RESOLVED:
        raise FlagClosedError("This flag is resolved.")


async def add_comment(
    session: AsyncSession, actor: User, flag: Flag, body: str, *, now: datetime
) -> FlagComment:
    _require_unresolved(flag)
    comment = FlagComment(
        tenant_id=flag.tenant_id,
        created_at=now,
        flag_id=flag.id,
        author_id=actor.id,
        body=body,
        is_subject_explanation=is_subject(actor, flag),
    )
    session.add(comment)
    await session.flush()
    return comment


async def assign(
    session: AsyncSession,
    actor: User,
    flag: Flag,
    user_id: uuid.UUID,
    note: str | None,
    *,
    now: datetime,
) -> Flag:
    _require_unresolved(flag)
    assignee = (
        await session.execute(
            select(User).where(
                User.id == user_id,
                User.tenant_id == flag.tenant_id,
                User.status == UserStatus.ACTIVE.value,
                User.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if assignee is None or UserRole(assignee.role) not in REVIEWER_ROLES:
        raise AssigneeInvalidError("The assignee must be an active reviewer of this tenant.")
    if is_subject(assignee, flag):
        raise AssigneeInvalidError("A flag cannot be assigned to its own subject.")
    from_owner = flag.owner_id
    flag.owner_id = assignee.id
    flag.owner_role = assignee.role
    session.add(
        _event(
            flag,
            FlagEventKind.ASSIGNED,
            actor_id=actor.id,
            now=now,
            from_status=flag.status,
            note=note,
            from_owner_id=from_owner,
        )
    )
    _notify(session, flag, [assignee.id], NotificationKind.FLAG_ASSIGNED)
    await session.flush()
    return flag


# --------------------------------------------------------------------------- OPS-010
@dataclass(frozen=True)
class Escalation:
    flag_id: uuid.UUID
    rule_id: str
    from_owner_id: uuid.UUID | None
    to_owner_id: uuid.UUID
    to_role: str


async def escalate_overdue(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    now: datetime,
    sla_hours: dict[str, int] | None = None,
) -> list[Escalation]:
    """Move every unresolved flag past its SLA one rung up; returns what moved."""
    overdue = (
        (
            await session.execute(
                select(Flag)
                .where(
                    Flag.tenant_id == tenant_id,
                    Flag.deleted_at.is_(None),
                    Flag.status.in_([s.value for s in UNRESOLVED]),
                    Flag.sla_due_at < now,
                )
                .order_by(Flag.sla_due_at, Flag.id)
                .with_for_update(skip_locked=True)
            )
        )
        .scalars()
        .all()
    )
    out: list[Escalation] = []
    for flag in overdue:
        hit = await next_level(
            session,
            tenant_id,
            Scope(cluster_id=flag.scope_cluster_id, store_id=flag.scope_store_id),
            flag.owner_role,
        )
        if hit is None:
            log.warning("flag_sla_top_of_ladder", flag_id=str(flag.id), rule_id=flag.rule_id)
            continue
        from_owner = flag.owner_id
        hours = (sla_hours or {}).get(flag.rule_id, DEFAULT_SLA_HOURS)
        flag.owner_id, flag.owner_role = hit[0], hit[1].value
        flag.escalation_level += 1
        flag.sla_due_at = now + timedelta(hours=hours)
        session.add(
            _event(
                flag,
                FlagEventKind.SLA_ESCALATED,
                actor_id=None,
                now=now,
                from_status=flag.status,
                note="SLA passed",
                from_owner_id=from_owner,
            )
        )
        _notify(session, flag, [hit[0]], NotificationKind.FLAG_ESCALATED)
        out.append(
            Escalation(
                flag_id=flag.id,
                rule_id=flag.rule_id,
                from_owner_id=from_owner,
                to_owner_id=hit[0],
                to_role=hit[1].value,
            )
        )
    await session.flush()
    if out:
        log.warning("flags_sla_escalated", tenant_id=str(tenant_id), count=len(out))
    return out


def evidence_records(flag: Flag) -> list[dict[str, Any]]:
    records = flag.evidence.get("records") if isinstance(flag.evidence, dict) else None
    return [r for r in (records or []) if isinstance(r, dict)]


__all__ = [
    "DEFAULT_SLA_HOURS",
    "FINANCE_RULES",
    "REVIEWER_ROLES",
    "Escalation",
    "add_comment",
    "assign",
    "dedupe_key",
    "escalate_overdue",
    "evidence_records",
    "flag_filters",
    "is_reviewer",
    "is_subject",
    "raise_flag",
    "raise_system_flag",
    "transition",
    "visible_flag",
    "watched_by",
]
