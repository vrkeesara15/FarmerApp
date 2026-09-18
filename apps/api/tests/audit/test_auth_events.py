"""Login and logout are audited through the explicit ``audit.record`` API (non-ORM events),
and the rows written for the auth tables never contain hashes or full phone numbers."""

from __future__ import annotations

import json
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.deps import AuthServices
from farmerapp.auth.models import OtpChallenge, RefreshToken, UserRole
from farmerapp.auth.providers import FakeProvider
from farmerapp.db.models import AuditLog
from tests.audit.conftest import (
    CLIENT_IP,
    REQUEST_HEADERS,
    TRACE,
    USER_AGENT,
    audit_rows,
    one_audit_row,
)
from tests.auth.conftest import last_code
from tests.authz.conftest import World


async def _login(
    client: AsyncClient, sms: FakeProvider, phone: str, device_id: str
) -> dict[str, Any]:
    resp = await client.post(
        "/v1/auth/otp/send", json={"phone": phone, "device_id": device_id}, headers=REQUEST_HEADERS
    )
    assert resp.status_code == 202, resp.text
    resp = await client.post(
        "/v1/auth/otp/verify",
        json={"phone": phone, "code": last_code(sms, phone), "device_id": device_id},
        headers=REQUEST_HEADERS,
    )
    assert resp.status_code == 200, resp.text
    body: dict[str, Any] = resp.json()
    return body


async def test_otp_verify_success_records_auth_login(
    client: AsyncClient,
    world: World,
    auth_services: AuthServices,
    sms: FakeProvider,
    db_session: AsyncSession,
) -> None:
    officer = world.a.user(UserRole.FIELD_OFFICER)
    await _login(client, sms, officer.phone, "officer-phone")

    row = await one_audit_row(db_session, action="auth.login", entity_id=officer.id)
    assert row.tenant_id == world.a.tenant.id
    assert row.actor_id == officer.id and row.actor_role == "field_officer"
    assert row.entity == "user"
    assert row.before is None
    assert row.after == {"device_id": "officer-phone", "channel": "sms"}
    assert row.device_id == "officer-phone"
    assert row.ip == CLIENT_IP and row.user_agent == USER_AGENT and row.trace_id == TRACE

    # The refresh token issued at login is an ORM insert audited by the generic listener,
    # attributed to the user who just logged in; its hash is never recorded.
    token_row = await one_audit_row(db_session, action="refresh_token.create")
    assert token_row.actor_id == officer.id
    assert token_row.after is not None and "token_hash" not in token_row.after
    assert token_row.after["user_id"] == str(officer.id)


async def test_failed_otp_does_not_record_login(
    client: AsyncClient,
    world: World,
    auth_services: AuthServices,
    sms: FakeProvider,
    db_session: AsyncSession,
) -> None:
    officer = world.a.user(UserRole.FIELD_OFFICER)
    resp = await client.post("/v1/auth/otp/send", json={"phone": officer.phone})
    assert resp.status_code == 202
    resp = await client.post("/v1/auth/otp/verify", json={"phone": officer.phone, "code": "000000"})
    assert resp.status_code == 401
    assert await audit_rows(db_session, action="auth.login") == []


async def test_logout_records_auth_logout(
    client: AsyncClient,
    world: World,
    auth_services: AuthServices,
    sms: FakeProvider,
    db_session: AsyncSession,
) -> None:
    officer = world.a.user(UserRole.FIELD_OFFICER)
    tokens = await _login(client, sms, officer.phone, "officer-phone")
    resp = await client.post(
        "/v1/auth/logout", json={"refresh_token": tokens["refresh_token"]}, headers=REQUEST_HEADERS
    )
    assert resp.status_code == 204, resp.text
    row = await one_audit_row(db_session, action="auth.logout", entity_id=officer.id)
    assert row.actor_id == officer.id and row.actor_role == "field_officer"
    assert row.entity == "user" and row.tenant_id == world.a.tenant.id
    assert row.device_id == "officer-phone" and row.trace_id == TRACE
    assert row.after is not None and "family_id" in row.after

    # Idempotent logout of an unknown token audits nothing (nothing happened).
    resp = await client.post("/v1/auth/logout", json={"refresh_token": "nope"})
    assert resp.status_code == 204
    assert len(await audit_rows(db_session, action="auth.logout")) == 1


async def test_auth_tables_never_leak_secrets_or_full_phones(
    client: AsyncClient,
    world: World,
    auth_services: AuthServices,
    sms: FakeProvider,
    db_session: AsyncSession,
) -> None:
    officer = world.a.user(UserRole.FIELD_OFFICER)
    await _login(client, sms, officer.phone, "officer-phone")
    challenge = (
        await db_session.execute(select(OtpChallenge).where(OtpChallenge.phone == officer.phone))
    ).scalar_one()
    token = (await db_session.execute(select(RefreshToken))).scalars().first()
    assert token is not None
    rows = (await db_session.execute(select(AuditLog))).scalars().all()
    assert {r.entity for r in rows} >= {"otp_challenge", "refresh_token", "user"}
    blob = json.dumps([(r.before, r.after) for r in rows])
    assert challenge.code_hash not in blob
    assert token.token_hash not in blob
    assert officer.phone not in blob
    assert "+91******0004" in blob  # masked to the last 4 digits (otp_challenge.create)
    for r in rows:
        for payload in (r.before, r.after):
            if payload:
                assert "code_hash" not in payload and "token_hash" not in payload
