"""M6 API gaps closed for the crop doctor apps and the agronomist console:

* FM-006 ``POST /v1/diagnoses/{id}/ask-expert`` — an answered case goes to the agronomist
  queue as ``flagged`` with the same photos (no second diagnosis), agronomists notified,
  idempotent, only the farmer it is about or the officer who asked;
* ``crop_code`` as an alternative to ``crop_id`` (REST and the sync create op);
* the DX-001 ``on_device`` block stored as DX-005 provenance."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.catalog.crops import Crop
from farmerapp.db.models import AuditLog
from farmerapp.diagnosis.images import synthetic_leaf
from farmerapp.diagnosis.llm import LlmOutcome
from farmerapp.diagnosis.models import Diagnosis
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.diagnosis.thresholds import set_thresholds
from farmerapp.notifications.models import Notification
from farmerapp.uploads.blobstore import BlobStore
from tests.authz.conftest import Bearer, World
from tests.diagnosis.conftest import Paddy, ScriptedLlm, put_photo

ZINC = "paddy_zinc_deficiency"

ON_DEVICE: dict[str, Any] = {
    "model": "crop_quality",
    "model_version": "ondevice-v1.0",
    "model_sha256": "a" * 64,
    "plant_score": 0.998,
    "quality": {"ok": 0.97, "blurry": 0.02, "dark": 0.01},
    "crop_scores": {"paddy": 0.93, "cotton": 0.01, "other": 0.06},
    "latency_ms": 38,
}


async def _create(
    client: AsyncClient, headers: dict[str, str], body: dict[str, Any]
) -> dict[str, Any]:
    resp = await client.post("/v1/diagnoses", json=body, headers=headers)
    assert resp.status_code == 202, resp.text
    out: dict[str, Any] = resp.json()
    return out


async def _answered(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    blobs: BlobStore,
    variant: int,
    *,
    as_officer: bool = False,
) -> dict[str, Any]:
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, variant))
    body: dict[str, Any] = {"crop_id": str(paddy.crop.id), "images": [{"blob_uri": photo}]}
    if as_officer:
        body["farmer_id"] = str(paddy.farmer.id)
    out = await _create(client, bearer(paddy.officer if as_officer else paddy.farmer_user), body)
    assert out["status"] == "answered" and out["source"] == "corpus", out
    return out


async def _expert_notifications(session: AsyncSession, diagnosis_id: str) -> list[uuid.UUID]:
    rows = await session.execute(
        select(Notification.user_id).where(
            Notification.kind == "diagnosis_expert_requested",
            Notification.data["diagnosis_id"].astext == diagnosis_id,
        )
    )
    return list(rows.scalars())


# --------------------------------------------------------------------------- ask expert
async def test_ask_expert_moves_an_answered_case_into_the_queue_without_reupload(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
) -> None:
    answered = await _answered(client, bearer, paddy, blobs, 401)
    did = answered["id"]
    assert answered["flagged"] is False and answered["expert_requested_at"] is None
    before = await db_session.scalar(select(func.count()).select_from(Diagnosis))
    queue = await client.get("/v1/diagnoses/review-queue", headers=bearer(paddy.agronomist))
    assert did not in {i["id"] for i in queue.json()["items"]}

    resp = await client.post(
        f"/v1/diagnoses/{did}/ask-expert",
        json={"note": "Spots spread to the next field"},
        headers=bearer(paddy.farmer_user),
    )
    assert resp.status_code == 200, resp.text
    out = resp.json()
    assert out["id"] == did and out["flagged"] is True and out["expert_requested_at"]
    # the farmer's answer is unchanged (still buyable) and no provenance leaks to them
    assert out["status"] == "answered" and out["can_buy"] is True
    assert out["scores"] is None and out["expert_note"] is None
    # no second diagnosis, same photos
    assert await db_session.scalar(select(func.count()).select_from(Diagnosis)) == before
    assert [i["sha256"] for i in out["images"]] == [i["sha256"] for i in answered["images"]]

    # in the agronomist queue as a flagged case, with the note and who asked
    queue = await client.get(
        "/v1/diagnoses/review-queue", params={"flagged": "true"}, headers=bearer(paddy.agronomist)
    )
    (item,) = [i for i in queue.json()["items"] if i["id"] == did]
    assert item["flagged"] is True and item["expert_note"] == "Spots spread to the next field"
    assert item["expert_requested_by"] == str(paddy.farmer_user.id)
    # agronomists are notified once
    agronomists = {u.id for u in await _tenant_users(db_session, paddy, UserRole.AGRONOMIST)}
    assert agronomists and set(await _expert_notifications(db_session, did)) == agronomists
    # audited through the FA-006 listener
    audit = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.action == "diagnosis.update", AuditLog.entity_id == uuid.UUID(did)
            )
        )
    ).scalars()
    assert any((a.after or {}).get("flagged") is True for a in audit)

    # idempotent: the same again changes nothing and notifies nobody new
    again = await client.post(
        f"/v1/diagnoses/{did}/ask-expert", json={"note": "again"}, headers=bearer(paddy.farmer_user)
    )
    assert again.status_code == 200
    assert again.json()["expert_requested_at"] == out["expert_requested_at"]
    assert again.json()["version"] == out["version"]
    assert len(await _expert_notifications(db_session, did)) == len(agronomists)
    row = await db_session.get_one(Diagnosis, uuid.UUID(did))
    assert row.expert_note == "Spots spread to the next field"

    # the change reaches the farmer's app through the sync feed
    feed = await client.post(
        "/v1/sync",
        json={"device_id": "kisan", "cursor": None, "ops": []},
        headers=bearer(paddy.farmer_user),
    )
    entries = [c for c in feed.json()["changes"] if c["entity_id"] == did]
    assert entries and entries[-1]["data"]["flagged"] is True

    # once the agronomist answered there is nothing to escalate
    review = await client.post(
        f"/v1/diagnoses/{did}/review",
        json={"action": "confirm", "note": "zinc, as the corpus said"},
        headers=bearer(paddy.agronomist),
    )
    assert review.status_code == 200, review.text
    assert review.json()["flagged"] is False
    resp = await client.post(f"/v1/diagnoses/{did}/ask-expert", headers=bearer(paddy.farmer_user))
    assert resp.status_code == 409 and resp.json()["code"] == "diagnosis_already_reviewed"


async def _tenant_users(session: AsyncSession, paddy: Paddy, role: UserRole) -> list[User]:
    rows = await session.execute(
        select(User).where(
            User.tenant_id == paddy.farmer.tenant_id,
            User.role == role.value,
            User.deleted_at.is_(None),
        )
    )
    return [u for u in rows.scalars() if u.status == "active"]


async def test_ask_expert_scope_officer_who_asked_and_farmer_only(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    world: World,
) -> None:
    officer_case = await _answered(client, bearer, paddy, blobs, 402, as_officer=True)
    farmer_case = await _answered(client, bearer, paddy, blobs, 403)
    others = [
        u
        for u in world.a.everyone
        if u.role == UserRole.FIELD_OFFICER.value and u.id != paddy.officer.id
    ]
    stranger = others[0]
    # the officer who asked may escalate; the farmer it is about may too
    resp = await client.post(
        f"/v1/diagnoses/{officer_case['id']}/ask-expert", headers=bearer(paddy.officer)
    )
    assert resp.status_code == 200 and resp.json()["flagged"] is True
    # the farmer's officer sees the farmer's own case but did not ask for it: 403
    resp = await client.post(
        f"/v1/diagnoses/{farmer_case['id']}/ask-expert", headers=bearer(paddy.officer)
    )
    assert resp.status_code == 403 and resp.json()["code"] == "forbidden"
    # an officer who cannot see it, another tenant, an unknown id: 404
    for headers, did in (
        (bearer(stranger), farmer_case["id"]),
        (bearer(world.b.user(UserRole.FARMER)), farmer_case["id"]),
        (bearer(paddy.farmer_user), str(uuid.uuid4())),
    ):
        resp = await client.post(f"/v1/diagnoses/{did}/ask-expert", headers=headers)
        assert resp.status_code == 404, resp.text
    # reviewers do not ask themselves
    resp = await client.post(
        f"/v1/diagnoses/{farmer_case['id']}/ask-expert", headers=bearer(paddy.agronomist)
    )
    assert resp.status_code == 403
    # a note is bounded
    resp = await client.post(
        f"/v1/diagnoses/{farmer_case['id']}/ask-expert",
        json={"note": "x" * 2001},
        headers=bearer(paddy.farmer_user),
    )
    assert resp.status_code == 422


async def test_ask_expert_on_a_provisional_llm_answer(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
    llm: ScriptedLlm,
) -> None:
    await set_thresholds(
        db_session,
        paddy.agronomist,
        crop_id=paddy.crop.id,
        t1=0.9999,
        agreement=0.6,
        min_similarity=0.5,
        note="force the LLM",
    )
    llm.script = lambda _r: LlmOutcome.unknown("unknown", "scripted-llm")
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, 404))
    body = await _create(
        client,
        bearer(paddy.farmer_user),
        {"crop_id": str(paddy.crop.id), "images": [{"blob_uri": photo}]},
    )
    assert body["status"] == "provisional" and body["source"] == "llm"
    resp = await client.post(
        f"/v1/diagnoses/{body['id']}/ask-expert", headers=bearer(paddy.farmer_user)
    )
    assert resp.status_code == 200 and resp.json()["flagged"] is True
    assert resp.json()["status"] == "provisional"
    assert await _expert_notifications(db_session, body["id"])


# --------------------------------------------------------------------------- crop codes
async def test_crop_code_resolves_per_tenant(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
    world: World,
) -> None:
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, 405))
    headers = bearer(paddy.farmer_user)
    body = await _create(client, headers, {"crop_code": "Paddy", "images": [{"blob_uri": photo}]})
    assert body["crop_id"] == str(paddy.crop.id) and body["status"] == "answered"
    # resolved in the caller's tenant only: a code no crop of this tenant has is unknown
    crop = await db_session.get_one(Crop, paddy.crop.id)
    crop.code = "rice"
    await db_session.flush()
    resp = await client.post(
        "/v1/diagnoses",
        json={"crop_code": "paddy", "images": [{"blob_uri": photo}]},
        headers=headers,
    )
    assert resp.status_code == 422 and resp.json()["code"] == "diagnosis_invalid"
    crop.code = "paddy"
    await db_session.flush()

    unknown = await client.post(
        "/v1/diagnoses",
        json={"crop_code": "banana", "images": [{"blob_uri": photo}]},
        headers=headers,
    )
    assert unknown.status_code == 422 and unknown.json()["code"] == "diagnosis_invalid"
    assert {"loc": ["crop_code"]} in unknown.json()["errors"]
    for bad in (
        {"images": [{"blob_uri": photo}]},  # neither
        {"crop_id": str(paddy.crop.id), "crop_code": "paddy", "images": [{"blob_uri": photo}]},
    ):
        resp = await client.post("/v1/diagnoses", json=bad, headers=headers)
        assert resp.status_code == 422 and resp.json()["code"] == "validation_error"
    # `unknown` plus a code: the code wins
    body = await _create(
        client,
        headers,
        {"crop_id": "unknown", "crop_code": "paddy", "images": [{"blob_uri": photo}]},
    )
    assert body["crop_id"] == str(paddy.crop.id)


async def test_sync_create_accepts_a_crop_code(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
) -> None:
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, 406))

    def op(code: str) -> dict[str, Any]:
        return {
            "op_id": str(uuid.uuid4()),
            "entity": "diagnosis",
            "action": "create",
            "entity_id": str(uuid.uuid4()),
            "base_version": 0,
            "payload": {
                "farmer_id": str(paddy.farmer.id),
                "crop_code": code,
                "images": [{"blob_uri": photo}],
                "on_device": ON_DEVICE,
            },
            "client_ts": datetime.now(UTC).isoformat(),
        }

    resp = await client.post(
        "/v1/sync",
        json={"device_id": "agent-1", "cursor": None, "ops": [op("paddy"), op("banana")]},
        headers=bearer(paddy.officer),
    )
    assert resp.status_code == 200, resp.text
    good, bad = resp.json()["results"]
    assert good["status"] == "applied", good
    assert good["server"]["crop_id"] == str(paddy.crop.id)
    assert good["server"]["model_versions"]["on_device"] == "ondevice-v1.0"
    assert bad["status"] == "rejected" and bad["error"]["code"] == "diagnosis_invalid"


# --------------------------------------------------------------------------- on-device block
async def test_on_device_block_is_stored_as_provenance(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
) -> None:
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, 407))
    headers = bearer(paddy.farmer_user)
    body = await _create(
        client,
        headers,
        {
            "crop_code": "paddy",
            "images": [{"blob_uri": photo}],
            "on_device_model": "ignored-when-the-block-is-there",
            "on_device": ON_DEVICE,
        },
    )
    assert body["model_versions"]["on_device"] == "ondevice-v1.0"
    row = await db_session.get_one(Diagnosis, uuid.UUID(body["id"]))
    assert row.on_device == ON_DEVICE
    # reviewers see it with the rest of the DX-005 provenance; the farmer does not
    mine = await client.get(f"/v1/diagnoses/{body['id']}", headers=headers)
    assert mine.json()["on_device"] is None
    expert = await client.get(f"/v1/diagnoses/{body['id']}", headers=bearer(paddy.agronomist))
    assert expert.json()["on_device"] == ON_DEVICE

    # the laplacian fallback shape is accepted too
    fallback = {
        "model": "crop_quality",
        "model_version": "heuristic-laplacian-v1",
        "fallback": "laplacian",
        "heuristic": {"blur_score": 212.4, "brightness": 0.46},
        "latency_ms": 12,
    }
    body = await _create(
        client,
        headers,
        {"crop_code": "paddy", "images": [{"blob_uri": photo}], "on_device": fallback},
    )
    assert body["model_versions"]["on_device"] == "heuristic-laplacian-v1"
    for bad in (
        {**ON_DEVICE, "plant_score": 1.5},
        {**ON_DEVICE, "latitude": 17.9},  # no location or anything else
        {**ON_DEVICE, "crop_scores": {"": 0.5}},
        {key: value for key, value in ON_DEVICE.items() if key != "model_version"},
    ):
        resp = await client.post(
            "/v1/diagnoses",
            json={"crop_code": "paddy", "images": [{"blob_uri": photo}], "on_device": bad},
            headers=headers,
        )
        assert resp.status_code == 422, bad
