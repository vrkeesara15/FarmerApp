"""Read and write models of ``/v1/flags`` (WC-010)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.flags.models import (
    Flag,
    FlagComment,
    FlagEvent,
    FlagStatus,
    FlagSummary,
    SummaryStatus,
)


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


class AutomatedSummaryOut(BaseModel):
    """VA-004: the review agent's summary. The console shows it under ``label_key``
    ("Automated summary — verify evidence"); ``summary_lines`` is null unless ``status`` is
    ``done`` (``refused`` / ``invalid`` / ``error``: no summary, the reviewer reads the
    evidence)."""

    label_key: str
    status: SummaryStatus
    summary_lines: list[str] | None
    suggested_action: str | None
    cited_record_ids: list[str]
    model: str | None
    completed_at: datetime | None

    @classmethod
    def from_row(cls, row: FlagSummary, *, label_key: str) -> AutomatedSummaryOut:
        done = row.status == SummaryStatus.DONE.value
        return cls(
            label_key=label_key,
            status=SummaryStatus(row.status),
            summary_lines=list(row.summary_lines or []) if done else None,
            suggested_action=row.suggested_action if done else None,
            cited_record_ids=list(row.cited_record_ids or []) if done else [],
            model=row.model,
            completed_at=row.completed_at,
        )


class FlagDetailOut(FlagOut):
    """C71: the flag with its evidence bundle, history and comment thread."""

    evidence: EvidenceOut
    events: list[FlagEventOut]
    comments: list[FlagCommentOut]
    allowed_transitions: list[FlagStatus]
    automated_summary: AutomatedSummaryOut | None = Field(
        default=None, description="VA-004 review agent summary (reviewers only)."
    )


# --------------------------------------------------------------------------- VA-005
SubjectState = Literal["open", "in_review", "resolved"]


class SubjectOutcome(BaseModel):
    """How a flag about the caller was resolved (only once it is resolved)."""

    status: FlagStatus
    label: str | None = Field(description="true_positive | false_positive (VA-006)")
    note: str | None
    resolved_at: datetime


class SubjectFlagOut(BaseModel):
    """VA-005: a flag about the caller, as the caller sees it — no owner, no reviewer notes,
    no escalations; the outcome only after resolution."""

    id: uuid.UUID
    rule_id: str
    rule_title: str | None
    severity: str
    title: str
    state: SubjectState
    created_at: datetime
    can_explain: bool
    outcome: SubjectOutcome | None
    explanations: list[FlagCommentOut]


class SubjectFlagDetailOut(SubjectFlagOut):
    evidence: EvidenceOut


class SubjectFlagPage(BaseModel):
    items: list[SubjectFlagOut]
    next_cursor: str | None = None


class ExplanationIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(min_length=1, max_length=2000)


# --------------------------------------------------------------------------- VA-006
class RulePrecisionOut(BaseModel):
    true_positive: int
    false_positive: int
    resolved: int
    precision: float | None


class RuleQualityOut(BaseModel):
    rule_id: str
    version: int | None
    title: str | None
    enabled: bool
    disabled_reason: str | None
    week: RulePrecisionOut
    four_weeks: RulePrecisionOut
    raised_this_week: int
    open_now: int


class RuleQualityList(BaseModel):
    items: list[RuleQualityOut]
    precision_floor: float
    window_weeks: int


class RuleEnableIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reason: str = Field(min_length=3, max_length=1000)


class RuleOverrideOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    rule_id: str
    enabled: bool
    source: str
    reason: str
    set_by: uuid.UUID | None
    set_at: datetime


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


class RuleVolumeOut(BaseModel):
    """AN-009: one rule's flag volume, resolution time and VA-006 precision."""

    rule_id: str
    title: str | None
    total: int
    open: int
    resolved: int
    false_positives: int
    false_positive_rate: float | None
    median_resolution_hours: float | None
    p90_resolution_hours: float | None
    precision: float | None = Field(
        description="VA-006 precision over the last four weeks of resolutions."
    )
    precision_resolved: int = Field(description="Labelled resolutions behind `precision`.")


class RepeatSubjectOut(BaseModel):
    """AN-009 repeat offender: one subject flagged more than once in the window."""

    subject_type: str
    subject_id: uuid.UUID
    title: str | None = Field(description="Title of the newest flag on the subject.")
    flags: int
    open_flags: int
    rules: list[str]
    last_at: datetime


class FlagSummaryOut(BaseModel):
    """AN-009 data quality over the flags raised in the last `days` IST days."""

    days: int
    from_date: date
    to_date: date
    total: int
    open: int
    resolved: int
    overdue: int = Field(description="Unresolved and past the SLA.")
    by_severity: dict[str, int]
    by_subject_type: dict[str, int]
    by_rule: list[RuleVolumeOut]
    median_resolution_hours: float | None
    p90_resolution_hours: float | None
    false_positive_rate: float | None
    repeat_min: int
    repeat_subjects: list[RepeatSubjectOut]
    precision_floor: float
    precision_window_weeks: int


__all__ = [
    "AssignIn",
    "AutomatedSummaryOut",
    "CommentIn",
    "EvidenceOut",
    "EvidencePhoto",
    "EvidenceRecord",
    "ExplanationIn",
    "FlagCommentOut",
    "FlagCounts",
    "FlagDetailOut",
    "FlagEventOut",
    "FlagOut",
    "FlagPage",
    "FlagSummaryOut",
    "RepeatSubjectOut",
    "RuleEnableIn",
    "RuleOverrideOut",
    "RulePrecisionOut",
    "RuleQualityList",
    "RuleQualityOut",
    "RuleVolumeOut",
    "SubjectFlagDetailOut",
    "SubjectFlagOut",
    "SubjectFlagPage",
    "SubjectOutcome",
    "SubjectState",
    "TransitionIn",
]
