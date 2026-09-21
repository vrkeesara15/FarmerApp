"""FM-013 referral logic.

The one entry point registration uses is :func:`attribute`, which is called from two places:

* ``POST /v1/farmers`` (FA-012) when the officer typed the code the farmer was invited with;
* ``POST /v1/me/referral/claim`` when the invited farmer opens the app from the invite link
  (the farmer app never asks anyone to *type* a code — NF-010 forbids typing on farmer
  screens — so the code always arrives from the shared link).

Both paths end in the same row, so "referral attributed" (the FM-013 acceptance criterion) is
one code path with one set of rules:

* the code must belong to a live farmer of the tenant (``referral_code_unknown``);
* that farmer may not be the invited one (``referral_self``);
* the invited farmer may be credited **once**, ever (``referral_already_attributed``) — also
  enforced by ``uq_referral_invited_farmer``, so a race ends in the same answer;
* the claim must be inside ``settings.referral.claim_window_days`` of the farmer's
  registration (``referral_window_closed``);
* a ``pending`` invite the referrer had already shared to that phone is *reused* rather than
  duplicated.

Credit goes to the referrer **and** to the invited farmer's nearest store (the store that
will serve them; ``farmerapp.orders.service.nearest_store``), with the reward amounts of the
moment copied onto the row — the tenant may change the rule later without rewriting history.
"""

from __future__ import annotations

import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import Select, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError
from farmerapp.auth.models import User, UserRole
from farmerapp.farmers.models import Farmer
from farmerapp.logging import get_logger
from farmerapp.orders import service as orders
from farmerapp.pii.crypto import phone_hash
from farmerapp.referrals.errors import (
    ReferralAlreadyAttributedError,
    ReferralCodeUnknownError,
    ReferralDisabledError,
    ReferralNotAttributedError,
    ReferralSelfError,
    ReferralWindowClosedError,
)
from farmerapp.referrals.models import (
    CODE_ALPHABET,
    CODE_LENGTH,
    Referral,
    ReferralSource,
    ReferralStatus,
)
from farmerapp.tenants.models import Store
from farmerapp.tenants.settings import ReferralSettings, get_tenant_settings

log = get_logger("farmerapp.referrals.service")

#: Attempts before giving up on minting a free code (1 in 31^8 collisions; 8 is plenty).
_MINT_ATTEMPTS = 8


def new_code() -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))


def normalise(code: str) -> str:
    """Codes are compared case-insensitively with spaces and dashes ignored."""
    return "".join(ch for ch in code.upper() if ch.isalnum())


async def ensure_code(session: AsyncSession, farmer: Farmer) -> str:
    """The farmer's referral code, minted on first use (no backfill; FM-013)."""
    if farmer.referral_code:
        return farmer.referral_code
    for _ in range(_MINT_ATTEMPTS):
        candidate = new_code()
        taken = await session.scalar(
            select(Farmer.id)
            .where(Farmer.tenant_id == farmer.tenant_id, Farmer.referral_code == candidate)
            .limit(1)
        )
        if taken is None:
            farmer.referral_code = candidate
            await session.flush()
            return candidate
    raise RuntimeError("could not mint a free referral code")  # pragma: no cover - 31^8


async def farmer_by_code(
    session: AsyncSession, *, tenant_id: uuid.UUID, code: str
) -> Farmer | None:
    row: Farmer | None = await session.scalar(
        select(Farmer)
        .where(
            Farmer.tenant_id == tenant_id,
            Farmer.referral_code == normalise(code),
            Farmer.deleted_at.is_(None),
        )
        .limit(1)
    )
    return row


async def _settings(session: AsyncSession, tenant_id: uuid.UUID) -> ReferralSettings:
    return (await get_tenant_settings(session, tenant_id)).referral


# --------------------------------------------------------------------------- invite
async def create_invite(
    session: AsyncSession,
    *,
    referrer: Farmer,
    phone: str | None,
    now: datetime | None = None,
) -> Referral:
    """FM-013: record the invite the farmer is about to share (status ``pending``).

    Sharing the same phone twice returns the existing pending row instead of a second one.
    """
    settings = await _settings(session, referrer.tenant_id)
    if not settings.enabled:
        raise ReferralDisabledError("Referrals are switched off for this tenant.")
    now = now or datetime.now(UTC)
    code = await ensure_code(session, referrer)
    digest = phone_hash(phone) if phone else None
    if digest is not None:
        if referrer.phone_hash == digest:
            raise ReferralSelfError("You cannot invite your own number.")
        existing = await session.scalar(
            select(Referral)
            .where(
                Referral.tenant_id == referrer.tenant_id,
                Referral.referrer_farmer_id == referrer.id,
                Referral.invited_phone_hash == digest,
                Referral.deleted_at.is_(None),
            )
            .order_by(Referral.created_at.desc())
            .limit(1)
        )
        if existing is not None:
            return existing
    row = Referral(
        tenant_id=referrer.tenant_id,
        code=code,
        referrer_farmer_id=referrer.id,
        invited_phone_hash=digest,
        invited_phone_last4=phone[-4:] if phone else None,
        status=ReferralStatus.PENDING,
        source=ReferralSource.INVITE,
        reward_note=settings.reward_note,
    )
    session.add(row)
    await session.flush()
    log.info(
        "referral_invited",
        tenant_id=str(referrer.tenant_id),
        referral_id=str(row.id),
        referrer_farmer_id=str(referrer.id),
    )
    return row


# --------------------------------------------------------------------------- attribution
async def _nearest_store_id(session: AsyncSession, farmer: Farmer) -> uuid.UUID | None:
    try:
        return (await orders.nearest_store(session, farmer)).store.id
    except NotFoundError:  # a tenant with no store yet: the referrer is still credited
        return None


async def attribute(
    session: AsyncSession,
    *,
    invited: Farmer,
    code: str,
    source: ReferralSource,
    now: datetime | None = None,
) -> Referral:
    """FM-013: credit ``code``'s owner and ``invited``'s nearest store with this registration."""
    settings = await _settings(session, invited.tenant_id)
    if not settings.enabled:
        raise ReferralDisabledError("Referrals are switched off for this tenant.")
    now = now or datetime.now(UTC)
    referrer = await farmer_by_code(session, tenant_id=invited.tenant_id, code=code)
    if referrer is None:
        raise ReferralCodeUnknownError("That invite code does not belong to any farmer.")
    if referrer.id == invited.id:
        raise ReferralSelfError("A farmer cannot refer themself.")
    already = await session.scalar(
        select(Referral)
        .where(
            Referral.tenant_id == invited.tenant_id,
            Referral.invited_farmer_id == invited.id,
            Referral.deleted_at.is_(None),
        )
        .limit(1)
    )
    if already is not None:
        raise ReferralAlreadyAttributedError("This farmer was already credited to a referrer.")
    registered = invited.created_at or now
    if registered.tzinfo is None:  # pragma: no cover - timestamptz everywhere
        registered = registered.replace(tzinfo=UTC)
    if now - registered > timedelta(days=settings.claim_window_days):
        raise ReferralWindowClosedError("The invite can no longer be claimed.")

    store_id = await _nearest_store_id(session, invited)
    pending = None
    if invited.phone_hash:
        pending = await session.scalar(
            select(Referral)
            .where(
                Referral.tenant_id == invited.tenant_id,
                Referral.referrer_farmer_id == referrer.id,
                Referral.invited_phone_hash == invited.phone_hash,
                Referral.status == ReferralStatus.PENDING,
                Referral.deleted_at.is_(None),
            )
            .limit(1)
        )
    row = pending or Referral(
        tenant_id=invited.tenant_id,
        code=normalise(code),
        referrer_farmer_id=referrer.id,
    )
    row.code = normalise(code)
    row.invited_farmer_id = invited.id
    row.invited_phone_hash = invited.phone_hash
    row.invited_phone_last4 = invited.phone_last4
    row.store_id = store_id
    row.status = ReferralStatus.ATTRIBUTED
    row.source = source
    row.referrer_reward_paise = settings.referrer_reward_paise
    row.store_reward_paise = settings.store_reward_paise
    row.reward_note = settings.reward_note
    row.attributed_at = now
    if pending is None:
        session.add(row)
    try:
        await session.flush()
    except IntegrityError as exc:  # uq_referral_invited_farmer: a concurrent claim won
        raise ReferralAlreadyAttributedError(
            "This farmer was already credited to a referrer."
        ) from exc
    log.info(
        "referral_attributed",
        tenant_id=str(invited.tenant_id),
        referral_id=str(row.id),
        referrer_farmer_id=str(referrer.id),
        invited_farmer_id=str(invited.id),
        store_id=str(store_id) if store_id else None,
        source=str(source),
    )
    return row


async def attribute_quietly(
    session: AsyncSession,
    *,
    invited: Farmer,
    code: str | None,
    source: ReferralSource,
    now: datetime | None = None,
) -> str | None:
    """Attribution during farmer registration: a bad code is a **warning, never a 4xx**.

    Registering a farmer must not fail because an invite code was mistyped or stale, so
    ``POST /v1/farmers`` calls this and surfaces the reason in the response ``warnings``.
    """
    if not code:
        return None
    try:
        await attribute(session, invited=invited, code=code, source=source, now=now)
    except (
        ReferralAlreadyAttributedError,
        ReferralCodeUnknownError,
        ReferralDisabledError,
        ReferralSelfError,
        ReferralWindowClosedError,
    ) as exc:
        log.info(
            "referral_not_attributed",
            tenant_id=str(invited.tenant_id),
            invited_farmer_id=str(invited.id),
            reason=exc.code,
        )
        return exc.code
    return None


# --------------------------------------------------------------------------- reward
async def reward(
    session: AsyncSession,
    *,
    actor: User,
    referral: Referral,
    note: str | None = None,
    now: datetime | None = None,
) -> Referral:
    """Mark an attributed referral as rewarded (the credit was actually given)."""
    if referral.status == ReferralStatus.REWARDED:
        return referral
    if referral.status != ReferralStatus.ATTRIBUTED:
        raise ReferralNotAttributedError("Only an attributed referral can be rewarded.")
    referral.status = ReferralStatus.REWARDED
    referral.rewarded_at = now or datetime.now(UTC)
    referral.rewarded_by = actor.id
    if note:
        referral.note = note
    await session.flush()
    log.info(
        "referral_rewarded",
        tenant_id=str(referral.tenant_id),
        referral_id=str(referral.id),
        store_id=str(referral.store_id) if referral.store_id else None,
    )
    return referral


# --------------------------------------------------------------------------- reads
@dataclass(frozen=True)
class StoreReferrals:
    store_id: uuid.UUID | None
    store_code: str | None
    store_name: str | None
    pending: int
    attributed: int
    rewarded: int
    referrer_reward_paise: int
    store_reward_paise: int

    @property
    def total(self) -> int:
        return self.pending + self.attributed + self.rewarded


def _scope(stmt: Select[tuple[Referral]], actor: User) -> Select[tuple[Referral]]:
    """SPEC 2.6: a store manager sees their own store's referrals, tenant roles see all."""
    if UserRole(actor.role) == UserRole.STORE_MANAGER:
        return stmt.where(Referral.store_id == actor.store_id)
    return stmt


async def list_referrals(
    session: AsyncSession,
    actor: User,
    *,
    store_id: uuid.UUID | None = None,
    status: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[Referral], int]:
    stmt = select(Referral).where(
        Referral.tenant_id == actor.tenant_id, Referral.deleted_at.is_(None)
    )
    stmt = _scope(stmt, actor)
    if store_id is not None:
        stmt = stmt.where(Referral.store_id == store_id)
    if status:
        stmt = stmt.where(Referral.status == status)
    total = await session.scalar(select(func.count()).select_from(stmt.order_by(None).subquery()))
    rows = list(
        (
            await session.scalars(
                stmt.order_by(Referral.created_at.desc()).limit(limit).offset(offset)
            )
        ).all()
    )
    return rows, int(total or 0)


async def summary_by_store(session: AsyncSession, actor: User) -> list[StoreReferrals]:
    """WC: referrals per store — what the console's Referrals screen shows."""
    stmt = (
        select(
            Referral.store_id,
            Referral.status,
            func.count().label("n"),
            func.coalesce(func.sum(Referral.referrer_reward_paise), 0),
            func.coalesce(func.sum(Referral.store_reward_paise), 0),
        )
        .where(Referral.tenant_id == actor.tenant_id, Referral.deleted_at.is_(None))
        .group_by(Referral.store_id, Referral.status)
    )
    if UserRole(actor.role) == UserRole.STORE_MANAGER:
        stmt = stmt.where(Referral.store_id == actor.store_id)
    rows = (await session.execute(stmt)).all()
    stores = {
        s.id: s
        for s in (
            await session.scalars(
                select(Store).where(Store.tenant_id == actor.tenant_id, Store.deleted_at.is_(None))
            )
        ).all()
    }
    counts: dict[uuid.UUID | None, dict[str, int]] = {}
    money: dict[uuid.UUID | None, tuple[int, int]] = {}
    for store_id, status, n, referrer_paise, store_paise in rows:
        bucket = counts.setdefault(store_id, {})
        bucket[str(status)] = bucket.get(str(status), 0) + int(n)
        had = money.get(store_id, (0, 0))
        # Only a rewarded referral has actually cost anything.
        if str(status) == ReferralStatus.REWARDED:
            money[store_id] = (had[0] + int(referrer_paise), had[1] + int(store_paise))
        else:
            money.setdefault(store_id, had)
    out = [
        StoreReferrals(
            store_id=store_id,
            store_code=stores[store_id].code if store_id in stores else None,
            store_name=stores[store_id].name if store_id in stores else None,
            pending=bucket.get(ReferralStatus.PENDING, 0),
            attributed=bucket.get(ReferralStatus.ATTRIBUTED, 0),
            rewarded=bucket.get(ReferralStatus.REWARDED, 0),
            referrer_reward_paise=money.get(store_id, (0, 0))[0],
            store_reward_paise=money.get(store_id, (0, 0))[1],
        )
        for store_id, bucket in counts.items()
    ]
    return sorted(out, key=lambda s: (s.store_code or "~", str(s.store_id)))


async def my_referrals(session: AsyncSession, farmer: Farmer) -> list[Referral]:
    return list(
        (
            await session.scalars(
                select(Referral)
                .where(
                    Referral.tenant_id == farmer.tenant_id,
                    Referral.referrer_farmer_id == farmer.id,
                    Referral.deleted_at.is_(None),
                )
                .order_by(Referral.created_at.desc())
            )
        ).all()
    )


__all__ = [
    "StoreReferrals",
    "attribute",
    "attribute_quietly",
    "create_invite",
    "ensure_code",
    "farmer_by_code",
    "list_referrals",
    "my_referrals",
    "new_code",
    "normalise",
    "reward",
    "summary_by_store",
]
