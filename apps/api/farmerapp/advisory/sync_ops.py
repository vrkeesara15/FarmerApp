"""FM-007 calendar tasks through ``POST /v1/sync`` (entity ``crop_plot_task``).

Devices never create tasks (the server generates them). An ``update`` op carries the two
fields the farmer owns — ``status`` (``pending`` | ``done``) and ``reminder_enabled`` — and is
merged whatever its ``base_version`` (``merge_fields``: every other field is server-owned and
dropped). The same code as ``PATCH /v1/calendar/tasks/{id}``.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.advisory.calendar import update_task, visible_task
from farmerapp.advisory.models import TaskStatus
from farmerapp.advisory.schemas import CropPlotTaskOut
from farmerapp.auth.models import User, UserRole
from farmerapp.farmers.errors import UnsupportedActionError

FARMER_OWNED = frozenset({"status", "reminder_enabled"})
WRITE_ROLES = frozenset({UserRole.FARMER, UserRole.FIELD_OFFICER})


async def update(
    session: AsyncSession,
    actor: User,
    task_id: uuid.UUID,
    payload: dict[str, Any],
    now: datetime,
) -> CropPlotTaskOut:
    if UserRole(actor.role) not in WRITE_ROLES:
        raise UnsupportedActionError("Only the farmer or their officer updates calendar tasks.")
    task = await visible_task(session, actor, task_id)
    fields = {k: v for k, v in payload.items() if k in FARMER_OWNED}
    status = TaskStatus(fields["status"]) if fields.get("status") is not None else None
    reminder = fields.get("reminder_enabled")
    row = await update_task(
        session,
        actor,
        task,
        status=status,
        reminder_enabled=bool(reminder) if reminder is not None else None,
        expected_version=None,
        now=now,
    )
    return CropPlotTaskOut.from_row(row)


__all__ = ["FARMER_OWNED", "update"]
