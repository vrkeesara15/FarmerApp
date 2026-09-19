"""NF-003 resumable chunked uploads: init, chunks in any order (idempotent re-PUT), status
for resume, complete with whole-file sha256 verification, blob store hand-off, signed URLs,
expiry purge, and the scope/authz edges."""

from __future__ import annotations

import hashlib
import os
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.session import tenant_scope
from farmerapp.jobs.purge_expired import purge_expired
from farmerapp.uploads.blobstore import LocalBlobStore
from farmerapp.uploads.models import UploadChunk, UploadSession
from tests.authz.conftest import Bearer, World

CHUNK = 262144


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@pytest.fixture
def blobs(app: FastAPI, tmp_path: Any) -> LocalBlobStore:
    store = LocalBlobStore(tmp_path / "blobs")
    app.state.blobs = store
    return store


@pytest.fixture
def officer(world: World) -> Any:
    return world.a.user(UserRole.FIELD_OFFICER)


@pytest.fixture
def headers(bearer: Bearer, officer: Any) -> dict[str, str]:
    return bearer(officer)


def _chunks(data: bytes) -> list[bytes]:
    return [data[i : i + CHUNK] for i in range(0, len(data), CHUNK)] or [b""]


async def _init(
    client: AsyncClient, headers: dict[str, str], data: bytes, **extra: Any
) -> dict[str, Any]:
    body = {
        "sha256": _sha(data),
        "size_bytes": len(data),
        "content_type": "image/jpeg",
        "purpose": "farm_photo",
        "chunk_size": CHUNK,
        **extra,
    }
    resp = await client.post("/v1/uploads", json=body, headers=headers)
    assert resp.status_code == 201, resp.text
    out: dict[str, Any] = resp.json()
    return out


async def _put(
    client: AsyncClient, headers: dict[str, str], upload_id: str, index: int, chunk: bytes
) -> Any:
    return await client.put(
        f"/v1/uploads/{upload_id}/chunks/{index}",
        content=chunk,
        headers={
            **headers,
            "X-Chunk-Sha256": _sha(chunk),
            "Content-Type": "application/octet-stream",
        },
    )


async def test_upload_out_of_order_resume_and_complete(
    client: AsyncClient,
    headers: dict[str, str],
    blobs: LocalBlobStore,
    db_session: AsyncSession,
    world: World,
) -> None:
    data = os.urandom(CHUNK * 2 + 1234)  # 3 chunks, last one partial
    chunks = _chunks(data)
    init = await _init(client, headers, data)
    assert init["chunk_size"] == CHUNK and init["received_chunks"] == []
    assert init["chunk_count"] == 3 and init["status"] == "pending"
    expires = datetime.fromisoformat(init["expires_at"])
    assert timedelta(minutes=14) < expires - datetime.now(UTC) <= timedelta(minutes=15)
    uid = init["upload_id"]

    resp = await _put(client, headers, uid, 2, chunks[2])
    assert resp.status_code == 200 and resp.json()["received_chunks"] == [2]
    resp = await _put(client, headers, uid, 0, chunks[0])
    assert resp.status_code == 200 and resp.json()["received_chunks"] == [0, 2]
    # Idempotent re-PUT of the same chunk.
    resp = await _put(client, headers, uid, 0, chunks[0])
    assert resp.status_code == 200 and resp.json()["received_chunks"] == [0, 2]

    # Completing early is a 409 that lists what is missing.
    resp = await client.post(f"/v1/uploads/{uid}/complete", headers=headers)
    assert resp.status_code == 409 and resp.json()["code"] == "upload_incomplete"
    assert resp.json()["missing_chunks"] == [1]

    # Resume: the status endpoint says what is there.
    resp = await client.get(f"/v1/uploads/{uid}", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["received_chunks"] == [0, 2] and resp.json()["status"] == "pending"

    resp = await _put(client, headers, uid, 1, chunks[1])
    assert resp.status_code == 200 and resp.json()["received_chunks"] == [0, 1, 2]
    resp = await client.post(f"/v1/uploads/{uid}/complete", headers=headers)
    assert resp.status_code == 200, resp.text
    done = resp.json()
    assert done["sha256"] == _sha(data) and done["size_bytes"] == len(data)
    assert done["content_type"] == "image/jpeg"
    assert done["blob_uri"].startswith("gs://") and "farm_photo/" in done["blob_uri"]
    assert str(world.a.tenant.id) in done["blob_uri"]
    assert await blobs.get(done["blob_uri"]) == data
    # Completing twice is idempotent; chunks are gone after completion.
    resp = await client.post(f"/v1/uploads/{uid}/complete", headers=headers)
    assert resp.status_code == 200 and resp.json() == done
    resp = await client.get(f"/v1/uploads/{uid}", headers=headers)
    assert resp.json()["status"] == "complete" and resp.json()["blob_uri"] == done["blob_uri"]
    async with tenant_scope(db_session, world.a.tenant.id):
        left = (
            await db_session.execute(
                select(UploadChunk).where(UploadChunk.upload_id == uuid.UUID(uid))
            )
        ).all()
        assert left == []
    # A completed upload no longer accepts chunks.
    resp = await _put(client, headers, uid, 0, chunks[0])
    assert resp.status_code == 409 and resp.json()["code"] == "upload_complete"


async def test_whole_file_sha_mismatch_is_422(
    client: AsyncClient, headers: dict[str, str], blobs: LocalBlobStore
) -> None:
    data = os.urandom(1000)
    init = await _init(client, headers, data, sha256=_sha(b"something else"))
    resp = await _put(client, headers, init["upload_id"], 0, data)
    assert resp.status_code == 200
    resp = await client.post(f"/v1/uploads/{init['upload_id']}/complete", headers=headers)
    assert resp.status_code == 422 and resp.json()["code"] == "upload_sha_mismatch"
    # Still resumable: the chunks are kept so the client can re-send the wrong one.
    resp = await client.get(f"/v1/uploads/{init['upload_id']}", headers=headers)
    assert resp.json()["received_chunks"] == [0] and resp.json()["status"] == "pending"


async def test_chunk_validation(
    client: AsyncClient, headers: dict[str, str], blobs: LocalBlobStore
) -> None:
    data = os.urandom(CHUNK + 10)
    chunks = _chunks(data)
    init = await _init(client, headers, data)
    uid = init["upload_id"]
    # Wrong per-chunk hash.
    resp = await client.put(
        f"/v1/uploads/{uid}/chunks/0",
        content=chunks[0],
        headers={**headers, "X-Chunk-Sha256": "0" * 64},
    )
    assert resp.status_code == 422 and resp.json()["code"] == "chunk_sha_mismatch"
    # Missing hash header.
    resp = await client.put(f"/v1/uploads/{uid}/chunks/0", content=chunks[0], headers=headers)
    assert resp.status_code == 422
    # Index out of range.
    resp = await _put(client, headers, uid, 2, chunks[1])
    assert resp.status_code == 422 and resp.json()["code"] == "chunk_index_invalid"
    # Wrong size for the index (a full chunk where the tail is expected, and vice versa).
    resp = await _put(client, headers, uid, 1, chunks[0])
    assert resp.status_code == 422 and resp.json()["code"] == "chunk_size_invalid"
    resp = await _put(client, headers, uid, 0, chunks[1])
    assert resp.status_code == 422 and resp.json()["code"] == "chunk_size_invalid"
    # Empty body.
    resp = await client.put(
        f"/v1/uploads/{uid}/chunks/0", content=b"", headers={**headers, "X-Chunk-Sha256": _sha(b"")}
    )
    assert resp.status_code == 422


async def test_init_validation(client: AsyncClient, headers: dict[str, str]) -> None:
    good = {
        "sha256": "a" * 64,
        "size_bytes": 10,
        "content_type": "image/jpeg",
        "purpose": "farm_photo",
        "chunk_size": CHUNK,
    }
    for patch in (
        {"sha256": "xyz"},
        {"size_bytes": 0},
        {"size_bytes": 50 * 1024 * 1024},
        {"purpose": "selfie"},
        {"chunk_size": 1000},
        {"content_type": "application/x-sh"},
    ):
        resp = await client.post("/v1/uploads", json={**good, **patch}, headers=headers)
        assert resp.status_code == 422, (patch, resp.text)


async def test_upload_is_private_to_its_owner(
    client: AsyncClient,
    headers: dict[str, str],
    bearer: Bearer,
    world: World,
    blobs: LocalBlobStore,
) -> None:
    data = os.urandom(100)
    init = await _init(client, headers, data)
    uid = init["upload_id"]
    other = bearer(world.a.user(UserRole.STORE_MANAGER))
    resp = await client.get(f"/v1/uploads/{uid}", headers=other)
    assert resp.status_code == 404
    resp = await _put(client, other, uid, 0, data)
    assert resp.status_code == 404
    resp = await client.post(f"/v1/uploads/{uid}/complete", headers=other)
    assert resp.status_code == 404
    resp = await client.get(f"/v1/uploads/{uuid.uuid4()}", headers=headers)
    assert resp.status_code == 404


async def test_expired_upload_is_gone_and_purged(
    client: AsyncClient,
    headers: dict[str, str],
    blobs: LocalBlobStore,
    db_session: AsyncSession,
    world: World,
) -> None:
    data = os.urandom(100)
    init = await _init(client, headers, data)
    uid = uuid.UUID(init["upload_id"])
    assert (await _put(client, headers, str(uid), 0, data)).status_code == 200
    async with tenant_scope(db_session, world.a.tenant.id):
        row = await db_session.get_one(UploadSession, uid)
        row.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        await db_session.flush()
    resp = await client.get(f"/v1/uploads/{uid}", headers=headers)
    assert resp.status_code == 410 and resp.json()["code"] == "upload_expired"
    resp = await client.post(f"/v1/uploads/{uid}/complete", headers=headers)
    assert resp.status_code == 410
    async with tenant_scope(db_session, world.a.tenant.id):
        report = await purge_expired(db_session, tenant_id=world.a.tenant.id)
        assert report.upload_sessions == 1 and report.upload_chunks == 1
        assert await db_session.get(UploadSession, uid) is None
        assert (await purge_expired(db_session, tenant_id=world.a.tenant.id)).upload_sessions == 0


async def test_signed_url_for_a_blob(
    client: AsyncClient, headers: dict[str, str], blobs: LocalBlobStore, world: World
) -> None:
    data = b"jpeg bytes"
    init = await _init(client, headers, data, purpose="profile")
    await _put(client, headers, init["upload_id"], 0, data)
    resp = await client.post(f"/v1/uploads/{init['upload_id']}/complete", headers=headers)
    uri = resp.json()["blob_uri"]
    resp = await client.get("/v1/blobs/signed-url", params={"uri": uri}, headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["url"] and body["expires_at"] and body["note"]
    expires = datetime.fromisoformat(body["expires_at"])
    assert timedelta(minutes=14) < expires - datetime.now(UTC) <= timedelta(minutes=15)
    # Another tenant's prefix, a foreign scheme or an unknown object are not signed.
    for bad in (f"gs://photos/{uuid.uuid4()}/profile/x.jpg", "http://evil/x", uri + ".nope"):
        resp = await client.get("/v1/blobs/signed-url", params={"uri": bad}, headers=headers)
        assert resp.status_code == 404, bad


async def test_agronomist_uploads_corpus_images_only(
    client: AsyncClient, bearer: Bearer, blobs: LocalBlobStore, world: World
) -> None:
    """WC-007: the agronomist starts corpus uploads (C61 corpus manager); every other
    purpose is 403 for that role."""
    agronomist = bearer(world.a.user(UserRole.AGRONOMIST))
    data = os.urandom(1000)
    init = await _init(client, agronomist, data, purpose="corpus")
    uid = init["upload_id"]
    resp = await _put(client, agronomist, uid, 0, data)
    assert resp.status_code == 200, resp.text
    resp = await client.get(f"/v1/uploads/{uid}", headers=agronomist)
    assert resp.status_code == 200 and resp.json()["received_chunks"] == [0]
    resp = await client.post(f"/v1/uploads/{uid}/complete", headers=agronomist)
    assert resp.status_code == 200, resp.text
    assert "/corpus/" in resp.json()["blob_uri"]
    assert await blobs.get(resp.json()["blob_uri"]) == data
    for purpose in ("farm_photo", "diagnosis", "receipt"):
        resp = await client.post(
            "/v1/uploads",
            json={
                "sha256": _sha(data),
                "size_bytes": len(data),
                "content_type": "image/jpeg",
                "purpose": purpose,
                "chunk_size": CHUNK,
            },
            headers=agronomist,
        )
        assert resp.status_code == 403 and resp.json()["code"] == "forbidden", purpose
