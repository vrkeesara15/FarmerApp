"""Request / response models of ``/v1/uploads`` and ``/v1/blobs`` (NF-003, SEC-016)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from farmerapp.uploads.models import UploadPurpose

Sha256 = Field(pattern=r"^[0-9a-f]{64}$", description="Lower-case hex SHA-256.")

#: Content types a device may upload (photos and receipts only in this milestone).
ALLOWED_CONTENT_TYPES = frozenset({"image/jpeg", "image/png", "image/webp", "application/pdf"})


class UploadInit(BaseModel):
    sha256: str = Sha256
    size_bytes: int = Field(gt=0, description="Whole-file size; capped by UPLOAD_MAX_BYTES.")
    content_type: Literal["image/jpeg", "image/png", "image/webp", "application/pdf"]
    purpose: UploadPurpose
    chunk_size: Literal[262144] = Field(default=262144, description="256 KB (NF-003).")


class UploadStatusOut(BaseModel):
    upload_id: uuid.UUID
    status: Literal["pending", "complete"]
    chunk_size: int
    chunk_count: int
    size_bytes: int
    received_chunks: list[int] = Field(description="Indexes stored so far, ascending.")
    expires_at: datetime
    blob_uri: str | None = None


class ChunkAck(BaseModel):
    upload_id: uuid.UUID
    received_chunks: list[int]
    missing_chunks: list[int]


class UploadCompleteOut(BaseModel):
    upload_id: uuid.UUID
    blob_uri: str
    sha256: str
    size_bytes: int
    content_type: str


class SignedUrlOut(BaseModel):
    uri: str
    url: str
    expires_at: datetime
    note: str = Field(description="Adapter note (fake GCS / local URLs are not signed).")


__all__ = [
    "ALLOWED_CONTENT_TYPES",
    "ChunkAck",
    "SignedUrlOut",
    "UploadCompleteOut",
    "UploadInit",
    "UploadStatusOut",
]
