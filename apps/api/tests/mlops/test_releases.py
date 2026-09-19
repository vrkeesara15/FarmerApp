"""DX-012 approval gate: a candidate registered from the corpus bucket, approved / rejected /
retired by an agronomist or owner with step-up (audited), and the apps' download endpoint that
only ever serves the newest approved on-device model."""

from __future__ import annotations

import hashlib
import json
import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.models import AuditLog
from farmerapp.mlops.models import ModelRelease
from farmerapp.mlops.releases import (
    Candidate,
    InvalidCandidateError,
    register_candidate,
    run_register_candidate,
)
from farmerapp.notifications.models import Notification
from farmerapp.uploads.blobstore import BlobStore
from tests.authz.conftest import Bearer, World

MODEL = b"TFL3" + b"\x00" * 2048


def _metadata(version: str, data: bytes = MODEL, *, evaluation: bool = True) -> dict[str, object]:
    meta: dict[str, object] = {
        "model_name": "crop_quality",
        "model_version": version,
        "sha256": hashlib.sha256(data).hexdigest(),
        "labels": {"crop": ["paddy", "cotton", "other"]},
        "thresholds": {"plant_min": 0.5},
        "input": {"shape": [1, 224, 224, 3]},
        "output": {"shape": [1, 11]},
    }
    if evaluation:
        meta["evaluation"] = {"split": "field", "accuracy": {"crop": 0.91, "plant": 0.99}}
    return meta


async def _upload(blobs: BlobStore, version: str, **kw: bool) -> tuple[str, str]:
    data = MODEL + version.encode()
    artifact = await blobs.put(
        f"models/on-device/{version}/model.tflite", data, content_type="application/octet-stream"
    )
    meta = await blobs.put(
        f"models/on-device/{version}/metadata.json",
        json.dumps(_metadata(version, data, **kw)).encode(),
        content_type="application/json",
    )
    return artifact, meta


async def _register(
    session: AsyncSession, world: World, blobs: BlobStore, version: str, **kw: bool
) -> ModelRelease:
    artifact, meta = await _upload(blobs, version, **kw)
    data = await blobs.get(artifact)
    row, created = await register_candidate(
        session,
        world.a.tenant.id,
        Candidate(
            artifact_uri=artifact,
            data=data,
            metadata=json.loads(await blobs.get(meta)),
            training_manifest_uri="gs://local/training/x/manifest.csv",
        ),
    )
    assert created
    return row


async def test_candidate_registration(
    db_session: AsyncSession, world: World, blobs: BlobStore
) -> None:
    row = await _register(db_session, world, blobs, "ondevice-v1.1")
    assert (
        row.status == "candidate"
        and row.sha256 == hashlib.sha256(MODEL + b"ondevice-v1.1").hexdigest()
    )
    assert row.size_bytes == len(MODEL) + len("ondevice-v1.1")
    assert row.evaluation["accuracy"]["crop"] == 0.91
    notes = (
        (
            await db_session.execute(
                select(Notification).where(Notification.kind == "model_release_candidate")
            )
        )
        .scalars()
        .all()
    )
    assert {n.user_id for n in notes} >= {world.a.user(UserRole.AGRONOMIST).id, world.a.owner.id}
    # idempotent on the version with the same bytes; other bytes are refused
    same, created = await register_candidate(
        db_session,
        world.a.tenant.id,
        Candidate(
            artifact_uri=row.artifact_uri,
            data=MODEL + b"ondevice-v1.1",
            metadata=row.model_metadata,
        ),
    )
    assert same.id == row.id and not created
    with pytest.raises(InvalidCandidateError):
        await register_candidate(
            db_session,
            world.a.tenant.id,
            Candidate(
                artifact_uri=row.artifact_uri,
                data=b"other",
                metadata={**row.model_metadata, "sha256": None},
            ),
        )
    with pytest.raises(InvalidCandidateError, match="sha256"):
        await register_candidate(
            db_session,
            world.a.tenant.id,
            Candidate(artifact_uri="gs://x/y", data=b"tampered", metadata=_metadata("v9")),
        )
    with pytest.raises(InvalidCandidateError, match="model_version"):
        await register_candidate(
            db_session,
            world.a.tenant.id,
            Candidate(artifact_uri="gs://x/y", data=b"x", metadata={"model_name": "m"}),
        )


async def test_approval_gate_and_current_model(
    client: AsyncClient,
    bearer: Bearer,
    step_up: Bearer,
    db_session: AsyncSession,
    world: World,
    blobs: BlobStore,
) -> None:
    farmer = world.a.user(UserRole.FARMER)
    none = await client.get("/v1/models/on-device/current", headers=bearer(farmer))
    assert none.status_code == 404 and none.json()["code"] == "no_approved_model"

    v11 = await _register(db_session, world, blobs, "ondevice-v1.1")
    bare = await _register(db_session, world, blobs, "ondevice-v1.2-noeval", evaluation=False)
    agronomist = world.a.user(UserRole.AGRONOMIST)
    headers = {**bearer(agronomist), **step_up(agronomist)}

    no_step_up = await client.post(
        f"/v1/models/releases/{v11.id}/decision",
        json={"decision": "approve"},
        headers=bearer(agronomist),
    )
    assert no_step_up.status_code == 401 and no_step_up.json()["code"] == "step_up_required"
    missing = await client.post(
        f"/v1/models/releases/{bare.id}/decision", json={"decision": "approve"}, headers=headers
    )
    assert missing.status_code == 409 and missing.json()["code"] == "evaluation_missing"

    listed = await client.get("/v1/models/releases", headers=bearer(agronomist))
    assert [r["status"] for r in listed.json()["items"]][:2] == ["candidate", "candidate"]

    ok = await client.post(
        f"/v1/models/releases/{v11.id}/decision",
        json={"decision": "approve", "note": "field set 91 % crop"},
        headers=headers,
    )
    assert ok.status_code == 200, ok.text
    assert ok.json()["status"] == "approved" and ok.json()["decided_by"] == str(agronomist.id)
    audit = (
        await db_session.execute(
            select(AuditLog).where(AuditLog.action == "model_release.approved")
        )
    ).scalar_one()
    assert audit.entity_id == v11.id

    current = await client.get("/v1/models/on-device/current", headers=bearer(farmer))
    assert current.status_code == 200, current.text
    body = current.json()
    assert body["release_id"] == str(v11.id) and body["model_version"] == "ondevice-v1.1"
    assert body["sha256"] == v11.sha256 and body["url"] and body["labels"]["crop"]

    again = await client.post(
        f"/v1/models/releases/{v11.id}/decision", json={"decision": "approve"}, headers=headers
    )
    assert again.status_code == 409 and again.json()["code"] == "invalid_transition"

    rejected = await client.post(
        f"/v1/models/releases/{bare.id}/decision",
        json={"decision": "reject", "note": "no field evaluation"},
        headers={**bearer(world.a.owner), **step_up(world.a.owner)},
    )
    assert rejected.status_code == 200 and rejected.json()["status"] == "rejected"

    retired = await client.post(
        f"/v1/models/releases/{v11.id}/decision", json={"decision": "retire"}, headers=headers
    )
    assert retired.json()["status"] == "retired"
    gone = await client.get("/v1/models/on-device/current", headers=bearer(farmer))
    assert gone.status_code == 404


async def test_newest_approved_wins_and_scope(
    client: AsyncClient,
    bearer: Bearer,
    step_up: Bearer,
    db_session: AsyncSession,
    world: World,
    blobs: BlobStore,
) -> None:
    owner = world.a.owner
    headers = {**bearer(owner), **step_up(owner)}
    first = await _register(db_session, world, blobs, "ondevice-v1.1")
    second = await _register(db_session, world, blobs, "ondevice-v1.2")
    for row in (first, second):
        resp = await client.post(
            f"/v1/models/releases/{row.id}/decision", json={"decision": "approve"}, headers=headers
        )
        assert resp.status_code == 200
    current = await client.get(
        "/v1/models/on-device/current", headers=bearer(world.a.user(UserRole.FIELD_OFFICER))
    )
    assert current.json()["model_version"] == "ondevice-v1.2"
    other = world.b.owner
    assert (
        await client.get(f"/v1/models/releases/{first.id}", headers=bearer(other))
    ).status_code == 404
    assert (
        await client.get("/v1/models/on-device/current", headers=bearer(other))
    ).status_code == 404
    assert (
        await client.get(f"/v1/models/releases/{uuid.uuid4()}", headers=bearer(owner))
    ).status_code == 404


async def test_register_job_reads_the_bucket(
    db_session: AsyncSession, world: World, blobs: BlobStore, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The job's per-tenant loop (job_session) is exercised through its core function here;
    the bucket reads and metadata parsing through ``run_register_candidate``."""
    from farmerapp.mlops import releases

    artifact, meta = await _upload(blobs, "ondevice-v2.0")
    seen: list[str] = []

    async def fake_register(session: object, tenant_id: uuid.UUID, candidate: Candidate):  # type: ignore[no-untyped-def]
        seen.append(str(candidate.metadata["model_version"]))
        return await register_candidate(db_session, tenant_id, candidate)

    class _Session:
        async def __aenter__(self) -> object:
            return db_session

        async def __aexit__(self, *exc: object) -> None:
            return None

    monkeypatch.setattr(releases, "register_candidate", fake_register)
    monkeypatch.setattr(releases, "job_session", lambda _tid: _Session())
    out = await run_register_candidate(
        [world.a.tenant.id], blobs=blobs, artifact_uri=artifact, metadata_uri=meta
    )
    ((tenant_id, row, created),) = out
    assert tenant_id == world.a.tenant.id and created and row.model_version == "ondevice-v2.0"
    assert seen == ["ondevice-v2.0"]
