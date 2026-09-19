"""Khata write helpers (FA-022, FA-021, ST-007): the only way code should add ledger rows.

``khata_entry`` is append-only; a correction is a new row. Both helpers add the row to the
caller's transaction (flushed, not committed) and return it; the FA-006 audit listener
records the create and the sync change log picks it up for the farmer's scope.

* ``post_debit`` — the farmer owes (a credit sale: ``ref_type = order``; a manual
  adjustment). The due date defaults to ``credit_due_date``: the farmer's next expected
  harvest (crop plot ``expected_harvest``; ``harvest_month`` = its first day), else the
  tenant's ``credit_due_days`` after today.
* ``post_credit`` — the farmer paid or was credited. **Payments (FA-021) call this** with
  ``ref_type = "payment"`` and ``ref_id = payment.id``; a cancelled credit order is reversed
  with ``ref_type = "adjustment"``.

``actor`` is either the authenticated ``User`` or an audit ``Actor`` (jobs, webhooks);
``created_by`` is its user id (``None`` for the system).
"""

from __future__ import annotations

import uuid
from collections.abc import Mapping
from datetime import UTC, date, datetime, timedelta
from typing import Any

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError
from farmerapp.auth.models import User
from farmerapp.db.audit import Actor as AuditActor
from farmerapp.farmers.models import CropPlot, Farm
from farmerapp.khata.models import EntryRef, EntryType, KhataEntry
from farmerapp.tenants.settings import (
    DEFAULT_CREDIT_DUE_DAYS,
    DEFAULT_STORE_MANAGER_MAX_CREDIT_LIMIT_PAISE,
    get_tenant_settings,
)

#: Who is writing: the request's user, or an audit actor (system jobs, webhooks).
Actor = User | AuditActor


class InvalidKhataEntryError(AppError):
    status = 422
    code = "invalid_khata_entry"


class CreditSettings(BaseModel):
    """Credit keys of ``tenant.settings`` (WC-012 "credit limits"); defaults when absent.

    ``store_manager_max_credit_limit_paise`` — ST-007: a store manager may set a farmer's
    limit up to this; above it the cluster head (or owner / director) must set it.
    ``credit_due_days`` — FA-022: due date of a credit sale without a known harvest.
    """

    model_config = ConfigDict(extra="ignore")

    store_manager_max_credit_limit_paise: int = Field(
        default=DEFAULT_STORE_MANAGER_MAX_CREDIT_LIMIT_PAISE, ge=0
    )
    credit_due_days: int = Field(default=DEFAULT_CREDIT_DUE_DAYS, ge=1, le=730)


def credit_settings(raw: Mapping[str, Any] | None) -> CreditSettings:
    return CreditSettings.model_validate(dict(raw or {}))


async def tenant_credit_settings(session: AsyncSession, tenant_id: uuid.UUID) -> CreditSettings:
    """The credit keys of the tenant, read through ``get_tenant_settings`` (WC-012)."""
    settings = await get_tenant_settings(session, tenant_id)
    return CreditSettings(
        store_manager_max_credit_limit_paise=settings.store_manager_max_credit_limit_paise,
        credit_due_days=settings.credit_due_days,
    )


def actor_user_id(actor: Actor | None) -> uuid.UUID | None:
    if actor is None:
        return None
    if isinstance(actor, User):
        return actor.id
    return actor.actor_id


def today_utc() -> date:
    return datetime.now(UTC).date()


async def next_harvest(session: AsyncSession, farmer_id: uuid.UUID, today: date) -> date | None:
    """The farmer's earliest expected harvest on or after ``today`` (live crop plots)."""
    return await session.scalar(
        select(CropPlot.expected_harvest)
        .join(Farm, Farm.id == CropPlot.farm_id)
        .where(
            Farm.farmer_id == farmer_id,
            Farm.deleted_at.is_(None),
            CropPlot.deleted_at.is_(None),
            CropPlot.expected_harvest.is_not(None),
            CropPlot.expected_harvest >= today,
        )
        .order_by(CropPlot.expected_harvest)
        .limit(1)
    )


async def credit_due_date(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    farmer_id: uuid.UUID,
    today: date,
) -> tuple[date, date | None]:
    """``(due_date, harvest_month)`` for a new debit: the next expected harvest (and its
    month), else ``today + credit_due_days`` (no harvest month)."""
    harvest = await next_harvest(session, farmer_id, today)
    if harvest is not None:
        return harvest, harvest.replace(day=1)
    settings = await tenant_credit_settings(session, tenant_id)
    return today + timedelta(days=settings.credit_due_days), None


def _check(amount_paise: int, ref_type: str) -> EntryRef:
    if isinstance(amount_paise, bool) or not isinstance(amount_paise, int) or amount_paise <= 0:
        raise InvalidKhataEntryError("A khata entry needs a positive integer amount in paise.")
    try:
        return EntryRef(ref_type)
    except ValueError as exc:
        raise InvalidKhataEntryError(f"Unknown khata reference type {ref_type!r}.") from exc


async def post_debit(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    farmer_id: uuid.UUID,
    store_id: uuid.UUID,
    amount_paise: int,
    ref_type: str,
    ref_id: uuid.UUID | None,
    actor: Actor | None,
    due_date: date | None = None,
    harvest_month: date | None = None,
    note: str | None = None,
    today: date | None = None,
) -> KhataEntry:
    """Append a debit (the farmer owes); the due date defaults to ``credit_due_date``."""
    ref = _check(amount_paise, ref_type)
    if due_date is None:
        due_date, harvest_month = await credit_due_date(
            session, tenant_id=tenant_id, farmer_id=farmer_id, today=today or today_utc()
        )
    entry = KhataEntry(
        tenant_id=tenant_id,
        farmer_id=farmer_id,
        store_id=store_id,
        type=EntryType.DEBIT,
        amount_paise=amount_paise,
        due_date=due_date,
        harvest_month=harvest_month,
        ref_type=ref,
        ref_id=ref_id,
        note=note,
        created_by=actor_user_id(actor),
    )
    session.add(entry)
    await session.flush()
    return entry


async def post_credit(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    farmer_id: uuid.UUID,
    store_id: uuid.UUID,
    amount_paise: int,
    ref_type: str,
    ref_id: uuid.UUID | None,
    actor: Actor | None,
    note: str | None = None,
) -> KhataEntry:
    """Append a credit (the farmer paid / was credited): ``ref_type`` is ``payment`` for a
    collection (FA-021) or ``adjustment`` for a correction / reversal."""
    ref = _check(amount_paise, ref_type)
    entry = KhataEntry(
        tenant_id=tenant_id,
        farmer_id=farmer_id,
        store_id=store_id,
        type=EntryType.CREDIT,
        amount_paise=amount_paise,
        ref_type=ref,
        ref_id=ref_id,
        note=note,
        created_by=actor_user_id(actor),
    )
    session.add(entry)
    await session.flush()
    return entry


__all__ = [
    "DEFAULT_CREDIT_DUE_DAYS",
    "DEFAULT_STORE_MANAGER_MAX_CREDIT_LIMIT_PAISE",
    "Actor",
    "CreditSettings",
    "InvalidKhataEntryError",
    "actor_user_id",
    "credit_due_date",
    "credit_settings",
    "next_harvest",
    "post_credit",
    "post_debit",
    "tenant_credit_settings",
    "today_utc",
]
