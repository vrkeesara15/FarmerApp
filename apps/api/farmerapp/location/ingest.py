"""Location batch ingest (FA-010, VV-001, VV-002): points are stored **only inside a duty
session's window**.

A batch names the officer's own ``duty_session_id`` and carries up to 500 points. Each
point is accepted only when its ``ts`` lies within ``[start_at - 2 min, end_at (or now)
+ 2 min]`` of that session (``off_duty`` otherwise — nothing is ever stored while off
duty, whatever the device sends), is not more than 2 minutes in the server's future
(``future``) and is not a repeat of a stored or in-batch point of the officer at the same
``ts`` (``duplicate``). The server computes ``clock_drift_s`` = device ``sent_at`` - server
``received_at`` (rounded seconds) and stores it on every point of the batch (VV-002 /
VA-E01); ``received_at`` is the server time. A batch is idempotent by sync ``op_id`` (or
``Idempotency-Key`` on the REST twin); a replay stores nothing.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Literal

from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User
from farmerapp.db.geo import point_wkt
from farmerapp.duty.service import own_session, session_window
from farmerapp.location import events as location_events
from farmerapp.location.models import LocationPoint
from farmerapp.logging import get_logger

log = get_logger("farmerapp.location.ingest")

MAX_BATCH_POINTS = 500
FUTURE_SLACK = timedelta(minutes=2)

Provider = Literal["fused", "gps", "network"]
RejectReason = Literal["off_duty", "future", "duplicate"]


def _aware(ts: datetime) -> datetime:
    return ts if ts.tzinfo is not None else ts.replace(tzinfo=UTC)


class LocationPointIn(BaseModel):
    ts: datetime = Field(description="Sample time on the device (aware; naive is UTC).")
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    accuracy_m: float = Field(ge=0)
    speed_mps: float | None = Field(default=None, ge=0)
    bearing: float | None = Field(default=None, ge=0, le=360)
    battery_pct: int | None = Field(default=None, ge=0, le=100)
    is_mock: bool = False
    is_rooted: bool = False
    provider: Provider | None = None

    @field_validator("ts")
    @classmethod
    def _aware_ts(cls, value: datetime) -> datetime:
        return _aware(value)


class LocationBatchIn(BaseModel):
    id: uuid.UUID | None = Field(default=None, description="Client batch id (sync entity id).")
    duty_session_id: uuid.UUID
    device_id: str = Field(min_length=1, max_length=128)
    sent_at: datetime = Field(description="Device clock when the batch was sent (VV-002 drift).")
    points: list[LocationPointIn] = Field(min_length=1, max_length=MAX_BATCH_POINTS)

    @field_validator("sent_at")
    @classmethod
    def _aware_sent_at(cls, value: datetime) -> datetime:
        return _aware(value)


class RejectedPoint(BaseModel):
    index: int
    reason: RejectReason


class LocationBatchOut(BaseModel):
    duty_session_id: uuid.UUID
    accepted: int
    rejected: list[RejectedPoint]
    clock_drift_s: int = Field(description="Device `sent_at` minus server `received_at`.")
    received_at: datetime


async def ingest_batch(
    session: AsyncSession, actor: User, batch: LocationBatchIn, *, received_at: datetime
) -> LocationBatchOut:
    duty = await own_session(session, actor, batch.duty_session_id)
    lower, upper = session_window(duty, received_at)
    drift = round((batch.sent_at - received_at).total_seconds())
    stamps = [p.ts for p in batch.points]
    existing = set(
        (
            await session.execute(
                select(LocationPoint.ts).where(
                    LocationPoint.tenant_id == actor.tenant_id,
                    LocationPoint.officer_id == actor.id,
                    LocationPoint.ts >= min(stamps),
                    LocationPoint.ts <= max(stamps),
                )
            )
        ).scalars()
    )
    rejected: list[RejectedPoint] = []
    accepted = 0
    for index, point in enumerate(batch.points):
        if point.ts > received_at + FUTURE_SLACK:
            rejected.append(RejectedPoint(index=index, reason="future"))
            continue
        if point.ts < lower or point.ts > upper:
            rejected.append(RejectedPoint(index=index, reason="off_duty"))
            continue
        if point.ts in existing:
            rejected.append(RejectedPoint(index=index, reason="duplicate"))
            continue
        existing.add(point.ts)
        session.add(
            LocationPoint(
                tenant_id=actor.tenant_id,
                officer_id=actor.id,
                duty_session_id=duty.id,
                ts=point.ts,
                point=point_wkt(point.lon, point.lat),
                accuracy_m=point.accuracy_m,
                speed_mps=point.speed_mps,
                bearing=point.bearing,
                battery_pct=point.battery_pct,
                is_mock=point.is_mock,
                is_rooted=point.is_rooted,
                clock_drift_s=drift,
                provider=point.provider,
                received_at=received_at,
            )
        )
        accepted += 1
    await session.flush()
    log.info(
        "location_batch",
        duty_session_id=str(duty.id),
        officer_id=str(actor.id),
        device_id=batch.device_id,
        points=len(batch.points),
        accepted=accepted,
        rejected=len(rejected),
        clock_drift_s=drift,
    )
    if accepted:  # M4: VA-E01 / VA-E02 on the new points (a replay stores nothing)
        await location_events.bus.dispatch(
            session,
            location_events.LocationBatchIngested(
                tenant_id=actor.tenant_id,
                duty_session_id=duty.id,
                officer_id=actor.id,
                accepted=accepted,
                clock_drift_s=drift,
                at=received_at,
            ),
        )
    return LocationBatchOut(
        duty_session_id=duty.id,
        accepted=accepted,
        rejected=rejected,
        clock_drift_s=drift,
        received_at=received_at,
    )


__all__ = [
    "FUTURE_SLACK",
    "MAX_BATCH_POINTS",
    "LocationBatchIn",
    "LocationBatchOut",
    "LocationPointIn",
    "RejectedPoint",
    "ingest_batch",
]
