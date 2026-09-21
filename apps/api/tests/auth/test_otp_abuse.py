"""SEC-021 SMS pumping protection: country rules, velocity, block list, cost guard.

FA-001 covers hashing, constant-time compare, single use and the per-window resend cap
(tests/auth/test_otp.py). These tests cover the four layers that stop an attacker farming
OTP sends: a foreign number is refused outright, a number or IP that walks the resend window
is blocked and stays blocked longer on a repeat, and the tenant's hourly budget alerts and
then opens a breaker.
"""

from __future__ import annotations

import json
import uuid
from datetime import timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import PROBLEM_MEDIA_TYPE
from farmerapp.auth import otp_abuse
from farmerapp.auth.clock import FakeClock
from farmerapp.auth.models import OtpBlock, OtpBlockScope, OtpChallenge, User, UserRole
from farmerapp.auth.providers import FakeProvider
from farmerapp.db.models import Tenant
from farmerapp.settings import Settings, get_settings
from tests.auth.conftest import OFFICER_PHONE, send_otp
from tests.logcontract import capture, json_events

pytestmark = pytest.mark.usefixtures("officer")

FOREIGN_PHONE = "+15551230000"
IP_A = "203.0.113.10"
IP_B = "203.0.113.11"


def _problem(resp: Any, status: int, code: str) -> dict[str, Any]:
    assert resp.status_code == status, resp.text
    assert resp.headers["content-type"].startswith(PROBLEM_MEDIA_TYPE)
    body: dict[str, Any] = resp.json()
    assert body["code"] == code
    return body


async def _send(client: AsyncClient, *, phone: str = OFFICER_PHONE, ip: str | None = None) -> Any:
    headers = {"X-Forwarded-For": ip} if ip else {}
    return await client.post("/v1/auth/otp/send", json={"phone": phone}, headers=headers)


# --------------------------------------------------------------------------- country
def test_country_prefix_picks_the_longest_match() -> None:
    assert otp_abuse.country_prefix("+919000000004", ["+91", "+9"]) == "+91"
    assert otp_abuse.country_prefix("+15551230000", ["+91"]) is None


def test_india_only_by_default() -> None:
    settings = get_settings()
    assert settings.otp_allowed_country_codes == ["+91"], "SEC-021: India only until reviewed"
    otp_abuse.check_country(OFFICER_PHONE, settings)
    with pytest.raises(otp_abuse.OtpCountryBlockedError):
        otp_abuse.check_country(FOREIGN_PHONE, settings)


def test_block_list_wins_over_the_allow_list() -> None:
    settings = get_settings().model_copy(
        update={"otp_allowed_country_codes": ["+91", "+1"], "otp_blocked_country_codes": ["+1"]}
    )
    otp_abuse.check_country(OFFICER_PHONE, settings)
    with pytest.raises(otp_abuse.OtpCountryBlockedError):
        otp_abuse.check_country(FOREIGN_PHONE, settings)


async def test_send_to_a_foreign_number_is_refused_before_any_sms(
    db_session: AsyncSession,
    tenant: Tenant,
    sms: FakeProvider,
    auth_services: Any,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """The HTTP schema already refuses a non-Indian number (SEC-022, 422 validation_error);
    this is the layer *behind* it, for the send paths whose phone comes from the database
    (step-up, farmer confirmation, jobs)."""
    user = User(
        tenant_id=tenant.id, phone=FOREIGN_PHONE, name="Abroad", role=UserRole.FIELD_OFFICER
    )
    db_session.add(user)
    await db_session.flush()
    capture(caplog)
    with pytest.raises(otp_abuse.OtpCountryBlockedError) as exc:
        await auth_services.otp.send(db_session, phone=FOREIGN_PHONE, tenant_id=tenant.id)
    assert exc.value.status == 403
    assert sms.sent == [], "no SMS may leave for a blocked country"
    assert (await db_session.execute(select(OtpChallenge))).scalars().all() == []

    line = json_events(caplog, "otp_country_blocked")[-1]
    assert line["reason"] == "not_allowed"
    assert FOREIGN_PHONE not in json.dumps(line), "SEC-021 / FA-006: never log the full number"


async def test_the_http_schema_refuses_a_foreign_number_at_the_edge(client: AsyncClient) -> None:
    resp = await _send(client, phone=FOREIGN_PHONE)
    assert resp.status_code == 422
    assert resp.json()["code"] == "validation_error"


# --------------------------------------------------------------------------- block key
def test_block_keys_never_store_the_value() -> None:
    key = otp_abuse.block_key("pepper", OtpBlockScope.PHONE, OFFICER_PHONE)
    assert len(key) == 64 and OFFICER_PHONE not in key
    assert key != otp_abuse.block_key("pepper", OtpBlockScope.IP, OFFICER_PHONE), "scope is bound"
    assert key != otp_abuse.block_key("other", OtpBlockScope.PHONE, OFFICER_PHONE), "pepper keyed"


# --------------------------------------------------------------------------- velocity
async def _record_sends(
    db_session: AsyncSession, tenant: Tenant, count: int, clock: FakeClock, **extra: Any
) -> None:
    now = clock.now()
    for i in range(count):
        db_session.add(
            OtpChallenge(
                tenant_id=tenant.id,
                created_at=now - timedelta(seconds=i),
                phone=extra.get("phone", OFFICER_PHONE),
                purpose="login",
                code_hash="x" * 64,
                expires_at=now + timedelta(minutes=5),
                window_started_at=now,
                channel="sms",
                consumed_at=now,
                request_ip=extra.get("request_ip"),
            )
        )
    await db_session.flush()


async def test_per_phone_daily_cap_beyond_the_resend_window(
    client: AsyncClient,
    db_session: AsyncSession,
    tenant: Tenant,
    clock: FakeClock,
    sms: FakeProvider,
) -> None:
    """The 3-per-15-min resend cap only covers one window; this covers the whole day."""
    settings = get_settings()
    await _record_sends(db_session, tenant, settings.otp_max_sends_per_phone_day, clock)
    body = _problem(await _send(client), 429, "otp_rate_limited")
    assert body["retry_after"] == otp_abuse.PHONE_WINDOW_SECONDS
    assert sms.sent == []

    block = (await db_session.execute(select(OtpBlock))).scalar_one()
    assert block.scope == OtpBlockScope.PHONE
    assert block.reason == "phone_velocity"
    assert block.strikes == 1
    assert block.key_hash == otp_abuse.block_key(
        settings.otp_pepper, OtpBlockScope.PHONE, OFFICER_PHONE
    )


async def test_per_ip_hourly_cap_across_numbers(
    client: AsyncClient,
    db_session: AsyncSession,
    tenant: Tenant,
    clock: FakeClock,
    sms: FakeProvider,
) -> None:
    settings = get_settings()
    # Sends from one IP to other numbers of the tenant: the phone cap is untouched.
    await _record_sends(
        db_session,
        tenant,
        settings.otp_max_sends_per_ip_hour,
        clock,
        phone="+919000000099",
        request_ip=IP_A,
    )
    body = _problem(await _send(client, ip=IP_A), 429, "otp_rate_limited")
    assert body["retry_after"] == otp_abuse.IP_WINDOW_SECONDS
    assert sms.sent == []
    # A different IP is unaffected.
    assert (await _send(client, ip=IP_B)).status_code == 202


async def test_repeat_abusers_stay_blocked_longer(
    db_session: AsyncSession, tenant: Tenant, clock: FakeClock
) -> None:
    settings = get_settings()
    now = clock.now()
    first = await otp_abuse.record_strike(
        db_session,
        tenant_id=tenant.id,
        scope=OtpBlockScope.IP,
        value=IP_A,
        reason="ip_velocity",
        now=now,
        settings=settings,
    )
    first_window = first.blocked_until - now
    second = await otp_abuse.record_strike(
        db_session,
        tenant_id=tenant.id,
        scope=OtpBlockScope.IP,
        value=IP_A,
        reason="ip_velocity",
        now=now,
        settings=settings,
    )
    assert second.id == first.id, "one row per key, not a new block each time"
    assert second.strikes == 2
    assert second.blocked_until - now == first_window * 2
    assert (await db_session.execute(select(OtpBlock))).scalars().all() == [second]


async def test_a_block_is_capped_at_thirty_days(
    db_session: AsyncSession, tenant: Tenant, clock: FakeClock
) -> None:
    settings = get_settings()
    now = clock.now()
    row = None
    for _ in range(12):
        row = await otp_abuse.record_strike(
            db_session,
            tenant_id=tenant.id,
            scope=OtpBlockScope.PHONE,
            value=OFFICER_PHONE,
            reason="phone_velocity",
            now=now,
            settings=settings,
        )
    assert row is not None
    assert row.blocked_until - now == timedelta(seconds=otp_abuse.MAX_BLOCK_SECONDS)


async def test_an_active_block_refuses_the_send_and_expires(
    client: AsyncClient,
    db_session: AsyncSession,
    tenant: Tenant,
    clock: FakeClock,
    sms: FakeProvider,
) -> None:
    settings = get_settings()
    now = clock.now()
    await otp_abuse.record_strike(
        db_session,
        tenant_id=tenant.id,
        scope=OtpBlockScope.PHONE,
        value=OFFICER_PHONE,
        reason="phone_velocity",
        now=now,
        settings=settings,
    )
    body = _problem(await _send(client), 429, "otp_blocked")
    assert 0 < body["retry_after"] <= settings.otp_abuse_block_seconds
    assert sms.sent == []

    clock.advance(timedelta(seconds=settings.otp_abuse_block_seconds + 1))
    assert (await _send(client)).status_code == 202, "the block expires on its own"


async def test_a_blocked_ip_is_refused_even_for_a_clean_number(
    client: AsyncClient, db_session: AsyncSession, tenant: Tenant, clock: FakeClock
) -> None:
    await otp_abuse.record_strike(
        db_session,
        tenant_id=tenant.id,
        scope=OtpBlockScope.IP,
        value=IP_A,
        reason="ip_velocity",
        now=clock.now(),
        settings=get_settings(),
    )
    _problem(await _send(client, ip=IP_A), 429, "otp_blocked")
    assert (await _send(client, ip=IP_B)).status_code == 202


# --------------------------------------------------------------------------- cost guard
async def test_cost_guard_alerts_without_refusing(
    client: AsyncClient,
    db_session: AsyncSession,
    tenant: Tenant,
    clock: FakeClock,
    caplog: pytest.LogCaptureFixture,
) -> None:
    settings = get_settings()
    await _record_sends(
        db_session, tenant, settings.otp_cost_alert_per_hour, clock, phone="+919000000098"
    )
    capture(caplog)
    assert (await _send(client)).status_code == 202, "an alert never refuses a login"
    alerts = json_events(caplog, "otp_cost_alert")
    assert alerts and alerts[-1]["threshold"] == settings.otp_cost_alert_per_hour
    assert alerts[-1]["severity"] == "ERROR"


async def test_cost_guard_opens_the_breaker_at_the_hard_limit(
    client: AsyncClient, db_session: AsyncSession, tenant: Tenant, clock: FakeClock
) -> None:
    settings = get_settings().model_copy(update={"otp_cost_block_per_hour": 5})
    await _record_sends(db_session, tenant, 5, clock, phone="+919000000097")
    with pytest.raises(otp_abuse.OtpCostLimitedError) as exc:
        await otp_abuse.check_cost(
            db_session, tenant_id=tenant.id, now=clock.now(), settings=settings
        )
    assert exc.value.status == 429
    assert exc.value.code == "otp_cost_limited"


async def test_the_cost_guard_counts_only_this_tenant(
    db_session: AsyncSession, tenant: Tenant, clock: FakeClock
) -> None:
    await _record_sends(db_session, tenant, 3, clock)
    sends = await otp_abuse.check_cost(
        db_session, tenant_id=tenant.id, now=clock.now(), settings=get_settings()
    )
    assert sends == 3
    other = await otp_abuse.check_cost(
        db_session, tenant_id=uuid.uuid4(), now=clock.now(), settings=get_settings()
    )
    assert other == 0


# --------------------------------------------------------------------------- happy path
async def test_a_normal_login_send_records_its_ip_and_stays_allowed(
    client: AsyncClient, db_session: AsyncSession, sms: FakeProvider
) -> None:
    await send_otp(client)  # no X-Forwarded-For: the socket peer is recorded
    with_ip = await _send(client, ip=IP_A)
    assert with_ip.status_code == 202
    rows = (
        (await db_session.execute(select(OtpChallenge).order_by(OtpChallenge.created_at)))
        .scalars()
        .all()
    )
    assert rows[-1].request_ip == IP_A
    assert len(sms.sent) == 2


def test_every_layer_has_a_stable_problem_code() -> None:
    """The client contract: the app shows a different message for each (FM-001)."""
    assert otp_abuse.OtpCountryBlockedError.status == 403
    assert otp_abuse.OtpCountryBlockedError.code == "otp_country_blocked"
    assert otp_abuse.OtpBlockedError.status == 429
    assert otp_abuse.OtpBlockedError.code == "otp_blocked"
    assert otp_abuse.OtpCostLimitedError.status == 429
    assert otp_abuse.OtpCostLimitedError.code == "otp_cost_limited"


def test_defaults_are_the_documented_windows() -> None:
    settings = Settings()
    assert settings.otp_max_sends_per_phone_day == 10
    assert settings.otp_max_sends_per_ip_hour == 20
    assert settings.otp_abuse_block_seconds == 86_400
    assert settings.otp_cost_alert_per_hour < settings.otp_cost_block_per_hour
