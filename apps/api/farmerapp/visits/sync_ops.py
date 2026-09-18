"""``POST /v1/sync`` ops of the visit flow (FA-025 offline-capable writes).

The device queues exactly the REST bodies (``farmerapp.visits.schemas``); the sync service
calls these with the op's payload (server-owned fields already dropped by ``merge_payload``)
and wraps the outcome into a ``SyncResult``:

======================== ========== =======================================================
entity                   action     meaning
======================== ========== =======================================================
``visit``                create     FA-014 check-in (geofence evaluated when the batch
                                    arrives; ``outside_geofence`` rejects the op unless an
                                    ``override_note`` is in the payload)
``visit``                update     FA-015 capture (``notes``, ``crop_stage``, ``purpose``)
                                    and / or FA-017 check-out (``checkout_at``,
                                    ``checkout_point``) — last writer wins on the notes
``visit_photo``          create     FA-015 photo (``visit_id`` + the photo body; the blob
                                    must already be uploaded)
``visit_confirmation``   create     FA-016: an officer's ``{visit_id, channel: sms_otp,
                                    code}`` (the OTP the farmer typed on the officer's
                                    phone — verified when the batch arrives, so it must still
                                    be within the OTP validity) or a farmer's ``{visit_id,
                                    channel: qr | app_push, token, rating?, reason?}``
                                    (a QR scanned offline, posted when back online)
======================== ========== =======================================================

Requesting a confirmation (sending the OTP, issuing a QR token) is online-only by nature and
has no sync op: the officer app calls ``POST /v1/visits/{id}/confirm/request`` when it has
connectivity. A ``visit_confirmation`` op completes the *request row* the server created
then, so the result's ``server.id`` is that row's id (the op's ``entity_id`` is only the
idempotency handle; a replay of a known row id answers ``conflict`` with the server state).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import TYPE_CHECKING, Any

from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError
from farmerapp.auth.models import User, UserRole
from farmerapp.farmers.errors import UnsupportedActionError
from farmerapp.uploads.blobstore import BlobStore
from farmerapp.visits import service
from farmerapp.visits.errors import ConfirmationChannelInvalidError
from farmerapp.visits.models import ConfirmationChannel, Visit, VisitConfirmation, VisitPhoto
from farmerapp.visits.schemas import (
    FarmerConfirm,
    VisitCapture,
    VisitCheckIn,
    VisitCheckOut,
    VisitConfirmationOut,
    VisitDetailOut,
    VisitOut,
    VisitPhotoCreate,
    VisitPhotoOut,
)

if TYPE_CHECKING:
    from farmerapp.auth.deps import AuthServices

ENTITIES: frozenset[str] = frozenset({"visit", "visit_photo", "visit_confirmation"})
_CHECKOUT_KEYS = ("checkout_at", "checkout_point")


@dataclass(frozen=True)
class Applied:
    out: BaseModel
    version: int
    conflict: bool = False  # the entity already existed: the device adopts the server state


def _uuid(value: Any, what: str) -> uuid.UUID:
    try:
        return uuid.UUID(str(value))
    except ValueError as exc:
        raise NotFoundError(f"{what} not found.") from exc


async def _visit_out(session: AsyncSession, visit: Visit) -> VisitDetailOut:
    from farmerapp.visits.router import visit_detail  # detail without signed URLs

    return await visit_detail(session, visit)


async def create(
    session: AsyncSession,
    actor: User,
    entity: str,
    entity_id: uuid.UUID,
    payload: dict[str, Any],
    *,
    services: AuthServices,
    blobs: BlobStore,
    now: datetime,
) -> Applied:
    if entity == "visit":
        existing = await session.get(Visit, entity_id)
        if existing is not None:
            visible = await service.visible_visit(session, actor, entity_id)
            return Applied(await _visit_out(session, visible), visible.version, conflict=True)
        body = VisitCheckIn.model_validate({**payload, "id": str(entity_id)})
        visit = await service.check_in(session, actor, body, now=now)
        return Applied(await _visit_out(session, visit), visit.version)
    if entity == "visit_photo":
        existing_photo = await session.get(VisitPhoto, entity_id)
        if existing_photo is not None:
            await service.own_visit(session, actor, existing_photo.visit_id)
            return Applied(
                VisitPhotoOut.from_row(existing_photo), existing_photo.version, conflict=True
            )
        photo_body = VisitPhotoCreate.model_validate({**payload, "id": str(entity_id)})
        visit = await service.own_visit(session, actor, _uuid(payload.get("visit_id"), "Visit"))
        photo = await service.add_photo(session, actor, visit, photo_body, blobs=blobs, now=now)
        return Applied(VisitPhotoOut.from_row(photo), photo.version)
    if entity == "visit_confirmation":
        return await _confirm(session, actor, entity_id, payload, services=services, now=now)
    raise UnsupportedActionError(f"{entity} cannot be created from a device.")


async def _confirm(
    session: AsyncSession,
    actor: User,
    entity_id: uuid.UUID,
    payload: dict[str, Any],
    *,
    services: AuthServices,
    now: datetime,
) -> Applied:
    existing = await session.get(VisitConfirmation, entity_id)
    if existing is not None:
        await service.visible_visit(session, actor, existing.visit_id)
        return Applied(VisitConfirmationOut.from_row(existing), existing.version, conflict=True)
    channel = str(payload.get("channel") or "")
    visit_id = _uuid(payload.get("visit_id"), "Visit")
    if UserRole(actor.role) == UserRole.FARMER:
        if channel not in (ConfirmationChannel.APP_PUSH, ConfirmationChannel.QR):
            raise ConfirmationChannelInvalidError("A farmer confirms with a push or QR token.")
        visit = await service.visible_visit(session, actor, visit_id)
        body = FarmerConfirm.model_validate(
            {k: payload.get(k) for k in ("token", "rating", "reason") if payload.get(k) is not None}
        )
        row = await service.farmer_confirm(
            session, actor, visit, body, settings=services.settings, now=now
        )
        return Applied(VisitConfirmationOut.from_row(row), row.version)
    if channel != ConfirmationChannel.SMS_OTP:
        raise ConfirmationChannelInvalidError(
            "Push and QR confirmations are completed by the farmer's app."
        )
    code = str(payload.get("code") or "")
    if not code:
        raise ConfirmationChannelInvalidError("An SMS confirmation needs the code.")
    visit = await service.own_visit(session, actor, visit_id)
    row = await service.confirm_with_otp(session, actor, visit, code, services=services)
    return Applied(VisitConfirmationOut.from_row(row), row.version)


async def update(
    session: AsyncSession,
    actor: User,
    entity: str,
    entity_id: uuid.UUID,
    payload: dict[str, Any],
    *,
    now: datetime,
) -> Applied:
    if entity != "visit":
        raise UnsupportedActionError(f"{entity} rows are immutable once written.")
    visit = await service.own_visit(session, actor, entity_id)
    capture = {k: v for k, v in payload.items() if k in VisitCapture.model_fields}
    if capture:
        await service.capture(session, visit, VisitCapture.model_validate(capture))
    if payload.get("checkout_at") is not None:
        checkout = VisitCheckOut.model_validate({k: payload.get(k) for k in _CHECKOUT_KEYS})
        await service.check_out(session, visit, checkout, now=now)
    return Applied(VisitOut.from_row(visit), visit.version)


__all__ = ["ENTITIES", "Applied", "create", "update"]
