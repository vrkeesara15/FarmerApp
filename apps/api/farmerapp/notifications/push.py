"""FA-007 push delivery port (``PushSender``) and its adapters.

* ``FcmPushSender`` — the FCM HTTP v1 API (``POST https://fcm.googleapis.com/v1/projects/
  <project>/messages:send``) with an OAuth access token of the runtime service account
  (``farmerapp.gcp.GoogleAccessToken``, scope ``firebase.messaging``): no server key in
  code or configuration. The message is a *data* message plus an Android notification
  carrying the i18n keys (``title_loc_key`` / ``body_loc_key``): the apps resolve the text
  in the user's language, strings never travel from the server (FA-004).
* ``FakePushSender`` — records messages in memory; tests script failures per token
  (``unregistered`` / ``retryable`` / ``error``).
* ``DisabledPushSender`` — ``PUSH_PROVIDER=off`` (local default): every send is a retryable
  "disabled" outcome, so rows stay pending in the inbox and nothing leaves the machine.

Outcomes: ``ok``; ``unregistered`` (FCM ``UNREGISTERED`` / 404, or ``INVALID_ARGUMENT`` on
the token: the token is disabled); ``retryable`` (429, 5xx, network: tried again later);
``error`` (any other 4xx: not retried for this token).
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Any, Literal, Protocol

import httpx

Outcome = Literal["ok", "unregistered", "retryable", "error"]
FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
FCM_URL = "https://fcm.googleapis.com/v1/projects/{project}/messages:send"


@dataclass(frozen=True)
class PushMessage:
    token: str
    title_key: str
    body_key: str
    data: dict[str, str]
    platform: str = "android"


@dataclass(frozen=True)
class PushResult:
    outcome: Outcome
    detail: str | None = None
    message_id: str | None = None


class PushSender(Protocol):
    name: str

    async def send(self, message: PushMessage) -> PushResult: ...


def fcm_body(message: PushMessage) -> dict[str, Any]:
    """The FCM v1 ``message`` for one token (data + localisable Android notification)."""
    return {
        "message": {
            "token": message.token,
            "data": message.data,
            "android": {
                "priority": "high",
                "notification": {
                    "title_loc_key": message.title_key,
                    "body_loc_key": message.body_key,
                    "click_action": "FLUTTER_NOTIFICATION_CLICK",
                },
            },
            "apns": {
                "payload": {
                    "aps": {
                        "alert": {"title-loc-key": message.title_key, "loc-key": message.body_key}
                    }
                }
            },
        }
    }


def _fcm_error_code(resp: httpx.Response) -> str:
    try:
        err = resp.json().get("error") or {}
    except ValueError:
        return ""
    for detail in err.get("details") or []:
        code = detail.get("errorCode")
        if code:
            return str(code)
    return str(err.get("status") or "")


class FcmPushSender:
    name = "fcm"

    def __init__(
        self,
        *,
        project: str,
        token_provider: Callable[[], Awaitable[str]],
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._url = FCM_URL.format(project=project)
        self._token_provider = token_provider
        self._client = client

    async def send(self, message: PushMessage) -> PushResult:
        try:
            token = await self._token_provider()
            headers = {"Authorization": f"Bearer {token}"}
            body = fcm_body(message)
            if self._client is not None:
                resp = await self._client.post(self._url, json=body, headers=headers)
            else:  # pragma: no cover - real FCM (human gate)
                async with httpx.AsyncClient(timeout=10.0) as client:
                    resp = await client.post(self._url, json=body, headers=headers)
        except httpx.HTTPError as exc:
            return PushResult("retryable", f"network: {type(exc).__name__}")
        if resp.status_code < 300:
            try:
                name = str(resp.json().get("name") or "")
            except ValueError:
                name = ""
            return PushResult("ok", message_id=name or None)
        code = _fcm_error_code(resp)
        if resp.status_code == 404 or code == "UNREGISTERED":
            return PushResult("unregistered", code or "404")
        if code == "INVALID_ARGUMENT" and resp.status_code == 400:
            return PushResult("unregistered", code)
        if (
            resp.status_code == 429
            or resp.status_code >= 500
            or code in ("UNAVAILABLE", "INTERNAL")
        ):
            return PushResult("retryable", code or str(resp.status_code))
        return PushResult("error", code or str(resp.status_code))


@dataclass
class FakePushSender:
    """In-memory sender: ``sent`` keeps every accepted message; ``script`` maps a token to
    the outcome it should get (default ``ok``)."""

    name: str = "fake"
    sent: list[PushMessage] = field(default_factory=list)
    attempts: list[PushMessage] = field(default_factory=list)
    script: dict[str, Outcome] = field(default_factory=dict)

    async def send(self, message: PushMessage) -> PushResult:
        self.attempts.append(message)
        outcome = self.script.get(message.token, "ok")
        if outcome == "ok":
            self.sent.append(message)
            return PushResult("ok", message_id=f"fake-{len(self.sent)}")
        return PushResult(outcome, f"scripted {outcome}")


class DisabledPushSender:
    name = "off"

    async def send(self, message: PushMessage) -> PushResult:
        return PushResult("retryable", "push disabled (PUSH_PROVIDER=off)")


def build_push_sender(provider: str, project: str) -> PushSender:
    if provider == "fake":
        return FakePushSender()
    if provider == "fcm":  # pragma: no cover - needs Google credentials (human gate)
        from farmerapp.gcp import GoogleAccessToken

        return FcmPushSender(project=project, token_provider=GoogleAccessToken((FCM_SCOPE,)))
    return DisabledPushSender()


__all__ = [
    "FCM_SCOPE",
    "DisabledPushSender",
    "FakePushSender",
    "FcmPushSender",
    "Outcome",
    "PushMessage",
    "PushResult",
    "PushSender",
    "build_push_sender",
    "fcm_body",
]
