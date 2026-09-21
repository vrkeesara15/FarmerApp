"""Response / request models of the diagnosis ML operations APIs (DX-011, DX-012, AN-007)."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import Any, Literal, Self

from pydantic import BaseModel, ConfigDict, Field

from farmerapp.mlops.models import EvaluationRun, ModelRelease


class EvaluationCropOut(BaseModel):
    """AN-007: one crop's slice of a DX-011 run (the console plots accuracy per crop)."""

    crop_code: str
    cases: int
    correct: int
    top1_accuracy: float | None


def crop_rows(per_crop: dict[str, Any] | None) -> list[EvaluationCropOut]:
    """``{crop_code: tally}`` as the row stores it -> the stable, ordered API list."""
    return [
        EvaluationCropOut(
            crop_code=code,
            cases=int(tally.get("cases", 0)),
            correct=int(tally.get("correct", 0)),
            top1_accuracy=tally.get("top1_accuracy"),
        )
        for code, tally in sorted((per_crop or {}).items())
        if isinstance(tally, dict)
    ]


class EvaluationSummaryOut(BaseModel):
    """One DX-011 run with the per-crop accuracy, without the per-problem tallies."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    status: str
    manifest: str
    started_at: datetime
    finished_at: datetime | None
    encoder: str | None
    llm: str | None
    corpus_version: int | None
    cases: int
    top1_accuracy: float | None
    corpus_answer_share: float | None
    escalation_rate: float | None
    hallucinated_out_of_scope: int
    previous_run_id: uuid.UUID | None
    top1_delta_points: float | None
    alerted: bool
    error: str | None
    crops: list[EvaluationCropOut] = Field(
        default_factory=list,
        description="AN-007: top-1 accuracy per crop of this run, by crop code.",
    )

    @classmethod
    def from_row(cls, row: EvaluationRun) -> Self:
        out = cls.model_validate(row)
        out.crops = crop_rows(row.per_crop)
        return out


class EvaluationRunOut(EvaluationSummaryOut):
    totals: dict[str, Any] = Field(validation_alias="summary")
    per_crop: dict[str, Any]
    per_problem: dict[str, Any]


class EvaluationListOut(BaseModel):
    items: list[EvaluationSummaryOut]


class ReviewSlaOut(BaseModel):
    sla_hours: int
    reviewed: int
    reviewed_within_sla: int
    sla_rate: float | None = Field(description="Reviewed within the SLA / escalations.")
    avg_review_hours: float | None
    median_review_hours: float | None
    open_queue: int
    open_overdue: int


class UnknownOut(BaseModel):
    crop_id: uuid.UUID | None
    crop_code: str | None
    reason: str
    cases: int


class QualityOut(BaseModel):
    """AN-007 diagnosis quality over the last ``days`` IST days."""

    days: int
    from_date: date
    to_date: date
    requests: int
    answered_by_corpus: int
    corpus_share: float | None
    escalated: int
    escalation_rate: float | None
    llm_share: float | None
    by_source: dict[str, int]
    by_status: dict[str, int]
    review: ReviewSlaOut
    top_unknowns: list[UnknownOut]
    latest_evaluation: EvaluationSummaryOut | None
    evaluation_alert_drop_points: float = Field(
        default=5.0,
        description="DX-011: a top-1 drop of more than this many points against the previous "
        "run alerts (tenant setting `diagnosis_evaluation.alert_drop_points`).",
    )


class ModelReleaseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True, protected_namespaces=())

    id: uuid.UUID
    kind: str
    model_name: str
    model_version: str
    artifact_uri: str
    sha256: str
    size_bytes: int
    metadata: dict[str, Any] = Field(validation_alias="model_metadata")
    evaluation: dict[str, Any]
    training_manifest_uri: str | None
    pipeline_run: str | None
    status: str
    decided_by: uuid.UUID | None
    decided_at: datetime | None
    decision_note: str | None
    created_at: datetime
    version: int

    @classmethod
    def from_row(cls, row: ModelRelease) -> ModelReleaseOut:
        return cls.model_validate(row)


class ModelReleaseListOut(BaseModel):
    items: list[ModelReleaseOut]


class ReleaseDecisionIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    decision: Literal["approve", "reject", "retire"]
    note: str | None = Field(default=None, max_length=2000)


class OnDeviceModelOut(BaseModel):
    """What the apps need to download and verify the approved on-device model."""

    model_config = ConfigDict(protected_namespaces=())

    release_id: uuid.UUID
    model_name: str
    model_version: str
    sha256: str
    size_bytes: int
    url: str = Field(description="Signed download URL (15 minutes).")
    url_expires_at: datetime
    labels: Any = None
    thresholds: Any = None
    input: Any = None
    output: Any = None
    approved_at: datetime | None


__all__ = [
    "EvaluationCropOut",
    "EvaluationListOut",
    "EvaluationRunOut",
    "EvaluationSummaryOut",
    "ModelReleaseListOut",
    "ModelReleaseOut",
    "OnDeviceModelOut",
    "QualityOut",
    "ReleaseDecisionIn",
    "ReviewSlaOut",
    "UnknownOut",
    "crop_rows",
]
