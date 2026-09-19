"""FM-011 / F62: ``officer {id, name, phone}`` on the farmer's own profile read
(``GET /v1/farmers/{id}``, ``GET /v1/me``): who it is, the fallback rule, and phone masking."""

from __future__ import annotations

from datetime import UTC, datetime

from httpx import AsyncClient
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.auth.providers import mask_phone
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.farmers.officer import PHONE_READER_ROLES
from farmerapp.tenants.models import Village
from farmerapp.users.router import READ_ROLES as USER_READ_ROLES
from tests.authz.conftest import Bearer, World


def _own(world: World) -> tuple[User, Farmer]:
    user = world.a.user(UserRole.FARMER)
    farmer = next(f for f in world.a.farmers if f.user_id == user.id)
    return user, farmer


def _by_id(world: World, user_id: object) -> User:
    return next(u for u in world.a.everyone if u.id == user_id)


async def test_farmer_sees_their_registering_officer_with_full_phone(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    user, farmer = _own(world)
    assert farmer.registered_by is not None
    officer = _by_id(world, farmer.registered_by)
    resp = await client.get(f"/v1/farmers/{farmer.id}", headers=bearer(user))
    assert resp.status_code == 200, resp.text
    assert resp.json()["officer"] == {
        "id": str(officer.id),
        "name": officer.name,
        "phone": officer.phone,
    }
    assert officer.phone.startswith("+91") and "*" not in officer.phone

    me = await client.get("/v1/me", headers=bearer(user))
    assert me.status_code == 200, me.text
    assert me.json()["officer"] == resp.json()["officer"]
    assert me.json()["id"] == str(user.id) and me.json()["role"] == "farmer"


async def test_farmer_cannot_read_another_farmers_officer(
    client: AsyncClient, world: World, bearer: Bearer
) -> None:
    user, own = _own(world)
    other = next(f for f in world.a.farmers if f.id != own.id)
    resp = await client.get(f"/v1/farmers/{other.id}", headers=bearer(user))
    assert resp.status_code == 404
    assert "officer" not in resp.json()
    resp = await client.get(f"/v1/farmers/{world.b.farmer.id}", headers=bearer(user))
    assert resp.status_code == 404


async def test_staff_me_has_no_officer(client: AsyncClient, world: World, bearer: Bearer) -> None:
    for role in (UserRole.FIELD_OFFICER, UserRole.OWNER, UserRole.AGRONOMIST):
        resp = await client.get("/v1/me", headers=bearer(world.a.user(role)))
        assert resp.status_code == 200 and resp.json()["officer"] is None


async def test_phone_masking_by_reader(client: AsyncClient, world: World, bearer: Bearer) -> None:
    _, farmer = _own(world)
    officer = _by_id(world, farmer.registered_by)
    full, masked = officer.phone, mask_phone(officer.phone)

    async def phone_seen_by(viewer: User) -> str:
        resp = await client.get(f"/v1/farmers/{farmer.id}", headers=bearer(viewer))
        assert resp.status_code == 200, resp.text
        return str(resp.json()["officer"]["phone"])

    assert await phone_seen_by(officer) == full  # the officer themself
    for role in PHONE_READER_ROLES:
        assert await phone_seen_by(world.a.user(role)) == full, role
    agronomist = world.a.user(UserRole.AGRONOMIST)
    assert await phone_seen_by(agronomist) == masked
    resp = await client.get(f"/v1/farmers/{farmer.id}", headers=bearer(agronomist))
    assert full not in resp.text
    managers = [
        u
        for u in world.a.everyone
        if u.role == UserRole.STORE_MANAGER and u.store_id == officer.store_id
    ]
    for manager in managers:
        assert await phone_seen_by(manager) == masked


def test_phone_reader_roles_match_the_user_directory() -> None:
    assert frozenset(UserRole(r) for r in USER_READ_ROLES) == PHONE_READER_ROLES


async def test_falls_back_to_the_village_store_officer_then_null(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    user, farmer = _own(world)
    registrar = _by_id(world, farmer.registered_by)
    async with tenant_scope(db_session, world.a.tenant.id):
        store_id = (
            await db_session.execute(
                select(Village.store_id).where(Village.id == farmer.village_id)
            )
        ).scalar_one()
        # the store's existing officers leave; two new ones join, the older one is chosen
        await db_session.execute(
            update(User)
            .where(User.store_id == store_id, User.role == UserRole.FIELD_OFFICER)
            .values(status=UserStatus.DISABLED)
        )
        await db_session.execute(
            update(User).where(User.id == registrar.id).values(status=UserStatus.DISABLED)
        )
        senior, junior, disabled = (
            User(
                tenant_id=world.a.tenant.id,
                phone=f"+91900070000{i}",
                name=name,
                role=UserRole.FIELD_OFFICER,
                store_id=store_id,
                status=state,
                created_at=datetime(2026, 1, 1 + i, tzinfo=UTC),
            )
            for i, name, state in (
                (2, "Senior officer", UserStatus.ACTIVE),
                (3, "Junior officer", UserStatus.ACTIVE),
                (1, "Disabled officer", UserStatus.DISABLED),
            )
        )
        db_session.add_all([senior, junior, disabled])
        await db_session.flush()

    resp = await client.get(f"/v1/farmers/{farmer.id}", headers=bearer(user))
    assert resp.status_code == 200, resp.text
    assert resp.json()["officer"] == {
        "id": str(senior.id),
        "name": "Senior officer",
        "phone": "+919000700002",
    }
    me = await client.get("/v1/me", headers=bearer(user))
    assert me.json()["officer"]["id"] == str(senior.id)
    agronomist = world.a.user(UserRole.AGRONOMIST)
    agro = await client.get(f"/v1/farmers/{farmer.id}", headers=bearer(agronomist))
    assert agro.json()["officer"]["phone"] == "+91******0002"

    # nobody active at the store either -> null
    async with tenant_scope(db_session, world.a.tenant.id):
        await db_session.execute(
            update(User)
            .where(User.id.in_([senior.id, junior.id]))
            .values(deleted_at=datetime.now(UTC))
        )
        await db_session.flush()
    resp = await client.get(f"/v1/farmers/{farmer.id}", headers=bearer(world.a.owner))
    assert resp.status_code == 200 and resp.json()["officer"] is None
    me = await client.get("/v1/me", headers=bearer(user))
    assert me.status_code == 200 and me.json()["officer"] is None


async def test_registrar_who_is_no_longer_a_field_officer_is_skipped(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    _, farmer = _own(world)
    registrar = _by_id(world, farmer.registered_by)
    async with tenant_scope(db_session, world.a.tenant.id):
        await db_session.execute(
            update(User).where(User.id == registrar.id).values(role=UserRole.STORE_MANAGER)
        )
        await db_session.flush()
    resp = await client.get(f"/v1/farmers/{farmer.id}", headers=bearer(world.a.owner))
    assert resp.status_code == 200
    officer = resp.json()["officer"]
    assert officer is None or officer["id"] != str(registrar.id)


async def test_farmer_without_a_record_has_no_officer(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    user, farmer = _own(world)
    async with tenant_scope(db_session, world.a.tenant.id):
        await db_session.execute(
            update(Farmer).where(Farmer.id == farmer.id).values(deleted_at=datetime.now(UTC))
        )
        await db_session.flush()
    me = await client.get("/v1/me", headers=bearer(user))
    assert me.status_code == 200 and me.json()["officer"] is None
