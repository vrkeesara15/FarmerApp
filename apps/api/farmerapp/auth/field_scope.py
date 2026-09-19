"""Which field staff (users) a manager may see the M7 field records of (FA-018 / FA-023 /
FA-026 / FA-027): the SPEC 2.6 "Officer" rows, with finance reading travel.

======================================= ======================================================
role                                    staff whose beat plans / claims / meetings they see
======================================= ======================================================
owner / director / tenant admin /       every officer of the tenant
auditor / accountant
cluster head                            officers of their cluster (and themself)
field officer                           themself
store manager / agronomist / farmer     nobody
======================================= ======================================================
"""

from __future__ import annotations

import uuid
from collections.abc import Mapping
from typing import Any

from sqlalchemy import ColumnElement, Select, select

from farmerapp.auth.models import User, UserRole
from farmerapp.auth.scope import DEFAULT_VISIBILITY, USER_SCOPE, Visibility, scope_filters

FIELD_STAFF_VISIBILITY: Mapping[UserRole, Visibility] = {
    **DEFAULT_VISIBILITY,
    UserRole.STORE_MANAGER: Visibility.NONE,
    UserRole.AGRONOMIST: Visibility.NONE,
    UserRole.FARMER: Visibility.NONE,
}


def staff_filters(
    actor: User, visibility: Mapping[UserRole, Visibility] = FIELD_STAFF_VISIBILITY
) -> list[ColumnElement[bool]]:
    return scope_filters(actor, USER_SCOPE, visibility)


def staff_ids(
    actor: User, visibility: Mapping[UserRole, Visibility] = FIELD_STAFF_VISIBILITY
) -> Select[tuple[uuid.UUID]]:
    return select(User.id).where(*staff_filters(actor, visibility), User.deleted_at.is_(None))


def staff_column_filters(
    actor: User, column: Any, visibility: Mapping[UserRole, Visibility] = FIELD_STAFF_VISIBILITY
) -> list[ColumnElement[bool]]:
    """Narrow a ``*.officer_id`` column to the staff ``actor`` may see."""
    return [column.in_(staff_ids(actor, visibility))]


__all__ = ["FIELD_STAFF_VISIBILITY", "staff_column_filters", "staff_filters", "staff_ids"]
