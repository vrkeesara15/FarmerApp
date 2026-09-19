"""Request / response models of ``/v1/diagnoses`` and ``/v1/corpus`` (contracts for the
farmer app, the agent app and the console: docs/prs/M6-diagnosis-api.md)."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from farmerapp.api.pagination import PageOut
from farmerapp.diagnosis.models import (
    CorpusImage,
    CorpusProblem,
    CorpusSource,
    CorpusStatus,
    CorpusVersion,
    Diagnosis,
    DiagnosisReview,
    DiagnosisStatus,
    DiagnosisThreshold,
    ImagePart,
    ReviewAction,
    Severity,
)

LANGUAGES = ("en", "te", "kn", "hi", "mr")
MAX_PHOTOS = 3


def _check_languages(value: dict[str, Any]) -> dict[str, Any]:
    unknown = set(value) - set(LANGUAGES)
    if unknown:
        raise ValueError(f"unsupported language keys: {sorted(unknown)}")
    return value


# --------------------------------------------------------------------------- diagnoses
class PhotoQualityIn(BaseModel):
    """What the on-device check (DX-001 / NF-004) measured on the photo."""

    model_config = ConfigDict(extra="forbid")

    passed: bool | None = Field(default=None, description="The device's own verdict.")
    blur_score: float | None = Field(default=None, ge=0)
    brightness: float | None = Field(default=None, ge=0, le=1)
    plant_present: bool | None = Field(
        default=None, description="false = the device saw no leaf / plant (DX-010)."
    )


class DiagnosisPhotoIn(BaseModel):
    blob_uri: str = Field(max_length=512, description="From POST /v1/uploads/{id}/complete.")
    sha256: str | None = Field(default=None, min_length=64, max_length=64)
    quality: PhotoQualityIn | None = None


class CropGuessIn(BaseModel):
    code: str = Field(max_length=32, description="Crop code of the on-device model (DX-001).")
    confidence: float = Field(ge=0, le=1)


class OnDeviceQualityScores(BaseModel):
    model_config = ConfigDict(extra="forbid")

    ok: float | None = Field(default=None, ge=0, le=1)
    blurry: float | None = Field(default=None, ge=0, le=1)
    dark: float | None = Field(default=None, ge=0, le=1)


class OnDeviceHeuristic(BaseModel):
    model_config = ConfigDict(extra="forbid")

    blur_score: float | None = Field(default=None, ge=0)
    brightness: float | None = Field(default=None, ge=0, le=1)


class OnDeviceIn(BaseModel):
    """DX-001 on-device check (ml/ondevice/INTEGRATION.md section 5), kept as DX-005
    provenance. Scores describe the accepted photos; no location or identity."""

    model_config = ConfigDict(extra="forbid")

    model: str = Field(max_length=64, description="On-device model name, e.g. `crop_quality`.")
    model_version: str = Field(
        max_length=64, description="e.g. `ondevice-v1.0` or `heuristic-laplacian-v1`."
    )
    model_sha256: str | None = Field(default=None, pattern=r"^[0-9a-f]{64}$")
    fallback: str | None = Field(
        default=None, max_length=16, description="`laplacian` when the model was not used."
    )
    plant_score: float | None = Field(default=None, ge=0, le=1, description="Is-a-plant.")
    quality: OnDeviceQualityScores | None = None
    crop_scores: dict[str, Annotated[float, Field(ge=0, le=1)]] | None = Field(
        default=None, max_length=16, description="Crop code -> probability."
    )
    heuristic: OnDeviceHeuristic | None = None
    latency_ms: int | None = Field(default=None, ge=0, le=600_000, description="Inference ms.")

    @field_validator("crop_scores")
    @classmethod
    def _crop_codes(cls, value: dict[str, float] | None) -> dict[str, float] | None:
        if value is not None and any(not code or len(code) > 32 for code in value):
            raise ValueError("crop codes are 1-32 characters")
        return value


class DiagnosisCreate(BaseModel):
    """``POST /v1/diagnoses`` and the sync op ``diagnosis`` create (same body)."""

    id: uuid.UUID | None = Field(default=None, description="Client id (offline capture).")
    farmer_id: uuid.UUID | None = Field(
        default=None, description="Required for a field officer; a farmer asks for themself."
    )
    crop_plot_id: uuid.UUID | None = None
    crop_id: uuid.UUID | Literal["unknown"] | None = Field(
        default=None,
        description="The crop the user chose, or `unknown` (then the on-device guess / "
        "corpus). Give `crop_id` or `crop_code`.",
    )
    crop_code: str | None = Field(
        default=None,
        min_length=1,
        max_length=32,
        description="Crop code of the tenant (e.g. `paddy`) instead of `crop_id`; unknown "
        "codes are 422 `diagnosis_invalid`.",
    )
    images: list[DiagnosisPhotoIn] = Field(min_length=1, max_length=MAX_PHOTOS)
    crop_guess: CropGuessIn | None = None
    on_device_model: str | None = Field(default=None, max_length=64)
    crop_stage: str | None = Field(default=None, max_length=16)
    captured_at: datetime | None = None
    ask_expert: bool = Field(default=False, description="FM-006: send to the agronomist too.")
    on_device: OnDeviceIn | None = Field(
        default=None, description="DX-001 on-device scores (DX-005 provenance)."
    )

    @model_validator(mode="after")
    def _one_crop(self) -> DiagnosisCreate:
        if self.crop_id is None and self.crop_code is None:
            raise ValueError("crop_id or crop_code is required")
        if isinstance(self.crop_id, uuid.UUID) and self.crop_code is not None:
            raise ValueError("give crop_id or crop_code, not both")
        return self


class AskExpertIn(BaseModel):
    """FM-006 "Ask an expert" on an answered case."""

    model_config = ConfigDict(extra="forbid")

    note: str | None = Field(default=None, max_length=2000, description="For the agronomist.")


class DiagnosisPhotoOut(BaseModel):
    blob_uri: str
    sha256: str
    quality: dict[str, Any] | None = None
    signed_url: str | None = None


class DiagnosisOut(BaseModel):
    """What the apps poll (``GET /v1/diagnoses/{id}``) and receive in the sync feed."""

    id: uuid.UUID
    subject: str
    farmer_id: uuid.UUID
    crop_plot_id: uuid.UUID | None
    requested_by: uuid.UUID | None
    crop_id: uuid.UUID | None
    crop_detected_on_device: dict[str, Any] | None
    district: str | None
    season: str | None
    crop_stage: str | None
    status: DiagnosisStatus
    source: str | None
    confidence: str | None
    provisional: bool = Field(description="Show 'provisional — expert will confirm' (FM-005).")
    can_buy: bool = Field(description="False until corpus / agronomist confirmed (SPEC 3.4).")
    cta: str | None = Field(description="`buy` | `talk_to_field_officer` | `ask_expert`.")
    message_key: str | None = Field(description="i18n key of the headline message.")
    result: dict[str, Any] | None
    final_problem_id: uuid.UUID | None
    out_of_scope_reason: str | None
    flagged: bool
    expert_requested_at: datetime | None = Field(
        default=None, description="FM-006: when ask-expert moved it into the agronomist queue."
    )
    model_versions: dict[str, Any]
    corpus_version: int | None
    images: list[DiagnosisPhotoOut]
    captured_at: datetime | None
    answered_at: datetime | None
    reviewed_at: datetime | None
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    version: int

    @classmethod
    def from_row(cls, row: Diagnosis) -> DiagnosisOut:
        result = row.result or {}
        return cls(
            id=row.id,
            subject=row.subject,
            farmer_id=row.farmer_id,
            crop_plot_id=row.crop_plot_id,
            requested_by=row.requested_by,
            crop_id=row.crop_id,
            crop_detected_on_device=row.crop_detected_on_device,
            district=row.district,
            season=row.season,
            crop_stage=row.crop_stage,
            status=DiagnosisStatus(row.status),
            source=row.source,
            confidence=row.confidence,
            provisional=bool(result.get("provisional", row.status == "queued")),
            can_buy=bool(result.get("can_buy", False)),
            cta=result.get("cta"),
            message_key=result.get("message_key"),
            result=row.result,
            final_problem_id=row.final_problem_id,
            out_of_scope_reason=row.out_of_scope_reason,
            flagged=row.flagged,
            expert_requested_at=row.expert_requested_at,
            model_versions=dict(row.model_versions or {}),
            corpus_version=row.corpus_version,
            images=[
                DiagnosisPhotoOut(
                    blob_uri=i["blob_uri"], sha256=i["sha256"], quality=i.get("quality")
                )
                for i in row.images or []
            ],
            captured_at=row.captured_at,
            answered_at=row.answered_at,
            reviewed_at=row.reviewed_at,
            created_at=row.created_at,
            updated_at=row.updated_at,
            deleted_at=row.deleted_at,
            version=row.version,
        )


class DiagnosisReviewOut(BaseModel):
    id: uuid.UUID
    actor_id: uuid.UUID | None
    action: str
    from_status: str
    to_status: str
    from_problem_id: uuid.UUID | None
    to_problem_id: uuid.UUID | None
    note: str | None
    add_to_corpus: bool
    corpus_image_ids: list[uuid.UUID]
    created_at: datetime

    @classmethod
    def from_row(cls, row: DiagnosisReview) -> DiagnosisReviewOut:
        return cls(
            id=row.id,
            actor_id=row.actor_id,
            action=row.action,
            from_status=row.from_status,
            to_status=row.to_status,
            from_problem_id=row.from_problem_id,
            to_problem_id=row.to_problem_id,
            note=row.note,
            add_to_corpus=row.add_to_corpus,
            corpus_image_ids=list(row.corpus_image_ids or []),
            created_at=row.created_at,
        )


class DiagnosisDetailOut(DiagnosisOut):
    """Reviewer view (agronomist / owner / director / tenant admin): provenance included."""

    scores: dict[str, Any] | None = Field(
        default=None, description="DX-005 neighbours, votes, candidates, thresholds."
    )
    reviews: list[DiagnosisReviewOut] = Field(default_factory=list)
    reviewed_by: uuid.UUID | None = None
    llm_used: bool = False
    on_device: dict[str, Any] | None = Field(
        default=None, description="DX-001 on-device block as sent by the app (DX-005)."
    )
    expert_requested_by: uuid.UUID | None = None
    expert_note: str | None = Field(default=None, description="FM-006 ask-expert note.")


class DiagnosisPage(PageOut[DiagnosisOut]):
    pass


class ReviewQueueItem(DiagnosisDetailOut):
    age_hours: float
    overdue: bool = Field(description="Older than the 18 h DX-006 alert threshold.")


class ReviewQueueCounts(BaseModel):
    total: int
    overdue: int
    by_confidence: dict[str, int]


class ReviewQueuePage(PageOut[ReviewQueueItem]):
    counts: ReviewQueueCounts


class ReviewIn(BaseModel):
    action: ReviewAction
    problem_id: uuid.UUID | None = Field(
        default=None, description="Corpus problem id; required to `correct`."
    )
    note: str = Field(min_length=1, max_length=2000)
    add_to_corpus: bool = Field(
        default=False, description="Add the photos to the corpus as `reviewed` images."
    )


class ThresholdIn(BaseModel):
    crop_id: uuid.UUID | None = Field(default=None, description="null = the tenant default.")
    t1: float = Field(gt=0, le=1)
    agreement: float = Field(gt=0, le=1)
    min_similarity: float = Field(ge=0, le=1)
    note: str | None = Field(default=None, max_length=2000)


class ThresholdOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    crop_id: uuid.UUID | None
    t1: float
    agreement: float
    min_similarity: float
    config_version: int
    set_by: uuid.UUID | None
    note: str | None
    created_at: datetime

    @classmethod
    def from_row(cls, row: DiagnosisThreshold) -> ThresholdOut:
        return cls.model_validate(row)


class ThresholdsOut(BaseModel):
    defaults: dict[str, float]
    items: list[ThresholdOut]


# --------------------------------------------------------------------------- corpus
class CorpusProblemCreate(BaseModel):
    pest_or_disease_id: uuid.UUID
    crop_id: uuid.UUID
    names: dict[str, str] = Field(description="Per language; `en` required.")
    symptoms: dict[str, list[str]] = Field(default_factory=dict)
    cultural_practices: dict[str, list[str]] = Field(default_factory=dict)
    source: CorpusSource = CorpusSource.INTERNAL
    notes: str | None = Field(default=None, max_length=4000)

    @field_validator("names")
    @classmethod
    def _names(cls, value: dict[str, str]) -> dict[str, str]:
        if not value.get("en"):
            raise ValueError("names.en is required")
        return _check_languages(value)

    @field_validator("symptoms", "cultural_practices")
    @classmethod
    def _langs(cls, value: dict[str, list[str]]) -> dict[str, list[str]]:
        return _check_languages(value)


class CorpusProblemUpdate(BaseModel):
    names: dict[str, str] | None = None
    symptoms: dict[str, list[str]] | None = None
    cultural_practices: dict[str, list[str]] | None = None
    notes: str | None = Field(default=None, max_length=4000)

    @field_validator("names", "symptoms", "cultural_practices")
    @classmethod
    def _langs(cls, value: dict[str, Any] | None) -> dict[str, Any] | None:
        return None if value is None else _check_languages(value)


class CorpusProblemOut(BaseModel):
    id: uuid.UUID
    pest_or_disease_id: uuid.UUID
    pest_code: str | None
    crop_id: uuid.UUID
    problem_type: str
    names: dict[str, Any]
    symptoms: dict[str, Any]
    cultural_practices: dict[str, Any]
    status: CorpusStatus
    source: str
    labelled_by: uuid.UUID | None
    reviewed_by: uuid.UUID | None
    reviewed_at: datetime | None
    approved_by: uuid.UUID | None
    approved_at: datetime | None
    approved_in_version: int | None
    retired_at: datetime | None
    notes: str | None
    image_counts: dict[str, int]
    created_at: datetime
    updated_at: datetime
    version: int

    @classmethod
    def from_row(
        cls, row: CorpusProblem, *, pest_code: str | None, image_counts: dict[str, int]
    ) -> CorpusProblemOut:
        return cls(
            id=row.id,
            pest_or_disease_id=row.pest_or_disease_id,
            pest_code=pest_code,
            crop_id=row.crop_id,
            problem_type=row.problem_type,
            names=dict(row.names or {}),
            symptoms=dict(row.symptoms or {}),
            cultural_practices=dict(row.cultural_practices or {}),
            status=CorpusStatus(row.status),
            source=row.source,
            labelled_by=row.labelled_by,
            reviewed_by=row.reviewed_by,
            reviewed_at=row.reviewed_at,
            approved_by=row.approved_by,
            approved_at=row.approved_at,
            approved_in_version=row.approved_in_version,
            retired_at=row.retired_at,
            notes=row.notes,
            image_counts=image_counts,
            created_at=row.created_at,
            updated_at=row.updated_at,
            version=row.version,
        )


class CorpusProblemPage(PageOut[CorpusProblemOut]):
    corpus_version: int


class CorpusImageCreate(BaseModel):
    blob_uri: str = Field(max_length=512, description="A completed upload (purpose `corpus`).")
    sha256: str | None = Field(default=None, min_length=64, max_length=64)
    stage: str | None = Field(default=None, max_length=16)
    part: ImagePart | None = None
    severity: Severity | None = None
    region: str | None = Field(default=None, max_length=80)
    season: str | None = Field(default=None, max_length=8)
    source: CorpusSource = CorpusSource.INTERNAL


class CorpusImageOut(BaseModel):
    id: uuid.UUID
    problem_id: uuid.UUID
    crop_id: uuid.UUID
    blob_uri: str
    sha256: str
    encoder_name: str
    encoder_version: str
    stage: str | None
    part: str | None
    severity: str | None
    region: str | None
    season: str | None
    source: str
    status: CorpusStatus
    labelled_by: uuid.UUID | None
    approved_by: uuid.UUID | None
    approved_at: datetime | None
    approved_in_version: int | None
    from_diagnosis_id: uuid.UUID | None
    created_at: datetime
    version: int
    signed_url: str | None = Field(default=None, description="15-minute read URL (listings).")

    @classmethod
    def from_row(cls, row: CorpusImage) -> CorpusImageOut:
        return cls(
            id=row.id,
            problem_id=row.problem_id,
            crop_id=row.crop_id,
            blob_uri=row.blob_uri,
            sha256=row.sha256,
            encoder_name=row.encoder_name,
            encoder_version=row.encoder_version,
            stage=row.stage,
            part=row.part,
            severity=row.severity,
            region=row.region,
            season=row.season,
            source=row.source,
            status=CorpusStatus(row.status),
            labelled_by=row.labelled_by,
            approved_by=row.approved_by,
            approved_at=row.approved_at,
            approved_in_version=row.approved_in_version,
            from_diagnosis_id=row.from_diagnosis_id,
            created_at=row.created_at,
            version=row.version,
        )


class CorpusImagePage(PageOut[CorpusImageOut]):
    pass


class CorpusTransitionIn(BaseModel):
    to: CorpusStatus
    note: str | None = Field(default=None, max_length=2000)


class CorpusApprovalIn(BaseModel):
    problem_ids: list[uuid.UUID] = Field(default_factory=list, max_length=500)
    image_ids: list[uuid.UUID] = Field(default_factory=list, max_length=2000)
    note: str | None = Field(default=None, max_length=2000)


class CorpusVersionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    version: int
    approved_by: uuid.UUID | None
    note: str | None
    changes: dict[str, Any]
    created_at: datetime

    @classmethod
    def from_row(cls, row: CorpusVersion) -> CorpusVersionOut:
        return cls.model_validate(row)


class CorpusVersionsOut(BaseModel):
    current: int
    items: list[CorpusVersionOut]


__all__ = [
    "LANGUAGES",
    "MAX_PHOTOS",
    "AskExpertIn",
    "CorpusApprovalIn",
    "CorpusImageCreate",
    "CorpusImageOut",
    "CorpusImagePage",
    "CorpusProblemCreate",
    "CorpusProblemOut",
    "CorpusProblemPage",
    "CorpusProblemUpdate",
    "CorpusTransitionIn",
    "CorpusVersionOut",
    "CorpusVersionsOut",
    "CropGuessIn",
    "DiagnosisCreate",
    "DiagnosisDetailOut",
    "DiagnosisOut",
    "DiagnosisPage",
    "DiagnosisPhotoIn",
    "DiagnosisPhotoOut",
    "DiagnosisReviewOut",
    "OnDeviceIn",
    "PhotoQualityIn",
    "ReviewIn",
    "ReviewQueueCounts",
    "ReviewQueueItem",
    "ReviewQueuePage",
    "ThresholdIn",
    "ThresholdOut",
    "ThresholdsOut",
]
