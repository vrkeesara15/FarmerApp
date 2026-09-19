"""Google Cloud access tokens for the REST calls the API makes itself (SEC-016 IAM signBlob,
SEC-026 Cloud KMS, SEC-024 Play Integrity).

``GoogleAccessToken`` uses Application Default Credentials (``google.auth.default``): the
Cloud Run service account through the metadata server in GCP, ``gcloud auth
application-default login`` on a laptop. Tokens are cached until five minutes before expiry
and refreshed off the event loop (``asyncio.to_thread``). Tests never construct it: every
adapter takes a ``TokenProvider`` (an ``async () -> str``).
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable, Sequence
from datetime import UTC, datetime, timedelta
from typing import Any

TokenProvider = Callable[[], Awaitable[str]]

CLOUD_PLATFORM = "https://www.googleapis.com/auth/cloud-platform"
PLAY_INTEGRITY_SCOPE = "https://www.googleapis.com/auth/playintegrity"
_SKEW = timedelta(minutes=5)


class GoogleAccessToken:  # pragma: no cover - needs Google credentials (human gate)
    """Cached OAuth access token of the runtime credentials."""

    def __init__(self, scopes: Sequence[str] = (CLOUD_PLATFORM,)) -> None:
        self._scopes = list(scopes)
        self._credentials: Any = None
        self._lock = asyncio.Lock()

    def _refresh(self) -> None:
        import google.auth
        import google.auth.transport.requests

        if self._credentials is None:
            self._credentials, _ = google.auth.default(scopes=self._scopes)
        self._credentials.refresh(google.auth.transport.requests.Request())

    def _fresh(self) -> bool:
        creds = self._credentials
        if creds is None or not creds.token:
            return False
        expiry: datetime | None = creds.expiry
        if expiry is None:
            return True
        if expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=UTC)
        return expiry - _SKEW > datetime.now(UTC)

    async def __call__(self) -> str:
        async with self._lock:
            if not self._fresh():
                await asyncio.to_thread(self._refresh)
            return str(self._credentials.token)

    async def service_account_email(self) -> str:
        """The runtime service account (resolved by the first refresh on Cloud Run)."""
        await self()
        email = getattr(self._credentials, "service_account_email", None)
        if not email or email == "default":
            raise RuntimeError(
                "no service account email in the runtime credentials; "
                "set GCS_SIGNING_SERVICE_ACCOUNT"
            )
        return str(email)


_METADATA_IDENTITY = (
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity"
)
_ID_TOKEN_TTL = timedelta(minutes=50)


class MetadataIdentityToken:  # pragma: no cover - needs the Cloud Run metadata server
    """OIDC identity token for calling another Cloud Run service (the M6 ``embed`` service,
    ingress internal, invoker = the worker's service account). Cached for 50 minutes (the
    token lives an hour)."""

    def __init__(self, audience: str) -> None:
        self._audience = audience
        self._token: str | None = None
        self._expires = datetime.min.replace(tzinfo=UTC)
        self._lock = asyncio.Lock()

    async def __call__(self) -> str:
        import httpx

        async with self._lock:
            now = datetime.now(UTC)
            if self._token is None or now >= self._expires:
                async with httpx.AsyncClient(timeout=5.0) as client:
                    resp = await client.get(
                        _METADATA_IDENTITY,
                        params={"audience": self._audience},
                        headers={"Metadata-Flavor": "Google"},
                    )
                    resp.raise_for_status()
                self._token = resp.text.strip()
                self._expires = now + _ID_TOKEN_TTL
            return self._token


__all__ = [
    "CLOUD_PLATFORM",
    "PLAY_INTEGRITY_SCOPE",
    "GoogleAccessToken",
    "MetadataIdentityToken",
    "TokenProvider",
]
