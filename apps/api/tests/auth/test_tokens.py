"""SEC-020: 15-min access, 30-day refresh with rotation, reuse detection, device binding."""

from __future__ import annotations

from typing import Any

import jwt
import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.clock import FakeClock
from farmerapp.auth.models import RefreshToken, User
from farmerapp.auth.providers import FakeProvider
from farmerapp.settings import get_settings
from tests.auth.conftest import DEVICE

pytestmark = pytest.mark.usefixtures("officer")


async def _refresh(client: AsyncClient, token: str, device_id: str | None = DEVICE) -> Any:
    body: dict[str, Any] = {"refresh_token": token}
    if device_id is not None:
        body["device_id"] = device_id
    return await client.post("/v1/auth/refresh", json=body)


async def test_access_token_claims_and_lifetime(
    session_tokens: dict[str, Any], officer: User
) -> None:
    settings = get_settings()
    claims = jwt.decode(
        session_tokens["access_token"],
        settings.jwt_signing_key,
        algorithms=[settings.jwt_algorithm],
        # Issued against the FakeClock, so PyJWT's wall-clock checks do not apply here.
        options={"verify_exp": False, "verify_iat": False},
    )
    assert claims["sub"] == str(officer.id)
    assert claims["tid"] == str(officer.tenant_id)
    assert claims["role"] == "field_officer"
    assert claims["typ"] == "access"
    assert claims["exp"] - claims["iat"] == 900
    assert claims["jti"]


async def test_refresh_token_stored_hashed_and_bound(
    session_tokens: dict[str, Any], db_session: AsyncSession, clock: FakeClock
) -> None:
    raw = session_tokens["refresh_token"]
    row = (await db_session.execute(select(RefreshToken))).scalar_one()
    assert raw not in row.token_hash
    assert len(row.token_hash) == 64
    assert row.device_id == DEVICE
    assert row.revoked_at is None and row.replaced_by is None
    assert (row.expires_at - clock.now()).days == 30


async def test_refresh_rotates(
    client: AsyncClient, session_tokens: dict[str, Any], db_session: AsyncSession, clock: FakeClock
) -> None:
    clock.advance(60)
    resp = await _refresh(client, session_tokens["refresh_token"])
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["refresh_token"] != session_tokens["refresh_token"]
    assert body["access_token"] != session_tokens["access_token"]
    assert body["user"]["phone"] == "+919000000004"
    rows = (
        (await db_session.execute(select(RefreshToken).order_by(RefreshToken.created_at)))
        .scalars()
        .all()
    )
    assert len(rows) == 2
    old, new = rows
    assert old.family_id == new.family_id
    assert old.revoked_at is not None and old.replaced_by == new.id
    assert new.revoked_at is None
    # The new token works too.
    resp = await _refresh(client, body["refresh_token"])
    assert resp.status_code == 200


async def test_reuse_revokes_whole_family(
    client: AsyncClient, session_tokens: dict[str, Any], db_session: AsyncSession
) -> None:
    first = session_tokens["refresh_token"]
    second = (await _refresh(client, first)).json()["refresh_token"]
    # Replay of the rotated-out token: attacker or client bug -> kill the family.
    resp = await _refresh(client, first)
    assert resp.status_code == 401
    assert resp.json()["code"] == "refresh_reused"
    resp = await _refresh(client, second)
    assert resp.status_code == 401
    assert resp.json()["code"] == "refresh_reused"
    rows = (await db_session.execute(select(RefreshToken))).scalars().all()
    assert all(r.revoked_at is not None for r in rows)


async def test_refresh_expired(
    client: AsyncClient, session_tokens: dict[str, Any], clock: FakeClock
) -> None:
    clock.advance(30 * 86400 + 1)
    resp = await _refresh(client, session_tokens["refresh_token"])
    assert resp.status_code == 401
    assert resp.json()["code"] == "refresh_expired"


async def test_refresh_unknown_token(client: AsyncClient) -> None:
    resp = await _refresh(client, "not-a-real-refresh-token-at-all")
    assert resp.status_code == 401
    assert resp.json()["code"] == "refresh_invalid"


async def test_refresh_device_mismatch(client: AsyncClient, session_tokens: dict[str, Any]) -> None:
    resp = await _refresh(client, session_tokens["refresh_token"], device_id="other-device")
    assert resp.status_code == 401
    assert resp.json()["code"] == "refresh_device_mismatch"
    # A token bound to a device cannot be used without one either.
    resp = await _refresh(client, session_tokens["refresh_token"], device_id=None)
    assert resp.status_code == 401


async def test_console_login_without_device_is_unbound(
    client: AsyncClient, sms: FakeProvider, owner: User
) -> None:
    await client.post("/v1/auth/otp/send", json={"phone": owner.phone})
    from tests.auth.conftest import last_code

    resp = await client.post(
        "/v1/auth/otp/verify", json={"phone": owner.phone, "code": last_code(sms, owner.phone)}
    )
    assert resp.status_code == 200, resp.text
    resp = await _refresh(client, resp.json()["refresh_token"], device_id=None)
    assert resp.status_code == 200


async def test_logout_revokes_family(client: AsyncClient, session_tokens: dict[str, Any]) -> None:
    resp = await client.post(
        "/v1/auth/logout", json={"refresh_token": session_tokens["refresh_token"]}
    )
    assert resp.status_code == 204
    resp = await _refresh(client, session_tokens["refresh_token"])
    assert resp.status_code == 401
    # Idempotent: unknown / already revoked tokens still give 204.
    resp = await client.post("/v1/auth/logout", json={"refresh_token": "nope"})
    assert resp.status_code == 204


async def test_refresh_rejected_for_disabled_user(
    client: AsyncClient, session_tokens: dict[str, Any], officer: User, db_session: AsyncSession
) -> None:
    officer.status = "disabled"
    await db_session.flush()
    resp = await _refresh(client, session_tokens["refresh_token"])
    # SEC-025: a device-bound session of a disabled account is told to wipe the device.
    assert resp.status_code == 401
    assert resp.json()["code"] == "device_wipe_required"


async def test_access_token_with_bad_subject_is_rejected(client: AsyncClient) -> None:
    settings = get_settings()
    token = jwt.encode(
        {
            "iss": settings.jwt_issuer,
            "sub": "not-a-uuid",
            "tid": "x",
            "typ": "access",
            "exp": 4102444800,
        },
        settings.jwt_signing_key,
        algorithm=settings.jwt_algorithm,
    )
    resp = await client.get("/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 401
    assert resp.json()["code"] == "unauthenticated"


async def test_refresh_for_deleted_user(
    client: AsyncClient,
    session_tokens: dict[str, Any],
    officer: User,
    db_session: AsyncSession,
    clock: FakeClock,
) -> None:
    officer.deleted_at = clock.now()
    await db_session.flush()
    resp = await _refresh(client, session_tokens["refresh_token"])
    assert resp.status_code == 401
    assert resp.json()["code"] == "refresh_invalid"
