"""``PlayIntegrityVerifier``: decodes a Play Integrity token into its payload.

* ``GooglePlayIntegrityVerifier`` — ``POST https://playintegrity.googleapis.com/v1/
  {packageName}:decodeIntegrityToken`` with the API service account's token (scope
  ``playintegrity``). Google decrypts and verifies the token; we check what it says
  (``farmerapp.integrity.verdict.evaluate``). The token names no package before decoding, so
  each allowed package is tried in turn (a token of another app is a 400).
* ``FakePlayIntegrityVerifier`` — tests / local: a token is ``fake.<base64url(JSON payload)>``
  (``fake_token``), decoded without any network.
"""

from __future__ import annotations

import base64
import json
from collections.abc import Sequence
from typing import Any, Protocol
from urllib.parse import quote

import httpx

from farmerapp.gcp import TokenProvider

PLAY_INTEGRITY_API = "https://playintegrity.googleapis.com"
FAKE_PREFIX = "fake."


class IntegrityDecodeError(Exception):
    """The token could not be decoded for any allowed package."""


class PlayIntegrityVerifier(Protocol):
    async def decode(self, token: str, packages: Sequence[str]) -> dict[str, Any]:
        """The token's ``tokenPayloadExternal``; ``IntegrityDecodeError`` when invalid."""
        ...


class GooglePlayIntegrityVerifier:
    def __init__(
        self,
        token: TokenProvider,
        *,
        client: httpx.AsyncClient | None = None,
        base_url: str = PLAY_INTEGRITY_API,
        timeout: float = 2.0,
    ) -> None:
        self._token = token
        self._client = client
        self._base = base_url.rstrip("/")
        self._timeout = timeout

    async def _post(self, url: str, body: dict[str, str], headers: dict[str, str]) -> Any:
        if self._client is not None:
            return await self._client.post(url, json=body, headers=headers)
        async with httpx.AsyncClient(timeout=self._timeout) as client:  # pragma: no cover
            return await client.post(url, json=body, headers=headers)

    async def decode(self, token: str, packages: Sequence[str]) -> dict[str, Any]:
        headers = {"Authorization": f"Bearer {await self._token()}"}
        for package in packages:
            url = f"{self._base}/v1/{quote(package, safe='.')}:decodeIntegrityToken"
            resp = await self._post(url, {"integrityToken": token}, headers)
            if resp.status_code == 400:
                continue  # not this app's token (or malformed): try the next package
            resp.raise_for_status()
            payload = resp.json().get("tokenPayloadExternal")
            if isinstance(payload, dict):
                return payload
        raise IntegrityDecodeError("token not decodable for any allowed package")


def fake_token(payload: dict[str, Any]) -> str:
    raw = base64.urlsafe_b64encode(json.dumps(payload).encode()).rstrip(b"=").decode()
    return FAKE_PREFIX + raw


class FakePlayIntegrityVerifier:
    def __init__(self) -> None:
        self.calls = 0

    async def decode(self, token: str, packages: Sequence[str]) -> dict[str, Any]:
        self.calls += 1
        if not token.startswith(FAKE_PREFIX):
            raise IntegrityDecodeError("not a fake token")
        raw = token[len(FAKE_PREFIX) :]
        try:
            payload = json.loads(base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)))
        except ValueError as exc:
            raise IntegrityDecodeError("malformed fake token") from exc
        if not isinstance(payload, dict):
            raise IntegrityDecodeError("malformed fake token")
        return payload


__all__ = [
    "FAKE_PREFIX",
    "FakePlayIntegrityVerifier",
    "GooglePlayIntegrityVerifier",
    "IntegrityDecodeError",
    "PlayIntegrityVerifier",
    "fake_token",
]
