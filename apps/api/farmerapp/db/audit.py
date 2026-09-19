"""Automatic audit trail (FA-006): every ORM create/update/delete writes an ``audit_log`` row.

How it works
------------
* **Who**: the actor is a ``ContextVar``. The auth dependency binds it for a request
  (``bind_actor(actor_from_request(request, user))``); jobs and the worker wrap their work
  in ``actor_scope(system_actor(tenant_id))``. Writes with no context are attributed to the
  system (``actor_id`` NULL, ``actor_role`` "system").
* **What**: a ``before_flush`` listener on every ``Session`` inspects ``new`` / ``dirty`` /
  ``deleted`` objects that carry a ``tenant_id`` (``BaseColumns`` / ``TenantRow``) and adds an
  ``AuditLog`` per object to the *same* flush, so the row commits or rolls back with the
  mutation. Diffs list only the changed columns plus ``id``; creates record the full row
  (``before`` NULL), hard deletes the full row (``after`` NULL), and setting ``deleted_at``
  (soft delete) is an ``<entity>.delete``.
* **Redaction** (one place: ``REDACTED_COLUMNS`` / ``MASKED_COLUMNS`` / ``EXCLUDED_COLUMNS``):
  secret hashes are never recorded, phones are masked to the last four digits, and the
  bookkeeping columns ``updated_at`` / ``version`` are left out.
* **Explicit events** that are not row changes (login, logout, exports later) go through
  ``record(session, action=..., ...)`` with the same actor context.

A model opts out with ``__audit__ = False`` (``AuditLog`` itself; high-volume telemetry
tables such as raw location points later).
"""

from __future__ import annotations

import contextlib
import contextvars
import uuid
from collections.abc import Callable, Iterator, Mapping
from dataclasses import dataclass, replace
from datetime import UTC, date, datetime
from decimal import Decimal
from enum import Enum
from typing import Any

import structlog
from fastapi import Request
from geoalchemy2.elements import _SpatialElement
from sqlalchemy import event
from sqlalchemy.orm import Session
from sqlalchemy.orm.base import instance_state

from farmerapp.db.models.audit_log import AuditLog
from farmerapp.pii.fields import audit_values, pii_columns
from farmerapp.pii.fields import install_listeners as install_pii_listeners

SYSTEM_ROLE = "system"

#: Columns whose values are never written to the trail (secrets at rest).
REDACTED_COLUMNS: frozenset[str] = frozenset({"code_hash", "token_hash"})
#: Bookkeeping columns that would only add noise to a diff.
#: ``embedding`` (M6 corpus images): 768 floats of derived data, never a meaningful diff.
EXCLUDED_COLUMNS: frozenset[str] = frozenset({"updated_at", "version", "embedding"})

DEVICE_HEADER = "X-Device-Id"
FORWARDED_FOR_HEADER = "X-Forwarded-For"
USER_AGENT_MAX = 512


def mask_phone(phone: str) -> str:
    """``+919876543210`` -> ``+91******3210`` (same rule as the auth logs)."""
    prefix = "+91" if phone.startswith("+91") else ""
    rest = phone[len(prefix) :]
    if len(rest) <= 4:
        return prefix + "*" * len(rest)
    return prefix + "*" * (len(rest) - 4) + rest[-4:]


def _mask_if_str(fn: Callable[[str], str]) -> Callable[[Any], Any]:
    def masked(value: Any) -> Any:
        return fn(value) if isinstance(value, str) else value

    return masked


#: Columns recorded in masked form: column -> masking function.
MASKED_COLUMNS: Mapping[str, Callable[[Any], Any]] = {"phone": _mask_if_str(mask_phone)}


# --------------------------------------------------------------------------- actor context
@dataclass(frozen=True)
class Actor:
    """Who is acting, and from where. ``actor_id`` is NULL for the system."""

    tenant_id: uuid.UUID | None
    actor_id: uuid.UUID | None
    actor_role: str
    ip: str | None = None
    device_id: str | None = None
    user_agent: str | None = None
    trace_id: str | None = None


_actor: contextvars.ContextVar[Actor | None] = contextvars.ContextVar("audit_actor", default=None)
#: SEC-024: the Play Integrity verdict of the current request (``farmerapp.integrity.deps``),
#: copied into every audit row the request writes (``audit_log.integrity``).
_integrity: contextvars.ContextVar[dict[str, Any] | None] = contextvars.ContextVar(
    "audit_integrity", default=None
)


def current_actor() -> Actor | None:
    return _actor.get()


def bind_actor(actor: Actor) -> contextvars.Token[Actor | None]:
    """Bind the actor for the rest of the current task (a request); see ``clear_actor``."""
    return _actor.set(actor)


def clear_actor() -> None:
    _actor.set(None)
    _integrity.set(None)


def bind_integrity(verdict: dict[str, Any] | None) -> None:
    """Attach a Play Integrity verdict to the audit rows of the rest of the request."""
    _integrity.set(verdict)


def current_integrity() -> dict[str, Any] | None:
    return _integrity.get()


@contextlib.contextmanager
def actor_scope(actor: Actor) -> Iterator[None]:
    """Attribute every write inside the block to ``actor`` (jobs, worker, tests)."""
    token = _actor.set(actor)
    try:
        yield
    finally:
        _actor.reset(token)


def _trace_id() -> str | None:
    value = structlog.contextvars.get_contextvars().get("trace_id")
    return str(value) if value else None


def system_actor(tenant_id: uuid.UUID | None = None) -> Actor:
    """The actor for jobs, the worker and scheduled tasks."""
    return Actor(tenant_id=tenant_id, actor_id=None, actor_role=SYSTEM_ROLE, trace_id=_trace_id())


def client_ip(request: Request) -> str | None:
    """First ``X-Forwarded-For`` hop (set by the load balancer) or the socket peer."""
    forwarded = request.headers.get(FORWARDED_FOR_HEADER)
    if forwarded:
        first = forwarded.split(",", 1)[0].strip()
        if first:
            return first[:45]
    return request.client.host if request.client else None


def actor_from_request(request: Request, user: Any, *, device_id: str | None = None) -> Actor:
    """Actor for an authenticated request: the user plus ip / device / user agent / trace.

    Device precedence: explicit ``device_id`` (login body), the ``X-Device-Id`` header, then
    the device bound on the user at their last login.
    """
    user_agent = request.headers.get("user-agent")
    device = device_id or request.headers.get(DEVICE_HEADER) or getattr(user, "device_id", None)
    return Actor(
        tenant_id=user.tenant_id,
        actor_id=user.id,
        actor_role=str(user.role),
        ip=client_ip(request),
        device_id=device[:128] if device else None,
        user_agent=user_agent[:USER_AGENT_MAX] if user_agent else None,
        trace_id=_trace_id(),
    )


# --------------------------------------------------------------------------- payloads
def jsonable(value: Any) -> Any:
    """Plain JSON for column values (uuid/datetime/date/enum/Decimal/geometry -> str)."""
    if isinstance(value, Enum):
        return jsonable(value.value)
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, _SpatialElement):
        # WKT as written, or the hex WKB PostGIS returned; either replays into ST_GeomFromEWKT/WKB.
        return str(value.desc)
    if isinstance(value, dict):
        return {str(k): jsonable(v) for k, v in value.items()}
    if isinstance(value, list | tuple | set | frozenset):
        return [jsonable(v) for v in value]
    return value


def redact(values: Mapping[str, Any]) -> dict[str, Any]:
    """Apply the redaction/masking lists and make the mapping JSON-safe."""
    out: dict[str, Any] = {}
    for key, value in values.items():
        if key in REDACTED_COLUMNS or key in EXCLUDED_COLUMNS:
            continue
        mask = MASKED_COLUMNS.get(key)
        out[key] = jsonable(mask(value) if mask is not None else value)
    return out


# --------------------------------------------------------------------------- explicit events
def record(
    session: Session | Any,
    *,
    action: str,
    entity: str,
    entity_id: uuid.UUID,
    tenant_id: uuid.UUID | None = None,
    before: Mapping[str, Any] | None = None,
    after: Mapping[str, Any] | None = None,
    actor: Actor | None = None,
) -> AuditLog:
    """Add an audit row for a non-ORM event (login, logout, export...) to ``session``.

    ``actor`` defaults to the bound context (or the system); ``tenant_id`` to the actor's.
    The row is flushed with the caller's transaction like any other object. ``created_at``
    is taken from the wall clock (not the transaction's ``now()``) so rows written in one
    transaction keep their order.
    """
    who = actor or current_actor() or system_actor()
    tenant = tenant_id or who.tenant_id
    if tenant is None:
        raise ValueError("audit.record needs a tenant_id (none bound on the actor)")
    row = AuditLog(
        id=uuid.uuid4(),
        tenant_id=tenant,
        actor_id=who.actor_id,
        actor_role=who.actor_role,
        action=action,
        entity=entity,
        entity_id=entity_id,
        before=redact(before) if before is not None else None,
        after=redact(after) if after is not None else None,
        ip=who.ip,
        device_id=who.device_id,
        user_agent=who.user_agent,
        trace_id=who.trace_id or _trace_id(),
        integrity=current_integrity(),
        created_at=datetime.now(UTC),
    )
    session.add(row)
    return row


# --------------------------------------------------------------------------- ORM listener
def is_audited(obj: object) -> bool:
    """Mapped rows with a ``tenant_id`` are audited unless the model says ``__audit__ = False``."""
    return (
        hasattr(obj, "__tablename__")
        and hasattr(obj, "tenant_id")
        and hasattr(obj, "id")
        and getattr(obj, "__audit__", True) is not False
    )


def _column_keys(obj: object) -> list[str]:
    return [attr.key for attr in instance_state(obj).mapper.column_attrs]


def _current_values(obj: object) -> dict[str, Any]:
    return {key: getattr(obj, key, None) for key in _column_keys(obj)}


def _ensure_ids(obj: Any) -> tuple[uuid.UUID, uuid.UUID]:
    """Ids for a row about to be inserted (Python-side defaults are not applied yet)."""
    if obj.id is None:
        obj.id = uuid.uuid4()
    if obj.tenant_id is None and obj.__tablename__ == "tenant":
        obj.tenant_id = obj.id  # a tenant is its own tenant (see models/tenant.py)
    if obj.tenant_id is None:
        raise ValueError(f"{obj.__tablename__} row has no tenant_id; cannot audit it")
    return obj.id, obj.tenant_id


def _diff(obj: object) -> tuple[dict[str, Any], dict[str, Any]] | None:
    """(before, after) of the changed columns, or ``None`` when nothing changed."""
    state = instance_state(obj)
    before: dict[str, Any] = {}
    after: dict[str, Any] = {}
    for key in _column_keys(obj):
        history = state.attrs[key].history
        if not history.has_changes():
            continue
        old = (
            history.deleted[0]
            if history.deleted
            else (history.unchanged[0] if history.unchanged else None)
        )
        new = history.added[0] if history.added else None
        if old == new:
            continue
        before[key] = old
        after[key] = new
    if not before and not after:
        return None
    return before, after


@dataclass(frozen=True)
class Change:
    """One row mutation detected at flush time: the object, the verb and the redacted diff.

    ``action`` is ``create`` / ``update`` / ``delete`` (a soft delete — ``deleted_at`` set —
    is a ``delete``). ``version`` is the row version *after* this flush (creates are 1,
    updates and soft deletes bump the ORM version counter; tables without a version column
    report 1).
    """

    obj: Any
    action: str
    before: dict[str, Any] | None
    after: dict[str, Any] | None
    hard_delete: bool = False  # the row is removed (session.deleted), not soft-deleted

    @property
    def table(self) -> str:
        return str(self.obj.__tablename__)

    @property
    def version(self) -> int:
        mapper = instance_state(self.obj).mapper
        column = mapper.version_id_col
        if self.action == "create" or column is None or column.key is None:
            return 1  # no optimistic-locking column (append-only rows): always version 1
        current = int(getattr(self.obj, column.key, None) or 0)
        return current if self.hard_delete else current + 1


ChangeHook = Callable[[Session, Change], None]
_hooks: list[ChangeHook] = []


def on_change(hook: ChangeHook) -> ChangeHook:
    """Register a hook that runs for every audited mutation in the same flush (FA-025 uses it
    for the sync change log). Hooks may add rows to the session; they must not query."""
    if hook not in _hooks:
        _hooks.append(hook)
    return hook


def pending_changes(session: Session) -> list[Change]:
    """The audited mutations the session is about to flush, in new / dirty / deleted order."""
    changes: list[Change] = []
    for obj in list(session.new):
        if not is_audited(obj):
            continue
        _ensure_ids(obj)
        pii = pii_columns(obj)
        snapshot = {k: v for k, v in _current_values(obj).items() if v is not None and k not in pii}
        after = {**redact(snapshot), **audit_values(obj, created=True)[1]}
        changes.append(Change(obj=obj, action="create", before=None, after=after))
    for obj in list(session.dirty):
        if not is_audited(obj) or not session.is_modified(obj):
            continue
        diff = _diff(obj)
        if diff is None:
            continue
        before, after = diff
        pii = pii_columns(obj)
        pii_before, pii_after = audit_values(obj, created=False)
        before = {k: v for k, v in before.items() if k not in pii}
        after = {k: v for k, v in after.items() if k not in pii}
        soft_deleted = (
            "deleted_at" in after
            and after["deleted_at"] is not None
            and before.get("deleted_at") is None
        )
        action = "delete" if soft_deleted else "update"
        before["id"] = after["id"] = obj.id
        changes.append(
            Change(
                obj=obj,
                action=action,
                before={**redact(before), **pii_before},
                after={**redact(after), **pii_after},
            )
        )
    for obj in list(session.deleted):
        if not is_audited(obj):
            continue
        pii = pii_columns(obj)
        values = {k: v for k, v in _current_values(obj).items() if k not in pii}
        changes.append(
            Change(
                obj=obj,
                action="delete",
                before={**redact(values), **audit_values(obj, created=True)[1]},
                after=None,
                hard_delete=True,
            )
        )
    return changes


def _new_row(session: Session, obj: Any, *, action: str, before: Any, after: Any) -> None:
    entity_id, tenant_id = _ensure_ids(obj)
    who = current_actor() or system_actor()
    if who.tenant_id != tenant_id:
        who = replace(who, tenant_id=tenant_id)
    session.add(
        AuditLog(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            actor_id=who.actor_id,
            actor_role=who.actor_role,
            action=f"{obj.__tablename__}.{action}",
            entity=obj.__tablename__,
            entity_id=entity_id,
            before=before,
            after=after,
            ip=who.ip,
            device_id=who.device_id,
            user_agent=who.user_agent,
            trace_id=who.trace_id or _trace_id(),
            integrity=current_integrity(),
            created_at=datetime.now(UTC),
        )
    )


def _before_flush(session: Session, _flush_context: Any, _instances: Any) -> None:
    for change in pending_changes(session):
        _new_row(
            session, change.obj, action=change.action, before=change.before, after=change.after
        )
        for hook in _hooks:
            hook(session, change)


_INSTALLED = False


def install_audit_listener() -> None:
    """Register the flush listener once, for every ``Session`` (sync core of ``AsyncSession``),
    together with the change hooks that ride on it (FA-025 sync change log)."""
    global _INSTALLED
    if _INSTALLED:
        return
    # SEC-026 first (``insert=True``): PII values are encrypted before the diff is taken, so
    # a changed landmark is a changed row here too.
    install_pii_listeners()
    event.listen(Session, "before_flush", _before_flush)
    # Local import: the hook module imports this one (``on_change`` / ``Change``).
    from farmerapp.sync.changes import record_change

    on_change(record_change)
    _INSTALLED = True


install_audit_listener()

__all__ = [
    "DEVICE_HEADER",
    "EXCLUDED_COLUMNS",
    "MASKED_COLUMNS",
    "REDACTED_COLUMNS",
    "SYSTEM_ROLE",
    "Actor",
    "Change",
    "ChangeHook",
    "actor_from_request",
    "actor_scope",
    "bind_actor",
    "bind_integrity",
    "clear_actor",
    "client_ip",
    "current_actor",
    "current_integrity",
    "install_audit_listener",
    "is_audited",
    "jsonable",
    "mask_phone",
    "on_change",
    "pending_changes",
    "record",
    "redact",
    "system_actor",
]
