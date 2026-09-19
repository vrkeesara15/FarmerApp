"""FA-007 / FA-025: notifications in the sync change feed (the offline inbox).

``notification`` is not audited (a derived row), so the audit listener's change hook
(``farmerapp.sync.changes``) never sees it. This flush listener appends the ``sync_change``
rows itself: ``create`` for a new notification and ``update`` when ``read_at`` changes (the
inbox read receipt), in the same flush as the row. Delivery bookkeeping (status, attempts)
is not a feed change. The feed shows a user only their own notifications
(``farmerapp.sync.field_p1``).
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import event
from sqlalchemy.orm import Session, attributes

from farmerapp.db import audit
from farmerapp.notifications.models import Notification
from farmerapp.sync.models import SyncChange

ENTITY = "notification"


def _change(obj: Notification, action: str, version: int) -> SyncChange:
    who = audit.current_actor()
    return SyncChange(
        tenant_id=obj.tenant_id,
        entity=ENTITY,
        entity_id=obj.id,
        action=action,
        version=version,
        changed_at=datetime.now(UTC),
        actor_id=who.actor_id if who is not None else None,
    )


def _before_flush(session: Session, _ctx: Any, _instances: Any) -> None:
    changes: list[SyncChange] = []
    for obj in session.new:
        if isinstance(obj, Notification):
            if getattr(obj, "id", None) is None:  # the Python default runs at insert
                obj.id = uuid.uuid4()
            changes.append(_change(obj, "create", 1))
    for obj in session.dirty:
        if isinstance(obj, Notification) and obj not in session.new:
            history = attributes.get_history(obj, "read_at")
            if history.has_changes():
                changes.append(_change(obj, "update", 2))
    session.add_all(changes)


_INSTALLED = False


def install_feed_listener() -> None:
    global _INSTALLED
    if _INSTALLED:
        return
    event.listen(Session, "before_flush", _before_flush)
    _INSTALLED = True


__all__ = ["ENTITY", "install_feed_listener"]
