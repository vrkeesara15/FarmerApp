"""``BlobStore``: where completed uploads land (NF-003) and how they are read back
(SEC-016: private buckets, 15-minute signed URLs).

Blob URIs are ``gs://<bucket>/<tenant_id>/<purpose>/<sha256>`` everywhere, whatever the
adapter, so a URI stored in ``farm_photo`` keeps working when the adapter changes.

* ``LocalBlobStore`` — a directory (unit tests, ``BLOB_STORE=local``).
* ``FakeGcsBlobStore`` — the JSON API of fsouza/fake-gcs-server from docker compose
  (``BLOB_STORE=fake_gcs``, ``STORAGE_EMULATOR_HOST``). Its "signed" URL is the emulator's
  plain media link: fake-gcs-server does not verify signatures.
* ``GcsBlobStore`` — Cloud Storage over its JSON API (``BLOB_STORE=gcs``; SEC-016): private
  buckets, reads through **V4 signed URLs** (``GOOG4-RSA-SHA256``, 15 minutes) whose
  string-to-sign is signed by the service account through IAM ``signBlob``
  (``IamBlobSigner``; the api SA holds ``roles/iam.serviceAccountTokenCreator`` on itself), so
  no key file exists anywhere. The signer is a port (``BlobSigner``): tests sign with a local
  RSA key and verify the URL.
"""

from __future__ import annotations

import base64
import hashlib
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import quote

import httpx

from farmerapp.gcp import TokenProvider
from farmerapp.settings import Settings

URI_SCHEME = "gs://"


class BlobNotFoundError(LookupError):
    """The URI names no object in the store."""


@dataclass(frozen=True)
class SignedUrl:
    url: str
    expires_at: datetime
    note: str


def blob_key(tenant_id: uuid.UUID, purpose: str, sha256: str) -> str:
    return f"{tenant_id}/{purpose}/{sha256}"


def parse_uri(uri: str) -> tuple[str, str]:
    """``gs://bucket/key`` -> ``(bucket, key)``; ``ValueError`` for anything else."""
    if not uri.startswith(URI_SCHEME):
        raise ValueError(f"not a blob URI: {uri!r}")
    bucket, _, key = uri[len(URI_SCHEME) :].partition("/")
    if not bucket or not key or ".." in key.split("/"):
        raise ValueError(f"malformed blob URI: {uri!r}")
    return bucket, key


class BlobStore(Protocol):
    bucket: str

    async def put(self, key: str, data: bytes, *, content_type: str) -> str:
        """Store ``data`` under ``key``; return the blob URI."""
        ...

    async def get(self, uri: str) -> bytes: ...

    async def exists(self, uri: str) -> bool: ...

    async def signed_url(self, uri: str, *, ttl: timedelta, now: datetime) -> SignedUrl: ...


# --------------------------------------------------------------------------- local
class LocalBlobStore:
    """Files under ``root``; URIs use the pseudo bucket ``local``."""

    bucket = "local"

    def __init__(self, root: Path | str) -> None:
        self.root = Path(root)

    def _path(self, key: str) -> Path:
        path = (self.root / key).resolve()
        if self.root.resolve() not in path.parents:
            raise ValueError("blob key escapes the store root")
        return path

    async def put(self, key: str, data: bytes, *, content_type: str) -> str:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return f"{URI_SCHEME}{self.bucket}/{key}"

    async def get(self, uri: str) -> bytes:
        _, key = parse_uri(uri)
        path = self._path(key)
        if not path.is_file():
            raise BlobNotFoundError(uri)
        return path.read_bytes()

    async def exists(self, uri: str) -> bool:
        try:
            _, key = parse_uri(uri)
            return self._path(key).is_file()
        except ValueError:
            return False

    async def signed_url(self, uri: str, *, ttl: timedelta, now: datetime) -> SignedUrl:
        _, key = parse_uri(uri)
        return SignedUrl(
            url=self._path(key).as_uri(),
            expires_at=now + ttl,
            note="local blob store: file URL, not signed (unit tests / dev only)",
        )


# --------------------------------------------------------------------------- fake GCS
class FakeGcsBlobStore:
    """fsouza/fake-gcs-server over its JSON API (no google-cloud-storage dependency)."""

    def __init__(self, base_url: str, *, bucket: str, timeout: float = 10.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.bucket = bucket
        self._timeout = timeout

    def _client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(base_url=self.base_url, timeout=self._timeout)

    def _object_url(self, key: str) -> str:
        return f"{self.base_url}/storage/v1/b/{self.bucket}/o/{quote(key, safe='')}"

    async def ensure_bucket(self) -> None:
        async with self._client() as client:
            resp = await client.get(f"/storage/v1/b/{self.bucket}")
            if resp.status_code == 404:
                resp = await client.post("/storage/v1/b", json={"name": self.bucket})
            resp.raise_for_status()

    async def put(self, key: str, data: bytes, *, content_type: str) -> str:
        async with self._client() as client:
            resp = await client.post(
                f"/upload/storage/v1/b/{self.bucket}/o",
                params={"uploadType": "media", "name": key},
                content=data,
                headers={"Content-Type": content_type},
            )
            resp.raise_for_status()
        return f"{URI_SCHEME}{self.bucket}/{key}"

    async def get(self, uri: str) -> bytes:
        bucket, key = parse_uri(uri)
        async with self._client() as client:
            resp = await client.get(
                f"/storage/v1/b/{bucket}/o/{quote(key, safe='')}", params={"alt": "media"}
            )
        if resp.status_code == 404:
            raise BlobNotFoundError(uri)
        resp.raise_for_status()
        return resp.content

    async def exists(self, uri: str) -> bool:
        try:
            bucket, key = parse_uri(uri)
        except ValueError:
            return False
        async with self._client() as client:
            resp = await client.get(f"/storage/v1/b/{bucket}/o/{quote(key, safe='')}")
        return resp.status_code == 200

    async def signed_url(self, uri: str, *, ttl: timedelta, now: datetime) -> SignedUrl:
        bucket, key = parse_uri(uri)
        return SignedUrl(
            url=f"{self.base_url}/storage/v1/b/{bucket}/o/{quote(key, safe='')}?alt=media",
            expires_at=now + ttl,
            note="fake-gcs-server: plain media URL, not signed (GcsBlobStore signs in GCP)",
        )


# --------------------------------------------------------------------------- real GCS
GCS_HOST = "storage.googleapis.com"
GCS_API = f"https://{GCS_HOST}"
SIGNING_ALGORITHM = "GOOG4-RSA-SHA256"
MAX_SIGNED_URL_TTL = timedelta(days=7)  # V4 limit


class BlobSigner(Protocol):
    """Signs bytes with a service account's key (RSA-SHA256), without holding the key."""

    async def email(self) -> str: ...

    async def sign(self, payload: bytes) -> bytes: ...


class IamBlobSigner:
    """IAM Service Account Credentials ``signBlob`` (SEC-016: no key file)."""

    def __init__(
        self,
        token: TokenProvider,
        *,
        service_account: str | None = None,
        email_provider: TokenProvider | None = None,
        client: httpx.AsyncClient | None = None,
        base_url: str = "https://iamcredentials.googleapis.com",
    ) -> None:
        self._token = token
        self._service_account = service_account
        self._email_provider = email_provider
        self._client = client
        self._base = base_url.rstrip("/")

    async def email(self) -> str:
        if self._service_account is None:
            if self._email_provider is None:
                raise RuntimeError("IamBlobSigner needs a service account email")
            self._service_account = await self._email_provider()
        return self._service_account

    async def sign(self, payload: bytes) -> bytes:
        email = await self.email()
        url = f"{self._base}/v1/projects/-/serviceAccounts/{quote(email, safe='@.')}:signBlob"
        body = {"payload": base64.b64encode(payload).decode()}
        headers = {"Authorization": f"Bearer {await self._token()}"}
        if self._client is not None:
            resp = await self._client.post(url, json=body, headers=headers)
        else:  # pragma: no cover - real network
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(url, json=body, headers=headers)
        resp.raise_for_status()
        return base64.b64decode(resp.json()["signedBlob"])


def _v4_quote(value: str, *, safe: str = "~") -> str:
    return quote(value, safe=safe)


def v4_string_to_sign(
    *,
    bucket: str,
    key: str,
    email: str,
    now: datetime,
    ttl: timedelta,
    method: str = "GET",
) -> tuple[str, str, str]:
    """The V4 pieces ``(canonical_uri, canonical_query, string_to_sign)``.

    https://cloud.google.com/storage/docs/access-control/signing-urls-manually"""
    stamp = now.astimezone(UTC)
    request_ts = stamp.strftime("%Y%m%dT%H%M%SZ")
    scope = f"{stamp.strftime('%Y%m%d')}/auto/storage/goog4_request"
    canonical_uri = f"/{bucket}/{_v4_quote(key, safe='/~')}"
    params = {
        "X-Goog-Algorithm": SIGNING_ALGORITHM,
        "X-Goog-Credential": f"{email}/{scope}",
        "X-Goog-Date": request_ts,
        "X-Goog-Expires": str(int(ttl.total_seconds())),
        "X-Goog-SignedHeaders": "host",
    }
    canonical_query = "&".join(f"{_v4_quote(k)}={_v4_quote(v)}" for k, v in sorted(params.items()))
    canonical_request = "\n".join(
        [method, canonical_uri, canonical_query, f"host:{GCS_HOST}\n", "host", "UNSIGNED-PAYLOAD"]
    )
    string_to_sign = "\n".join(
        [
            SIGNING_ALGORITHM,
            request_ts,
            scope,
            hashlib.sha256(canonical_request.encode()).hexdigest(),
        ]
    )
    return canonical_uri, canonical_query, string_to_sign


class GcsBlobStore:
    """Cloud Storage JSON API with V4 signed read URLs (SEC-016)."""

    def __init__(
        self,
        *,
        bucket: str,
        token: TokenProvider,
        signer: BlobSigner,
        client: httpx.AsyncClient | None = None,
        api_base: str = GCS_API,
    ) -> None:
        self.bucket = bucket
        self._token = token
        self._signer = signer
        self._client = client
        self._api = api_base.rstrip("/")

    async def _request(
        self,
        method: str,
        url: str,
        *,
        params: dict[str, str] | None = None,
        content: bytes | None = None,
        headers: dict[str, str] | None = None,
    ) -> httpx.Response:
        all_headers = {"Authorization": f"Bearer {await self._token()}", **(headers or {})}
        kwargs: dict[str, Any] = {"params": params, "content": content, "headers": all_headers}
        if self._client is not None:
            return await self._client.request(method, url, **kwargs)
        async with httpx.AsyncClient(timeout=30.0) as client:  # pragma: no cover - network
            return await client.request(method, url, **kwargs)

    def _object(self, bucket: str, key: str) -> str:
        return f"{self._api}/storage/v1/b/{bucket}/o/{quote(key, safe='')}"

    async def put(self, key: str, data: bytes, *, content_type: str) -> str:
        resp = await self._request(
            "POST",
            f"{self._api}/upload/storage/v1/b/{self.bucket}/o",
            params={"uploadType": "media", "name": key},
            content=data,
            headers={"Content-Type": content_type},
        )
        resp.raise_for_status()
        return f"{URI_SCHEME}{self.bucket}/{key}"

    async def get(self, uri: str) -> bytes:
        bucket, key = parse_uri(uri)
        resp = await self._request("GET", self._object(bucket, key), params={"alt": "media"})
        if resp.status_code == 404:
            raise BlobNotFoundError(uri)
        resp.raise_for_status()
        return resp.content

    async def exists(self, uri: str) -> bool:
        try:
            bucket, key = parse_uri(uri)
        except ValueError:
            return False
        resp = await self._request("GET", self._object(bucket, key))
        return resp.status_code == 200

    async def signed_url(self, uri: str, *, ttl: timedelta, now: datetime) -> SignedUrl:
        bucket, key = parse_uri(uri)
        ttl = min(ttl, MAX_SIGNED_URL_TTL)
        email = await self._signer.email()
        canonical_uri, query, to_sign = v4_string_to_sign(
            bucket=bucket, key=key, email=email, now=now, ttl=ttl
        )
        signature = (await self._signer.sign(to_sign.encode())).hex()
        return SignedUrl(
            url=f"https://{GCS_HOST}{canonical_uri}?{query}&X-Goog-Signature={signature}",
            expires_at=now + ttl,
            note="V4 signed URL (IAM signBlob)",
        )


def build_blob_store(settings: Settings) -> BlobStore:
    if settings.blob_store == "local":
        return LocalBlobStore(settings.blob_local_dir)
    if settings.blob_store == "gcs":  # pragma: no cover - needs Google credentials
        from farmerapp.gcp import GoogleAccessToken

        token = GoogleAccessToken()
        signer = IamBlobSigner(
            token,
            service_account=settings.gcs_signing_service_account,
            email_provider=token.service_account_email,
        )
        return GcsBlobStore(bucket=settings.photos_bucket, token=token, signer=signer)
    if not settings.storage_emulator_host:
        raise ValueError("BLOB_STORE=fake_gcs needs STORAGE_EMULATOR_HOST")
    return FakeGcsBlobStore(settings.storage_emulator_host, bucket=settings.photos_bucket)


def utcnow() -> datetime:
    return datetime.now(UTC)


__all__ = [
    "GCS_HOST",
    "SIGNING_ALGORITHM",
    "URI_SCHEME",
    "BlobNotFoundError",
    "BlobSigner",
    "BlobStore",
    "FakeGcsBlobStore",
    "GcsBlobStore",
    "IamBlobSigner",
    "LocalBlobStore",
    "SignedUrl",
    "blob_key",
    "build_blob_store",
    "parse_uri",
    "utcnow",
    "v4_string_to_sign",
]
