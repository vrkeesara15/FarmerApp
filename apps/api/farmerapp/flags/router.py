"""``/v1/flags`` — the validation agent inbox backend (WC-010, VA-002, VA-003, VA-005).

* ``GET /v1/flags`` — newest first, cursor pagination; filters ``status`` / ``severity``
  (repeatable), ``rule_id``, ``subject_type``, ``owner=me`` (owner or watcher), ``overdue``;
  ``counts`` groups the filtered set by severity and by rule (C70 inbox).
* ``GET /v1/flags/{id}`` — the flag with its evidence bundle (each record with a short
  summary, photos with signed read URLs), history, comments and allowed transitions (C71).
* ``POST /v1/flags/{id}/transition`` — SPEC 6.1 state machine, 409 ``invalid_transition``.
* ``POST /v1/flags/{id}/comments`` — review thread; the subject's own comment is marked as
  their explanation (VA-005).
* ``POST /v1/flags/{id}/assign`` — hand the flag to another reviewer.

Scope (``flags.service.flag_filters``): owner / director / auditor / tenant admin see the
tenant; a cluster head their cluster's flags and any they own or watch; a store manager the
farmer-data flags of their store and any they own; a field officer only flags about
themselves (read and explain, never transition). Anything else is a 404.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Annotated, Any

from fastapi import APIRouter, Query, Request
from sqlalchemy import ColumnElement, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.farmers.models import Farm, Farmer
from farmerapp.flags import service
from farmerapp.flags.models import (
    TRANSITIONS,
    UNRESOLVED,
    Flag,
    FlagComment,
    FlagEvent,
    FlagStatus,
)
from farmerapp.flags.schemas import (
    AssignIn,
    CommentIn,
    EvidenceOut,
    EvidencePhoto,
    EvidenceRecord,
    FlagCommentOut,
    FlagCounts,
    FlagDetailOut,
    FlagEventOut,
    FlagOut,
    FlagPage,
    TransitionIn,
)
from farmerapp.payments.models import Payment
from farmerapp.rules.schema import Severity, Subject
from farmerapp.tenants.models import Store
from farmerapp.uploads.blobstore import BlobStore
from farmerapp.uploads.router import get_blob_store
from farmerapp.visits.models import Visit

REVIEW_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.AUDITOR,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.TENANT_ADMIN,
)
#: Field officers read flags about themselves (VA-005); accountants the OPS-008 finance
#: tickets they watch.
READ_ROLES = (*REVIEW_ROLES, Role.FIELD_OFFICER, Role.ACCOUNTANT)

router = APIRouter(prefix="/flags", tags=["flags"])


# --------------------------------------------------------------------------- evidence
async def _summary(session: AsyncSession, kind: str, record_id: uuid.UUID) -> dict[str, Any]:
    match kind:
        case "farmer":
            farmer = await session.get(Farmer, record_id)
            if farmer is None:
                return {}
            return {
                "name": farmer.name,
                "phone_last4": farmer.phone_last4,
                "village_id": str(farmer.village_id),
                "registered_by": str(farmer.registered_by) if farmer.registered_by else None,
                "phone_verified": farmer.phone_verified,
            }
        case "farm":
            farm = await session.get(Farm, record_id)
            if farm is None:
                return {}
            return {
                "name": farm.name,
                "farmer_id": str(farm.farmer_id),
                "area_acres": float(farm.area_acres),
                "area_acres_computed": (
                    float(farm.area_acres_computed)
                    if farm.area_acres_computed is not None
                    else None
                ),
            }
        case "user":
            user = await session.get(User, record_id)
            return {"name": user.name, "role": user.role} if user is not None else {}
        case "visit":
            visit = await session.get(Visit, record_id)
            if visit is None:
                return {}
            return {
                "officer_id": str(visit.officer_id),
                "farmer_id": str(visit.farmer_id),
                "checkin_at": visit.checkin_at.isoformat(),
                "status": visit.status,
            }
        case "store":
            store = await session.get(Store, record_id)
            return {"code": store.code, "name": store.name} if store is not None else {}
        case "payment":
            payment = await session.get(Payment, record_id)
            if payment is None:
                return {}
            return {
                "mode": payment.mode,
                "status": payment.status,
                "amount_paise": payment.amount_paise,
                "store_id": str(payment.store_id),
                "provider_ref": payment.provider_ref,
            }
    return {}


async def _evidence(
    session: AsyncSession,
    actor: User,
    flag: Flag,
    *,
    blobs: BlobStore,
    now: datetime,
    ttl_s: int,
) -> EvidenceOut:
    raw = flag.evidence if isinstance(flag.evidence, dict) else {}
    summarise = service.is_reviewer(actor)  # the subject sees ids, not other people's data
    records: list[EvidenceRecord] = []
    for item in service.evidence_records(flag):
        kind, rid = str(item.get("type", "")), str(item.get("id", ""))
        summary: dict[str, Any] = {}
        if summarise:
            try:
                summary = await _summary(session, kind, uuid.UUID(rid))
            except ValueError:
                summary = {}
        records.append(EvidenceRecord(type=kind, id=rid, summary=summary))
    photos: list[EvidencePhoto] = []
    for uri in raw.get("photos") or []:
        try:
            signed = await blobs.signed_url(str(uri), ttl=timedelta(seconds=ttl_s), now=now)
        except ValueError:
            photos.append(EvidencePhoto(blob_uri=str(uri)))
            continue
        photos.append(
            EvidencePhoto(
                blob_uri=str(uri), signed_url=signed.url, signed_url_expires_at=signed.expires_at
            )
        )
    geo = raw.get("map") or {}
    return EvidenceOut(
        records=records,
        map={"points": list(geo.get("points") or []), "polygons": list(geo.get("polygons") or [])},
        photos=photos,
        metrics=dict(raw.get("metrics") or {}),
    )


async def _detail(
    request: Request, services: Services, session: AsyncSession, actor: User, flag: Flag
) -> FlagDetailOut:
    now = services.clock.now()
    await session.refresh(flag)
    events = (
        await session.execute(
            select(FlagEvent)
            .where(FlagEvent.flag_id == flag.id)
            .order_by(FlagEvent.created_at, FlagEvent.id)
        )
    ).scalars()
    comments = (
        await session.execute(
            select(FlagComment)
            .where(FlagComment.flag_id == flag.id, FlagComment.deleted_at.is_(None))
            .order_by(FlagComment.created_at, FlagComment.id)
        )
    ).scalars()
    base = FlagOut.from_row(flag, now=now)
    allowed = sorted(TRANSITIONS[FlagStatus(flag.status)]) if service.is_reviewer(actor) else []
    return FlagDetailOut(
        **base.model_dump(),
        evidence=await _evidence(
            session,
            actor,
            flag,
            blobs=get_blob_store(request),
            now=now,
            ttl_s=services.settings.signed_url_ttl_seconds,
        ),
        events=[FlagEventOut.from_row(e) for e in events],
        comments=[FlagCommentOut.from_row(c) for c in comments],
        allowed_transitions=allowed,
    )


# --------------------------------------------------------------------------- reads
@router.get(
    "",
    operation_id="listFlags",
    summary="Validation flags visible to the caller, newest first, with counts (WC-010)",
    response_model=FlagPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_flags(
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    services: Services,
    page: Page,
    status: Annotated[list[FlagStatus] | None, Query()] = None,
    severity: Annotated[list[Severity] | None, Query()] = None,
    rule_id: Annotated[str | None, Query(max_length=16)] = None,
    subject_type: Annotated[Subject | None, Query()] = None,
    owner: Annotated[
        str | None, Query(pattern="^me$", description="`me`: owned or watched")
    ] = None,
    overdue: Annotated[bool | None, Query(description="Unresolved and past the SLA")] = None,
) -> FlagPage:
    now = services.clock.now()
    filters: list[ColumnElement[bool]] = [Flag.deleted_at.is_(None), *service.flag_filters(actor)]
    if status:
        filters.append(Flag.status.in_([s.value for s in status]))
    if severity:
        filters.append(Flag.severity.in_([s.value for s in severity]))
    if rule_id:
        filters.append(Flag.rule_id == rule_id)
    if subject_type is not None:
        filters.append(Flag.subject_type == subject_type.value)
    if owner == "me":
        filters.append(or_(Flag.owner_id == actor.id, service.watched_by(actor.id)))
    if overdue is not None:
        late = Flag.status.in_([s.value for s in UNRESOLVED]) & (Flag.sla_due_at < now)
        filters.append(late if overdue else ~late)
    stmt = select(Flag).where(*filters)
    keyset = page.before(Flag.created_at, Flag.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (
            await session.execute(
                stmt.order_by(Flag.created_at.desc(), Flag.id.desc()).limit(page.fetch)
            )
        )
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    by_severity = {
        str(k): int(v)
        for k, v in (
            await session.execute(
                select(Flag.severity, func.count()).where(*filters).group_by(Flag.severity)
            )
        ).tuples()
    }
    by_rule = {
        str(k): int(v)
        for k, v in (
            await session.execute(
                select(Flag.rule_id, func.count()).where(*filters).group_by(Flag.rule_id)
            )
        ).tuples()
    }
    return FlagPage(
        items=[FlagOut.from_row(f, now=now) for f in items],
        next_cursor=cursor,
        counts=FlagCounts(
            total=sum(by_severity.values()), by_severity=by_severity, by_rule=by_rule
        ),
    )


@router.get(
    "/{id}",
    operation_id="getFlag",
    summary="A flag with its evidence bundle, history and comments (WC-010, VA-002)",
    response_model=FlagDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_flag(
    id: uuid.UUID,
    request: Request,
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    services: Services,
) -> FlagDetailOut:
    flag = await service.visible_flag(session, actor, id)
    return await _detail(request, services, session, actor, flag)


# --------------------------------------------------------------------------- writes
@router.post(
    "/{id}/transition",
    operation_id="transitionFlag",
    summary="Move a flag through the SPEC 6.1 review states",
    response_model=FlagDetailOut,
    responses=problem_responses((404, "not_found"), (409, "invalid_transition")),
)
async def transition_flag(
    id: uuid.UUID,
    body: TransitionIn,
    request: Request,
    actor: Annotated[User, require_roles(*REVIEW_ROLES)],
    session: DbSession,
    services: Services,
) -> FlagDetailOut:
    flag = await service.visible_flag(session, actor, id, for_update=True)
    await service.transition(session, actor, flag, body.to, body.note, now=services.clock.now())
    return await _detail(request, services, session, actor, flag)


@router.post(
    "/{id}/comments",
    operation_id="commentOnFlag",
    summary="Add a review comment, or the subject's explanation (VA-005)",
    status_code=201,
    response_model=FlagCommentOut,
    responses=problem_responses((404, "not_found"), (409, "flag_resolved")),
)
async def comment_on_flag(
    id: uuid.UUID,
    body: CommentIn,
    actor: Annotated[User, require_roles(*READ_ROLES)],
    session: DbSession,
    services: Services,
) -> FlagCommentOut:
    flag = await service.visible_flag(session, actor, id)  # an officer only sees own flags
    comment = await service.add_comment(session, actor, flag, body.body, now=services.clock.now())
    return FlagCommentOut.from_row(comment)


@router.post(
    "/{id}/assign",
    operation_id="assignFlag",
    summary="Hand a flag to another reviewer (VA-003)",
    response_model=FlagDetailOut,
    responses=problem_responses(
        (404, "not_found"), (409, "flag_resolved"), (422, "assignee_invalid")
    ),
)
async def assign_flag(
    id: uuid.UUID,
    body: AssignIn,
    request: Request,
    actor: Annotated[User, require_roles(*REVIEW_ROLES)],
    session: DbSession,
    services: Services,
) -> FlagDetailOut:
    flag = await service.visible_flag(session, actor, id, for_update=True)
    await service.assign(session, actor, flag, body.user_id, body.note, now=services.clock.now())
    return await _detail(request, services, session, actor, flag)


__all__ = ["READ_ROLES", "REVIEW_ROLES", "router"]
