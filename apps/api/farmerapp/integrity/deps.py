"""The FastAPI side of Play Integrity: ``integrity_for(action)`` is a route dependency.

It reads ``X-Integrity-Token`` / ``X-Integrity-Status`` / ``X-Integrity-Action``, recomputes
the request hash from the method, path, raw body and action header, decodes the token through
``app.state.integrity`` (a ``PlayIntegrityVerifier``; ``PLAY_INTEGRITY_MODE``) within
``PLAY_INTEGRITY_TIMEOUT_S`` and evaluates it. The verdict is

* put on ``request.state.integrity`` and bound for the request (``audit.bind_integrity``), so
  **every audit row the request writes** (the ``auth.login`` event, the payment, POS sale or
  day close rows) carries it in ``audit_log.integrity``;
* logged: INFO ``integrity_verdict`` always, WARNING ``integrity_signal`` when it is a
  signal (``failed`` or ``absent``) — VA-E01 reads failed verdicts from the audit trail.

It **never blocks**: every outcome, including a verifier outage, lets the request through.
``action=None`` (``POST /v1/sync``) means "sensitive only when the app says so": without any
integrity header the verdict is ``not_required`` and nothing is recorded.
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime
from typing import Annotated

from fastapi import Header, Request

from farmerapp.db import audit
from farmerapp.integrity.verdict import (
    IntegrityReason,
    IntegrityStatus,
    IntegrityVerdict,
    evaluate,
    parse_actions,
    request_hash,
)
from farmerapp.integrity.verifier import (
    FakePlayIntegrityVerifier,
    IntegrityDecodeError,
    PlayIntegrityVerifier,
)
from farmerapp.logging import get_logger
from farmerapp.settings import Settings, get_settings

log = get_logger("farmerapp.integrity")

UNAVAILABLE = "unavailable"

TokenHeader = Annotated[
    str | None,
    Header(
        alias="X-Integrity-Token",
        description="SEC-024: Play Integrity standard token bound to this request "
        "(requestHash). Verified server-side; never blocks.",
    ),
]
StatusHeader = Annotated[
    str | None,
    Header(
        alias="X-Integrity-Status",
        description="`unavailable` when the app could not get a token (never blocks).",
    ),
]
ActionHeader = Annotated[
    str | None,
    Header(
        alias="X-Integrity-Action",
        description="Comma list of sensitive actions: login, credit_sale, "
        "payment_collection, day_close.",
    ),
]


def build_verifier(settings: Settings) -> PlayIntegrityVerifier | None:
    if settings.play_integrity_mode == "fake":
        return FakePlayIntegrityVerifier()
    if settings.play_integrity_mode == "google":  # pragma: no cover - needs Google credentials
        from farmerapp.gcp import PLAY_INTEGRITY_SCOPE, GoogleAccessToken
        from farmerapp.integrity.verifier import GooglePlayIntegrityVerifier

        return GooglePlayIntegrityVerifier(
            GoogleAccessToken(scopes=(PLAY_INTEGRITY_SCOPE,)),
            timeout=settings.play_integrity_timeout_s,
        )
    return None


async def _decide(
    request: Request,
    *,
    token: str | None,
    status: str | None,
    action_header: str | None,
    default_action: str | None,
    settings: Settings,
    now: datetime,
) -> IntegrityVerdict:
    actions = parse_actions(action_header) or ((default_action,) if default_action else ())
    if token is None:
        if status is not None and status.strip().lower() == UNAVAILABLE:
            return IntegrityVerdict(IntegrityStatus.UNAVAILABLE, actions=actions)
        if not actions:
            return IntegrityVerdict(IntegrityStatus.NOT_REQUIRED)
        return IntegrityVerdict(IntegrityStatus.ABSENT, actions=actions)
    verifier: PlayIntegrityVerifier | None = getattr(request.app.state, "integrity", None)
    if verifier is None:
        return IntegrityVerdict(
            IntegrityStatus.UNVERIFIED,
            actions=actions,
            reasons=(IntegrityReason.VERIFICATION_OFF.value,),
        )
    packages = settings.play_integrity_package_names
    try:
        payload = await asyncio.wait_for(
            verifier.decode(token, packages), timeout=settings.play_integrity_timeout_s
        )
    except IntegrityDecodeError:
        return IntegrityVerdict(
            IntegrityStatus.FAILED, actions=actions, reasons=(IntegrityReason.TOKEN_INVALID,)
        )
    except Exception:  # never block: an outage or a timeout is "unverified", logged
        log.warning("integrity_verifier_error", exc_info=True)
        return IntegrityVerdict(
            IntegrityStatus.UNVERIFIED,
            actions=actions,
            reasons=(IntegrityReason.VERIFIER_ERROR.value,),
        )
    expected = request_hash(
        request.method, request.url.path, await request.body(), (action_header or "").strip()
    )
    return evaluate(payload, expected_hash=expected, packages=packages, actions=actions, now=now)


def record_verdict(request: Request, verdict: IntegrityVerdict) -> None:
    request.state.integrity = verdict
    if verdict.status == IntegrityStatus.NOT_REQUIRED:
        return
    audit.bind_integrity(verdict.as_json())
    fields = {
        "status": verdict.status.value,
        "actions": list(verdict.actions),
        "reasons": list(verdict.reasons),
        "device_id": request.headers.get(audit.DEVICE_HEADER),
    }
    log.info("integrity_verdict", **fields)
    if verdict.is_signal:
        log.warning("integrity_signal", source="play_integrity", **fields)


def integrity_for(
    action: str | None,
) -> Callable[..., Awaitable[IntegrityVerdict]]:
    """Dependency for a route whose sensitive action is ``action`` (``None``: header only)."""

    async def dependency(
        request: Request,
        x_integrity_token: TokenHeader = None,
        x_integrity_status: StatusHeader = None,
        x_integrity_action: ActionHeader = None,
    ) -> IntegrityVerdict:
        verdict = await _decide(
            request,
            token=x_integrity_token,
            status=x_integrity_status,
            action_header=x_integrity_action,
            default_action=action,
            settings=get_settings(),
            now=datetime.now(UTC),
        )
        record_verdict(request, verdict)
        return verdict

    return dependency


__all__ = ["build_verifier", "integrity_for", "record_verdict"]
