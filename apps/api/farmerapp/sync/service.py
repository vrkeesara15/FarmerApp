"""Apply outbox operations and read the change feed (FA-025, NF-003, SPEC 8.3).

Operations
----------
Applied in order, each inside its own SAVEPOINT of the request transaction: a rejected op
rolls back only itself and the batch continues. ``op_id`` is the idempotency key: the
result of every op is stored in ``sync_op`` and a replay returns it with status
``duplicate``. Payloads are the write models of ``farmerapp.farmers.schemas`` and the
mutation goes through ``farmerapp.farmers.service`` — the same code the REST endpoints run,
so validation, scope and warnings are identical. Failures become ``rejected`` with a
problem-style ``error`` (``code`` / ``status`` / ``detail`` / ``errors``).

Conflicts
---------
``base_version`` is the version the device edited. When it differs from the row's version
the entity's strategy decides (``CONFLICT_RULES``):

* ``last_writer_wins`` — farmer, farm, crop plot (SPEC FA-025 "last-writer for notes"):
  the op is applied when ``client_ts`` is newer than the row's ``updated_at``, otherwise
  the result is ``conflict`` with the current server state for the device to adopt.
* ``server_wins`` — reserved for money-bearing entities (khata, payments; SPEC FA-025
  "server wins for money") and used for the append-only consent record: a mismatch is
  always a ``conflict``.
* ``merge_fields`` — visits and duty sessions (M2): the client's fields are merged over the
  row whatever the ``base_version``, except the **server-owned** fields
  (``SERVER_OWNED_FIELDS``: a visit's score / status / confirmation / geofence decision;
  a duty session's ``end_at`` / ``end_reason`` once the server auto-ended it, VV-007), which
  are dropped from the payload (``merge_payload``). Visit photos, confirmations and policy
  acceptances are immutable once written (``server_wins``).

Visit ops (``visit`` create = FA-014 check-in / update = FA-015 capture + FA-017 check-out,
``visit_photo`` create, ``visit_confirmation`` create) are applied by
``farmerapp.visits.sync_ops``; duty sessions, location batches and policy acceptances by
the FA-010 / FA-011 services — all through the same code the REST endpoints use.

Changes feed
------------
``sync_change`` rows after the cursor, filtered by the actor's SPEC 2.6 scope (an officer
sees their own farmers' entities, a farmer their own), capped at ``MAX_CHANGES`` with
``has_more``; several changes of one entity collapse into the latest state. Deleted rows
come back as ``action: delete`` with ``{id, deleted_at}``.
"""

from __future__ import annotations

import base64
import binascii
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from typing import TYPE_CHECKING, Any

from pydantic import BaseModel, ValidationError
from sqlalchemy import and_, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, ForbiddenError, NotFoundError
from farmerapp.api.pagination import InvalidCursorError
from farmerapp.auth.models import User
from farmerapp.auth.scope import (
    duty_session_filters,
    farmer_filters,
    khata_entry_filters,
    officer_filters,
    order_filters,
    payment_filters,
    visit_filters,
)
from farmerapp.duty import service as duty
from farmerapp.duty.schemas import DutyEndIn, DutyStartIn
from farmerapp.farmers import service as farmers
from farmerapp.farmers.errors import UnsupportedActionError
from farmerapp.farmers.models import ConsentRecord, CropPlot, Farm, Farmer
from farmerapp.farmers.schemas import (
    ConsentIn,
    ConsentRecordOut,
    CropPlotCreate,
    CropPlotOut,
    CropPlotUpdate,
    FarmCreate,
    FarmerCreate,
    FarmerOut,
    FarmerUpdate,
    FarmOut,
    FarmUpdate,
)
from farmerapp.khata.credit import CreditLimitExceededError, decision_extra
from farmerapp.khata.models import KhataEntry
from farmerapp.khata.schemas import KhataEntryOut
from farmerapp.location.ingest import LocationBatchIn, ingest_batch
from farmerapp.location.models import DutySession, PolicyAcceptance
from farmerapp.location.schemas import DutySessionOut, PolicyAcceptanceOut
from farmerapp.logging import get_logger
from farmerapp.orders import sync_ops as order_sync
from farmerapp.orders.models import Order, OrderLine
from farmerapp.orders.schemas import OrderLineOut, OrderOut
from farmerapp.payments.models import Payment
from farmerapp.payments.schemas import PaymentOut
from farmerapp.policies import service as policies
from farmerapp.policies.schemas import PolicyAcceptIn
from farmerapp.settings import Settings
from farmerapp.sync.models import SyncChange, SyncOp
from farmerapp.sync.schemas import SyncChangeOut, SyncError, SyncOpIn, SyncResult
from farmerapp.uploads.blobstore import BlobStore
from farmerapp.visits import sync_ops as visit_sync
from farmerapp.visits.models import Visit, VisitConfirmation, VisitPhoto
from farmerapp.visits.schemas import VisitConfirmationOut, VisitOut, VisitPhotoOut

if TYPE_CHECKING:
    from farmerapp.auth.deps import AuthServices
    from farmerapp.payments.service import PaymentServices

log = get_logger("farmerapp.sync")

MAX_CHANGES = 500


class Strategy(StrEnum):
    SERVER_WINS = "server_wins"
    LAST_WRITER_WINS = "last_writer_wins"
    MERGE_FIELDS = "merge_fields"


CONFLICT_RULES: dict[str, Strategy] = {
    "farmer": Strategy.LAST_WRITER_WINS,
    "farm": Strategy.LAST_WRITER_WINS,
    "crop_plot": Strategy.LAST_WRITER_WINS,
    "consent_record": Strategy.SERVER_WINS,
    "visit": Strategy.MERGE_FIELDS,  # notes / crop_stage from the device; score etc. server
    "visit_photo": Strategy.SERVER_WINS,  # immutable once uploaded (EXIF, hashes, server time)
    "visit_confirmation": Strategy.SERVER_WINS,  # one outcome per request (FA-016)
    "duty_session": Strategy.MERGE_FIELDS,  # server wins for end_at once auto-ended (VV-007)
    "policy_acceptance": Strategy.SERVER_WINS,  # append-only (FA-011)
    "location_batch": Strategy.SERVER_WINS,  # write-only telemetry batch (FA-010); no feed row
    # M3 money-bearing entities (SPEC FA-025 "server wins for money"): totals, stock and
    # balances are recomputed server-side; a stale device version is always a conflict.
    "order": Strategy.SERVER_WINS,
    "order_line": Strategy.SERVER_WINS,
    "payment": Strategy.SERVER_WINS,
    "khata_entry": Strategy.SERVER_WINS,  # append-only ledger (FA-022)
}

#: ``merge_fields`` entities: fields a device may never overwrite.
SERVER_OWNED_FIELDS: dict[str, frozenset[str]] = {
    "visit": frozenset(
        {
            "score",
            "score_components",
            "status",
            "confirmation_channel",
            "confirmed_at",
            "geofence_result",
            "override_approved_by",
            "duration_s",
            "officer_id",
            "farmer_id",
            "tenant_id",
        }
    ),
    "duty_session": frozenset({"km", "stops", "officer_id", "tenant_id"}),
}

#: ``duty_session`` end fields become server-owned once the server ended the session.
_DUTY_END_FIELDS = frozenset({"end_at", "end_reason"})
#: Synced entities whose device write path has not landed yet: order lines (they travel
#: inside the ``order`` create, FA-020), payments and khata entries (FA-021 / FA-022). Ops on
#: them are rejected with ``unsupported_action``; they are already in the changes feed.
_ENTITIES_WITHOUT_WRITE_PATH: frozenset[str] = frozenset({"order_line", "payment", "khata_entry"})


def server_owned_fields(entity: str, row: Any) -> frozenset[str]:
    """The fields the server owns on ``row`` (static list plus the auto-ended duty end)."""
    owned = SERVER_OWNED_FIELDS.get(entity, frozenset())
    if entity == "duty_session" and getattr(row, "auto_ended", False):
        owned = owned | _DUTY_END_FIELDS
    return owned


def merge_payload(entity: str, row: Any, payload: dict[str, Any]) -> dict[str, Any]:
    """``merge_fields``: the payload without the server-owned fields of ``row``."""
    owned = server_owned_fields(entity, row)
    return {k: v for k, v in payload.items() if k not in owned}


# --------------------------------------------------------------------------- cursor
def encode_cursor(seq: int) -> str:
    return base64.urlsafe_b64encode(str(seq).encode()).decode().rstrip("=")


def decode_cursor(cursor: str | None) -> int:
    if not cursor:
        return 0
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        value = int(base64.urlsafe_b64decode(padded.encode()).decode())
    except (ValueError, binascii.Error, UnicodeDecodeError) as exc:
        raise InvalidCursorError("Malformed sync cursor.") from exc
    if value < 0:
        raise InvalidCursorError("Malformed sync cursor.")
    return value


# --------------------------------------------------------------------------- results
def _dump(model: BaseModel) -> dict[str, Any]:
    return model.model_dump(mode="json")


def _applied(op: SyncOpIn, out: BaseModel, version: int) -> SyncResult:
    return SyncResult(
        op_id=op.op_id, status="applied", entity_id=op.entity_id, version=version, server=_dump(out)
    )


def _conflict(op: SyncOpIn, out: BaseModel, version: int) -> SyncResult:
    return SyncResult(
        op_id=op.op_id,
        status="conflict",
        entity_id=op.entity_id,
        version=version,
        server=_dump(out),
    )


def _rejected(op: SyncOpIn, error: SyncError) -> SyncResult:
    return SyncResult(op_id=op.op_id, status="rejected", entity_id=op.entity_id, error=error)


def _aware(ts: datetime) -> datetime:
    return ts if ts.tzinfo is not None else ts.replace(tzinfo=UTC)


def _loses_conflict(op: SyncOpIn, row: Any) -> bool:
    """True when the op must not be applied: a stale ``base_version`` the strategy rejects."""
    if op.base_version == row.version:
        return False
    strategy = CONFLICT_RULES[op.entity]
    if strategy == Strategy.LAST_WRITER_WINS:
        return _aware(op.client_ts) <= _aware(row.updated_at)
    # merge_fields: client-owned fields merge, server-owned ones are dropped anyway.
    return strategy != Strategy.MERGE_FIELDS


def _check_write_path(op: SyncOpIn) -> None:
    if op.entity in _ENTITIES_WITHOUT_WRITE_PATH:
        raise UnsupportedActionError(f"{op.entity} sync writes are not available yet.")


@dataclass(frozen=True)
class OpContext:
    """What the write paths need besides the session: the auth clock's ``now``, settings,
    the auth services (OTP for FA-016) and the blob store (photo bytes for FA-015)."""

    settings: Settings
    now: datetime
    services: AuthServices | None = None
    blobs: BlobStore | None = None
    payments: PaymentServices | None = None  # FA-021 payment ops

    def visit_deps(self) -> tuple[AuthServices, BlobStore]:
        if self.services is None or self.blobs is None:
            raise UnsupportedActionError("Visit sync ops need the auth services and blob store.")
        return self.services, self.blobs


def _from_visit(op: SyncOpIn, applied: visit_sync.Applied) -> SyncResult:
    if applied.conflict:
        return _conflict(op, applied.out, applied.version)
    return _applied(op, applied.out, applied.version)


# --------------------------------------------------------------------------- dispatch
async def _create(session: AsyncSession, actor: User, op: SyncOpIn, ctx: OpContext) -> SyncResult:
    if op.entity == "payment":  # FA-021 officer offline cash / credit capture
        from farmerapp.payments import sync_ops as payment_sync

        paid = await payment_sync.create(
            session,
            actor,
            op.entity_id,
            dict(op.payload),
            services=ctx.payments,
            sms=ctx.services.sms if ctx.services else None,
            whatsapp=ctx.services.whatsapp if ctx.services else None,
            blobs=ctx.blobs,
            now=ctx.now,
        )
        return (_conflict if paid.conflict else _applied)(op, paid.out, paid.out.version)
    _check_write_path(op)
    settings, now = ctx.settings, ctx.now
    if op.entity in visit_sync.ENTITIES:
        services, blobs = ctx.visit_deps()
        applied = await visit_sync.create(
            session,
            actor,
            op.entity,
            op.entity_id,
            dict(op.payload),
            services=services,
            blobs=blobs,
            now=now,
        )
        return _from_visit(op, applied)
    if op.entity == "order":  # FA-020 offline order capture (``farmerapp.orders.sync_ops``)
        placed = await order_sync.create(
            session, actor, op.entity_id, dict(op.payload), today=ctx.now.date()
        )
        if placed.blocked is not None:
            return _rejected(
                op,
                SyncError(
                    code=CreditLimitExceededError.code,
                    status=CreditLimitExceededError.status,
                    detail="The credit sale is beyond the farmer's limit; approval requested.",
                    errors=[decision_extra(placed.blocked)],
                ),
            )
        if placed.out is None:  # pragma: no cover - create returns an order unless blocked
            raise RuntimeError("order sync create returned no order")
        if placed.conflict:
            return _conflict(op, placed.out, placed.out.version)
        return _applied(op, placed.out, placed.out.version)
    payload = {**op.payload, "id": str(op.entity_id)}
    if op.entity == "duty_session":  # FA-010 start
        if await session.get(DutySession, op.entity_id) is not None:
            duty_row = await duty.own_session(session, actor, op.entity_id)
            return _conflict(op, DutySessionOut.from_row(duty_row), duty_row.version)
        duty_out = await duty.start_duty(
            session, actor, DutyStartIn.model_validate(payload), now=now
        )
        return _applied(op, duty_out, duty_out.version)
    if op.entity == "policy_acceptance":  # FA-011 offline first run
        if await session.get(PolicyAcceptance, op.entity_id) is not None:
            acceptance = await session.get_one(PolicyAcceptance, op.entity_id)
            return _conflict(op, PolicyAcceptanceOut.from_row(acceptance), 1)
        accepted = await policies.accept_policy(
            session,
            actor,
            PolicyAcceptIn.model_validate({"accepted_at": op.client_ts, **payload}),
            now=now,
        )
        return _applied(op, accepted, 1)
    if op.entity == "location_batch":  # FA-010 / VV-001 on-duty points only
        batch = await ingest_batch(
            session, actor, LocationBatchIn.model_validate(payload), received_at=now
        )
        return SyncResult(
            op_id=op.op_id, status="applied", entity_id=op.entity_id, server=_dump(batch)
        )
    if op.entity == "farmer":
        existing = await session.get(Farmer, op.entity_id)
        if existing is not None:
            visible = await farmers.visible_farmer(session, actor, op.entity_id)
            return _conflict(op, FarmerOut.from_row(visible), visible.version)
        out = await farmers.create_farmer(
            session, actor, FarmerCreate.model_validate(payload), settings=settings, now=now
        )
        return _applied(op, out, out.version)
    if op.entity == "farm":
        if await session.get(Farm, op.entity_id) is not None:
            farm = await farmers.visible_farm(session, actor, op.entity_id)
            return _conflict(op, await farmers.farm_out(session, farm), farm.version)
        farmer = await farmers.visible_farmer(session, actor, _uuid(payload.get("farmer_id")))
        farm_out = await farmers.add_farm(
            session, actor, farmer, FarmCreate.model_validate(payload)
        )
        return _applied(op, farm_out, farm_out.version)
    if op.entity == "crop_plot":
        if await session.get(CropPlot, op.entity_id) is not None:
            plot = await farmers.visible_crop_plot(session, actor, op.entity_id)
            return _conflict(op, CropPlotOut.from_row(plot), plot.version)
        farm = await farmers.visible_farm(session, actor, _uuid(payload.get("farm_id")))
        plot_out = await farmers.add_crop_plot(
            session, farm, CropPlotCreate.model_validate(payload)
        )
        return _applied(op, plot_out, plot_out.version)
    # consent_record
    if await session.get(ConsentRecord, op.entity_id) is not None:
        record = await session.get_one(ConsentRecord, op.entity_id)
        return _conflict(op, ConsentRecordOut.from_row(record), 1)
    farmer = await farmers.visible_farmer(session, actor, _uuid(payload.get("farmer_id")))
    consent = await farmers.add_consent(
        session, actor, farmer, ConsentIn.model_validate(payload), record_id=op.entity_id
    )
    return _applied(op, consent, 1)


async def _update(session: AsyncSession, actor: User, op: SyncOpIn, ctx: OpContext) -> SyncResult:
    _check_write_path(op)
    if op.entity == "duty_session":  # FA-010 end; server-owned end once auto-ended (VV-007)
        duty_row = await duty.own_session(session, actor, op.entity_id)
        if duty_row.end_at is not None:
            return _conflict(op, DutySessionOut.from_row(duty_row), duty_row.version)
        end_body = DutyEndIn.model_validate(merge_payload("duty_session", duty_row, op.payload))
        duty_out = await duty.end_duty(session, actor, end_body, now=ctx.now, duty=duty_row)
        return _applied(op, duty_out, duty_out.version)
    if op.entity in visit_sync.ENTITIES:
        if op.entity != "visit":
            raise UnsupportedActionError(f"{op.entity} rows are immutable once written.")
        row = await session.get(Visit, op.entity_id)
        payload = merge_payload("visit", row, dict(op.payload)) if row else dict(op.payload)
        applied = await visit_sync.update(
            session, actor, op.entity, op.entity_id, payload, now=ctx.now
        )
        return _from_visit(op, applied)
    if op.entity == "farmer":
        farmer = await farmers.visible_farmer(session, actor, op.entity_id)
        if _loses_conflict(op, farmer):
            return _conflict(op, FarmerOut.from_row(farmer), farmer.version)
        body = FarmerUpdate.model_validate({**op.payload, "version": None})
        out = await farmers.update_farmer(session, actor, farmer, body)
        return _applied(op, out, out.version)
    if op.entity == "farm":
        farm = await farmers.visible_farm(session, actor, op.entity_id)
        if _loses_conflict(op, farm):
            return _conflict(op, await farmers.farm_out(session, farm), farm.version)
        farm_out = await farmers.update_farm(
            session, actor, farm, FarmUpdate.model_validate({**op.payload, "version": None})
        )
        return _applied(op, farm_out, farm_out.version)
    if op.entity == "crop_plot":
        plot = await farmers.visible_crop_plot(session, actor, op.entity_id)
        if _loses_conflict(op, plot):
            return _conflict(op, CropPlotOut.from_row(plot), plot.version)
        plot_out = await farmers.update_crop_plot(
            session, plot, CropPlotUpdate.model_validate({**op.payload, "version": None})
        )
        return _applied(op, plot_out, plot_out.version)
    raise UnsupportedActionError(f"{op.entity} records are append-only: create a new record.")


async def _delete(session: AsyncSession, actor: User, op: SyncOpIn) -> SyncResult:
    _check_write_path(op)
    if op.entity == "farm":
        farm = await farmers.visible_farm(session, actor, op.entity_id)
        if _loses_conflict(op, farm):
            return _conflict(op, await farmers.farm_out(session, farm), farm.version)
        farm_out = await farmers.delete_farm(session, farm)
        return _applied(op, farm_out, farm_out.version)
    if op.entity == "crop_plot":
        plot = await farmers.visible_crop_plot(session, actor, op.entity_id)
        if _loses_conflict(op, plot):
            return _conflict(op, CropPlotOut.from_row(plot), plot.version)
        plot_out = await farmers.delete_crop_plot(session, plot)
        return _applied(op, plot_out, plot_out.version)
    raise UnsupportedActionError(f"{op.entity} cannot be deleted from a device.")


def _uuid(value: Any) -> uuid.UUID:
    try:
        return uuid.UUID(str(value))
    except ValueError as exc:
        raise NotFoundError("Parent entity not found.") from exc


async def _dispatch(session: AsyncSession, actor: User, op: SyncOpIn, ctx: OpContext) -> SyncResult:
    if op.action == "create":
        return await _create(session, actor, op, ctx)
    if op.action == "update":
        return await _update(session, actor, op, ctx)
    return await _delete(session, actor, op)


async def _apply_one(
    session: AsyncSession, actor: User, op: SyncOpIn, ctx: OpContext
) -> SyncResult:
    try:
        async with session.begin_nested():
            return await _dispatch(session, actor, op, ctx)
    except ValidationError as exc:
        errors = [
            {"loc": [str(p) for p in e.get("loc", ())], "msg": e.get("msg"), "type": e.get("type")}
            for e in exc.errors()
        ]
        return _rejected(
            op,
            SyncError(
                code="validation_error",
                status=422,
                detail="Payload validation failed.",
                errors=errors,
            ),
        )
    except ForbiddenError as exc:
        return _rejected(op, SyncError(code=exc.code, status=exc.status, detail=exc.detail))
    except AppError as exc:
        extra_errors: list[dict[str, Any]] | None = (
            list(exc.extra["errors"]) if exc.extra and "errors" in exc.extra else None
        )
        return _rejected(
            op,
            SyncError(code=exc.code, status=exc.status, detail=exc.detail, errors=extra_errors),
        )
    except IntegrityError as exc:
        log.warning("sync_op_integrity_error", op_id=str(op.op_id), entity=op.entity)
        return _rejected(
            op, SyncError(code="integrity_error", status=409, detail=str(exc.orig).splitlines()[0])
        )


async def apply_ops(
    session: AsyncSession,
    actor: User,
    *,
    device_id: str,
    ops: list[SyncOpIn],
    settings: Settings,
    now: datetime | None = None,
    services: AuthServices | None = None,
    blobs: BlobStore | None = None,
    payments: PaymentServices | None = None,
) -> list[SyncResult]:
    """``now`` is the auth clock (phone verification tokens); defaults to the wall clock.
    ``services`` (OTP) and ``blobs`` (photo bytes) are needed by the visit ops, ``payments``
    by the FA-021 payment op."""
    now = now or datetime.now(UTC)
    ctx = OpContext(settings=settings, now=now, services=services, blobs=blobs, payments=payments)
    results: list[SyncResult] = []
    for op in ops:
        stored = (
            await session.execute(
                select(SyncOp).where(SyncOp.tenant_id == actor.tenant_id, SyncOp.op_id == op.op_id)
            )
        ).scalar_one_or_none()
        if stored is not None:
            results.append(SyncResult.model_validate({**stored.result, "status": "duplicate"}))
            continue
        result = await _apply_one(session, actor, op, ctx)
        session.add(
            SyncOp(
                tenant_id=actor.tenant_id,
                op_id=op.op_id,
                device_id=device_id,
                actor_id=actor.id,
                entity=op.entity,
                action=op.action,
                entity_id=op.entity_id,
                result=_dump(result),
            )
        )
        await session.flush()
        results.append(result)
    log.info(
        "sync_ops_applied",
        actor_id=str(actor.id),
        device_id=device_id,
        ops=len(ops),
        applied=sum(r.status == "applied" for r in results),
        rejected=sum(r.status == "rejected" for r in results),
        conflicts=sum(r.status == "conflict" for r in results),
        duplicates=sum(r.status == "duplicate" for r in results),
    )
    return results


# --------------------------------------------------------------------------- changes feed
def _scope(actor: User) -> Any:
    visible = select(Farmer.id).where(*farmer_filters(actor))
    farms = select(Farm.id).where(Farm.farmer_id.in_(visible))
    visits = select(Visit.id).where(*visit_filters(actor))
    officers = select(User.id).where(*officer_filters(actor))
    orders = select(Order.id).where(*order_filters(actor))
    return or_(
        and_(SyncChange.entity == "farmer", SyncChange.entity_id.in_(visible)),
        and_(SyncChange.entity == "farm", SyncChange.entity_id.in_(farms)),
        and_(
            SyncChange.entity == "crop_plot",
            SyncChange.entity_id.in_(select(CropPlot.id).where(CropPlot.farm_id.in_(farms))),
        ),
        and_(
            SyncChange.entity == "consent_record",
            SyncChange.entity_id.in_(
                select(ConsentRecord.id).where(ConsentRecord.subject_id.in_(visible))
            ),
        ),
        and_(SyncChange.entity == "visit", SyncChange.entity_id.in_(visits)),
        and_(
            SyncChange.entity == "visit_photo",
            SyncChange.entity_id.in_(select(VisitPhoto.id).where(VisitPhoto.visit_id.in_(visits))),
        ),
        and_(
            SyncChange.entity == "visit_confirmation",
            SyncChange.entity_id.in_(
                select(VisitConfirmation.id).where(VisitConfirmation.visit_id.in_(visits))
            ),
        ),
        and_(
            SyncChange.entity == "duty_session",
            SyncChange.entity_id.in_(select(DutySession.id).where(*duty_session_filters(actor))),
        ),
        and_(
            SyncChange.entity == "policy_acceptance",
            SyncChange.entity_id.in_(
                select(PolicyAcceptance.id).where(PolicyAcceptance.user_id.in_(officers))
            ),
        ),
        # M3 money entities: the same scope as their REST reads.
        and_(SyncChange.entity == "order", SyncChange.entity_id.in_(orders)),
        and_(
            SyncChange.entity == "order_line",
            SyncChange.entity_id.in_(select(OrderLine.id).where(OrderLine.order_id.in_(orders))),
        ),
        and_(
            SyncChange.entity == "payment",
            SyncChange.entity_id.in_(select(Payment.id).where(*payment_filters(actor))),
        ),
        and_(
            SyncChange.entity == "khata_entry",
            SyncChange.entity_id.in_(select(KhataEntry.id).where(*khata_entry_filters(actor))),
        ),
    )


async def _current_state(
    session: AsyncSession, changes: list[SyncChange]
) -> dict[tuple[str, uuid.UUID], BaseModel]:
    ids: dict[str, list[uuid.UUID]] = {}
    for change in changes:
        ids.setdefault(change.entity, []).append(change.entity_id)
    state: dict[tuple[str, uuid.UUID], BaseModel] = {}
    if ids.get("farmer"):
        for row in (
            await session.execute(select(Farmer).where(Farmer.id.in_(ids["farmer"])))
        ).scalars():
            state[("farmer", row.id)] = FarmerOut.from_row(row)
    if ids.get("farm"):
        for farm in (await session.execute(select(Farm).where(Farm.id.in_(ids["farm"])))).scalars():
            state[("farm", farm.id)] = FarmOut.from_row(farm)
    if ids.get("crop_plot"):
        plots = await session.execute(select(CropPlot).where(CropPlot.id.in_(ids["crop_plot"])))
        for plot in plots.scalars():
            state[("crop_plot", plot.id)] = CropPlotOut.from_row(plot)
    if ids.get("consent_record"):
        records = await session.execute(
            select(ConsentRecord).where(ConsentRecord.id.in_(ids["consent_record"]))
        )
        for record in records.scalars():
            state[("consent_record", record.id)] = ConsentRecordOut.from_row(record)
    if ids.get("visit"):
        visits = await session.execute(select(Visit).where(Visit.id.in_(ids["visit"])))
        for visit in visits.scalars():
            state[("visit", visit.id)] = VisitOut.from_row(visit)
    if ids.get("visit_photo"):
        photos = await session.execute(
            select(VisitPhoto).where(VisitPhoto.id.in_(ids["visit_photo"]))
        )
        for photo in photos.scalars():
            state[("visit_photo", photo.id)] = VisitPhotoOut.from_row(photo)
    if ids.get("visit_confirmation"):
        confirmations = await session.execute(
            select(VisitConfirmation).where(VisitConfirmation.id.in_(ids["visit_confirmation"]))
        )
        for confirmation in confirmations.scalars():
            state[("visit_confirmation", confirmation.id)] = VisitConfirmationOut.from_row(
                confirmation
            )
    if ids.get("duty_session"):
        sessions = await session.execute(
            select(DutySession).where(DutySession.id.in_(ids["duty_session"]))
        )
        for duty in sessions.scalars():
            state[("duty_session", duty.id)] = DutySessionOut.from_row(duty)
    if ids.get("policy_acceptance"):
        rows = await session.execute(
            select(PolicyAcceptance).where(PolicyAcceptance.id.in_(ids["policy_acceptance"]))
        )
        for acceptance in rows.scalars():
            state[("policy_acceptance", acceptance.id)] = PolicyAcceptanceOut.from_row(acceptance)
    money: tuple[tuple[str, Any, Callable[[Any], BaseModel]], ...] = (
        ("order", Order, OrderOut.model_validate),
        ("order_line", OrderLine, OrderLineOut.model_validate),
        ("payment", Payment, PaymentOut.model_validate),
        ("khata_entry", KhataEntry, KhataEntryOut.from_row),
    )
    for entity, model, to_out in money:
        if ids.get(entity):
            for row in (
                await session.execute(select(model).where(model.id.in_(ids[entity])))
            ).scalars():
                state[(entity, row.id)] = to_out(row)
    return state


async def changes_since(
    session: AsyncSession, actor: User, cursor: str | None
) -> tuple[list[SyncChangeOut], str, bool]:
    since = decode_cursor(cursor)
    rows = (
        (
            await session.execute(
                select(SyncChange)
                .where(
                    SyncChange.tenant_id == actor.tenant_id, SyncChange.seq > since, _scope(actor)
                )
                .order_by(SyncChange.seq)
                .limit(MAX_CHANGES + 1)
            )
        )
        .scalars()
        .all()
    )
    has_more = len(rows) > MAX_CHANGES
    window = list(rows[:MAX_CHANGES])
    last_seq = window[-1].seq if window else since
    latest: dict[tuple[str, uuid.UUID], SyncChange] = {}
    for change in window:
        latest[(change.entity, change.entity_id)] = change  # ascending seq: last wins
    state = await _current_state(session, list(latest.values()))
    out: list[SyncChangeOut] = []
    for key, change in latest.items():
        current = state.get(key)
        deleted_at = getattr(current, "deleted_at", None) if current is not None else None
        if current is None or change.action == "delete" or deleted_at is not None:
            data: dict[str, Any] = {
                "id": str(change.entity_id),
                "deleted_at": deleted_at.isoformat()
                if deleted_at
                else change.changed_at.isoformat(),
            }
            action = "delete"
        else:
            data = _dump(current)
            action = change.action
        out.append(
            SyncChangeOut(
                entity=change.entity,
                action=action,
                entity_id=change.entity_id,
                version=change.version,
                data=data,
                seq=change.seq,
            )
        )
    out.sort(key=lambda c: c.seq)
    return out, encode_cursor(last_seq), has_more


__all__ = [
    "CONFLICT_RULES",
    "MAX_CHANGES",
    "SERVER_OWNED_FIELDS",
    "OpContext",
    "Strategy",
    "apply_ops",
    "changes_since",
    "decode_cursor",
    "encode_cursor",
    "merge_payload",
    "server_owned_fields",
]
