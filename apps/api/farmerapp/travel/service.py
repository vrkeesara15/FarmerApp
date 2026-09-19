"""FA-023 travel allowance and expense claims.

**Daily km** — the processed km (VV-006, ``duty_session.km``) of the officer's ended duty
sessions that *started* that IST day, capped by the tenant's ``ta_daily_km_cap``; the
allowance is ``km_capped x ta_rate_per_km_paise`` rounded half-up to a paisa. No track, no
automatic TA (SPEC 4.2): an open session adds nothing until it ends.

**Claims** — ``POST /v1/travel/claims`` (or the ``travel_claim`` sync create) with the
receipt uploaded first (``receipt_uri`` must be a completed upload of the tenant). The km the
processing computed for that day is stored with the claim and ``TravelClaimSubmitted`` is
dispatched for VA-E07; the cluster head(s) of the officer's cluster get a notification. A
claim is decided once (``submitted`` -> ``approved`` | ``rejected``) by the cluster head of
the officer's cluster, or an owner / director / tenant admin — never by its own officer.

**Statement** — per month: every day with duty, the TA total, the claims by status and the
payable total (TA + approved claims).
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.analytics.filters import ist_bounds, ist_date
from farmerapp.api.errors import AppError, ConflictError, ForbiddenError, NotFoundError
from farmerapp.api.pagination import PageRequest
from farmerapp.auth.field_scope import staff_column_filters
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.location.models import DutySession
from farmerapp.notifications.models import NotificationKind
from farmerapp.notifications.service import notify
from farmerapp.payments.service import validate_blob
from farmerapp.tenants.settings import TenantSettings, get_tenant_settings
from farmerapp.travel import events
from farmerapp.travel.models import ClaimStatus, TravelClaim
from farmerapp.travel.schemas import (
    TravelClaimIn,
    TravelClaimOut,
    TravelClaimPage,
    TravelDayOut,
    TravelStatementOut,
)
from farmerapp.uploads.blobstore import BlobStore

CLAIM_MAX_AGE_DAYS = 90
APPROVER_ROLES = frozenset(
    {UserRole.CLUSTER_HEAD, UserRole.OWNER, UserRole.DIRECTOR, UserRole.TENANT_ADMIN}
)
CENT = Decimal("0.01")


class ClaimNotPendingError(ConflictError):
    code = "claim_not_pending"


class ClaimDateInvalidError(AppError):
    status = 422
    code = "claim_date_invalid"


class OfficerRequiredError(AppError):
    status = 422
    code = "officer_required"


class InvalidMonthError(AppError):
    status = 422
    code = "invalid_month"


def ta_for(km: Decimal, settings: TenantSettings) -> tuple[Decimal, int]:
    """``(km_capped, ta_paise)`` for one day's km."""
    capped = min(km, Decimal(settings.ta_daily_km_cap)).quantize(CENT)
    ta = (capped * settings.ta_rate_per_km_paise).quantize(Decimal(1), rounding=ROUND_HALF_UP)
    return capped, int(ta)


async def travel_days(
    session: AsyncSession, tenant_id: uuid.UUID, officer_id: uuid.UUID, first: date, last: date
) -> list[TravelDayOut]:
    """One row per IST day in ``[first, last]`` with duty (the officer's sessions)."""
    settings = await get_tenant_settings(session, tenant_id)
    start, end = ist_bounds(first, last)
    rows = await session.execute(
        select(DutySession.km, DutySession.end_at, ist_date(DutySession.start_at)).where(
            DutySession.tenant_id == tenant_id,
            DutySession.officer_id == officer_id,
            DutySession.deleted_at.is_(None),
            DutySession.start_at >= start,
            DutySession.start_at < end,
        )
    )
    km: dict[date, Decimal] = defaultdict(Decimal)
    sessions: dict[date, int] = defaultdict(int)
    open_days: set[date] = set()
    for row_km, end_at, day in rows:
        if end_at is None:
            open_days.add(day)
            continue
        sessions[day] += 1
        km[day] += Decimal(row_km or 0)
    out: list[TravelDayOut] = []
    for day in sorted(set(sessions) | open_days):
        total = km.get(day, Decimal(0)).quantize(CENT)
        capped, ta = ta_for(total, settings)
        out.append(
            TravelDayOut(
                date=day,
                sessions=sessions.get(day, 0),
                km=total,
                km_capped=capped,
                cap_km=settings.ta_daily_km_cap,
                rate_per_km_paise=settings.ta_rate_per_km_paise,
                ta_paise=ta,
                open_session=day in open_days,
            )
        )
    return out


async def travel_day(
    session: AsyncSession, tenant_id: uuid.UUID, officer_id: uuid.UUID, day: date
) -> TravelDayOut:
    days = await travel_days(session, tenant_id, officer_id, day, day)
    if days:
        return days[0]
    settings = await get_tenant_settings(session, tenant_id)
    return TravelDayOut(
        date=day,
        sessions=0,
        km=Decimal("0.00"),
        km_capped=Decimal("0.00"),
        cap_km=settings.ta_daily_km_cap,
        rate_per_km_paise=settings.ta_rate_per_km_paise,
        ta_paise=0,
        open_session=False,
    )


# --------------------------------------------------------------------------- claims
async def _cluster_heads(session: AsyncSession, officer: User) -> list[uuid.UUID]:
    if officer.cluster_id is None:
        return []
    rows = await session.execute(
        select(User.id).where(
            User.tenant_id == officer.tenant_id,
            User.role == UserRole.CLUSTER_HEAD.value,
            User.status == UserStatus.ACTIVE.value,
            User.cluster_id == officer.cluster_id,
            User.deleted_at.is_(None),
            User.id != officer.id,
        )
    )
    return list(rows.scalars())


async def submit_claim(
    session: AsyncSession,
    actor: User,
    body: TravelClaimIn,
    *,
    blobs: BlobStore,
    now: datetime,
    today: date,
) -> tuple[TravelClaim, bool]:
    """Create the claim (``(row, created)``; a replayed client id returns the stored row)."""
    if body.id is not None:
        existing = await session.get(TravelClaim, body.id)
        if existing is not None:
            if existing.tenant_id != actor.tenant_id or existing.officer_id != actor.id:
                raise NotFoundError("Claim not found.")
            return existing, False
    if body.claim_date > today or body.claim_date < today - timedelta(days=CLAIM_MAX_AGE_DAYS):
        raise ClaimDateInvalidError(
            f"A claim is for today or one of the last {CLAIM_MAX_AGE_DAYS} days."
        )
    await validate_blob(body.receipt_uri, actor.tenant_id, blobs)
    day = await travel_day(session, actor.tenant_id, actor.id, body.claim_date)
    claim = TravelClaim(
        id=body.id or uuid.uuid4(),
        tenant_id=actor.tenant_id,
        officer_id=actor.id,
        claim_date=body.claim_date,
        type=body.type,
        amount_paise=body.amount_paise,
        receipt_uri=body.receipt_uri,
        note=body.note,
        km_computed=day.km if day.sessions else None,
    )
    session.add(claim)
    await session.flush()
    await session.refresh(claim)
    for head in await _cluster_heads(session, actor):
        notify(
            session,
            tenant_id=actor.tenant_id,
            user_id=head,
            kind=NotificationKind.TRAVEL_CLAIM_SUBMITTED.value,
            data={
                "claim_id": claim.id,
                "officer_id": actor.id,
                "claim_date": str(claim.claim_date),
            },
        )
    await session.flush()
    await events.bus.dispatch(
        session,
        events.TravelClaimSubmitted(
            tenant_id=actor.tenant_id,
            claim_id=claim.id,
            officer_id=actor.id,
            claim_date=claim.claim_date,
            claim_type=claim.type,
            amount_paise=claim.amount_paise,
            km_computed=claim.km_computed,
            ta_paise=day.ta_paise,
            at=now,
        ),
    )
    return claim, True


async def visible_claim(session: AsyncSession, actor: User, claim_id: uuid.UUID) -> TravelClaim:
    row = (
        await session.execute(
            select(TravelClaim).where(
                TravelClaim.id == claim_id,
                TravelClaim.tenant_id == actor.tenant_id,
                TravelClaim.deleted_at.is_(None),
                *staff_column_filters(actor, TravelClaim.officer_id),
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise NotFoundError("Claim not found.")
    return row


async def decide_claim(
    session: AsyncSession,
    actor: User,
    claim_id: uuid.UUID,
    *,
    approve: bool,
    note: str | None,
    now: datetime,
) -> TravelClaim:
    claim = await visible_claim(session, actor, claim_id)
    if claim.officer_id == actor.id:
        raise ForbiddenError("An officer cannot decide their own claim.")
    if claim.status != ClaimStatus.SUBMITTED:
        raise ClaimNotPendingError(f"This claim is already {claim.status}.")
    claim.status = (ClaimStatus.APPROVED if approve else ClaimStatus.REJECTED).value
    claim.decided_by = actor.id
    claim.decided_at = now
    claim.decision_note = note
    notify(
        session,
        tenant_id=claim.tenant_id,
        user_id=claim.officer_id,
        kind=NotificationKind.TRAVEL_CLAIM_DECIDED.value,
        data={"claim_id": claim.id, "status": claim.status},
        body=f"notification.travel_claim_decided.body.{claim.status}",
    )
    await session.flush()
    await session.refresh(claim)
    return claim


async def list_claims(
    session: AsyncSession,
    actor: User,
    page: PageRequest,
    *,
    status: str | None,
    officer_id: uuid.UUID | None,
) -> TravelClaimPage:
    stmt = select(TravelClaim).where(
        TravelClaim.tenant_id == actor.tenant_id,
        TravelClaim.deleted_at.is_(None),
        *staff_column_filters(actor, TravelClaim.officer_id),
    )
    if status is not None:
        stmt = stmt.where(TravelClaim.status == status)
    if officer_id is not None:
        stmt = stmt.where(TravelClaim.officer_id == officer_id)
    keyset = page.after(TravelClaim.created_at, TravelClaim.id)
    if keyset is not None:
        stmt = stmt.where(keyset)
    rows = (
        (
            await session.execute(
                stmt.order_by(TravelClaim.created_at, TravelClaim.id).limit(page.fetch)
            )
        )
        .scalars()
        .all()
    )
    items, cursor = page.slice(rows)
    return TravelClaimPage(items=[TravelClaimOut.from_row(r) for r in items], next_cursor=cursor)


# --------------------------------------------------------------------------- statement
def month_bounds(month: str) -> tuple[date, date]:
    try:
        first = datetime.strptime(month + "-01", "%Y-%m-%d").date()
    except ValueError as exc:
        raise InvalidMonthError("`month` must be YYYY-MM.") from exc
    nxt = (first.replace(day=28) + timedelta(days=4)).replace(day=1)
    return first, nxt - timedelta(days=1)


async def statement_officer(
    session: AsyncSession, actor: User, officer_id: uuid.UUID | None
) -> uuid.UUID:
    """The officer of a statement: the caller when they do duty, else a visible officer."""
    if officer_id is None or officer_id == actor.id:
        if UserRole(actor.role) in (UserRole.FIELD_OFFICER, UserRole.CLUSTER_HEAD):
            return actor.id
        raise OfficerRequiredError("Pass `officer_id`.")
    visible = await session.scalar(
        select(User.id).where(
            User.id == officer_id,
            User.tenant_id == actor.tenant_id,
            *staff_column_filters(actor, User.id),
        )
    )
    if visible is None:
        raise NotFoundError("Officer not found.")
    return officer_id


async def statement(
    session: AsyncSession, actor: User, *, month: str, officer_id: uuid.UUID | None
) -> TravelStatementOut:
    officer = await statement_officer(session, actor, officer_id)
    first, last = month_bounds(month)
    settings = await get_tenant_settings(session, actor.tenant_id)
    days = await travel_days(session, actor.tenant_id, officer, first, last)
    claims = (
        (
            await session.execute(
                select(TravelClaim)
                .where(
                    TravelClaim.tenant_id == actor.tenant_id,
                    TravelClaim.officer_id == officer,
                    TravelClaim.deleted_at.is_(None),
                    TravelClaim.claim_date >= first,
                    TravelClaim.claim_date <= last,
                )
                .order_by(TravelClaim.claim_date, TravelClaim.created_at)
            )
        )
        .scalars()
        .all()
    )

    def total(status: ClaimStatus) -> int:
        return sum(c.amount_paise for c in claims if c.status == status)

    ta_total = sum(d.ta_paise for d in days)
    approved = total(ClaimStatus.APPROVED)
    return TravelStatementOut(
        officer_id=officer,
        month=month,
        rate_per_km_paise=settings.ta_rate_per_km_paise,
        cap_km=settings.ta_daily_km_cap,
        days=days,
        km_total=sum((d.km for d in days), Decimal("0.00")),
        km_capped_total=sum((d.km_capped for d in days), Decimal("0.00")),
        ta_total_paise=ta_total,
        claims=[TravelClaimOut.from_row(c) for c in claims],
        claims_submitted_paise=total(ClaimStatus.SUBMITTED),
        claims_approved_paise=approved,
        claims_rejected_paise=total(ClaimStatus.REJECTED),
        payable_paise=ta_total + approved,
    )


__all__ = [
    "APPROVER_ROLES",
    "ClaimDateInvalidError",
    "ClaimNotPendingError",
    "InvalidMonthError",
    "OfficerRequiredError",
    "decide_claim",
    "list_claims",
    "month_bounds",
    "statement",
    "submit_claim",
    "ta_for",
    "travel_day",
    "travel_days",
    "visible_claim",
]
