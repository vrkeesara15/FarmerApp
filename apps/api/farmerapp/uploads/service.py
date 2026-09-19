"""Resumable chunked uploads (NF-003): init -> PUT chunks in any order -> complete.

Chunks are verified per request (``X-Chunk-Sha256``, expected size for the index) and
staged in ``upload_chunk``; ``complete`` reassembles them in order, verifies the whole-file
sha256 and size, hands the bytes to the ``BlobStore`` under
``<tenant>/<purpose>/<sha256>`` and drops the staged chunks. Every step is private to the
actor that started the upload (a colleague's upload id is a 404) and moves ``expires_at``
15 minutes ahead; ``purge-expired`` removes what was never completed.
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, ForbiddenError, NotFoundError
from farmerapp.auth.models import User, UserRole
from farmerapp.settings import Settings
from farmerapp.uploads.blobstore import BlobStore, blob_key
from farmerapp.uploads.models import UploadChunk, UploadPurpose, UploadSession, UploadStatus
from farmerapp.uploads.schemas import (
    ChunkAck,
    SignedUrlOut,
    UploadCompleteOut,
    UploadInit,
    UploadStatusOut,
)

#: Roles that may only upload some purposes (403 otherwise): the agronomist uploads corpus
#: images for the WC-007 corpus manager and nothing else.
PURPOSE_LIMITED_ROLES: dict[UserRole, frozenset[UploadPurpose]] = {
    UserRole.AGRONOMIST: frozenset({UploadPurpose.CORPUS}),
}


class UploadTooLargeError(AppError):
    status = 422
    code = "upload_too_large"


class UploadExpiredError(AppError):
    status = 410
    code = "upload_expired"


class UploadCompleteError(AppError):
    status = 409
    code = "upload_complete"


class UploadIncompleteError(AppError):
    status = 409
    code = "upload_incomplete"


class UploadShaMismatchError(AppError):
    status = 422
    code = "upload_sha_mismatch"


class ChunkShaMismatchError(AppError):
    status = 422
    code = "chunk_sha_mismatch"


class ChunkIndexInvalidError(AppError):
    status = 422
    code = "chunk_index_invalid"


class ChunkSizeInvalidError(AppError):
    status = 422
    code = "chunk_size_invalid"


def _now() -> datetime:
    return datetime.now(UTC)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def chunk_count(size_bytes: int, chunk_size: int) -> int:
    return max(1, -(-size_bytes // chunk_size))


def expected_chunk_size(upload: UploadSession, index: int) -> int:
    if index == upload.chunk_count - 1:
        return upload.size_bytes - upload.chunk_size * (upload.chunk_count - 1)
    return upload.chunk_size


async def _received(session: AsyncSession, upload_id: uuid.UUID) -> list[int]:
    rows = await session.execute(
        select(UploadChunk.index)
        .where(UploadChunk.upload_id == upload_id)
        .order_by(UploadChunk.index)
    )
    return [int(r[0]) for r in rows]


def _status_out(upload: UploadSession, received: list[int]) -> UploadStatusOut:
    return UploadStatusOut(
        upload_id=upload.id,
        status=UploadStatus(upload.status),
        chunk_size=upload.chunk_size,
        chunk_count=upload.chunk_count,
        size_bytes=upload.size_bytes,
        received_chunks=received,
        expires_at=upload.expires_at,
        blob_uri=upload.blob_uri,
    )


async def init_upload(
    session: AsyncSession, actor: User, body: UploadInit, *, settings: Settings
) -> UploadStatusOut:
    if (
        UserRole(actor.role) in PURPOSE_LIMITED_ROLES
        and body.purpose not in PURPOSE_LIMITED_ROLES[UserRole(actor.role)]
    ):
        raise ForbiddenError(f"This role cannot upload {body.purpose!s} files.")
    if body.size_bytes > settings.upload_max_bytes:
        raise UploadTooLargeError(f"Uploads are capped at {settings.upload_max_bytes} bytes.")
    now = _now()
    upload = UploadSession(
        tenant_id=actor.tenant_id,
        actor_id=actor.id,
        device_id=actor.device_id,
        sha256=body.sha256,
        size_bytes=body.size_bytes,
        content_type=body.content_type,
        purpose=body.purpose,
        chunk_size=body.chunk_size,
        chunk_count=chunk_count(body.size_bytes, body.chunk_size),
        status=UploadStatus.PENDING,
        expires_at=now + timedelta(seconds=settings.upload_ttl_seconds),
    )
    session.add(upload)
    await session.flush()
    return _status_out(upload, [])


async def own_upload(session: AsyncSession, actor: User, upload_id: uuid.UUID) -> UploadSession:
    """The actor's own upload session; expired pending uploads are ``410 upload_expired``."""
    upload = await session.get(UploadSession, upload_id)
    if upload is None or upload.actor_id != actor.id or upload.tenant_id != actor.tenant_id:
        raise NotFoundError("Upload not found.")
    if upload.status == UploadStatus.PENDING and upload.expires_at <= _now():
        raise UploadExpiredError("This upload expired; start again.")
    return upload


async def upload_status(session: AsyncSession, upload: UploadSession) -> UploadStatusOut:
    return _status_out(upload, await _received(session, upload.id))


async def put_chunk(
    session: AsyncSession,
    upload: UploadSession,
    *,
    index: int,
    data: bytes,
    declared_sha256: str,
    settings: Settings,
) -> ChunkAck:
    if upload.status == UploadStatus.COMPLETE:
        raise UploadCompleteError("This upload is already complete.")
    if not 0 <= index < upload.chunk_count:
        raise ChunkIndexInvalidError(f"Chunk index must be 0..{upload.chunk_count - 1}.")
    expected = expected_chunk_size(upload, index)
    if len(data) != expected:
        raise ChunkSizeInvalidError(f"Chunk {index} must be {expected} bytes.")
    digest = sha256_hex(data)
    if digest != declared_sha256.lower():
        raise ChunkShaMismatchError("X-Chunk-Sha256 does not match the body.")
    stmt = insert(UploadChunk).values(
        id=uuid.uuid4(),
        tenant_id=upload.tenant_id,
        upload_id=upload.id,
        index=index,
        sha256=digest,
        size=len(data),
        data=data,
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=[UploadChunk.upload_id, UploadChunk.index],
        set_={"sha256": digest, "size": len(data), "data": data},
    )
    await session.execute(stmt)
    upload.expires_at = _now() + timedelta(seconds=settings.upload_ttl_seconds)
    await session.flush()
    received = await _received(session, upload.id)
    missing = [i for i in range(upload.chunk_count) if i not in set(received)]
    return ChunkAck(upload_id=upload.id, received_chunks=received, missing_chunks=missing)


async def complete_upload(
    session: AsyncSession, upload: UploadSession, *, blobs: BlobStore
) -> UploadCompleteOut:
    if upload.status == UploadStatus.COMPLETE and upload.blob_uri:
        return UploadCompleteOut(
            upload_id=upload.id,
            blob_uri=upload.blob_uri,
            sha256=upload.sha256,
            size_bytes=upload.size_bytes,
            content_type=upload.content_type,
        )
    received = await _received(session, upload.id)
    missing = [i for i in range(upload.chunk_count) if i not in set(received)]
    if missing:
        raise UploadIncompleteError(
            f"{len(missing)} chunk(s) missing.", extra={"missing_chunks": missing}
        )
    rows = await session.execute(
        select(UploadChunk.data)
        .where(UploadChunk.upload_id == upload.id)
        .order_by(UploadChunk.index)
    )
    data = b"".join(bytes(r[0]) for r in rows)
    if len(data) != upload.size_bytes or sha256_hex(data) != upload.sha256:
        raise UploadShaMismatchError("The assembled file does not match the announced sha256.")
    key = blob_key(upload.tenant_id, upload.purpose, upload.sha256)
    uri = await blobs.put(key, data, content_type=upload.content_type)
    upload.status = UploadStatus.COMPLETE
    upload.blob_uri = uri
    upload.completed_at = _now()
    await session.execute(delete(UploadChunk).where(UploadChunk.upload_id == upload.id))
    await session.flush()
    return UploadCompleteOut(
        upload_id=upload.id,
        blob_uri=uri,
        sha256=upload.sha256,
        size_bytes=upload.size_bytes,
        content_type=upload.content_type,
    )


async def signed_url(
    session: AsyncSession, actor: User, uri: str, *, blobs: BlobStore, settings: Settings
) -> SignedUrlOut:
    """A 15-minute URL for a blob of the actor's tenant that a completed upload produced."""
    known = await session.scalar(
        select(UploadSession.id)
        .where(
            UploadSession.tenant_id == actor.tenant_id,
            UploadSession.blob_uri == uri,
            UploadSession.status == UploadStatus.COMPLETE,
        )
        .limit(1)
    )
    if known is None or not await blobs.exists(uri):
        raise NotFoundError("Blob not found.")
    signed = await blobs.signed_url(
        uri, ttl=timedelta(seconds=settings.signed_url_ttl_seconds), now=_now()
    )
    return SignedUrlOut(uri=uri, url=signed.url, expires_at=signed.expires_at, note=signed.note)


__all__ = [
    "PURPOSE_LIMITED_ROLES",
    "ChunkIndexInvalidError",
    "ChunkShaMismatchError",
    "ChunkSizeInvalidError",
    "UploadCompleteError",
    "UploadExpiredError",
    "UploadIncompleteError",
    "UploadShaMismatchError",
    "UploadTooLargeError",
    "chunk_count",
    "complete_upload",
    "expected_chunk_size",
    "init_upload",
    "own_upload",
    "put_chunk",
    "sha256_hex",
    "signed_url",
    "upload_status",
]
