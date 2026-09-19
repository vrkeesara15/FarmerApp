"""Resumable upload bookkeeping (NF-003).

* ``upload_session`` — one per file: what the client announced (sha256, size, type,
  purpose, chunk size), who started it, when it expires (15 min after the last activity)
  and, once complete, the blob URI.
* ``upload_chunk`` — staged 256 KB chunks as ``bytea`` (simpler than a temp prefix in the
  blob store; a pending upload holds at most ``upload_max_bytes``). Unique per
  ``(upload_id, index)`` so a re-PUT is an upsert. Deleted on completion or by the
  ``purge-expired`` job.

Both are bookkeeping (``__audit__ = False``): the data outcome is the ``farm_photo`` row.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    UniqueConstraint,
    Uuid,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.db.base import Base, BaseColumns, TenantRow


class UploadPurpose(StrEnum):
    FARM_PHOTO = "farm_photo"
    VISIT_PHOTO = "visit_photo"
    RECEIPT = "receipt"
    DIAGNOSIS = "diagnosis"
    PROFILE = "profile"
    CORPUS = "corpus"  # WC-007 corpus manager image uploads (M6)
    DEMO_PLOT = "demo_plot"  # FA-026 demo plot stage photos (M7)


class UploadStatus(StrEnum):
    PENDING = "pending"
    COMPLETE = "complete"


def _in(values: type[StrEnum]) -> str:
    return ", ".join(f"'{v.value}'" for v in values)


class UploadSession(Base, BaseColumns):
    __tablename__ = "upload_session"
    __table_args__ = (
        CheckConstraint(f"purpose IN ({_in(UploadPurpose)})", name="purpose"),
        CheckConstraint(f"status IN ({_in(UploadStatus)})", name="status"),
        CheckConstraint("char_length(sha256) = 64", name="sha256"),
        CheckConstraint("size_bytes > 0 AND chunk_size > 0 AND chunk_count > 0", name="sizes"),
        Index("ix_upload_session_actor_id", "actor_id"),
        Index("ix_upload_session_expires_at", "expires_at"),
        Index("ix_upload_session_blob_uri", "blob_uri"),
    )
    __audit__ = False

    actor_id: Mapped[uuid.UUID] = mapped_column(Uuid, nullable=False)
    device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    size_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False)
    content_type: Mapped[str] = mapped_column(String(100), nullable=False)
    purpose: Mapped[str] = mapped_column(String(16), nullable=False)
    chunk_size: Mapped[int] = mapped_column(Integer, nullable=False)
    chunk_count: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'pending'"), default=UploadStatus.PENDING
    )
    blob_uri: Mapped[str | None] = mapped_column(String(512), nullable=True)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class UploadChunk(Base, TenantRow):
    __tablename__ = "upload_chunk"
    __table_args__ = (
        UniqueConstraint("upload_id", "index"),
        CheckConstraint("index >= 0 AND size > 0", name="index_size"),
    )
    __audit__ = False

    upload_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("upload_session.id", ondelete="CASCADE"), nullable=False
    )
    index: Mapped[int] = mapped_column(Integer, nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    size: Mapped[int] = mapped_column(Integer, nullable=False)
    data: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)


__all__ = ["UploadChunk", "UploadPurpose", "UploadSession", "UploadStatus"]
