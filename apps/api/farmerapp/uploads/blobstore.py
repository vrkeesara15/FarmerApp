"""``BlobStore``: where completed uploads land (NF-003) and how they are read back
(SEC-016: private buckets, 15-minute signed URLs).

Blob URIs are ``gs://<bucket>/<tenant_id>/<purpose>/<sha256>`` everywhere, whatever the
adapter, so a URI stored in ``farm_photo`` keeps working when the adapter changes.

* ``LocalBlobStore`` — a directory (unit tests, ``BLOB_STORE=local``).
* ``FakeGcsBlobStore`` — the JSON API of fsouza/fake-gcs-server from docker compose
  (``BLOB_STORE=fake_gcs``, ``STORAGE_EMULATOR_HOST``). Its "signed" URL is the emulator's
  plain media link: fake-gcs-server does not verify signatures.
* Real GCS — ``GcsBlobStore`` is the seam for SEC-016 (M5): V4 signed URLs from the service
  account's IAM ``signBlob``; same interface, not implemented yet.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Protocol
from urllib.parse import quote

import httpx

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

    def signed_url(self, uri: str, *, ttl: timedelta, now: datetime) -> SignedUrl: ...


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

    def signed_url(self, uri: str, *, ttl: timedelta, now: datetime) -> SignedUrl:
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

    def signed_url(self, uri: str, *, ttl: timedelta, now: datetime) -> SignedUrl:
        bucket, key = parse_uri(uri)
        return SignedUrl(
            url=f"{self.base_url}/storage/v1/b/{bucket}/o/{quote(key, safe='')}?alt=media",
            expires_at=now + ttl,
            note="fake-gcs-server: plain media URL, not signed; real V4 signing comes with "
            "SEC-016 (GcsBlobStore)",
        )


def build_blob_store(settings: Settings) -> BlobStore:
    if settings.blob_store == "local":
        return LocalBlobStore(settings.blob_local_dir)
    if not settings.storage_emulator_host:
        raise ValueError("BLOB_STORE=fake_gcs needs STORAGE_EMULATOR_HOST")
    return FakeGcsBlobStore(settings.storage_emulator_host, bucket=settings.photos_bucket)


def utcnow() -> datetime:
    return datetime.now(UTC)


__all__ = [
    "URI_SCHEME",
    "BlobNotFoundError",
    "BlobStore",
    "FakeGcsBlobStore",
    "LocalBlobStore",
    "SignedUrl",
    "blob_key",
    "build_blob_store",
    "parse_uri",
    "utcnow",
]
