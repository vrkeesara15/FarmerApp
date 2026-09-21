"""``/v1/uploads`` (resumable chunked uploads, NF-003) and ``/v1/blobs/signed-url``
(SEC-016 read access). The blob store adapter is ``app.state.blobs``."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Header, Path, Query, Request, status

from farmerapp.api.errors import AppError, problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.uploads import service
from farmerapp.uploads.blobstore import BlobStore
from farmerapp.uploads.schemas import (
    ChunkAck,
    SignedUrlOut,
    UploadCompleteOut,
    UploadInit,
    UploadStatusOut,
)

router = APIRouter(prefix="/uploads", tags=["uploads"])
blob_router = APIRouter(prefix="/blobs", tags=["uploads"])

#: Devices that capture photos: field staff and farmers (plus the admin for the console), and
#: the agronomist for WC-007 corpus images (purpose ``corpus`` only).
UPLOAD_ROLES = (
    Role.FIELD_OFFICER,
    Role.STORE_MANAGER,
    Role.CLUSTER_HEAD,
    Role.FARMER,
    Role.TENANT_ADMIN,
    Role.AGRONOMIST,
)

CHUNK_SHA_HEADER = "X-Chunk-Sha256"
_UPLOAD_PROBLEMS = ((404, "not_found"), (410, "upload_expired"))


class ChunkHeaderMissingError(AppError):
    status = 422
    code = "chunk_sha_missing"


def get_blob_store(request: Request) -> BlobStore:
    blobs: BlobStore = request.app.state.blobs
    return blobs


@router.post(
    "",
    operation_id="initUpload",
    summary="Start a resumable upload (256 KB chunks)",
    status_code=status.HTTP_201_CREATED,
    response_model=UploadStatusOut,
    responses=problem_responses((422, "upload_too_large"), (409, "plan_limit_exceeded")),
)
async def init_upload(
    body: UploadInit,
    actor: Annotated[User, require_roles(*UPLOAD_ROLES)],
    session: DbSession,
    services: Services,
) -> UploadStatusOut:
    return await service.init_upload(session, actor, body, settings=services.settings)


@router.get(
    "/{upload_id}",
    operation_id="getUpload",
    summary="Upload status for resume: which chunks the server already has",
    response_model=UploadStatusOut,
    responses=problem_responses(*_UPLOAD_PROBLEMS),
)
async def get_upload(
    upload_id: uuid.UUID,
    actor: Annotated[User, require_roles(*UPLOAD_ROLES)],
    session: DbSession,
) -> UploadStatusOut:
    upload = await service.own_upload(session, actor, upload_id)
    return await service.upload_status(session, upload)


@router.put(
    "/{upload_id}/chunks/{index}",
    operation_id="putUploadChunk",
    summary="Store one chunk (raw bytes body; idempotent per index)",
    response_model=ChunkAck,
    responses=problem_responses(
        *_UPLOAD_PROBLEMS,
        (409, "upload_complete"),
        (422, "chunk_sha_missing"),
        (422, "chunk_sha_mismatch"),
        (422, "chunk_index_invalid"),
        (422, "chunk_size_invalid"),
    ),
    openapi_extra={
        "requestBody": {
            "required": True,
            "content": {
                "application/octet-stream": {"schema": {"type": "string", "format": "binary"}}
            },
        }
    },
)
async def put_chunk(
    request: Request,
    upload_id: uuid.UUID,
    index: Annotated[int, Path(ge=0)],
    actor: Annotated[User, require_roles(*UPLOAD_ROLES)],
    session: DbSession,
    services: Services,
    x_chunk_sha256: Annotated[
        str | None, Header(description="Lower-case hex SHA-256 of this chunk.")
    ] = None,
) -> ChunkAck:
    upload = await service.own_upload(session, actor, upload_id)
    if not x_chunk_sha256:
        raise ChunkHeaderMissingError(f"{CHUNK_SHA_HEADER} header is required.")
    data = await request.body()
    return await service.put_chunk(
        session,
        upload,
        index=index,
        data=data,
        declared_sha256=x_chunk_sha256,
        settings=services.settings,
    )


@router.post(
    "/{upload_id}/complete",
    operation_id="completeUpload",
    summary="Assemble the chunks, verify the sha256 and store the blob",
    response_model=UploadCompleteOut,
    responses=problem_responses(
        *_UPLOAD_PROBLEMS, (409, "upload_incomplete"), (422, "upload_sha_mismatch")
    ),
)
async def complete_upload(
    request: Request,
    upload_id: uuid.UUID,
    actor: Annotated[User, require_roles(*UPLOAD_ROLES)],
    session: DbSession,
) -> UploadCompleteOut:
    upload = await service.own_upload(session, actor, upload_id)
    return await service.complete_upload(session, upload, blobs=get_blob_store(request))


@blob_router.get(
    "/signed-url",
    operation_id="getSignedUrl",
    summary="A 15-minute URL to read a blob of the caller's tenant (SEC-016)",
    response_model=SignedUrlOut,
    responses=problem_responses((404, "not_found")),
)
async def get_signed_url(
    request: Request,
    uri: Annotated[str, Query(max_length=512, description="`blob_uri` of a completed upload.")],
    actor: Annotated[User, require_roles(*Role)],
    session: DbSession,
    services: Services,
) -> SignedUrlOut:
    return await service.signed_url(
        session, actor, uri, blobs=get_blob_store(request), settings=services.settings
    )


__all__ = ["UPLOAD_ROLES", "blob_router", "get_blob_store", "router"]
