"""M7 field P1 sync entities (FA-025 offline use of FA-007 / VV-008 / FA-023 / FA-018 /
FA-026 / FA-027): which ops a device may send, how they are applied (through the same
service functions the REST endpoints call), who receives each entity in the changes feed and
how its current state is rendered.

================================ ================== ==========================================
entity                           ops                feed (who receives it)
================================ ================== ==========================================
``notification``                 update (read_at)   the user it is addressed to (inbox)
``track_gap``                    create / update    the officer (their gap reasons)
                                 (reason, note)
``beat_plan``                    update (items)     the officer (their plans)
``travel_claim``                 create             the officer; cluster head / tenant roles
                                                    per the field-staff scope
``demo_plot``                    create / update    the demo's officer, managers in scope,
                                 (status / yield)   agronomists
``demo_observation``             create             same as its demo plot
``farmer_meeting``               create / update    the officer, managers in scope
                                 (status closed)
``meeting_attendance``           create             same as its meeting
================================ ================== ==========================================

Conflict rules: notifications, gap reasons, beat plans, demo plots and meetings are
``last_writer_wins`` (the device's newer edit applies; an older one gets the server state);
claims, observations and attendance are immutable once written (``server_wins``: a replayed
id returns the stored row as a ``conflict``).
"""

from __future__ import annotations

import uuid
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from pydantic import BaseModel
from sqlalchemy import ColumnElement, and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.filters import today_ist
from farmerapp.api.errors import NotFoundError
from farmerapp.auth.field_scope import staff_column_filters
from farmerapp.auth.models import User
from farmerapp.beat import service as beat
from farmerapp.beat.models import BeatPlan
from farmerapp.beat.schemas import BeatPlanOut, BeatPlanUpdate
from farmerapp.demo_plots import service as demos
from farmerapp.demo_plots.models import DemoObservation, DemoPlot
from farmerapp.demo_plots.schemas import (
    DemoPlotCreate,
    DemoPlotOut,
    DemoTransitionIn,
    ObservationIn,
    ObservationOut,
    YieldIn,
)
from farmerapp.duty import timeline
from farmerapp.duty.models import TrackGap
from farmerapp.farmers.errors import UnsupportedActionError
from farmerapp.meetings import service as meetings
from farmerapp.meetings.models import FarmerMeeting, MeetingAttendance
from farmerapp.meetings.schemas import AttendanceIn, AttendanceOut, MeetingCreate, MeetingOut
from farmerapp.notifications import service as inbox
from farmerapp.notifications.models import Notification
from farmerapp.notifications.schemas import NotificationOut
from farmerapp.sync.models import SyncChange
from farmerapp.travel import service as travel
from farmerapp.travel.models import TravelClaim
from farmerapp.travel.schemas import TravelClaimIn, TravelClaimOut

LAST_WRITER_WINS = "last_writer_wins"
SERVER_WINS = "server_wins"

#: entity -> conflict strategy (merged into ``farmerapp.sync.service.CONFLICT_RULES``).
STRATEGIES: dict[str, str] = {
    "notification": LAST_WRITER_WINS,
    "track_gap": LAST_WRITER_WINS,
    "beat_plan": LAST_WRITER_WINS,
    "travel_claim": SERVER_WINS,
    "demo_plot": LAST_WRITER_WINS,
    "demo_observation": SERVER_WINS,
    "farmer_meeting": LAST_WRITER_WINS,
    "meeting_attendance": SERVER_WINS,
}
ENTITIES: tuple[str, ...] = tuple(STRATEGIES)


@dataclass(frozen=True)
class Applied:
    out: BaseModel
    version: int
    conflict: bool = False


def _aware(ts: datetime) -> datetime:
    return ts if ts.tzinfo is not None else ts.replace(tzinfo=UTC)


def _stale(op: Any, row: Any) -> bool:
    """``last_writer_wins``: a stale base version loses unless the edit is newer."""
    if op.base_version == getattr(row, "version", op.base_version):
        return False
    updated = getattr(row, "updated_at", None)
    return updated is not None and _aware(op.client_ts) <= _aware(updated)


def _blobs(ctx: Any) -> Any:
    if ctx.blobs is None:
        raise UnsupportedActionError("This op needs the blob store.")
    return ctx.blobs


def _services(ctx: Any) -> Any:
    if ctx.services is None:
        raise UnsupportedActionError("This op needs the auth services.")
    return ctx.services


# --------------------------------------------------------------------------- apply
async def create(session: AsyncSession, actor: User, op: Any, ctx: Any) -> Applied:
    payload = {**op.payload, "id": str(op.entity_id)}
    now: datetime = ctx.now
    if op.entity == "travel_claim":
        claim, created = await travel.submit_claim(
            session,
            actor,
            TravelClaimIn.model_validate(payload),
            blobs=_blobs(ctx),
            now=now,
            today=today_ist(now),
        )
        return Applied(TravelClaimOut.from_row(claim), claim.version, conflict=not created)
    if op.entity == "demo_plot":
        demo, created = await demos.create_demo(
            session, actor, DemoPlotCreate.model_validate(payload), now=now
        )
        return Applied(DemoPlotOut.from_row(demo), demo.version, conflict=not created)
    if op.entity == "demo_observation":
        demo = await demos.own_demo(session, actor, _uuid(payload.get("demo_plot_id")))
        obs, created = await demos.add_observation(
            session, actor, demo, ObservationIn.model_validate(payload), blobs=_blobs(ctx)
        )
        return Applied(ObservationOut.from_row(obs), obs.version, conflict=not created)
    if op.entity == "farmer_meeting":
        meeting, created = await meetings.create_meeting(
            session, actor, MeetingCreate.model_validate(payload)
        )
        return Applied(MeetingOut.from_row(meeting), meeting.version, conflict=not created)
    if op.entity == "meeting_attendance":
        meeting = await meetings.own_meeting(session, actor, _uuid(payload.get("meeting_id")))
        body = AttendanceIn.model_validate({"recorded_at": op.client_ts, **payload})
        row, created = await meetings.record_attendance(
            session, actor, meeting, body, services=_services(ctx), now=now
        )
        return Applied(AttendanceOut.from_row(row), row.version, conflict=not created)
    if op.entity == "track_gap":
        return await _gap(session, actor, op, ctx)
    raise UnsupportedActionError(f"{op.entity} records are not created from a device.")


async def _gap(session: AsyncSession, actor: User, op: Any, ctx: Any) -> Applied:
    row = await session.get(TrackGap, op.entity_id)
    newer = (
        row is not None
        and row.officer_id == actor.id
        and row.reason_at is not None
        and _aware(row.reason_at) >= _aware(op.client_ts)
    )
    if row is not None and newer:  # a later reason (another device) wins
        return Applied(timeline.GapOutRow.from_row(row), row.version, conflict=True)
    out = await timeline.give_reason(
        session, actor, op.entity_id, timeline.GapReasonIn.model_validate(op.payload), now=ctx.now
    )
    stored = await session.get_one(TrackGap, out.id)
    return Applied(out, stored.version)


async def update(session: AsyncSession, actor: User, op: Any, ctx: Any) -> Applied:
    now: datetime = ctx.now
    payload = dict(op.payload)
    if op.entity == "notification":
        row = await inbox.own_notification(session, actor, op.entity_id)
        out = await inbox.mark_read(session, actor, row.id, now=now)
        return Applied(out, 2 if row.read_at else 1)
    if op.entity == "track_gap":
        return await _gap(session, actor, op, ctx)
    if op.entity == "beat_plan":
        plan = await session.get(BeatPlan, op.entity_id)
        if plan is None or plan.tenant_id != actor.tenant_id or plan.officer_id != actor.id:
            raise NotFoundError("Beat plan not found.")
        if _stale(op, plan):
            return Applied(BeatPlanOut.from_row(plan), plan.version, conflict=True)
        body = BeatPlanUpdate.model_validate({**payload, "version": None})
        updated = await beat.update_plan(session, actor, plan.plan_date, body, now=now)
        return Applied(updated, updated.version)
    if op.entity == "demo_plot":
        demo = await demos.own_demo(session, actor, op.entity_id)
        if _stale(op, demo):
            return Applied(DemoPlotOut.from_row(demo), demo.version, conflict=True)
        if payload.get("demo_yield_kg_per_acre") is not None:
            demo = await demos.record_yield(session, demo, YieldIn.model_validate(payload), now=now)
        if payload.get("status") in ("active", "reported"):
            demo = await demos.transition(
                session, demo, DemoTransitionIn(to=payload["status"], at=op.client_ts), now=now
            )
        return Applied(DemoPlotOut.from_row(demo), demo.version)
    if op.entity == "farmer_meeting":
        meeting = await meetings.own_meeting(session, actor, op.entity_id)
        if payload.get("status") == "closed":
            await meetings.close_meeting(session, meeting, now=now)
        return Applied(MeetingOut.from_row(meeting), meeting.version)
    raise UnsupportedActionError(f"{op.entity} records are immutable once written.")


def _uuid(value: Any) -> uuid.UUID:
    try:
        return uuid.UUID(str(value))
    except ValueError as exc:
        raise NotFoundError("Parent entity not found.") from exc


# --------------------------------------------------------------------------- feed
def feed_clauses(actor: User) -> list[ColumnElement[bool]]:
    """``sync_change`` filters: the M7 entities ``actor`` receives."""
    visible_demos = select(DemoPlot.id).where(*demos.demo_filters(actor))
    visible_meetings = select(FarmerMeeting.id).where(*meetings.meeting_filters(actor))

    def entity(name: str, ids: Any) -> ColumnElement[bool]:
        return and_(SyncChange.entity == name, SyncChange.entity_id.in_(ids))

    return [
        entity(
            "notification",
            select(Notification.id).where(
                Notification.tenant_id == actor.tenant_id, Notification.user_id == actor.id
            ),
        ),
        entity(
            "track_gap",
            select(TrackGap.id).where(
                TrackGap.tenant_id == actor.tenant_id, TrackGap.officer_id == actor.id
            ),
        ),
        entity(
            "beat_plan",
            select(BeatPlan.id).where(
                BeatPlan.tenant_id == actor.tenant_id, BeatPlan.officer_id == actor.id
            ),
        ),
        entity(
            "travel_claim",
            select(TravelClaim.id).where(
                TravelClaim.tenant_id == actor.tenant_id,
                *staff_column_filters(actor, TravelClaim.officer_id),
            ),
        ),
        entity("demo_plot", visible_demos),
        entity(
            "demo_observation",
            select(DemoObservation.id).where(DemoObservation.demo_plot_id.in_(visible_demos)),
        ),
        entity("farmer_meeting", visible_meetings),
        entity(
            "meeting_attendance",
            select(MeetingAttendance.id).where(MeetingAttendance.meeting_id.in_(visible_meetings)),
        ),
    ]


Loader = Callable[[AsyncSession, list[uuid.UUID]], Awaitable[dict[uuid.UUID, BaseModel]]]


def _plain(model: Any, to_out: Callable[[Any], BaseModel]) -> Loader:
    async def load(session: AsyncSession, ids: list[uuid.UUID]) -> dict[uuid.UUID, BaseModel]:
        rows = (await session.execute(select(model).where(model.id.in_(ids)))).scalars()
        return {row.id: to_out(row) for row in rows}

    return load


LOADERS: dict[str, Loader] = {
    "notification": _plain(Notification, NotificationOut.from_row),
    "track_gap": _plain(TrackGap, timeline.GapOutRow.from_row),
    "beat_plan": _plain(BeatPlan, BeatPlanOut.from_row),
    "travel_claim": _plain(TravelClaim, TravelClaimOut.from_row),
    "demo_plot": _plain(DemoPlot, DemoPlotOut.from_row),
    "demo_observation": _plain(DemoObservation, ObservationOut.from_row),
    "farmer_meeting": _plain(FarmerMeeting, MeetingOut.from_row),
    "meeting_attendance": _plain(MeetingAttendance, AttendanceOut.from_row),
}


async def current_state(
    session: AsyncSession, ids: dict[str, list[uuid.UUID]]
) -> dict[tuple[str, uuid.UUID], BaseModel]:
    state: dict[tuple[str, uuid.UUID], BaseModel] = {}
    for entity, load in LOADERS.items():
        if ids.get(entity):
            for key, out in (await load(session, ids[entity])).items():
                state[(entity, key)] = out
    return state


__all__ = [
    "ENTITIES",
    "LOADERS",
    "STRATEGIES",
    "Applied",
    "create",
    "current_state",
    "feed_clauses",
    "update",
]
