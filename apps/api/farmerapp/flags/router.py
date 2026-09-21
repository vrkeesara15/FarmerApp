"""``/v1/flags`` — the validation agent inbox backend (WC-010, VA-002, VA-003, VA-005).

* ``GET /v1/flags`` — newest first, cursor pagination; filters ``status`` / ``severity``
  (repeatable), ``rule_id``, ``subject_type``, ``owner=me`` (owner or watcher), ``overdue``;
  ``counts`` groups the filtered set by severity and by rule (C70 inbox).
* ``GET /v1/flags/summary`` — AN-009 data quality over the flags raised in the window:
  volume by rule and subject, median / p90 resolution time, repeat subjects and the VA-006
  precision per rule. Registered before ``/{id}`` so ``summary`` is not read as a flag id.
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

from fastapi import APIRouter, Path, Query, Request
from sqlalchemy import ColumnElement, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.auth.stepup import STEP_UP_OPENAPI, StepUp
from farmerapp.farmers.models import Farm, Farmer
from farmerapp.flags import service
from farmerapp.flags.models import (
    LABELS,
    RESOLVED,
    TRANSITIONS,
    UNRESOLVED,
    Flag,
    FlagComment,
    FlagEvent,
    FlagStatus,
    FlagSummary,
)
from farmerapp.flags.precision import (
    PRECISION_FLOOR,
    WINDOW_WEEKS,
    RuleNotDisabledError,
    enable_rule,
    rule_quality,
)
from farmerapp.flags.review_agent import SUMMARY_LABEL_KEY
from farmerapp.flags.schemas import (
    AssignIn,
    AutomatedSummaryOut,
    CommentIn,
    EvidenceOut,
    EvidencePhoto,
    EvidenceRecord,
    ExplanationIn,
    FlagCommentOut,
    FlagCounts,
    FlagDetailOut,
    FlagEventOut,
    FlagOut,
    FlagPage,
    FlagSummaryOut,
    RuleEnableIn,
    RuleOverrideOut,
    RulePrecisionOut,
    RuleQualityList,
    RuleQualityOut,
    SubjectFlagDetailOut,
    SubjectFlagOut,
    SubjectFlagPage,
    SubjectOutcome,
    SubjectState,
    TransitionIn,
)
from farmerapp.flags.summary import DEFAULT_DAYS as DEFAULT_SUMMARY_DAYS
from farmerapp.flags.summary import flag_summary
from farmerapp.payments.models import Payment
from farmerapp.rules.loader import get_rule_set
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
#: VA-005: any staff member can be the subject of an employee flag.
SUBJECT_ROLES = tuple(r for r in Role if r != Role.FARMER)
#: VA-006: who reads rule quality, and who re-enables an auto-disabled rule (step-up).
RULE_READ_ROLES = (Role.OWNER, Role.DIRECTOR, Role.AUDITOR, Role.TENANT_ADMIN)
RULE_ADMIN_ROLES = (Role.OWNER, Role.TENANT_ADMIN)

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
    summarise: bool | None = None,
) -> EvidenceOut:
    raw = flag.evidence if isinstance(flag.evidence, dict) else {}
    if summarise is None:  # the subject sees ids, not other people's data
        summarise = service.is_reviewer(actor) and not service.is_subject(actor, flag)
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
    reviewer = service.is_reviewer(actor) and not service.is_subject(actor, flag)
    allowed = sorted(TRANSITIONS[FlagStatus(flag.status)]) if reviewer else []
    summary = None
    if reviewer:  # VA-004: the review agent's summary, for reviewers only
        row = (
            await session.execute(select(FlagSummary).where(FlagSummary.flag_id == flag.id))
        ).scalar_one_or_none()
        if row is not None:
            summary = AutomatedSummaryOut.from_row(row, label_key=SUMMARY_LABEL_KEY)
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
        automated_summary=summary,
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


# --------------------------------------------------------------------------- AN-009
@router.get(
    "/summary",
    operation_id="getFlagSummary",
    summary="AN-009 data quality: volume by rule, resolution time, repeat subjects, precision",
    response_model=FlagSummaryOut,
)
async def flag_summary_route(
    actor: Annotated[User, require_roles(*REVIEW_ROLES)],
    session: DbSession,
    services: Services,
    days: Annotated[int, Query(ge=1, le=365, description="IST days back (default 90).")] = (
        DEFAULT_SUMMARY_DAYS
    ),
) -> FlagSummaryOut:
    return await flag_summary(session, actor, now=services.clock.now(), days=days)


# --------------------------------------------------------------------------- VA-005
def _state(flag: Flag) -> SubjectState:
    status = FlagStatus(flag.status)
    if status in RESOLVED:
        return "resolved"
    return "open" if status == FlagStatus.OPEN else "in_review"  # escalations stay internal


async def _subject_view(
    session: AsyncSession, actor: User, flags: list[Flag]
) -> list[SubjectFlagOut]:
    ids = [f.id for f in flags]
    own: dict[uuid.UUID, list[FlagComment]] = {}
    if ids:
        rows = await session.execute(
            select(FlagComment)
            .where(
                FlagComment.flag_id.in_(ids),
                FlagComment.author_id == actor.id,
                FlagComment.deleted_at.is_(None),
            )
            .order_by(FlagComment.created_at, FlagComment.id)
        )
        for comment in rows.scalars():
            own.setdefault(comment.flag_id, []).append(comment)
    rules = get_rule_set().rules
    out: list[SubjectFlagOut] = []
    for flag in flags:
        status = FlagStatus(flag.status)
        label = LABELS.get(status)
        outcome = None
        if status in RESOLVED and flag.resolved_at is not None:
            outcome = SubjectOutcome(
                status=status,
                label=label.value if label else None,
                note=flag.resolution_note,
                resolved_at=flag.resolved_at,
            )
        out.append(
            SubjectFlagOut(
                id=flag.id,
                rule_id=flag.rule_id,
                rule_title=rules[flag.rule_id].title if flag.rule_id in rules else None,
                severity=flag.severity,
                title=flag.title,
                state=_state(flag),
                created_at=flag.created_at,
                can_explain=outcome is None,
                outcome=outcome,
                explanations=[FlagCommentOut.from_row(c) for c in own.get(flag.id, [])],
            )
        )
    return out


@router.get(
    "/mine",
    operation_id="listMyFlags",
    summary="Flags about the caller: outcome once resolved, explanations while open (VA-005)",
    response_model=SubjectFlagPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_my_flags(
    actor: Annotated[User, require_roles(*SUBJECT_ROLES)],
    session: DbSession,
    page: Page,
    state: Annotated[
        str | None, Query(pattern="^(open|resolved)$", description="open: not yet resolved")
    ] = None,
) -> SubjectFlagPage:
    filters: list[ColumnElement[bool]] = service.about_me(actor)
    if state == "open":
        filters.append(Flag.status.in_([s.value for s in UNRESOLVED]))
    elif state == "resolved":
        filters.append(Flag.status.in_([s.value for s in RESOLVED]))
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
    return SubjectFlagPage(
        items=await _subject_view(session, actor, list(items)), next_cursor=cursor
    )


@router.get(
    "/mine/{id}",
    operation_id="getMyFlag",
    summary="A flag about the caller with its evidence (ids and metrics only; VA-005)",
    response_model=SubjectFlagDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_my_flag(
    id: uuid.UUID,
    request: Request,
    actor: Annotated[User, require_roles(*SUBJECT_ROLES)],
    session: DbSession,
    services: Services,
) -> SubjectFlagDetailOut:
    flag = await service.own_flag(session, actor, id)
    (view,) = await _subject_view(session, actor, [flag])
    evidence = await _evidence(
        session,
        actor,
        flag,
        blobs=get_blob_store(request),
        now=services.clock.now(),
        ttl_s=services.settings.signed_url_ttl_seconds,
        summarise=False,
    )
    return SubjectFlagDetailOut(**view.model_dump(), evidence=evidence)


@router.post(
    "/mine/{id}/explanations",
    operation_id="explainMyFlag",
    summary="Add the caller's explanation to an open flag about them (VA-005)",
    status_code=201,
    response_model=FlagCommentOut,
    responses=problem_responses((404, "not_found"), (409, "flag_resolved")),
)
async def explain_my_flag(
    id: uuid.UUID,
    body: ExplanationIn,
    actor: Annotated[User, require_roles(*SUBJECT_ROLES)],
    session: DbSession,
    services: Services,
) -> FlagCommentOut:
    flag = await service.own_flag(session, actor, id)
    comment = await service.add_comment(session, actor, flag, body.body, now=services.clock.now())
    return FlagCommentOut.from_row(comment)


# --------------------------------------------------------------------------- VA-006
@router.get(
    "/rules",
    operation_id="listRuleQuality",
    summary="Every validation rule with its precision and tenant state (VA-006)",
    response_model=RuleQualityList,
)
async def list_rule_quality(
    actor: Annotated[User, require_roles(*RULE_READ_ROLES)],
    session: DbSession,
    services: Services,
) -> RuleQualityList:
    rows = await rule_quality(session, actor.tenant_id, now=services.clock.now())
    return RuleQualityList(
        items=[
            RuleQualityOut(
                rule_id=r.rule_id,
                version=r.version,
                title=r.title,
                enabled=r.enabled,
                disabled_reason=r.disabled_reason,
                week=RulePrecisionOut(**r.week.as_json()),
                four_weeks=RulePrecisionOut(**r.four_weeks.as_json()),
                raised_this_week=r.raised_this_week,
                open_now=r.open_now,
            )
            for r in rows
        ],
        precision_floor=PRECISION_FLOOR,
        window_weeks=WINDOW_WEEKS,
    )


@router.post(
    "/rules/{rule_id}/enable",
    operation_id="enableRule",
    summary="Re-enable a rule the tenant auto-disabled (step-up required; audited; VA-006)",
    response_model=RuleOverrideOut,
    openapi_extra=STEP_UP_OPENAPI,
    responses=problem_responses(
        (401, "step_up_required"), (404, "not_found"), (409, "rule_not_disabled")
    ),
)
async def enable_rule_route(
    rule_id: Annotated[str, Path(pattern=r"^VA-[FE][0-9]{2}$")],
    body: RuleEnableIn,
    actor: Annotated[User, require_roles(*RULE_ADMIN_ROLES)],
    _step_up: StepUp,
    session: DbSession,
    services: Services,
) -> RuleOverrideOut:
    row = await enable_rule(session, actor, rule_id, body.reason, now=services.clock.now())
    return RuleOverrideOut.model_validate(row)


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


__all__ = [
    "READ_ROLES",
    "REVIEW_ROLES",
    "RULE_ADMIN_ROLES",
    "RULE_READ_ROLES",
    "SUBJECT_ROLES",
    "RuleNotDisabledError",
    "router",
]
