"""Diagnosis engine data model (SPEC 3, 8.2; Alembic ``0027_m6_diagnosis``).

Corpus (SPEC 3.2, WC-007):

* ``corpus_problem`` — one diagnosable problem **of one crop**: it references the shared
  ``pest_or_disease`` master (which, with ``label_claim``, stays the single source of truth
  for treatments, DX-007), carries names and a symptom checklist per language, cultural
  practices, the status workflow ``draft -> reviewed -> approved -> retired`` and its
  provenance (labelled / reviewed / approved by, when, ``source`` internal | public).
* ``corpus_image`` — a labelled image of a problem: blob URI + sha256, the 768-dim
  embedding (pgvector, HNSW ``vector_cosine_ops``) with the encoder name + version that
  produced it (DX-005: the kNN never compares vectors of two encoders), stage, part, severity,
  region, season, source and its own status. ``crop_id`` is denormalised from the problem so
  the kNN filter needs no join to narrow the crop.
* ``corpus_version`` — append-only, monotonic per tenant: every approval set bumps it; every
  diagnosis stores the version it ran against (DX-005).

**Only approved problems with approved images are used in production** (WC-007): the kNN
filters on both statuses.

Diagnoses (SPEC 3 flowchart, FA-019, FM-004 / FM-005, DX-005, DX-006):

* ``diagnosis`` — who asked (``subject`` farmer | officer, ``requested_by``), for which farmer
  and crop plot, the images (blob URI + sha256 + on-device quality), the crop (chosen or
  detected on the device), district and season, the lifecycle status, the farmer-facing
  ``result``, ``source`` / ``confidence``, and the provenance: ``model_versions`` (encoder,
  on-device, LLM), ``corpus_version``, ``scores`` (neighbours, votes, candidates, thresholds)
  and ``final_problem_id``. Review fields and ``notified_at`` for the agronomist queue.
* ``diagnosis_review`` — append-only history of agronomist actions (WC-006).
* ``diagnosis_threshold`` — DX-003 decision thresholds per crop (``crop_id`` NULL = tenant
  default), versioned: a change is a new row with the next ``config_version``; the newest row per
  crop is in force; audited like every table.
* ``llm_call_log`` — append-only record of every LLM fallback call (SEC-027, SPEC 3.4): the
  prompt without image bytes (blob URI + sha256 instead), the raw output, model, latency,
  tokens, stop reason; ``retain_until`` = one year after the call.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from enum import StrEnum
from typing import Any

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import ProblemType, sql_in
from farmerapp.db.base import Base, BaseColumns, TenantRow
from farmerapp.diagnosis.encoder import EMBEDDING_DIM


class CorpusStatus(StrEnum):
    DRAFT = "draft"
    REVIEWED = "reviewed"
    APPROVED = "approved"
    RETIRED = "retired"


#: WC-007 workflow: draft -> reviewed -> approved -> retired (a reviewed entry may go back to
#: draft for changes; retired is final — a new entry replaces it).
CORPUS_TRANSITIONS: dict[CorpusStatus, frozenset[CorpusStatus]] = {
    CorpusStatus.DRAFT: frozenset({CorpusStatus.REVIEWED, CorpusStatus.RETIRED}),
    CorpusStatus.REVIEWED: frozenset(
        {CorpusStatus.APPROVED, CorpusStatus.DRAFT, CorpusStatus.RETIRED}
    ),
    CorpusStatus.APPROVED: frozenset({CorpusStatus.RETIRED}),
    CorpusStatus.RETIRED: frozenset(),
}


class CorpusSource(StrEnum):
    INTERNAL = "internal"  # FCC field images, agronomist-labelled (SPEC 3.3 step 3)
    PUBLIC = "public"  # licensed public datasets, bootstrap only (SPEC 3.3 step 2)


class ImagePart(StrEnum):
    LEAF = "leaf"
    STEM = "stem"
    FRUIT = "fruit"
    WHOLE = "whole"


class Severity(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class DiagnosisSubject(StrEnum):
    FARMER = "farmer"  # the farmer's own crop doctor (FM-004)
    OFFICER = "officer"  # a field officer scouting for a farmer (FA-019)


class DiagnosisStatus(StrEnum):
    QUEUED = "queued"
    ANSWERED = "answered"  # corpus answer, high confidence
    PROVISIONAL = "provisional"  # LLM / medium-low: expert will confirm
    CONFIRMED = "confirmed"  # agronomist confirmed
    CORRECTED = "corrected"  # agronomist corrected the label
    OUT_OF_SCOPE = "out_of_scope"  # not a plant / unsupported crop / no match (DX-010)


class DiagnosisSource(StrEnum):
    CORPUS = "corpus"
    LLM = "llm"
    AGRONOMIST = "agronomist"


class Confidence(StrEnum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class ReviewAction(StrEnum):
    CONFIRM = "confirm"
    CORRECT = "correct"
    NOT_DIAGNOSABLE = "not_diagnosable"  # expert closes an out-of-scope / unknown case


#: Statuses the agronomist queue shows until someone reviews them (DX-006, WC-006).
REVIEWABLE: frozenset[DiagnosisStatus] = frozenset(
    {DiagnosisStatus.PROVISIONAL, DiagnosisStatus.OUT_OF_SCOPE}
)


class CorpusProblem(Base, BaseColumns):
    __tablename__ = "corpus_problem"
    __table_args__ = (
        Index(
            "uq_corpus_problem_crop_pest",
            "tenant_id",
            "crop_id",
            "pest_or_disease_id",
            unique=True,
            postgresql_where=text("deleted_at IS NULL AND status <> 'retired'"),
        ),
        CheckConstraint(f"status IN ({sql_in(CorpusStatus)})", name="status"),
        CheckConstraint(f"source IN ({sql_in(CorpusSource)})", name="source"),
        CheckConstraint(f"problem_type IN ({sql_in(ProblemType)})", name="problem_type"),
        CheckConstraint("status <> 'approved' OR approved_at IS NOT NULL", name="approved_at"),
        Index("ix_corpus_problem_crop_status", "tenant_id", "crop_id", "status"),
        Index("ix_corpus_problem_pest_or_disease_id", "pest_or_disease_id"),
    )

    pest_or_disease_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("pest_or_disease.id", ondelete="RESTRICT"), nullable=False
    )
    crop_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("crop.id", ondelete="RESTRICT"), nullable=False
    )
    problem_type: Mapped[str] = mapped_column(String(16), nullable=False)
    #: {"en": "Rice blast", "te": "...", "kn": ..., "hi": ..., "mr": ...}
    names: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    #: {"en": ["Spindle-shaped spots ...", ...], "te": [...]} (SPEC 3.2 checklist)
    symptoms: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    #: DX-007 cultural treatments per language (the product treatments come from label claims)
    cultural_practices: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'draft'"), default=CorpusStatus.DRAFT
    )
    source: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'internal'"), default="internal"
    )
    labelled_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    approved_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    retired_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    #: corpus_version that approved it (DX-005)
    approved_in_version: Mapped[int | None] = mapped_column(Integer, nullable=True)
    #: "high confidence capable" once it has >= 150 approved field images (SPEC 3.3 step 4)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)


class CorpusImage(Base, BaseColumns):
    __tablename__ = "corpus_image"
    __table_args__ = (
        UniqueConstraint("tenant_id", "problem_id", "sha256"),
        CheckConstraint(f"status IN ({sql_in(CorpusStatus)})", name="status"),
        CheckConstraint(f"source IN ({sql_in(CorpusSource)})", name="source"),
        CheckConstraint(f"part IS NULL OR part IN ({sql_in(ImagePart)})", name="part"),
        CheckConstraint(f"severity IS NULL OR severity IN ({sql_in(Severity)})", name="severity"),
        CheckConstraint("char_length(sha256) = 64", name="sha256"),
        CheckConstraint("status <> 'approved' OR approved_at IS NOT NULL", name="approved_at"),
        Index(
            "ix_corpus_image_embedding_hnsw",
            "embedding",
            postgresql_using="hnsw",
            postgresql_with={"m": 16, "ef_construction": 64},
            postgresql_ops={"embedding": "vector_cosine_ops"},
        ),
        Index("ix_corpus_image_crop_status", "tenant_id", "crop_id", "status"),
        Index("ix_corpus_image_problem_id", "problem_id"),
    )

    problem_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("corpus_problem.id", ondelete="CASCADE"), nullable=False
    )
    crop_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("crop.id", ondelete="RESTRICT"), nullable=False
    )
    blob_uri: Mapped[str] = mapped_column(String(512), nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    embedding: Mapped[list[float]] = mapped_column(Vector(EMBEDDING_DIM), nullable=False)
    encoder_name: Mapped[str] = mapped_column(String(64), nullable=False)
    encoder_version: Mapped[str] = mapped_column(String(32), nullable=False)
    stage: Mapped[str | None] = mapped_column(String(16), nullable=True)  # crop stage
    part: Mapped[str | None] = mapped_column(String(8), nullable=True)
    severity: Mapped[str | None] = mapped_column(String(8), nullable=True)
    region: Mapped[str | None] = mapped_column(String(80), nullable=True)  # district
    season: Mapped[str | None] = mapped_column(String(8), nullable=True)
    source: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'internal'"), default="internal"
    )
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'draft'"), default=CorpusStatus.DRAFT
    )
    labelled_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    approved_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    approved_in_version: Mapped[int | None] = mapped_column(Integer, nullable=True)
    #: WC-006 "add to corpus": the diagnosis the image came from
    from_diagnosis_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("diagnosis.id", ondelete="SET NULL"), nullable=True
    )


class CorpusVersion(Base, TenantRow):
    """Append-only: one row per approval set; ``version`` is monotonic per tenant."""

    __tablename__ = "corpus_version"
    __table_args__ = (
        UniqueConstraint("tenant_id", "version"),
        CheckConstraint("version >= 1", name="version"),
    )

    version: Mapped[int] = mapped_column(Integer, nullable=False)
    approved_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    #: {"problems": [ids], "images": [ids], "retired": [ids]} of this set
    changes: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)


class Diagnosis(Base, BaseColumns):
    __tablename__ = "diagnosis"
    __table_args__ = (
        CheckConstraint(f"subject IN ({sql_in(DiagnosisSubject)})", name="subject"),
        CheckConstraint(f"status IN ({sql_in(DiagnosisStatus)})", name="status"),
        CheckConstraint(f"source IS NULL OR source IN ({sql_in(DiagnosisSource)})", name="source"),
        CheckConstraint(
            f"confidence IS NULL OR confidence IN ({sql_in(Confidence)})", name="confidence"
        ),
        CheckConstraint("attempts >= 0", name="attempts"),
        Index("ix_diagnosis_farmer_created", "tenant_id", "farmer_id", "created_at"),
        Index("ix_diagnosis_status_created", "tenant_id", "status", "created_at"),
        Index("ix_diagnosis_requested_by", "requested_by"),
        Index("ix_diagnosis_crop_plot_id", "crop_plot_id"),
    )

    subject: Mapped[str] = mapped_column(String(8), nullable=False)
    farmer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("farmer.id", ondelete="CASCADE"), nullable=False
    )
    crop_plot_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("crop_plot.id", ondelete="SET NULL"), nullable=True
    )
    requested_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    #: [{"blob_uri", "sha256", "quality": {...}}] — 1 to 3 photos (FM-004)
    images: Mapped[list[dict[str, Any]]] = mapped_column(JSONB, nullable=False, default=list)
    crop_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("crop.id", ondelete="RESTRICT"), nullable=True
    )
    #: the on-device crop guess (DX-001): {"code": "paddy", "confidence": 0.93}
    crop_detected_on_device: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    district: Mapped[str | None] = mapped_column(String(80), nullable=True)
    season: Mapped[str | None] = mapped_column(String(8), nullable=True)
    crop_stage: Mapped[str | None] = mapped_column(String(16), nullable=True)
    language: Mapped[str] = mapped_column(String(8), nullable=False, server_default="en")
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=text("'queued'"), default="queued"
    )
    #: farmer-facing answer (problem, symptoms, treatments, message key, cta, can_buy)
    result: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    source: Mapped[str | None] = mapped_column(String(16), nullable=True)
    confidence: Mapped[str | None] = mapped_column(String(8), nullable=True)
    #: DX-005 {"encoder": "fake-dct@1", "on_device": "...", "llm": "claude-opus-5" | null}
    model_versions: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    corpus_version: Mapped[int | None] = mapped_column(Integer, nullable=True)
    #: DX-001 / DX-005 on-device block the app sent (model, version, plant / quality / crop
    #: scores, latency_ms, fallback) — ml/ondevice/INTEGRATION.md section 5
    on_device: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    #: DX-005 {"top1", "votes", "agreement", "neighbours", "candidates", "thresholds", ...}
    scores: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    final_problem_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("corpus_problem.id", ondelete="SET NULL"), nullable=True
    )
    out_of_scope_reason: Mapped[str | None] = mapped_column(String(32), nullable=True)
    llm_used: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false"), default=False
    )
    #: FM-006 "ask expert" / officer escalation: put it in the queue whatever the confidence
    flagged: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false"), default=False
    )
    #: FM-006 ``POST /v1/diagnoses/{id}/ask-expert``: who moved it into the queue, when, why
    expert_requested_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    expert_requested_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    expert_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    captured_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    answered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    notified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    #: OPS-009: when the 18 h queue-age alert went out for it (once)
    age_alerted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class DiagnosisReview(Base, TenantRow):
    """Append-only WC-006 history: every agronomist action on a diagnosis."""

    __tablename__ = "diagnosis_review"
    __table_args__ = (
        CheckConstraint(f"action IN ({sql_in(ReviewAction)})", name="action"),
        Index("ix_diagnosis_review_diagnosis_id", "diagnosis_id"),
    )

    diagnosis_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("diagnosis.id", ondelete="CASCADE"), nullable=False
    )
    actor_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    action: Mapped[str] = mapped_column(String(16), nullable=False)
    from_status: Mapped[str] = mapped_column(String(16), nullable=False)
    to_status: Mapped[str] = mapped_column(String(16), nullable=False)
    from_problem_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    to_problem_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    add_to_corpus: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    corpus_image_ids: Mapped[list[uuid.UUID]] = mapped_column(
        ARRAY(Uuid()), nullable=False, default=list
    )


class DiagnosisThreshold(Base, BaseColumns):
    """DX-003 thresholds, versioned per crop (``crop_id`` NULL = the tenant default)."""

    __tablename__ = "diagnosis_threshold"
    __table_args__ = (
        Index(
            "uq_diagnosis_threshold_crop_version",
            "tenant_id",
            text("coalesce(crop_id, '00000000-0000-0000-0000-000000000000'::uuid)"),
            "config_version",
            unique=True,
        ),
        CheckConstraint("t1 > 0 AND t1 <= 1", name="t1"),
        CheckConstraint("agreement > 0 AND agreement <= 1", name="agreement"),
        CheckConstraint("min_similarity >= 0 AND min_similarity <= t1", name="min_similarity"),
        CheckConstraint("config_version >= 1", name="config_version"),
    )

    crop_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("crop.id", ondelete="RESTRICT"), nullable=True
    )
    t1: Mapped[float] = mapped_column(Float, nullable=False)
    agreement: Mapped[float] = mapped_column(Float, nullable=False)
    min_similarity: Mapped[float] = mapped_column(Float, nullable=False)
    #: the DX-003 config version of this crop (1, 2, ...); ``version`` is the row lock
    config_version: Mapped[int] = mapped_column(Integer, nullable=False)
    set_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    note: Mapped[str | None] = mapped_column(Text, nullable=True)


class LlmCallLog(Base, TenantRow):
    """Append-only SEC-027 / SPEC 3.4 log of every LLM fallback call (kept one year)."""

    __tablename__ = "llm_call_log"
    __table_args__ = (
        Index("ix_llm_call_log_diagnosis_id", "diagnosis_id"),
        Index("ix_llm_call_log_flag_id", "flag_id"),
        Index("ix_llm_call_log_tenant_created", "tenant_id", "created_at"),
    )
    __audit__ = False  # it *is* the audit record of the call

    diagnosis_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("diagnosis.id", ondelete="SET NULL"), nullable=True
    )
    #: M7 (0029): the flag a VA-004 review-agent summary call was about (NULL for DX-004).
    flag_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("flag.id", ondelete="SET NULL"), nullable=True
    )
    provider: Mapped[str] = mapped_column(String(32), nullable=False)
    model: Mapped[str] = mapped_column(String(64), nullable=False)
    attempt: Mapped[int] = mapped_column(Integer, nullable=False)
    #: system + text blocks + image references ({blob_uri, sha256, sent_sha256, bytes}); never
    #: the image bytes
    prompt: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    raw_output: Mapped[str | None] = mapped_column(Text, nullable=True)
    parsed: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    outcome: Mapped[str] = mapped_column(String(16), nullable=False)
    stop_reason: Mapped[str | None] = mapped_column(String(32), nullable=True)
    stop_details: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    input_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    output_tokens: Mapped[int | None] = mapped_column(Integer, nullable=True)
    latency_ms: Mapped[int] = mapped_column(Integer, nullable=False)
    retain_until: Mapped[date] = mapped_column(Date, nullable=False)


__all__ = [
    "CORPUS_TRANSITIONS",
    "REVIEWABLE",
    "Confidence",
    "CorpusImage",
    "CorpusProblem",
    "CorpusSource",
    "CorpusStatus",
    "CorpusVersion",
    "Diagnosis",
    "DiagnosisReview",
    "DiagnosisSource",
    "DiagnosisStatus",
    "DiagnosisSubject",
    "DiagnosisThreshold",
    "ImagePart",
    "LlmCallLog",
    "ReviewAction",
    "Severity",
]
