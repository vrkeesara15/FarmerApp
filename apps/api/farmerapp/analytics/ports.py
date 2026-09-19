"""``FlagCountsPort``: open validation flags for the analytics screens.

The ``flag`` table and the rules engine (SPEC section 6, VA-*, WC-010) are built on their own
branch (``farmerapp/flags/``, ``farmerapp/rules/``). The owner home ("open validation flags"
KPI, open high-severity flags) and the field team scorecard ("flags" column) read them only
through this port, so the analytics package never imports the flags internals.

TODO(M4 flags branch, ``farmerapp/flags``): register the real adapter with
``app.state.flag_counts = <FlagsFlagCounts()>`` in ``create_app`` once the ``flag`` table
lands; until then ``NullFlagCounts`` answers zeros and empty lists.
"""

from __future__ import annotations

import uuid
from collections.abc import Collection
from dataclasses import dataclass, field
from datetime import datetime
from typing import Protocol

from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession


@dataclass(frozen=True)
class FlagQuery:
    """Which flags to count: the tenant, optional store / officer narrowing, a time window."""

    tenant_id: uuid.UUID
    store_ids: Collection[uuid.UUID] | None = None  # None = whole tenant
    officer_ids: Collection[uuid.UUID] | None = None  # None = every officer
    opened_before: datetime | None = None  # open as of this instant (None = now)


@dataclass(frozen=True)
class FlagCounts:
    open_total: int = 0
    open_high: int = 0
    by_officer: dict[uuid.UUID, int] = field(default_factory=dict)


@dataclass(frozen=True)
class FlagSummary:
    """One open high-severity flag for the owner home list (C10)."""

    id: uuid.UUID
    rule: str
    severity: str
    title: str
    opened_at: datetime
    officer_id: uuid.UUID | None = None
    store_id: uuid.UUID | None = None
    farmer_id: uuid.UUID | None = None


class FlagCountsPort(Protocol):
    async def counts(self, session: AsyncSession, query: FlagQuery) -> FlagCounts: ...

    async def open_high_severity(
        self, session: AsyncSession, query: FlagQuery, limit: int
    ) -> list[FlagSummary]: ...


class NullFlagCounts:
    """Until the flags branch lands: no flags anywhere."""

    async def counts(self, session: AsyncSession, query: FlagQuery) -> FlagCounts:
        return FlagCounts()

    async def open_high_severity(
        self, session: AsyncSession, query: FlagQuery, limit: int
    ) -> list[FlagSummary]:
        return []


NULL_FLAG_COUNTS = NullFlagCounts()


def get_flag_counts(request: Request) -> FlagCountsPort:
    """Dependency: the adapter on ``app.state.flag_counts``, else the null adapter."""
    port: FlagCountsPort = getattr(request.app.state, "flag_counts", NULL_FLAG_COUNTS)
    return port


__all__ = [
    "NULL_FLAG_COUNTS",
    "FlagCounts",
    "FlagCountsPort",
    "FlagQuery",
    "FlagSummary",
    "NullFlagCounts",
    "get_flag_counts",
]
