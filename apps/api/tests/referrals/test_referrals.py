"""FM-013: the full attribution path, duplicate and self-referral prevention, the reward
step and the console's per-store view.

The acceptance criterion is *referral attributed*, so the attribution path is tested end to
end twice — once through officer registration (``POST /v1/farmers`` with ``referral_code``)
and once through the farmer app (``POST /v1/me/referral/claim``) — and both must credit the
referrer **and** the invited farmer's nearest store.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.models import Tenant
from farmerapp.farmers.models import Farmer
from farmerapp.orders import service as orders
from farmerapp.referrals import service
from farmerapp.referrals.errors import (
    ReferralAlreadyAttributedError,
    ReferralCodeUnknownError,
    ReferralDisabledError,
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
from farmerapp.tenants.models import Village
from tests.authz.conftest import Bearer, World
from tests.referrals.conftest import Pair

T0 = datetime(2026, 9, 21, 4, 0, tzinfo=UTC)

#: The seed registers farmers 1-120 days in the past, so a route test that claims a code has
#: to widen the window the same way a tenant would for a back-dated pilot.
WIDE_WINDOW = 365


async def _settings(session: AsyncSession, tenant_id: uuid.UUID, **referral: object) -> None:
    tenant = await session.get_one(Tenant, tenant_id)
    tenant.settings = {**(tenant.settings or {}), "referral": referral}
    await session.flush()


def _soon(farmer: Farmer) -> datetime:
    """An hour after the farmer registered: inside any claim window."""
    registered = farmer.created_at or T0
    return (registered if registered.tzinfo else registered.replace(tzinfo=UTC)) + timedelta(
        hours=1
    )


# --------------------------------------------------------------------------- codes
def test_the_code_alphabet_has_no_ambiguous_characters() -> None:
    assert set("OISL01") & set(CODE_ALPHABET) == {"L"}  # O, I, S, 0, 1 are all excluded
    assert len(service.new_code()) == CODE_LENGTH


def test_codes_are_compared_without_case_or_separators() -> None:
    assert service.normalise(" abcd-1234 ") == "ABCD1234"


async def test_a_code_is_minted_once_and_kept(db_session: AsyncSession, pair: Pair) -> None:
    first = await service.ensure_code(db_session, pair.referrer.farmer)
    second = await service.ensure_code(db_session, pair.referrer.farmer)
    assert first == second and len(first) == CODE_LENGTH
    assert set(first) <= set(CODE_ALPHABET)


# --------------------------------------------------------------------------- attribution
async def test_attribution_credits_the_referrer_and_the_nearest_store(
    db_session: AsyncSession, pair: Pair
) -> None:
    await _settings(
        db_session,
        pair.referrer.farmer.tenant_id,
        enabled=True,
        referrer_reward_paise=5_000,
        store_reward_paise=2_500,
        reward_note="One free soil test",
    )
    code = await service.ensure_code(db_session, pair.referrer.farmer)
    row = await service.attribute(
        db_session,
        invited=pair.invited,
        code=code.lower(),  # the app may deep-link it in any case
        source=ReferralSource.FARMER_APP,
        now=_soon(pair.invited),
    )
    assert row.status == ReferralStatus.ATTRIBUTED
    assert row.referrer_farmer_id == pair.referrer.farmer.id
    assert row.invited_farmer_id == pair.invited.id
    assert row.attributed_at == _soon(pair.invited)
    # FM-013: credited to the referrer *and* the nearest store of the invited farmer.
    expected = await orders.nearest_store(db_session, pair.invited)
    assert row.store_id == expected.store.id
    # The reward the tenant promised that day is snapshotted on the row.
    assert (row.referrer_reward_paise, row.store_reward_paise) == (5_000, 2_500)
    assert row.reward_note == "One free soil test"
    assert row.invited_phone_last4 == pair.invited.phone_last4
    assert row.invited_phone_hash == pair.invited.phone_hash


async def test_a_farmer_cannot_refer_themself(db_session: AsyncSession, pair: Pair) -> None:
    code = await service.ensure_code(db_session, pair.referrer.farmer)
    with pytest.raises(ReferralSelfError):
        await service.attribute(
            db_session,
            invited=pair.referrer.farmer,
            code=code,
            source=ReferralSource.FARMER_APP,
            now=_soon(pair.referrer.farmer),
        )


async def test_a_farmer_is_credited_to_at_most_one_referrer(
    db_session: AsyncSession, pair: Pair, world: World
) -> None:
    code = await service.ensure_code(db_session, pair.referrer.farmer)
    await service.attribute(
        db_session,
        invited=pair.invited,
        code=code,
        source=ReferralSource.OFFICER,
        now=_soon(pair.invited),
    )
    with pytest.raises(ReferralAlreadyAttributedError):
        await service.attribute(
            db_session,
            invited=pair.invited,
            code=code,
            source=ReferralSource.OFFICER,
            now=_soon(pair.invited),
        )
    # ... including from a different referrer.
    third = (
        await db_session.scalars(
            select(Farmer).where(
                Farmer.tenant_id == world.a.tenant.id,
                Farmer.id.notin_([pair.referrer.farmer.id, pair.invited.id]),
            )
        )
    ).first()
    if third is not None:
        other_code = await service.ensure_code(db_session, third)
        with pytest.raises(ReferralAlreadyAttributedError):
            await service.attribute(
                db_session,
                invited=pair.invited,
                code=other_code,
                source=ReferralSource.OFFICER,
                now=_soon(pair.invited),
            )


async def test_an_unknown_code_is_refused(db_session: AsyncSession, pair: Pair) -> None:
    with pytest.raises(ReferralCodeUnknownError):
        await service.attribute(
            db_session,
            invited=pair.invited,
            code="ZZZZ9999",
            source=ReferralSource.FARMER_APP,
            now=_soon(pair.invited),
        )


async def test_the_claim_window_closes(db_session: AsyncSession, pair: Pair) -> None:
    await _settings(db_session, pair.referrer.farmer.tenant_id, enabled=True, claim_window_days=1)
    code = await service.ensure_code(db_session, pair.referrer.farmer)
    late = (pair.invited.created_at or T0) + timedelta(days=2)
    with pytest.raises(ReferralWindowClosedError):
        await service.attribute(
            db_session,
            invited=pair.invited,
            code=code,
            source=ReferralSource.FARMER_APP,
            now=late,
        )


async def test_referrals_can_be_switched_off_per_tenant(
    db_session: AsyncSession, pair: Pair
) -> None:
    code = await service.ensure_code(db_session, pair.referrer.farmer)
    await _settings(db_session, pair.referrer.farmer.tenant_id, enabled=False)
    with pytest.raises(ReferralDisabledError):
        await service.attribute(
            db_session,
            invited=pair.invited,
            code=code,
            source=ReferralSource.OFFICER,
            now=_soon(pair.invited),
        )


async def test_a_pending_invite_becomes_the_attributed_row(
    db_session: AsyncSession, pair: Pair
) -> None:
    invite = await service.create_invite(
        db_session, referrer=pair.referrer.farmer, phone=pair.invited.phone, now=T0
    )
    assert invite.status == ReferralStatus.PENDING
    assert invite.source == ReferralSource.INVITE
    assert invite.invited_farmer_id is None
    # Sharing the same number twice reuses the row rather than making a second one.
    again = await service.create_invite(
        db_session, referrer=pair.referrer.farmer, phone=pair.invited.phone, now=T0
    )
    assert again.id == invite.id

    attributed = await service.attribute(
        db_session,
        invited=pair.invited,
        code=invite.code,
        source=ReferralSource.FARMER_APP,
        now=_soon(pair.invited),
    )
    assert attributed.id == invite.id  # the invite was completed, not duplicated
    assert attributed.status == ReferralStatus.ATTRIBUTED
    rows = await service.my_referrals(db_session, pair.referrer.farmer)
    assert len(rows) == 1


async def test_a_farmer_cannot_invite_their_own_number(
    db_session: AsyncSession, pair: Pair
) -> None:
    with pytest.raises(ReferralSelfError):
        await service.create_invite(
            db_session, referrer=pair.referrer.farmer, phone=pair.referrer.farmer.phone, now=T0
        )


async def test_attribute_quietly_never_raises(db_session: AsyncSession, pair: Pair) -> None:
    assert (
        await service.attribute_quietly(
            db_session, invited=pair.invited, code=None, source=ReferralSource.OFFICER, now=T0
        )
        is None
    )
    reason = await service.attribute_quietly(
        db_session, invited=pair.invited, code="NOPE0000", source=ReferralSource.OFFICER, now=T0
    )
    assert reason == "referral_code_unknown"


# --------------------------------------------------------------------------- routes
async def test_my_referral_returns_a_code_and_a_share_link(
    client: AsyncClient, bearer: Bearer, pair: Pair
) -> None:
    resp = await client.get("/v1/me/referral", headers=bearer(pair.referrer.user))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert len(body["code"]) == CODE_LENGTH
    assert body["share_link"].endswith(body["code"])
    assert body["enabled"] is True
    # The reward rule is a tenant setting with a placeholder value (human gate).
    assert body["referrer_reward_paise"] == 0 and body["store_reward_paise"] == 0
    assert body["invited"] == 0 and body["attributed"] == 0 and body["rewarded"] == 0
    # The code is stable across calls.
    again = await client.get("/v1/me/referral", headers=bearer(pair.referrer.user))
    assert again.json()["code"] == body["code"]


async def test_claim_attributes_and_refuses_a_second_time(
    client: AsyncClient,
    bearer: Bearer,
    pair: Pair,
    db_session: AsyncSession,
    world: World,
) -> None:
    # Only one seeded farmer has a login, so that farmer plays the *invited* role here and
    # claims the code of the other one. The path is identical.
    await _settings(db_session, world.a.tenant.id, enabled=True, claim_window_days=WIDE_WINDOW)
    code = await service.ensure_code(db_session, pair.referrer.farmer)
    invited_user = pair.referrer.user
    other_code = await service.ensure_code(db_session, pair.invited)
    await db_session.commit()

    resp = await client.post(
        "/v1/me/referral/claim",
        json={"code": other_code.lower()},
        headers=bearer(invited_user),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "attributed"
    assert body["referrer_farmer_id"] == str(pair.invited.id)
    assert body["invited_farmer_id"] == str(pair.referrer.farmer.id)
    assert body["store_id"] is not None
    assert body["source"] == "farmer_app"

    repeat = await client.post(
        "/v1/me/referral/claim", json={"code": other_code}, headers=bearer(invited_user)
    )
    assert repeat.status_code == 409
    assert repeat.json()["code"] == "referral_already_attributed"

    self_claim = await client.post(
        "/v1/me/referral/claim", json={"code": code}, headers=bearer(invited_user)
    )
    assert self_claim.status_code in (409, 422)


async def test_claiming_an_unknown_code_is_a_422(
    client: AsyncClient, bearer: Bearer, pair: Pair
) -> None:
    resp = await client.post(
        "/v1/me/referral/claim",
        json={"code": "ZZZZ9999"},
        headers=bearer(pair.referrer.user),
    )
    assert resp.status_code == 422 and resp.json()["code"] == "referral_code_unknown"


async def test_officer_registration_carries_the_code(
    client: AsyncClient,
    bearer: Bearer,
    pair: Pair,
    db_session: AsyncSession,
    world: World,
) -> None:
    code = await service.ensure_code(db_session, pair.referrer.farmer)
    village_id = await db_session.scalar(
        select(Village.id).where(Village.tenant_id == world.a.tenant.id).limit(1)
    )
    await db_session.commit()
    officer = world.a.user(UserRole.FIELD_OFFICER)
    resp = await client.post(
        "/v1/farmers",
        json={
            "phone": "+919000099001",
            "name": "Referred Farmer",
            "village_id": str(village_id),
            "referral_code": f"{code[:4]}-{code[4:]}".lower(),
        },
        headers=bearer(officer),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["referral_id"] is not None
    assert body["warnings"] == []

    row = await db_session.scalar(
        select(Referral).where(Referral.invited_farmer_id == uuid.UUID(body["id"]))
    )
    assert row is not None
    assert row.status == ReferralStatus.ATTRIBUTED
    assert row.source == ReferralSource.OFFICER
    assert row.referrer_farmer_id == pair.referrer.farmer.id
    assert row.store_id is not None


async def test_a_bad_code_warns_but_never_fails_a_registration(
    client: AsyncClient, bearer: Bearer, world: World, db_session: AsyncSession
) -> None:
    village_id = await db_session.scalar(
        select(Village.id).where(Village.tenant_id == world.a.tenant.id).limit(1)
    )
    await db_session.commit()
    officer = world.a.user(UserRole.FIELD_OFFICER)
    resp = await client.post(
        "/v1/farmers",
        json={
            "phone": "+919000099002",
            "name": "Mistyped Code",
            "village_id": str(village_id),
            "referral_code": "ZZZZ9999",
        },
        headers=bearer(officer),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["referral_id"] is None
    assert "referral_code_unknown" in body["warnings"]


# --------------------------------------------------------------------------- console
async def test_console_lists_referrals_per_store_and_rewards_one(
    client: AsyncClient,
    bearer: Bearer,
    pair: Pair,
    db_session: AsyncSession,
    world: World,
) -> None:
    await _settings(
        db_session,
        world.a.tenant.id,
        enabled=True,
        referrer_reward_paise=5_000,
        store_reward_paise=2_500,
    )
    code = await service.ensure_code(db_session, pair.referrer.farmer)
    row = await service.attribute(
        db_session,
        invited=pair.invited,
        code=code,
        source=ReferralSource.OFFICER,
        now=_soon(pair.invited),
    )
    referral_id, store_id = row.id, row.store_id
    await db_session.commit()

    owner = world.a.owner
    listing = await client.get("/v1/referrals", headers=bearer(owner))
    assert listing.status_code == 200, listing.text
    body = listing.json()
    assert body["total"] == 1
    (item,) = body["items"]
    assert item["id"] == str(referral_id) and item["status"] == "attributed"
    # SEC-026 / AN-014: the console sees four digits, never the number.
    assert item["invited_phone_last4"] == pair.invited.phone_last4
    assert "phone" not in item

    summary = await client.get("/v1/referrals/summary", headers=bearer(owner))
    assert summary.status_code == 200
    s = summary.json()
    assert s["attributed"] == 1 and s["rewarded"] == 0
    store = next(x for x in s["stores"] if x["store_id"] == str(store_id))
    assert store["total"] == 1 and store["store_code"]
    assert store["store_reward_paise"] == 0  # nothing rewarded yet

    rewarded = await client.post(
        f"/v1/referrals/{referral_id}/reward", json={"note": "credited"}, headers=bearer(owner)
    )
    assert rewarded.status_code == 200, rewarded.text
    assert rewarded.json()["status"] == "rewarded"
    assert rewarded.json()["rewarded_at"] is not None

    again = await client.post(f"/v1/referrals/{referral_id}/reward", json={}, headers=bearer(owner))
    assert again.status_code == 200  # idempotent

    after = (await client.get("/v1/referrals/summary", headers=bearer(owner))).json()
    store = next(x for x in after["stores"] if x["store_id"] == str(store_id))
    assert store["rewarded"] == 1 and store["store_reward_paise"] == 2_500
    assert store["referrer_reward_paise"] == 5_000


async def test_a_store_manager_only_sees_their_own_store(
    client: AsyncClient,
    bearer: Bearer,
    pair: Pair,
    db_session: AsyncSession,
    world: World,
) -> None:
    code = await service.ensure_code(db_session, pair.referrer.farmer)
    row = await service.attribute(
        db_session,
        invited=pair.invited,
        code=code,
        source=ReferralSource.OFFICER,
        now=_soon(pair.invited),
    )
    store_id, referral_id = row.store_id, row.id
    await db_session.commit()

    manager = world.a.user(UserRole.STORE_MANAGER)
    body = (await client.get("/v1/referrals", headers=bearer(manager))).json()
    ids = {item["store_id"] for item in body["items"]}
    assert ids <= {str(manager.store_id)}

    if manager.store_id != store_id:
        # A referral of another store is invisible, so rewarding it is a 404, not a 403.
        resp = await client.post(
            f"/v1/referrals/{referral_id}/reward", json={}, headers=bearer(manager)
        )
        assert resp.status_code == 404


async def test_another_tenant_never_sees_a_referral(
    client: AsyncClient,
    bearer: Bearer,
    pair: Pair,
    db_session: AsyncSession,
    world: World,
) -> None:
    code = await service.ensure_code(db_session, pair.referrer.farmer)
    await service.attribute(
        db_session,
        invited=pair.invited,
        code=code,
        source=ReferralSource.OFFICER,
        now=_soon(pair.invited),
    )
    await db_session.commit()
    body = (await client.get("/v1/referrals", headers=bearer(world.b.owner))).json()
    assert body["total"] == 0 and body["items"] == []
