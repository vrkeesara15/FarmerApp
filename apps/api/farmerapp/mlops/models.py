"""Diagnosis ML operations data model (M7; Alembic ``0032_farmer_p1``).

* ``evaluation_run`` — DX-011: one nightly evaluation of the production decision path over
  the held-out, agronomist-labelled manifest: top-1 accuracy, corpus-answer share,
  escalation rate, per crop / per problem tallies, the drop against the previous run and
  whether it alerted (> ``diagnosis_evaluation.alert_drop_points``).
* ``model_release`` — DX-012 approval gate: a candidate on-device model (artifact URI in the
  corpus bucket, sha256, metadata, evaluation numbers, the training manifest it came from)
  moves ``candidate -> approved | rejected`` by an agronomist or the owner; an approved
  release may later be ``retired``. Apps only ever download the newest approved release
  (``GET /v1/models/on-device/current``).
* ``corpus_embedding`` — DX-012 re-embedding: the vector of an approved corpus image under an
  encoder version that is **not yet active** (or the previous one, kept for rollback). The
  kNN keeps reading ``corpus_image.embedding`` (the active encoder); a staged encoder is
  searchable here while the API pin moves, and ``activate-encoder`` copies it into
  ``corpus_image`` in one transaction.
* ``encoder_activation`` — DX-012: append-only history of the active encoder per tenant (who
  flipped it, when, how many images).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from farmerapp.catalog.models import sql_in
from farmerapp.db.base import Base, BaseColumns, TenantRow
from farmerapp.diagnosis.encoder import EMBEDDING_DIM


class EvaluationStatus(StrEnum):
    OK = "ok"
    FAILED = "failed"


class ReleaseKind(StrEnum):
    ON_DEVICE = "on_device"  # DX-001 plant / quality / crop TFLite model


class ReleaseStatus(StrEnum):
    CANDIDATE = "candidate"
    APPROVED = "approved"
    REJECTED = "rejected"
    RETIRED = "retired"


#: DX-012 approval gate transitions.
RELEASE_TRANSITIONS: dict[ReleaseStatus, frozenset[ReleaseStatus]] = {
    ReleaseStatus.CANDIDATE: frozenset({ReleaseStatus.APPROVED, ReleaseStatus.REJECTED}),
    ReleaseStatus.APPROVED: frozenset({ReleaseStatus.RETIRED}),
    ReleaseStatus.REJECTED: frozenset(),
    ReleaseStatus.RETIRED: frozenset(),
}


class EvaluationRun(Base, BaseColumns):
    __tablename__ = "evaluation_run"
    __table_args__ = (
        CheckConstraint(f"status IN ({sql_in(EvaluationStatus)})", name="status"),
        Index("ix_evaluation_run_tenant_started", "tenant_id", "started_at"),
    )

    manifest: Mapped[str] = mapped_column(String(512), nullable=False)
    status: Mapped[str] = mapped_column(String(8), nullable=False)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    encoder: Mapped[str | None] = mapped_column(String(100), nullable=True)
    llm: Mapped[str | None] = mapped_column(String(64), nullable=True)
    corpus_version: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cases: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    top1_accuracy: Mapped[float | None] = mapped_column(Float, nullable=True)
    corpus_answer_share: Mapped[float | None] = mapped_column(Float, nullable=True)
    escalation_rate: Mapped[float | None] = mapped_column(Float, nullable=True)
    hallucinated_out_of_scope: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    #: the overall tally (`totals` in the API body; the column avoids the money-column
    #: naming rule of tests/catalog/test_models.py)
    summary: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    per_crop: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    per_problem: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    previous_run_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("evaluation_run.id", ondelete="SET NULL"), nullable=True
    )
    #: (this run - previous run) top-1 accuracy in percentage points
    top1_delta_points: Mapped[float | None] = mapped_column(Float, nullable=True)
    alerted: Mapped[bool] = mapped_column(
        nullable=False, server_default=text("false"), default=False
    )
    error: Mapped[str | None] = mapped_column(Text, nullable=True)


class ModelRelease(Base, BaseColumns):
    __tablename__ = "model_release"
    __table_args__ = (
        UniqueConstraint("tenant_id", "kind", "model_version"),
        CheckConstraint(f"kind IN ({sql_in(ReleaseKind)})", name="kind"),
        CheckConstraint(f"status IN ({sql_in(ReleaseStatus)})", name="status"),
        CheckConstraint("char_length(sha256) = 64", name="sha256"),
        CheckConstraint(
            "status NOT IN ('approved', 'rejected', 'retired') OR decided_at IS NOT NULL",
            name="decided_at",
        ),
        Index("ix_model_release_kind_status", "tenant_id", "kind", "status"),
    )

    kind: Mapped[str] = mapped_column(String(16), nullable=False)
    model_name: Mapped[str] = mapped_column(String(100), nullable=False)
    model_version: Mapped[str] = mapped_column(String(64), nullable=False)
    artifact_uri: Mapped[str] = mapped_column(String(512), nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    size_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False)
    #: the exporter's metadata.json (labels, thresholds, input / output contract, sources)
    model_metadata: Mapped[dict[str, Any]] = mapped_column(
        "metadata", JSONB, nullable=False, default=dict
    )
    #: evaluation numbers the approver saw (test split and field set per head)
    evaluation: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False, default=dict)
    training_manifest_uri: Mapped[str | None] = mapped_column(String(512), nullable=True)
    pipeline_run: Mapped[str | None] = mapped_column(String(256), nullable=True)
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        server_default=text("'candidate'"),
        default=ReleaseStatus.CANDIDATE,
    )
    decided_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    decision_note: Mapped[str | None] = mapped_column(Text, nullable=True)


class CorpusEmbedding(Base, TenantRow):
    """A staged (or previous) encoder's vector of one corpus image; rows are replaced, never
    updated in place, so the mixin is the lean one."""

    __tablename__ = "corpus_embedding"
    __table_args__ = (
        UniqueConstraint("corpus_image_id", "encoder_name", "encoder_version"),
        Index(
            "ix_corpus_embedding_hnsw",
            "embedding",
            postgresql_using="hnsw",
            postgresql_with={"m": 16, "ef_construction": 64},
            postgresql_ops={"embedding": "vector_cosine_ops"},
        ),
        Index("ix_corpus_embedding_encoder", "tenant_id", "encoder_name", "encoder_version"),
    )
    __audit__ = False  # derived data (vectors), re-computable from the audited images

    corpus_image_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("corpus_image.id", ondelete="CASCADE"), nullable=False
    )
    encoder_name: Mapped[str] = mapped_column(String(64), nullable=False)
    encoder_version: Mapped[str] = mapped_column(String(32), nullable=False)
    embedding: Mapped[list[float]] = mapped_column(Vector(EMBEDDING_DIM), nullable=False)


class EncoderActivation(Base, TenantRow):
    """Append-only: every flip of the active encoder of a tenant's corpus (DX-012)."""

    __tablename__ = "encoder_activation"
    __table_args__ = (Index("ix_encoder_activation_tenant_created", "tenant_id", "created_at"),)

    encoder_name: Mapped[str] = mapped_column(String(64), nullable=False)
    encoder_version: Mapped[str] = mapped_column(String(32), nullable=False)
    previous_name: Mapped[str | None] = mapped_column(String(64), nullable=True)
    previous_version: Mapped[str | None] = mapped_column(String(32), nullable=True)
    images: Mapped[int] = mapped_column(Integer, nullable=False)
    activated_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user.id", ondelete="SET NULL"), nullable=True
    )
    note: Mapped[str | None] = mapped_column(Text, nullable=True)


__all__ = [
    "RELEASE_TRANSITIONS",
    "CorpusEmbedding",
    "EncoderActivation",
    "EvaluationRun",
    "EvaluationStatus",
    "ModelRelease",
    "ReleaseKind",
    "ReleaseStatus",
]
