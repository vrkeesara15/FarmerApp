"""WC-006 agronomist queue and review (DX-006): confirm / correct updates the farmer's
result and notifies, add-to-corpus creates reviewed corpus images, history is appended."""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.diagnosis.images import synthetic_leaf, synthetic_non_plant
from farmerapp.diagnosis.models import CorpusImage, Diagnosis, DiagnosisReview
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.diagnosis.thresholds import set_thresholds
from farmerapp.notifications.models import Notification
from farmerapp.uploads.blobstore import BlobStore
from tests.authz.conftest import Bearer
from tests.diagnosis.conftest import Paddy, put_photo

ZINC, BPH = "paddy_zinc_deficiency", "paddy_bph"


async def _provisional(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    blobs: BlobStore,
    session: AsyncSession,
    variant: int = 200,
) -> dict[str, Any]:
    await set_thresholds(
        session,
        paddy.agronomist,
        crop_id=paddy.crop.id,
        t1=0.9999,
        agreement=0.6,
        min_similarity=0.5,
        note="force the LLM",
    )
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, variant))
    resp = await client.post(
        "/v1/diagnoses",
        json={"crop_id": str(paddy.crop.id), "images": [{"blob_uri": photo}]},
        headers=bearer(paddy.farmer_user),
    )
    body: dict[str, Any] = resp.json()
    assert body["status"] == "provisional", body
    return body


async def _review(
    client: AsyncClient, bearer: Bearer, paddy: Paddy, diagnosis_id: str, **body: Any
) -> Any:
    return await client.post(
        f"/v1/diagnoses/{diagnosis_id}/review",
        json={"note": "checked in the field", **body},
        headers=bearer(paddy.agronomist),
    )


async def test_confirm_makes_the_result_buyable_and_notifies(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
) -> None:
    body = await _provisional(client, bearer, paddy, blobs, db_session)
    resp = await _review(client, bearer, paddy, body["id"], action="confirm")
    assert resp.status_code == 200, resp.text
    out = resp.json()
    assert out["status"] == "confirmed" and out["source"] == "agronomist"
    assert out["confidence"] == "high" and out["can_buy"] is True and out["cta"] == "buy"
    assert out["reviewed_at"] and out["reviews"][0]["action"] == "confirm"
    kinds = (
        await db_session.execute(
            select(Notification.user_id).where(Notification.kind == "diagnosis_reviewed")
        )
    ).scalars()
    assert set(kinds) == {paddy.farmer_user.id, paddy.officer.id}
    # the farmer's poll shows the confirmed answer; the queue no longer lists it
    mine = await client.get(f"/v1/diagnoses/{body['id']}", headers=bearer(paddy.farmer_user))
    assert mine.json()["status"] == "confirmed" and mine.json()["can_buy"] is True
    queue = await client.get("/v1/diagnoses/review-queue", headers=bearer(paddy.agronomist))
    assert body["id"] not in [i["id"] for i in queue.json()["items"]]


async def test_correct_changes_the_label_and_adds_the_photos_to_the_corpus(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
) -> None:
    body = await _provisional(client, bearer, paddy, blobs, db_session, variant=201)
    target = paddy.problems[BPH]
    resp = await _review(
        client,
        bearer,
        paddy,
        body["id"],
        action="correct",
        problem_id=str(target.id),
        add_to_corpus=True,
    )
    assert resp.status_code == 200, resp.text
    out = resp.json()
    assert out["status"] == "corrected" and out["final_problem_id"] == str(target.id)
    assert out["result"]["problem"]["code"] == BPH
    (review,) = out["reviews"]
    assert review["from_problem_id"] == body["final_problem_id"]
    assert review["to_problem_id"] == str(target.id) and len(review["corpus_image_ids"]) == 1
    image = await db_session.get_one(CorpusImage, uuid.UUID(review["corpus_image_ids"][0]))
    assert image.status == "reviewed" and image.problem_id == target.id  # still needs approval
    assert image.from_diagnosis_id == uuid.UUID(body["id"])
    assert image.labelled_by == paddy.agronomist.id and image.encoder_name == "fake-dct"
    history = (
        (
            await db_session.execute(
                select(DiagnosisReview).where(DiagnosisReview.diagnosis_id == uuid.UUID(body["id"]))
            )
        )
        .scalars()
        .all()
    )
    assert [h.action for h in history] == ["correct"]


async def test_review_errors(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
) -> None:
    body = await _provisional(client, bearer, paddy, blobs, db_session, variant=202)
    resp = await _review(client, bearer, paddy, body["id"], action="correct")
    assert resp.status_code == 422 and resp.json()["code"] == "review_invalid"
    resp = await _review(
        client, bearer, paddy, body["id"], action="confirm", problem_id=str(uuid.uuid4())
    )
    assert resp.json()["code"] == "review_invalid"
    resp = await _review(
        client, bearer, paddy, body["id"], action="correct", problem_id=str(uuid.uuid4())
    )
    assert resp.status_code == 404
    resp = await _review(
        client, bearer, paddy, body["id"], action="not_diagnosable", add_to_corpus=True
    )
    assert resp.json()["code"] == "review_invalid"
    missing = await _review(client, bearer, paddy, str(uuid.uuid4()), action="confirm")
    assert missing.status_code == 404
    no_note = await client.post(
        f"/v1/diagnoses/{body['id']}/review",
        json={"action": "confirm"},
        headers=bearer(paddy.agronomist),
    )
    assert no_note.status_code == 422
    row = await db_session.get_one(Diagnosis, uuid.UUID(body["id"]))
    row.status = "queued"
    await db_session.flush()
    queued = await _review(client, bearer, paddy, body["id"], action="confirm")
    assert queued.status_code == 409 and queued.json()["code"] == "diagnosis_not_reviewable"


async def test_out_of_scope_can_be_closed_or_labelled(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
) -> None:
    tid = paddy.farmer.tenant_id
    ids = []
    for variant in (1, 2):
        photo = await put_photo(blobs, tid, synthetic_non_plant("wall", variant))
        resp = await client.post(
            "/v1/diagnoses",
            json={"crop_id": str(paddy.crop.id), "images": [{"blob_uri": photo}]},
            headers=bearer(paddy.farmer_user),
        )
        ids.append(resp.json()["id"])
    resp = await _review(client, bearer, paddy, ids[0], action="confirm")
    assert resp.json()["code"] == "review_invalid"  # nothing to confirm
    closed = await _review(client, bearer, paddy, ids[0], action="not_diagnosable")
    assert closed.json()["status"] == "out_of_scope" and closed.json()["source"] == "agronomist"
    assert closed.json()["result"]["problem"] is None
    labelled = await _review(
        client, bearer, paddy, ids[1], action="correct", problem_id=str(paddy.problems[ZINC].id)
    )
    assert labelled.json()["status"] == "corrected" and labelled.json()["can_buy"] is True


async def test_queue_filters_counts_and_order(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
) -> None:
    old = await _provisional(client, bearer, paddy, blobs, db_session, variant=203)
    new = await _provisional(client, bearer, paddy, blobs, db_session, variant=204)
    row = await db_session.get_one(Diagnosis, uuid.UUID(old["id"]))
    row.created_at = row.created_at - timedelta(hours=20)
    await db_session.flush()
    headers = bearer(paddy.agronomist)
    queue = (await client.get("/v1/diagnoses/review-queue", headers=headers)).json()
    ids = [i["id"] for i in queue["items"]]
    assert ids.index(old["id"]) < ids.index(new["id"])  # oldest first
    first = next(i for i in queue["items"] if i["id"] == old["id"])
    assert first["overdue"] is True and first["age_hours"] >= 20 and first["scores"]
    assert first["images"][0]["signed_url"]
    assert queue["counts"]["overdue"] >= 1 and queue["counts"]["total"] >= 2
    aged = (
        await client.get(
            "/v1/diagnoses/review-queue", params={"min_age_hours": 18}, headers=headers
        )
    ).json()
    assert [i["id"] for i in aged["items"]] == [old["id"]]
    by_crop = await client.get(
        "/v1/diagnoses/review-queue",
        params={"crop_id": str(paddy.crop.id), "confidence": ["medium", "low"], "flagged": False},
        headers=headers,
    )
    assert {old["id"], new["id"]} <= {i["id"] for i in by_crop.json()["items"]}
    paged = (
        await client.get("/v1/diagnoses/review-queue", params={"limit": 1}, headers=headers)
    ).json()
    assert len(paged["items"]) == 1 and paged["next_cursor"]
    nxt = await client.get(
        "/v1/diagnoses/review-queue",
        params={"limit": 1, "cursor": paged["next_cursor"]},
        headers=headers,
    )
    assert nxt.json()["items"][0]["id"] != paged["items"][0]["id"]
    owner = await client.get("/v1/diagnoses/review-queue", headers=bearer(paddy.farmer_user))
    assert owner.status_code == 403


async def test_ask_expert_puts_an_answered_case_in_the_queue(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
) -> None:
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, 205))
    resp = await client.post(
        "/v1/diagnoses",
        json={"crop_id": str(paddy.crop.id), "images": [{"blob_uri": photo}], "ask_expert": True},
        headers=bearer(paddy.farmer_user),
    )
    body = resp.json()
    assert body["status"] == "answered" and body["flagged"] is True
    flagged = await client.get(
        "/v1/diagnoses/review-queue", params={"flagged": True}, headers=bearer(paddy.agronomist)
    )
    assert [i["id"] for i in flagged.json()["items"]] == [body["id"]]


async def test_thresholds_api_versions_per_crop(
    client: AsyncClient, bearer: Bearer, paddy: Paddy
) -> None:
    headers = bearer(paddy.agronomist)
    empty = (await client.get("/v1/diagnoses/thresholds", headers=headers)).json()
    assert empty["defaults"]["t1"] == 0.92 and empty["items"] == []
    for t1 in (0.9, 0.93):
        resp = await client.put(
            "/v1/diagnoses/thresholds",
            json={"crop_id": str(paddy.crop.id), "t1": t1, "agreement": 0.6, "min_similarity": 0.8},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
    assert resp.json()["config_version"] == 2
    listed = (await client.get("/v1/diagnoses/thresholds", headers=headers)).json()["items"]
    assert [i["config_version"] for i in listed] == [1, 2]
    bad = await client.put(
        "/v1/diagnoses/thresholds",
        json={"t1": 0.8, "agreement": 0.6, "min_similarity": 0.9},
        headers=headers,
    )
    assert bad.status_code == 422
    unknown_crop = await client.put(
        "/v1/diagnoses/thresholds",
        json={"crop_id": str(uuid.uuid4()), "t1": 0.8, "agreement": 0.6, "min_similarity": 0.5},
        headers=headers,
    )
    assert unknown_crop.status_code == 422
    owner = await client.put(
        "/v1/diagnoses/thresholds",
        json={"t1": 0.8, "agreement": 0.6, "min_similarity": 0.5},
        headers=bearer(paddy.farmer_user),
    )
    assert owner.status_code == 403
