"""Change-log hook (FA-025): append a ``sync_change`` row for every synced entity mutation.

Registered on the FA-006 audit listener (``farmerapp.db.audit.install_audit_listener`` calls
``on_change(record_change)``), so it sees the same ``create`` / ``update`` / ``delete``
detection the audit trail uses — no second diff — and its rows are part of the same flush
as the mutation (they commit or roll back together). ``version`` is the row version after
the flush (creates 1, updates +1).
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy.orm import Session

from farmerapp.db import audit
from farmerapp.sync.models import SYNC_ENTITIES, SYNC_EXCLUDED_ENTITIES, SyncChange


def record_change(session: Session, change: audit.Change) -> None:
    if change.table in SYNC_EXCLUDED_ENTITIES or change.table not in SYNC_ENTITIES:
        return
    who = audit.current_actor()
    session.add(
        SyncChange(
            tenant_id=change.obj.tenant_id,
            entity=change.table,
            entity_id=change.obj.id,
            action=change.action,
            version=change.version,
            changed_at=datetime.now(UTC),
            actor_id=who.actor_id if who is not None else None,
        )
    )


__all__ = ["record_change"]
