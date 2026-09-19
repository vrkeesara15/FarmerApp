"""DX-012 on-device model releases and their approval gate.

A retraining run (``ml/ondevice/finetune.py``, or the Vertex AI pipeline in ``ml/pipelines``)
uploads a candidate TFLite model and its ``metadata.json`` to the corpus bucket; the
``register-model-candidate`` job records it (``model_release``, status ``candidate``, sha256
and size computed from the uploaded bytes, never trusted from the metadata) and notifies the
agronomists and owners. An agronomist or the owner approves or rejects it through
``POST /v1/models/releases/{id}/decision`` (step-up; audited) — only a candidate with
evaluation numbers can be approved. The apps download only the newest **approved** release
(``GET /v1/models/on-device/current``, a 15-minute signed URL); retiring it falls back to the
previous approved one.
"""

from __future__ import annotations

import hashlib
import json
import uuid
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, ConflictError, NotFoundError
from farmerapp.auth.models import User, UserRole, UserStatus
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.logging import get_logger
from farmerapp.mlops.models import (
    RELEASE_TRANSITIONS,
    ModelRelease,
    ReleaseKind,
    ReleaseStatus,
)
from farmerapp.notifications.models import Notification, NotificationKind
from farmerapp.uploads.blobstore import BlobStore

log = get_logger("farmerapp.mlops.releases")


class NoApprovedModelError(AppError):
    status = 404
    code = "no_approved_model"


class InvalidReleaseTransitionError(ConflictError):
    code = "invalid_transition"


class EvaluationMissingError(ConflictError):
    code = "evaluation_missing"


class InvalidCandidateError(AppError):
    status = 422
    code = "invalid_candidate"


async def visible_release(
    session: AsyncSession, actor: User, release_id: uuid.UUID
) -> ModelRelease:
    row = await session.get(ModelRelease, release_id)
    if row is None or row.tenant_id != actor.tenant_id or row.deleted_at is not None:
        raise NotFoundError("Model release not found.")
    return row


async def current_release(
    session: AsyncSession, tenant_id: uuid.UUID, kind: ReleaseKind = ReleaseKind.ON_DEVICE
) -> ModelRelease:
    row = await session.scalar(
        select(ModelRelease)
        .where(
            ModelRelease.tenant_id == tenant_id,
            ModelRelease.kind == kind.value,
            ModelRelease.status == ReleaseStatus.APPROVED.value,
            ModelRelease.deleted_at.is_(None),
        )
        .order_by(ModelRelease.decided_at.desc(), ModelRelease.id.desc())
        .limit(1)
    )
    if row is None:
        raise NoApprovedModelError("No approved on-device model yet; keep the bundled one.")
    return row


async def decide(
    session: AsyncSession,
    actor: User,
    release: ModelRelease,
    *,
    to: ReleaseStatus,
    note: str | None,
    now: datetime,
) -> ModelRelease:
    current = ReleaseStatus(release.status)
    if to not in RELEASE_TRANSITIONS[current]:
        raise InvalidReleaseTransitionError(
            f"A {current.value} release cannot become {to.value}.",
            extra={"from": current.value, "to": to.value},
        )
    if to == ReleaseStatus.APPROVED and not release.evaluation:
        raise EvaluationMissingError("Approve only a candidate with evaluation numbers.")
    before = {"status": release.status}
    release.status = to.value
    release.decided_by = actor.id
    release.decided_at = now
    release.decision_note = note
    await session.flush()
    audit.record(
        session,
        action=f"model_release.{to.value}",
        entity="model_release",
        entity_id=release.id,
        tenant_id=release.tenant_id,
        before=before,
        after={
            "status": to.value,
            "model_version": release.model_version,
            "sha256": release.sha256,
            "note": note,
        },
    )
    log.info(
        "model_release_decided",
        release_id=str(release.id),
        model_version=release.model_version,
        status=to.value,
        actor_id=str(actor.id),
    )
    await session.refresh(release)
    return release


# --------------------------------------------------------------------------- candidates
@dataclass(frozen=True)
class Candidate:
    artifact_uri: str
    data: bytes
    metadata: dict[str, Any]
    training_manifest_uri: str | None = None
    pipeline_run: str | None = None


def _evaluation(metadata: dict[str, Any]) -> dict[str, Any]:
    evaluation = metadata.get("evaluation")
    return dict(evaluation) if isinstance(evaluation, dict) else {}


async def register_candidate(
    session: AsyncSession, tenant_id: uuid.UUID, candidate: Candidate
) -> tuple[ModelRelease, bool]:
    """Record a candidate (idempotent on the model version). Returns (row, created)."""
    name = candidate.metadata.get("model_name")
    version = candidate.metadata.get("model_version")
    if not isinstance(name, str) or not isinstance(version, str) or not name or not version:
        raise InvalidCandidateError("metadata.json needs model_name and model_version.")
    sha = hashlib.sha256(candidate.data).hexdigest()
    declared = candidate.metadata.get("sha256")
    if declared and declared != sha:
        raise InvalidCandidateError("The artifact does not match the sha256 in its metadata.")
    existing = await session.scalar(
        select(ModelRelease).where(
            ModelRelease.tenant_id == tenant_id,
            ModelRelease.kind == ReleaseKind.ON_DEVICE.value,
            ModelRelease.model_version == version,
        )
    )
    if existing is not None:
        if existing.sha256 != sha:
            raise InvalidCandidateError(
                f"Version {version} is registered with other bytes; bump the model version."
            )
        return existing, False
    row = ModelRelease(
        tenant_id=tenant_id,
        kind=ReleaseKind.ON_DEVICE.value,
        model_name=name,
        model_version=version,
        artifact_uri=candidate.artifact_uri,
        sha256=sha,
        size_bytes=len(candidate.data),
        model_metadata=candidate.metadata,
        evaluation=_evaluation(candidate.metadata),
        training_manifest_uri=candidate.training_manifest_uri
        or candidate.metadata.get("training_manifest_uri"),
        pipeline_run=candidate.pipeline_run,
        status=ReleaseStatus.CANDIDATE.value,
    )
    session.add(row)
    await session.flush()
    kind = NotificationKind.MODEL_RELEASE_CANDIDATE.value
    approvers = await session.scalars(
        select(User.id).where(
            User.tenant_id == tenant_id,
            User.role.in_([UserRole.AGRONOMIST.value, UserRole.OWNER.value]),
            User.status == UserStatus.ACTIVE.value,
            User.deleted_at.is_(None),
        )
    )
    for user_id in approvers:
        session.add(
            Notification(
                tenant_id=tenant_id,
                user_id=user_id,
                kind=kind,
                title_key=f"notification.{kind}.title",
                body_key=f"notification.{kind}.body",
                data={"release_id": str(row.id), "model_version": version},
            )
        )
    await session.flush()
    return row, True


async def run_register_candidate(
    tenant_ids: Iterable[uuid.UUID],
    *,
    blobs: BlobStore,
    artifact_uri: str,
    metadata_uri: str,
    training_manifest_uri: str | None = None,
    pipeline_run: str | None = None,
) -> list[tuple[uuid.UUID, ModelRelease, bool]]:
    data = await blobs.get(artifact_uri)
    metadata = json.loads((await blobs.get(metadata_uri)).decode("utf-8"))
    if not isinstance(metadata, dict):
        raise InvalidCandidateError("metadata.json must be an object.")
    candidate = Candidate(
        artifact_uri=artifact_uri,
        data=data,
        metadata=metadata,
        training_manifest_uri=training_manifest_uri,
        pipeline_run=pipeline_run,
    )
    out: list[tuple[uuid.UUID, ModelRelease, bool]] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                row, created = await register_candidate(session, tenant_id, candidate)
                out.append((tenant_id, row, created))
    return out


def utcnow() -> datetime:
    return datetime.now(UTC)


__all__ = [
    "Candidate",
    "EvaluationMissingError",
    "InvalidCandidateError",
    "InvalidReleaseTransitionError",
    "NoApprovedModelError",
    "current_release",
    "decide",
    "register_candidate",
    "run_register_candidate",
    "visible_release",
]
