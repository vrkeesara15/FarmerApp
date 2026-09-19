"""``BlobStore`` adapters: the local directory store used by unit tests and the fake GCS
store (HTTP JSON API of fsouza/fake-gcs-server; ``integration`` — skipped when the compose
service is down). The real signed-URL adapter (SEC-016) is a seam for M5."""

from __future__ import annotations

import hashlib
import os
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import httpx
import pytest

from farmerapp.settings import Settings
from farmerapp.uploads.blobstore import (
    BlobNotFoundError,
    FakeGcsBlobStore,
    LocalBlobStore,
    blob_key,
    build_blob_store,
    parse_uri,
)

FAKE_GCS = os.environ.get("STORAGE_EMULATOR_HOST", "http://localhost:4443")


def test_uri_helpers() -> None:
    tid = uuid.uuid4()
    key = blob_key(tid, "farm_photo", "a" * 64)
    assert key == f"{tid}/farm_photo/{'a' * 64}"
    assert parse_uri(f"gs://photos/{key}") == ("photos", key)
    for bad in ("http://x/y", "gs://", "gs://bucket", "gs://bucket/", "s3://b/k"):
        with pytest.raises(ValueError):
            parse_uri(bad)


async def test_local_store_round_trip(tmp_path: Path) -> None:
    store = LocalBlobStore(tmp_path)
    data = os.urandom(3000)
    uri = await store.put("t/farm_photo/abc", data, content_type="image/jpeg")
    assert uri == "gs://local/t/farm_photo/abc"
    assert await store.exists(uri) and await store.get(uri) == data
    assert not await store.exists("gs://local/t/nope")
    with pytest.raises(BlobNotFoundError):
        await store.get("gs://local/t/nope")
    signed = await store.signed_url(
        uri, ttl=timedelta(minutes=15), now=datetime(2026, 1, 1, tzinfo=UTC)
    )
    assert signed.url.startswith("file://") and signed.expires_at == datetime(
        2026, 1, 1, 0, 15, tzinfo=UTC
    )
    assert "local" in signed.note.lower()
    # Paths cannot escape the root.
    with pytest.raises(ValueError):
        await store.put("../escape", b"x", content_type="text/plain")


def test_factory_from_settings(tmp_path: Path) -> None:
    local = build_blob_store(Settings(blob_store="local", blob_local_dir=str(tmp_path)))
    assert isinstance(local, LocalBlobStore)
    fake = build_blob_store(
        Settings(
            blob_store="fake_gcs", storage_emulator_host="http://gcs:4443", photos_bucket="photos"
        )
    )
    assert isinstance(fake, FakeGcsBlobStore) and fake.bucket == "photos"
    with pytest.raises(ValueError, match="STORAGE_EMULATOR_HOST"):
        build_blob_store(Settings(blob_store="fake_gcs", storage_emulator_host=None))


def _fake_gcs_up() -> bool:
    try:
        return httpx.get(f"{FAKE_GCS}/storage/v1/b", timeout=1.0).status_code == 200
    except httpx.HTTPError:
        return False


@pytest.mark.integration
async def test_fake_gcs_round_trip() -> None:
    if not _fake_gcs_up():
        pytest.skip(f"fake-gcs-server not reachable at {FAKE_GCS} (make up)")
    store = FakeGcsBlobStore(FAKE_GCS, bucket="photos")
    await store.ensure_bucket()
    data = os.urandom(600_000)
    key = f"integration/{uuid.uuid4()}/farm_photo/{hashlib.sha256(data).hexdigest()}"
    uri = await store.put(key, data, content_type="image/jpeg")
    assert uri == f"gs://photos/{key}"
    assert await store.exists(uri) and await store.get(uri) == data
    assert not await store.exists(f"gs://photos/{key}.missing")
    signed = await store.signed_url(uri, ttl=timedelta(minutes=15), now=datetime.now(UTC))
    assert signed.url.startswith(FAKE_GCS) and "alt=media" in signed.url
    async with httpx.AsyncClient(timeout=5.0) as client:
        assert (await client.get(signed.url)).content == data
    assert "fake" in signed.note.lower()
