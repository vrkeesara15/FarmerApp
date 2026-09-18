"""``POST /v1/sync`` request / response (SPEC 8.3, FA-025, NF-003)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

MAX_OPS = 200

Entity = Literal["farmer", "farm", "crop_plot", "consent_record"]
Action = Literal["create", "update", "delete"]
ResultStatus = Literal["applied", "duplicate", "conflict", "rejected"]


class SyncOpIn(BaseModel):
    op_id: uuid.UUID = Field(description="Client-generated; the idempotency key of the op.")
    entity: Entity
    action: Action
    entity_id: uuid.UUID = Field(description="Client-generated entity id.")
    base_version: int = Field(ge=0, description="Version the client edited; 0 for create.")
    payload: dict[str, Any] = Field(default_factory=dict)
    client_ts: datetime = Field(description="When the device made the change (aware).")


class SyncRequest(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    cursor: str | None = Field(default=None, description="Opaque cursor from a previous sync.")
    ops: list[SyncOpIn] = Field(default_factory=list, max_length=MAX_OPS)


class SyncError(BaseModel):
    """Problem-style error of a rejected op (same ``code`` values as the REST endpoints)."""

    code: str
    status: int
    detail: str | None = None
    errors: list[dict[str, Any]] | None = None


class SyncResult(BaseModel):
    op_id: uuid.UUID
    status: ResultStatus
    entity_id: uuid.UUID
    version: int | None = None
    error: SyncError | None = None
    server: dict[str, Any] | None = Field(
        default=None, description="Server state after the op (applied) or current (conflict)."
    )


class SyncChangeOut(BaseModel):
    entity: Entity
    action: Action
    entity_id: uuid.UUID
    version: int
    data: dict[str, Any] = Field(description="Current row; `{id, deleted_at}` for deletes.")
    seq: int


class SyncResponse(BaseModel):
    results: list[SyncResult]
    changes: list[SyncChangeOut]
    cursor: str
    has_more: bool


__all__ = [
    "MAX_OPS",
    "Action",
    "Entity",
    "ResultStatus",
    "SyncChangeOut",
    "SyncError",
    "SyncOpIn",
    "SyncRequest",
    "SyncResponse",
    "SyncResult",
]
