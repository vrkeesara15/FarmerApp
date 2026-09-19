"""FA-001 acceptance: send, verify, lockout, expiry, resend limit, single use, fallback.

SEC-021: code hashed at rest (HMAC-SHA256 + pepper), constant-time compare, single use.
"""

from __future__ import annotations

import logging
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import PROBLEM_MEDIA_TYPE
from farmerapp.auth.clock import FakeClock
from farmerapp.auth.models import OtpChallenge, User
from farmerapp.auth.otp import hash_code
from farmerapp.auth.providers import FakeProvider
from farmerapp.auth.scheduler import InProcessScheduler
from farmerapp.settings import get_settings
from tests.auth.conftest import DEVICE, OFFICER_PHONE, last_code, login, send_otp
from tests.logcontract import assert_fields, capture, one_event

pytestmark = pytest.mark.usefixtures("officer")


def _problem(resp: Any, status: int, code: str) -> dict[str, Any]:
    assert resp.status_code == status, resp.text
    assert resp.headers["content-type"].startswith(PROBLEM_MEDIA_TYPE)
    body: dict[str, Any] = resp.json()
    assert body["code"] == code
    return body


async def _verify(client: AsyncClient, code: str, phone: str = OFFICER_PHONE) -> Any:
    return await client.post(
        "/v1/auth/otp/verify", json={"phone": phone, "code": code, "device_id": DEVICE}
    )


# ---------------------------------------------------------------- send


async def test_send_creates_challenge_and_sms(
    client: AsyncClient, sms: FakeProvider, db_session: AsyncSession
) -> None:
    body = await send_otp(client)
    assert body["channel"] == "sms"
    assert body["expires_in"] == 300
    assert body["resends_left"] == 3
    assert body["phone_masked"] == "+91******0004"
    assert len(sms.sent) == 1
    msg = sms.sent[0]
    assert msg.to == OFFICER_PHONE
    code = last_code(sms, OFFICER_PHONE)
    assert len(code) == 6 and code.isdigit()

    challenge = (await db_session.execute(select(OtpChallenge))).scalar_one()
    assert challenge.phone == OFFICER_PHONE
    assert challenge.purpose == "login"
    assert challenge.channel == "sms"
    assert challenge.sms_sent_at is not None
    assert challenge.attempts == 0


async def test_code_is_hashed_at_rest(
    client: AsyncClient, sms: FakeProvider, db_session: AsyncSession
) -> None:
    await send_otp(client)
    code = last_code(sms, OFFICER_PHONE)
    challenge = (await db_session.execute(select(OtpChallenge))).scalar_one()
    assert code not in challenge.code_hash
    assert len(challenge.code_hash) == 64  # hex sha256
    assert challenge.code_hash == hash_code(get_settings().otp_pepper, challenge.id, code), (
        "HMAC-SHA256 over (challenge id, code) with the server pepper"
    )
    assert challenge.code_hash != hash_code("other-pepper", challenge.id, code)


async def test_send_accepts_national_format_and_normalises(
    client: AsyncClient, sms: FakeProvider
) -> None:
    body = await send_otp(client, "9000000004")
    assert body["phone_masked"] == "+91******0004"
    assert sms.sent[0].to == OFFICER_PHONE


@pytest.mark.parametrize("phone", ["12345", "+911234567890", "+1 555 0100", ""])
async def test_send_rejects_invalid_phone(client: AsyncClient, phone: str) -> None:
    resp = await client.post("/v1/auth/otp/send", json={"phone": phone})
    _problem(resp, 422, "validation_error")


async def test_send_unknown_user(client: AsyncClient, sms: FakeProvider) -> None:
    resp = await client.post("/v1/auth/otp/send", json={"phone": "+919111111111"})
    _problem(resp, 404, "user_not_found")
    assert sms.sent == []


async def test_send_disabled_user(
    client: AsyncClient, db_session: AsyncSession, officer: User
) -> None:
    officer.status = "disabled"
    await db_session.flush()
    resp = await client.post("/v1/auth/otp/send", json={"phone": OFFICER_PHONE})
    _problem(resp, 403, "user_disabled")


# ---------------------------------------------------------------- verify


async def test_verify_returns_tokens_and_profile(
    client: AsyncClient, sms: FakeProvider, db_session: AsyncSession, officer: User
) -> None:
    body = await login(client, sms)
    assert body["token_type"] == "Bearer"
    assert body["expires_in"] == 900
    assert body["access_token"].count(".") == 2
    assert len(body["refresh_token"]) >= 32
    user = body["user"]
    assert user["id"] == str(officer.id)
    assert user["tenant_id"] == str(officer.tenant_id)
    assert user["phone"] == OFFICER_PHONE
    assert user["role"] == "field_officer"
    assert user["name"] == "Ramesh"
    assert user["language"] == "te"
    assert user["status"] == "active"
    await db_session.refresh(officer)
    assert officer.device_id == DEVICE

    challenge = (await db_session.execute(select(OtpChallenge))).scalar_one()
    assert challenge.consumed_at is not None


async def test_wrong_code_reports_attempts_left(client: AsyncClient, sms: FakeProvider) -> None:
    await send_otp(client)
    body = _problem(await _verify(client, "000000"), 401, "otp_invalid")
    assert body["attempts_left"] == 4
    body = _problem(await _verify(client, "000001"), 401, "otp_invalid")
    assert body["attempts_left"] == 3
    # A correct code after two misses still works.
    resp = await _verify(client, last_code(sms, OFFICER_PHONE))
    assert resp.status_code == 200


async def test_lockout_after_five_wrong_attempts(
    client: AsyncClient, sms: FakeProvider, clock: FakeClock
) -> None:
    await send_otp(client)
    real = last_code(sms, OFFICER_PHONE)
    wrong = "999999" if real != "999999" else "111111"
    for i in range(4):
        body = _problem(await _verify(client, wrong), 401, "otp_invalid")
        assert body["attempts_left"] == 4 - i
    body = _problem(await _verify(client, wrong), 423, "otp_locked")
    assert body["retry_after"] == 900

    # Correct code is rejected while locked, and so is a new send.
    _problem(await _verify(client, real), 423, "otp_locked")
    _problem(
        await client.post("/v1/auth/otp/send", json={"phone": OFFICER_PHONE}), 423, "otp_locked"
    )

    # After the lockout window a fresh OTP can be requested and used.
    clock.advance(900)
    await send_otp(client)
    resp = await _verify(client, last_code(sms, OFFICER_PHONE))
    assert resp.status_code == 200, resp.text


async def test_code_expires_after_five_minutes(
    client: AsyncClient, sms: FakeProvider, clock: FakeClock
) -> None:
    await send_otp(client)
    code = last_code(sms, OFFICER_PHONE)
    clock.advance(299)
    # still valid at 4:59 -> but don't consume it; check with a wrong code first
    _problem(await _verify(client, "000000"), 401, "otp_invalid")
    clock.advance(2)
    _problem(await _verify(client, code), 401, "otp_expired")


async def test_code_is_single_use(client: AsyncClient, sms: FakeProvider) -> None:
    await send_otp(client)
    code = last_code(sms, OFFICER_PHONE)
    assert (await _verify(client, code)).status_code == 200
    _problem(await _verify(client, code), 404, "otp_not_found")


async def test_verify_without_challenge(client: AsyncClient) -> None:
    _problem(await _verify(client, "123456"), 404, "otp_not_found")


async def test_resend_supersedes_previous_code(client: AsyncClient, sms: FakeProvider) -> None:
    await send_otp(client)
    first = last_code(sms, OFFICER_PHONE)
    body = await send_otp(client)
    assert body["resends_left"] == 2
    second = last_code(sms, OFFICER_PHONE)
    assert len(sms.sent) == 2
    if first != second:  # 1-in-a-million collision would make the first code valid again
        _problem(await _verify(client, first), 401, "otp_invalid")
    assert (await _verify(client, second)).status_code == 200


async def test_fourth_resend_within_window_is_rate_limited(
    client: AsyncClient, sms: FakeProvider, clock: FakeClock
) -> None:
    await send_otp(client)  # initial
    for left in (2, 1, 0):
        clock.advance(31)
        body = await send_otp(client)  # resends 1..3
        assert body["resends_left"] == left
    clock.advance(31)
    body = _problem(
        await client.post("/v1/auth/otp/send", json={"phone": OFFICER_PHONE}),
        429,
        "otp_rate_limited",
    )
    assert 0 < body["retry_after"] <= 900
    assert len(sms.sent) == 4
    # Window is 15 min from the first send.
    clock.advance(body["retry_after"])
    body = await send_otp(client)
    assert body["resends_left"] == 3


async def test_dev_code_accepted_only_when_configured(
    client: AsyncClient, sms: FakeProvider, monkeypatch: pytest.MonkeyPatch, app: FastAPI
) -> None:
    await send_otp(client)
    _problem(await _verify(client, "123456"), 401, "otp_invalid")
    app.state.auth.settings = get_settings().model_copy(update={"otp_dev_code": "123456"})
    resp = await _verify(client, "123456")
    assert resp.status_code == 200, resp.text


# ---------------------------------------------------------------- WhatsApp fallback


async def test_whatsapp_fallback_when_sms_not_delivered_in_30s(
    client: AsyncClient,
    sms: FakeProvider,
    whatsapp: FakeProvider,
    clock: FakeClock,
    scheduler: InProcessScheduler,
    db_session: AsyncSession,
) -> None:
    sms.auto_deliver = False
    await send_otp(client)
    assert len(scheduler.pending) == 1
    clock.advance(29)
    assert await scheduler.run_due(db_session) == 0
    assert whatsapp.sent == []
    clock.advance(2)
    assert await scheduler.run_due(db_session) == 1
    assert len(whatsapp.sent) == 1
    assert whatsapp.sent[0].to == OFFICER_PHONE
    challenge = (await db_session.execute(select(OtpChallenge))).scalar_one()
    await db_session.refresh(challenge)
    assert challenge.channel == "whatsapp"
    assert challenge.whatsapp_sent_at is not None
    assert challenge.delivered_at is None
    # The same code works, whichever channel carried it.
    assert last_code(whatsapp, OFFICER_PHONE) == last_code(sms, OFFICER_PHONE)
    resp = await _verify(client, last_code(whatsapp, OFFICER_PHONE))
    assert resp.status_code == 200


async def test_no_fallback_when_sms_delivered(
    client: AsyncClient,
    sms: FakeProvider,
    whatsapp: FakeProvider,
    clock: FakeClock,
    scheduler: InProcessScheduler,
    db_session: AsyncSession,
) -> None:
    await send_otp(client)
    clock.advance(31)
    assert await scheduler.run_due(db_session) == 1
    assert whatsapp.sent == []
    challenge = (await db_session.execute(select(OtpChallenge))).scalar_one()
    await db_session.refresh(challenge)
    assert challenge.delivered_at is not None
    assert challenge.channel == "sms"


async def test_no_fallback_when_already_verified(
    client: AsyncClient,
    sms: FakeProvider,
    whatsapp: FakeProvider,
    clock: FakeClock,
    scheduler: InProcessScheduler,
    db_session: AsyncSession,
) -> None:
    sms.auto_deliver = False
    await login(client, sms)
    clock.advance(31)
    await scheduler.run_due(db_session)
    assert whatsapp.sent == []


# ---------------------------------------------------------------- logging hygiene


async def test_logs_never_contain_code_or_full_phone(
    client: AsyncClient, sms: FakeProvider, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.INFO, logger="farmerapp.auth")
    await send_otp(client)
    code = last_code(sms, OFFICER_PHONE)
    await _verify(client, "000000")
    await _verify(client, code)
    records = [r for r in caplog.records if r.name.startswith("farmerapp.auth")]
    assert records, "auth events must be logged"
    events = {
        str(r.msg.get("event")) if isinstance(r.msg, dict) else r.getMessage() for r in records
    }
    assert {"otp_sent", "otp_failed", "otp_verified"} <= events
    for r in records:
        text = str(r.msg)
        assert code not in text
        assert OFFICER_PHONE not in text
        assert "0004" in text  # masked suffix is kept for support


# ---------------------------------------------------------------- provider failure / edge cases


async def test_sms_provider_failure_falls_back_to_whatsapp_immediately(
    client: AsyncClient, sms: FakeProvider, whatsapp: FakeProvider, db_session: AsyncSession
) -> None:
    from farmerapp.auth.providers import ProviderError

    async def broken(to: str, body: str) -> str:
        raise ProviderError("gateway down")

    sms.send_sms = broken  # type: ignore[method-assign]
    body = await send_otp(client)
    assert body["channel"] == "whatsapp"
    assert len(whatsapp.sent) == 1
    challenge = (await db_session.execute(select(OtpChallenge))).scalar_one()
    assert challenge.sms_sent_at is None and challenge.whatsapp_sent_at is not None
    resp = await _verify(client, last_code(whatsapp, OFFICER_PHONE))
    assert resp.status_code == 200


async def test_verify_rejects_user_disabled_after_send(
    client: AsyncClient, sms: FakeProvider, db_session: AsyncSession, officer: User
) -> None:
    await send_otp(client)
    officer.status = "disabled"
    await db_session.flush()
    _problem(await _verify(client, last_code(sms, OFFICER_PHONE)), 403, "user_disabled")


async def test_verify_rejects_user_deleted_after_send(
    client: AsyncClient,
    sms: FakeProvider,
    db_session: AsyncSession,
    officer: User,
    clock: FakeClock,
) -> None:
    await send_otp(client)
    officer.deleted_at = clock.now()
    await db_session.flush()
    _problem(await _verify(client, last_code(sms, OFFICER_PHONE)), 404, "user_not_found")


async def test_delivery_check_skips_expired_challenge(
    client: AsyncClient,
    sms: FakeProvider,
    whatsapp: FakeProvider,
    clock: FakeClock,
    scheduler: InProcessScheduler,
    db_session: AsyncSession,
) -> None:
    sms.auto_deliver = False
    await send_otp(client)
    clock.advance(301)
    await scheduler.run_due(db_session)
    assert whatsapp.sent == []


async def test_scheduler_tick_runs_due_tasks(
    client: AsyncClient,
    sms: FakeProvider,
    whatsapp: FakeProvider,
    clock: FakeClock,
    scheduler: InProcessScheduler,
    db_session: AsyncSession,
) -> None:
    """``tick`` is what the API lifespan calls every second in local runs."""
    import contextlib
    from collections.abc import AsyncIterator

    from farmerapp.auth.deps import tick

    @contextlib.asynccontextmanager
    async def provider() -> AsyncIterator[AsyncSession]:
        yield db_session

    sms.auto_deliver = False
    await send_otp(client)
    assert await tick(scheduler, provider) == 0
    clock.advance(31)
    assert await tick(scheduler, provider) == 1
    assert len(whatsapp.sent) == 1


# ---------------------------------------------------------------- NF-014 log contract
async def test_otp_sent_and_delivered_log_contract(
    client: AsyncClient,
    sms: FakeProvider,
    clock: FakeClock,
    scheduler: InProcessScheduler,
    db_session: AsyncSession,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """``farmerapp_otp_sent{channel}`` / ``farmerapp_otp_delivered`` (OTP delivery SLO)."""
    capture(caplog)
    await send_otp(client)
    sent = one_event(caplog, "otp_sent")
    assert_fields(sent, channel=str, purpose=str, tenant_id=str, phone=str)
    assert sent["channel"] == "sms" and sent["purpose"] == "login"
    assert sent["phone"] == "+91******0004"  # masked, never the number
    clock.advance(31)
    assert await scheduler.run_due(db_session) == 1
    delivered = one_event(caplog, "otp_delivered")
    assert_fields(delivered, channel=str, tenant_id=str, challenge_id=str)
    assert delivered["tenant_id"] == sent["tenant_id"]
    assert delivered["challenge_id"] == sent["challenge_id"]


async def test_otp_whatsapp_fallback_log_contract(
    client: AsyncClient,
    sms: FakeProvider,
    clock: FakeClock,
    scheduler: InProcessScheduler,
    db_session: AsyncSession,
    caplog: pytest.LogCaptureFixture,
) -> None:
    capture(caplog)
    sms.auto_deliver = False
    await send_otp(client)
    clock.advance(31)
    await scheduler.run_due(db_session)
    fallback = one_event(caplog, "otp_fallback_whatsapp")
    assert_fields(fallback, challenge_id=str, phone=str)
