"""Read and write models of ``/v1/flags`` (WC-010)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.flags.models import Flag, FlagComment, FlagEvent, FlagStatus


class FlagOut(BaseModel):
    """An inbox row (FlagCard): no evidence bundle, see ``FlagDetailOut``."""

    id: uuid.UUID
    rule_id: str
    rule_version: int
    subject_type: str
    subject_id: uuid.UUID
    severity: str
    title: str
    status: FlagStatus
    owner_id: uuid.UUID | None
    owner_role: str | None
    watchers: list[uuid.UUID]
    sla_due_at: datetime
    overdue: bool
    escalation_level: int
    raised_by_mode: str
    resolution_note: str | None
    resolved_at: datetime | None
    resolved_by: uuid.UUID | None
    created_at: datetime
    version: int

    @classmethod
    def from_row(cls, flag: Flag, *, now: datetime) -> FlagOut:
        unresolved = flag.resolved_at is None
        return cls(
            id=flag.id,
            rule_id=flag.rule_id,
            rule_version=flag.rule_version,
            subject_type=flag.subject_type,
            subject_id=flag.subject_id,
            severity=flag.severity,
            title=flag.title,
            status=FlagStatus(flag.status),
            owner_id=flag.owner_id,
            owner_role=flag.owner_role,
            watchers=list(flag.watchers or []),
            sla_due_at=flag.sla_due_at,
            overdue=unresolved and flag.sla_due_at < now,
            escalation_level=flag.escalation_level,
            raised_by_mode=flag.raised_by_mode,
            resolution_note=flag.resolution_note,
            resolved_at=flag.resolved_at,
            resolved_by=flag.resolved_by,
            created_at=flag.created_at,
            version=flag.version,
        )


class FlagCounts(BaseModel):
    """Inbox grouping (C70): counts of the filtered set by severity and by rule."""

    total: int
    by_severity: dict[str, int]
    by_rule: dict[str, int]


class FlagPage(BaseModel):
    items: list[FlagOut]
    next_cursor: str | None = None
    counts: FlagCounts


class EvidenceRecord(BaseModel):
    type: str
    id: str
    summary: dict[str, Any] = Field(
        default_factory=dict, description="A few fields of the record (empty when not visible)."
    )


class EvidencePhoto(BaseModel):
    blob_uri: str
    signed_url: str | None = None
    signed_url_expires_at: datetime | None = None


class EvidenceOut(BaseModel):
    records: list[EvidenceRecord]
    map: dict[str, list[dict[str, Any]]]
    photos: list[EvidencePhoto]
    metrics: dict[str, Any]


class FlagEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    kind: str
    actor_id: uuid.UUID | None
    from_status: str | None
    to_status: str
    from_owner_id: uuid.UUID | None
    to_owner_id: uuid.UUID | None
    label: str | None
    note: str | None
    created_at: datetime

    @classmethod
    def from_row(cls, row: FlagEvent) -> FlagEventOut:
        return cls.model_validate(row)


class FlagCommentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    author_id: uuid.UUID
    body: str
    is_subject_explanation: bool
    created_at: datetime

    @classmethod
    def from_row(cls, row: FlagComment) -> FlagCommentOut:
        return cls.model_validate(row)


class FlagDetailOut(FlagOut):
    """C71: the flag with its evidence bundle, history and comment thread."""

    evidence: EvidenceOut
    events: list[FlagEventOut]
    comments: list[FlagCommentOut]
    allowed_transitions: list[FlagStatus]


class TransitionIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    to: FlagStatus
    note: str | None = Field(default=None, max_length=2000)


class CommentIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(min_length=1, max_length=2000)


class AssignIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    user_id: uuid.UUID
    note: str | None = Field(default=None, max_length=2000)


__all__ = [
    "AssignIn",
    "CommentIn",
    "EvidenceOut",
    "EvidencePhoto",
    "EvidenceRecord",
    "FlagCommentOut",
    "FlagCounts",
    "FlagDetailOut",
    "FlagEventOut",
    "FlagOut",
    "FlagPage",
    "TransitionIn",
]
