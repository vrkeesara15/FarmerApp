"""SEC-024 server side: Play Integrity tokens on login (and every sensitive action) are
verified through the ``PlayIntegrityVerifier`` port, recorded on the request and in the audit
rows, and **never block** — a failed or missing verdict is an integrity signal (VA-E01)."""

from __future__ import annotations

import asyncio
import json
from collections.abc import Sequence
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.providers import FakeProvider
from farmerapp.db.models import AuditLog
from farmerapp.integrity.verdict import (
    IntegrityStatus,
    evaluate,
    parse_actions,
    request_hash,
)
from farmerapp.integrity.verifier import (
    FakePlayIntegrityVerifier,
    GooglePlayIntegrityVerifier,
    IntegrityDecodeError,
    fake_token,
)
from tests.auth.conftest import DEVICE, OFFICER_PHONE, last_code, send_otp
from tests.logcontract import capture, json_events

pytestmark = pytest.mark.usefixtures("officer")

VERIFY = "/v1/auth/otp/verify"
AGENT = "in.farmerapp.mitra"


def payload(
    request_hash_value: str,
    *,
    package: str = AGENT,
    app: str = "PLAY_RECOGNIZED",
    device: Sequence[str] = ("MEETS_DEVICE_INTEGRITY",),
    at: datetime | None = None,
) -> dict[str, Any]:
    issued = at or datetime.now(UTC)
    return {
        "requestDetails": {
            "requestPackageName": package,
            "requestHash": request_hash_value,
            "timestampMillis": str(int(issued.timestamp() * 1000)),
        },
        "appIntegrity": {"appRecognitionVerdict": app},
        "deviceIntegrity": {"deviceRecognitionVerdict": list(device)},
    }


async def _login(
    client: AsyncClient, sms: FakeProvider, headers: dict[str, str] | None = None, **token: Any
) -> Any:
    await send_otp(client, device_id=DEVICE)
    body = json.dumps(
        {"phone": OFFICER_PHONE, "code": last_code(sms, OFFICER_PHONE), "device_id": DEVICE}
    ).encode()
    extra = dict(headers or {})
    if token.get("bind"):
        digest = request_hash("POST", VERIFY, body, "login")
        extra["X-Integrity-Token"] = fake_token(payload(digest, **token.get("claims", {})))
        extra["X-Integrity-Action"] = "login"
    resp = await client.post(
        VERIFY, content=body, headers={"Content-Type": "application/json", **extra}
    )
    assert resp.status_code == 200, resp.text  # never blocks
    return resp


async def _login_audit(db_session: AsyncSession) -> AuditLog:
    return (
        (
            await db_session.execute(
                select(AuditLog)
                .where(AuditLog.action == "auth.login")
                .order_by(AuditLog.created_at)
            )
        )
        .scalars()
        .all()[-1]
    )


@pytest.fixture
def verifier(app: FastAPI) -> FakePlayIntegrityVerifier:
    fake = FakePlayIntegrityVerifier()
    app.state.integrity = fake
    return fake


# ------------------------------------------------------------------ pure functions
def test_request_hash_matches_the_app_contract() -> None:
    import base64
    import hashlib

    body = b'{"phone":"+919000000004"}'
    material = f"POST\n{VERIFY}\n{hashlib.sha256(body).hexdigest()}\nlogin".encode()
    expected = base64.urlsafe_b64encode(hashlib.sha256(material).digest()).rstrip(b"=").decode()
    assert request_hash("post", VERIFY, body, "login") == expected
    assert "=" not in expected
    assert parse_actions(" credit_sale, payment_collection ,") == (
        "credit_sale",
        "payment_collection",
    )
    assert parse_actions(None) == ()


def test_evaluate_lists_every_failed_check() -> None:
    now = datetime.now(UTC)
    good = evaluate(payload("h"), expected_hash="h", packages=[AGENT], actions=("login",), now=now)
    assert good.status == IntegrityStatus.VERIFIED and good.reasons == ()
    bad = evaluate(
        payload(
            "other",
            package="com.evil",
            app="UNRECOGNIZED_VERSION",
            device=(),
            at=now - timedelta(hours=1),
        ),
        expected_hash="h",
        packages=[AGENT],
        actions=("login",),
        now=now,
    )
    assert bad.status == IntegrityStatus.FAILED and bad.is_signal
    assert set(bad.reasons) == {
        "package_mismatch",
        "request_hash_mismatch",
        "stale_token",
        "app_not_recognized",
        "device_integrity_missing",
    }
    garbage = evaluate({}, expected_hash="h", packages=[AGENT], actions=(), now=now)
    assert "stale_token" in garbage.reasons and garbage.package is None


# ------------------------------------------------------------------ login (API)
async def test_a_valid_token_is_verified_and_recorded_on_the_login_audit_row(
    client: AsyncClient,
    sms: FakeProvider,
    db_session: AsyncSession,
    verifier: FakePlayIntegrityVerifier,
) -> None:
    await _login(client, sms, bind=True)
    assert verifier.calls == 1
    row = await _login_audit(db_session)
    assert row.integrity is not None
    assert row.integrity["status"] == "verified" and row.integrity["actions"] == ["login"]
    assert row.integrity["package"] == AGENT
    assert row.integrity["device_verdicts"] == ["MEETS_DEVICE_INTEGRITY"]


async def test_a_token_for_another_request_fails_but_never_blocks(
    client: AsyncClient,
    sms: FakeProvider,
    db_session: AsyncSession,
    verifier: FakePlayIntegrityVerifier,
    caplog: pytest.LogCaptureFixture,
) -> None:
    capture(caplog)
    replayed = fake_token(payload("hash-of-some-other-request", device=("MEETS_BASIC_INTEGRITY",)))
    await _login(
        client,
        sms,
        headers={"X-Integrity-Token": replayed, "X-Integrity-Action": "login"},
    )
    row = await _login_audit(db_session)
    assert row.integrity is not None and row.integrity["status"] == "failed"
    assert set(row.integrity["reasons"]) == {"request_hash_mismatch", "device_integrity_missing"}
    signals = json_events(caplog, "integrity_signal")
    assert signals and signals[-1]["status"] == "failed" and signals[-1]["level"] == "warning"


async def test_undecodable_token_is_a_failed_verdict(
    client: AsyncClient,
    sms: FakeProvider,
    db_session: AsyncSession,
    verifier: FakePlayIntegrityVerifier,
) -> None:
    await _login(client, sms, headers={"X-Integrity-Token": "not-a-token"})
    row = await _login_audit(db_session)
    assert row.integrity is not None
    assert row.integrity["status"] == "failed" and row.integrity["reasons"] == ["token_invalid"]


async def test_unavailable_absent_and_verification_off(
    client: AsyncClient,
    sms: FakeProvider,
    db_session: AsyncSession,
    app: FastAPI,
    caplog: pytest.LogCaptureFixture,
) -> None:
    capture(caplog)
    app.state.integrity = FakePlayIntegrityVerifier()
    await _login(client, sms, headers={"X-Integrity-Status": "unavailable"})
    assert (await _login_audit(db_session)).integrity["status"] == "unavailable"  # type: ignore[index]
    # No header at all on a login: "absent" -> a signal (old app, or a scripted client).
    await _login(client, sms)
    assert (await _login_audit(db_session)).integrity["status"] == "absent"  # type: ignore[index]
    assert json_events(caplog, "integrity_signal")[-1]["status"] == "absent"
    # PLAY_INTEGRITY_MODE=off: the token is recorded as unverified, nothing is called.
    app.state.integrity = None
    await _login(client, sms, bind=True)
    row = await _login_audit(db_session)
    assert row.integrity["status"] == "unverified"  # type: ignore[index]
    assert row.integrity["reasons"] == ["verification_off"]  # type: ignore[index]


class _Broken:
    def __init__(self, *, hang: bool = False) -> None:
        self.hang = hang

    async def decode(self, token: str, packages: Sequence[str]) -> dict[str, Any]:
        if self.hang:
            await asyncio.sleep(5)
        raise RuntimeError("Play Integrity API unavailable")


async def test_verifier_outages_and_timeouts_are_unverified(
    client: AsyncClient,
    sms: FakeProvider,
    db_session: AsyncSession,
    app: FastAPI,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from farmerapp.settings import get_settings

    app.state.integrity = _Broken()
    await _login(client, sms, bind=True)
    row = await _login_audit(db_session)
    assert row.integrity["status"] == "unverified"  # type: ignore[index]
    assert row.integrity["reasons"] == ["verifier_error"]  # type: ignore[index]
    monkeypatch.setattr(get_settings(), "play_integrity_timeout_s", 0.05)
    app.state.integrity = _Broken(hang=True)
    await _login(client, sms, bind=True)
    assert (await _login_audit(db_session)).integrity["status"] == "unverified"  # type: ignore[index]


async def test_plain_requests_record_nothing(
    client: AsyncClient, db_session: AsyncSession, verifier: FakePlayIntegrityVerifier
) -> None:
    """``X-Integrity-*`` only on sensitive actions; the other audit rows keep NULL."""
    await send_otp(client)
    rows = (await db_session.execute(select(AuditLog))).scalars().all()
    assert rows and all(r.integrity is None for r in rows)
    assert verifier.calls == 0


# ------------------------------------------------------------------ Google adapter
async def test_google_verifier_tries_each_package_then_gives_up() -> None:
    import httpx

    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request.url.path)
        assert request.headers["Authorization"] == "Bearer t"
        assert json.loads(request.content) == {"integrityToken": "tok"}
        if "in.farmerapp.kisan" in request.url.path:
            return httpx.Response(200, json={"tokenPayloadExternal": payload("h")})
        return httpx.Response(400, json={"error": {"status": "INVALID_ARGUMENT"}})

    async def token() -> str:
        return "t"

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        google = GooglePlayIntegrityVerifier(token, client=client)
        decoded = await google.decode("tok", [AGENT, "in.farmerapp.kisan"])
        assert decoded["requestDetails"]["requestHash"] == "h"
        assert calls == [
            f"/v1/{AGENT}:decodeIntegrityToken",
            "/v1/in.farmerapp.kisan:decodeIntegrityToken",
        ]
        with pytest.raises(IntegrityDecodeError):
            await google.decode("tok", [AGENT])
