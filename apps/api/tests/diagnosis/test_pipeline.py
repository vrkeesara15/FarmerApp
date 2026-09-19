"""SPEC 3 pipeline end to end over the seeded paddy corpus: corpus answers (DX-003),
LLM fallback (DX-004, no PII: NF-011 / SEC-027), provenance (DX-005), out of scope (DX-010)
and the SPEC 3.4 "no buy button until confirmed" rule."""

from __future__ import annotations

import io
import json
import uuid
from typing import Any

from fastapi import FastAPI
from httpx import AsyncClient
from PIL import Image
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.crops import Crop
from farmerapp.catalog.recommendable import recommendable_skus
from farmerapp.diagnosis.decision import replay
from farmerapp.diagnosis.images import (
    NON_PLANT_KINDS,
    synthetic_leaf,
    synthetic_non_plant,
    to_jpeg,
)
from farmerapp.diagnosis.llm import NOT_A_PLANT_MARK, ClaudeDiagnosisClient, LlmOutcome
from farmerapp.diagnosis.models import (
    CorpusImage,
    CorpusStatus,
    Diagnosis,
    LlmCallLog,
)
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.diagnosis.thresholds import set_thresholds
from farmerapp.notifications.models import Notification
from farmerapp.uploads.blobstore import BlobStore
from tests.authz.conftest import Bearer
from tests.diagnosis.conftest import (
    FakeAnthropic,
    FakeResponse,
    Paddy,
    ScriptedLlm,
    put_photo,
    use_llm,
)

ZINC = "paddy_zinc_deficiency"


async def _ask(
    client: AsyncClient,
    headers: dict[str, str],
    *,
    photos: list[str],
    crop_id: str,
    farmer_id: uuid.UUID | None = None,
    **extra: Any,
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "crop_id": crop_id,
        "images": [{"blob_uri": uri} for uri in photos],
        **extra,
    }
    if farmer_id is not None:
        body["farmer_id"] = str(farmer_id)
    resp = await client.post("/v1/diagnoses", json=body, headers=headers)
    assert resp.status_code == 202, resp.text
    out: dict[str, Any] = resp.json()
    return out


async def _strict(session: AsyncSession, paddy: Paddy, t1: float = 0.9999) -> None:
    """Thresholds no photo can pass (paddy and the tenant default, used when the crop is
    unknown): every case goes to the LLM (medium / low)."""
    for crop_id in (paddy.crop.id, None):
        await set_thresholds(
            session,
            paddy.agronomist,
            crop_id=crop_id,
            t1=t1,
            agreement=0.6,
            min_similarity=0.5,
            note="test",
        )


async def test_high_confidence_corpus_answer_with_label_claim_treatments(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
    llm: ScriptedLlm,
) -> None:
    tid = paddy.farmer.tenant_id
    photo = await put_photo(blobs, tid, synthetic_leaf(ZINC, 101))
    body = await _ask(
        client,
        bearer(paddy.farmer_user),
        photos=[photo],
        crop_id=str(paddy.crop.id),
        on_device_model="crop-v1",
    )
    assert body["status"] == "answered"
    assert body["source"] == "corpus" and body["confidence"] == "high"
    assert body["can_buy"] is True and body["cta"] == "buy" and not body["provisional"]
    assert body["message_key"] == "diagnosis.result.answered"
    assert body["subject"] == "farmer" and body["district"]
    assert body["model_versions"] == {"encoder": "fake-dct@1", "on_device": "crop-v1", "llm": None}
    assert body["corpus_version"] == 1
    result = body["result"]
    assert result["problem"]["code"] == ZINC
    assert set(result["problem"]["names"]) == {"en", "te", "hi", "kn", "mr"}
    assert llm.requests == []  # a high-confidence answer never calls the LLM
    # DX-007: exactly the recommendable SKUs; DX-009: dose / PHI / PPE / safety on each
    treatments = result["treatments"]
    offered = treatments["chemical"] + treatments["organic"]
    allowed = await recommendable_skus(
        db_session,
        tenant_id=tid,
        crop_id=paddy.crop.id,
        pest_or_disease_id=paddy.problems[ZINC].pest_or_disease_id,
    )
    assert offered and {p["sku_id"] for p in offered} == {str(s.sku_id) for s in allowed}
    for product in treatments["chemical"]:
        assert product["dose_per_acre"] and product["label_claim_id"]
        assert "dose_per_tank_15l" in product and "phi_days" in product
        assert "ppe_text" in product and product["safety_text"]
        assert product["price_paise"] > 0 and "in_stock" in product
    assert treatments["store"]["id"] and treatments["cultural"]["en"]
    # the farmer and the officer are told (FA-007 delivers)
    notified = (
        (
            await db_session.execute(
                select(Notification.user_id).where(Notification.kind == "diagnosis_ready")
            )
        )
        .scalars()
        .all()
    )
    assert set(notified) == {paddy.farmer_user.id, paddy.officer.id}
    # DX-005: reproducible from stored data
    row = await db_session.get_one(Diagnosis, uuid.UUID(body["id"]))
    assert row.scores is not None
    again = replay(row.scores)
    assert again.to_json() == row.scores["decision"]
    assert str(again.problem_id) == str(row.final_problem_id)
    assert len(row.scores["neighbours"]) <= 20 and row.scores["thresholds"]["config_version"] == 0
    # polling returns the same; the farmer sees no provenance, the agronomist does
    mine = await client.get(f"/v1/diagnoses/{body['id']}", headers=bearer(paddy.farmer_user))
    assert mine.status_code == 200 and mine.json()["scores"] is None
    assert mine.json()["images"][0]["signed_url"]
    expert = await client.get(f"/v1/diagnoses/{body['id']}", headers=bearer(paddy.agronomist))
    assert expert.json()["scores"]["decision"]["confidence"] == "high"


async def test_llm_fallback_is_provisional_without_a_buy_button_and_without_pii(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
    app: FastAPI,
) -> None:
    await _strict(db_session, paddy)
    target = paddy.problems[ZINC]
    fake = FakeAnthropic(
        [
            FakeResponse(
                json.dumps(
                    {
                        "problem_id": str(target.id),
                        "confidence": "high",
                        "reasoning": "Bronzing on older leaves.",
                        "visible_symptoms": ["bronzing"],
                    }
                )
            )
        ]
    )
    use_llm(app, ClaudeDiagnosisClient(fake, model="claude-opus-5"))
    # a photo carrying EXIF (device + GPS) — it must not reach the LLM
    exif = Image.Exif()
    exif[0x010F] = "PhoneMaker"
    exif[0x8825] = {1: "N", 2: (17.0, 58.0, 8.0), 3: "E", 4: (79.0, 35.0, 38.0)}
    leaf = Image.open(io.BytesIO(synthetic_leaf(ZINC, 102)))
    photo = await put_photo(blobs, paddy.farmer.tenant_id, to_jpeg(leaf, exif=exif.tobytes()))
    body = await _ask(
        client,
        bearer(paddy.officer),
        photos=[photo],
        crop_id=str(paddy.crop.id),
        farmer_id=paddy.farmer.id,
        crop_stage="vegetative",
    )
    assert body["status"] == "provisional" and body["source"] == "llm"
    assert body["confidence"] == "medium"  # an LLM answer is capped at medium
    assert body["provisional"] and body["can_buy"] is False
    assert body["cta"] == "talk_to_field_officer"
    assert body["result"]["problem"]["id"] == str(target.id)
    assert body["result"]["treatments"]["chemical"]  # treatments shown, not buyable
    assert body["model_versions"]["llm"] == "claude-opus-5"
    # NF-011 / SEC-027: nothing about people in the request; EXIF stripped
    (call,) = fake.messages.calls
    serialized = json.dumps(call, ensure_ascii=False)
    for secret in (
        paddy.farmer.name,
        paddy.farmer.phone,
        paddy.farmer.phone[-10:],
        paddy.officer.name,
        paddy.officer.phone,
        str(paddy.farmer.id),
        str(paddy.officer.id),
        body["id"],
    ):
        assert secret not in serialized, secret
    image_b64 = call["messages"][0]["content"][0]["source"]["data"]
    import base64

    sent = Image.open(io.BytesIO(base64.b64decode(image_b64)))
    assert not sent.getexif()
    # SEC-027 / SPEC 3.4: the prompt and output are logged, without image bytes
    log = (
        await db_session.execute(
            select(LlmCallLog).where(LlmCallLog.diagnosis_id == uuid.UUID(body["id"]))
        )
    ).scalar_one()
    assert log.model == "claude-opus-5" and log.outcome == "ok"
    assert log.prompt["images"][0]["blob_uri"] == photo
    assert image_b64 not in json.dumps(log.prompt)
    assert log.raw_output and log.input_tokens == 1200 and log.stop_reason == "end_turn"
    assert (log.retain_until - log.created_at.date()).days >= 365
    # it waits in the agronomist queue
    queue = await client.get("/v1/diagnoses/review-queue", headers=bearer(paddy.agronomist))
    assert body["id"] in [i["id"] for i in queue.json()["items"]]


async def test_llm_unknown_is_provisional_without_a_problem(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
    llm: ScriptedLlm,
) -> None:
    await _strict(db_session, paddy)
    llm.script = lambda _r: LlmOutcome.unknown("unknown", "scripted-llm")
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, 103))
    body = await _ask(client, bearer(paddy.farmer_user), photos=[photo], crop_id="unknown")
    assert body["status"] == "provisional" and body["result"]["problem"] is None
    assert body["message_key"] == "diagnosis.result.unknown"
    assert body["can_buy"] is False and body["final_problem_id"] is None
    (request,) = llm.requests
    assert request.crop == "unknown" and 1 <= len(request.candidates) <= 5


async def test_non_plant_photos_never_get_a_diagnosis(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
    llm: ScriptedLlm,
) -> None:
    """DX-010 acceptance over the synthetic non-plant set: out of scope, friendly message,
    routed to the expert queue, no problem and no products — with the default thresholds
    (similarity floor) and with the LLM consulted (it says "not a plant")."""
    ids: list[str] = []
    for kind in NON_PLANT_KINDS:
        photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_non_plant(kind, 1))
        body = await _ask(
            client, bearer(paddy.farmer_user), photos=[photo], crop_id=str(paddy.crop.id)
        )
        assert body["status"] == "out_of_scope", kind
        assert body["out_of_scope_reason"] == "no_match"
        assert body["result"]["problem"] is None and body["final_problem_id"] is None
        assert body["result"]["treatments"]["chemical"] == []
        assert body["cta"] == "ask_expert" and body["can_buy"] is False
        assert body["message_key"] == "diagnosis.out_of_scope.no_match"
        ids.append(body["id"])
    assert llm.requests == []
    # a permissive floor: the LLM sees the photo and flags it as not a plant
    await set_thresholds(
        db_session,
        paddy.agronomist,
        crop_id=paddy.crop.id,
        t1=0.99,
        agreement=0.6,
        min_similarity=0.0,
        note="test",
    )
    llm.script = lambda _r: LlmOutcome(
        problem_id=None,
        confidence="high",
        reasoning=f"{NOT_A_PLANT_MARK} a brick wall",
        visible_symptoms=[],
        not_a_plant=True,
        status="unknown",
        model="scripted-llm",
    )
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_non_plant("brick", 2))
    body = await _ask(client, bearer(paddy.farmer_user), photos=[photo], crop_id=str(paddy.crop.id))
    assert body["status"] == "out_of_scope" and body["out_of_scope_reason"] == "not_a_plant"
    assert body["result"]["problem"] is None
    queue = await client.get("/v1/diagnoses/review-queue", headers=bearer(paddy.agronomist))
    listed = {i["id"] for i in queue.json()["items"]}
    assert set(ids) | {body["id"]} <= listed


async def test_other_out_of_scope_signals(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
) -> None:
    tid = paddy.farmer.tenant_id
    headers = bearer(paddy.farmer_user)
    leaf = await put_photo(blobs, tid, synthetic_leaf(ZINC, 104))
    # the device's quality check saw no plant on any photo
    body = await _ask(
        client,
        headers,
        photos=[leaf],
        crop_id=str(paddy.crop.id),
        images=[{"blob_uri": leaf, "quality": {"plant_present": False, "passed": True}}],
    )
    assert body["out_of_scope_reason"] == "not_a_plant"
    # a crop with no approved corpus (cotton in the SMALL seed)
    cotton = (
        await db_session.execute(select(Crop).where(Crop.tenant_id == tid, Crop.code == "cotton"))
    ).scalar_one()
    body = await _ask(client, headers, photos=[leaf], crop_id=str(cotton.id))
    assert body["out_of_scope_reason"] == "unsupported_crop"
    assert body["message_key"] == "diagnosis.out_of_scope.unsupported_crop"
    # bytes that are no image
    junk = await put_photo(blobs, tid, b"not an image at all")
    body = await _ask(client, headers, photos=[junk], crop_id=str(paddy.crop.id))
    assert body["out_of_scope_reason"] == "unreadable_image"


async def test_unknown_crop_uses_the_on_device_guess(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
) -> None:
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, 105))
    body = await _ask(
        client,
        bearer(paddy.farmer_user),
        photos=[photo],
        crop_id="unknown",
        crop_guess={"code": "paddy", "confidence": 0.93},
    )
    assert body["crop_id"] == str(paddy.crop.id)
    assert body["crop_detected_on_device"] == {"code": "paddy", "confidence": 0.93}
    assert body["status"] == "answered"
    # no guess at all: the corpus of every crop is searched, the answer fixes the crop
    body = await _ask(client, bearer(paddy.farmer_user), photos=[photo], crop_id="unknown")
    assert body["status"] == "answered" and body["crop_id"] == str(paddy.crop.id)


async def test_only_approved_corpus_entries_are_used(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
) -> None:
    """WC-007 acceptance: a problem whose images are not approved is never an answer."""
    target = paddy.problems[ZINC]
    images = (
        (await db_session.execute(select(CorpusImage).where(CorpusImage.problem_id == target.id)))
        .scalars()
        .all()
    )
    for image in images:
        image.status = CorpusStatus.DRAFT.value
        image.approved_at = None
    await db_session.flush()
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, 106))
    body = await _ask(client, bearer(paddy.farmer_user), photos=[photo], crop_id=str(paddy.crop.id))
    row = await db_session.get_one(Diagnosis, uuid.UUID(body["id"]))
    assert row.scores is not None
    assert str(target.id) not in {n["problem_id"] for n in row.scores["neighbours"]}
    assert body["final_problem_id"] != str(target.id)
    # and a retired problem likewise (its images approved again)
    for image in images:
        image.status = CorpusStatus.APPROVED.value
        image.approved_at = row.created_at
    target.status = CorpusStatus.RETIRED.value
    await db_session.flush()
    body = await _ask(client, bearer(paddy.farmer_user), photos=[photo], crop_id=str(paddy.crop.id))
    assert body["final_problem_id"] != str(target.id)


async def test_several_photos_and_validation(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
) -> None:
    tid = paddy.farmer.tenant_id
    photos = [await put_photo(blobs, tid, synthetic_leaf(ZINC, 110 + i)) for i in range(3)]
    body = await _ask(client, bearer(paddy.farmer_user), photos=photos, crop_id=str(paddy.crop.id))
    assert body["status"] == "answered" and len(body["images"]) == 3
    headers = bearer(paddy.farmer_user)
    too_many = {"crop_id": "unknown", "images": [{"blob_uri": photos[0]}] * 4}
    assert (await client.post("/v1/diagnoses", json=too_many, headers=headers)).status_code == 422
    missing = {"crop_id": "unknown", "images": [{"blob_uri": f"gs://local/{tid}/diagnosis/nope"}]}
    resp = await client.post("/v1/diagnoses", json=missing, headers=headers)
    assert resp.status_code == 422 and resp.json()["code"] == "diagnosis_image_missing"
    foreign = {"crop_id": "unknown", "images": [{"blob_uri": f"gs://local/{uuid.uuid4()}/x/y"}]}
    resp = await client.post("/v1/diagnoses", json=foreign, headers=headers)
    assert resp.json()["code"] == "diagnosis_image_missing"
    sha = {"crop_id": "unknown", "images": [{"blob_uri": photos[0], "sha256": "0" * 64}]}
    resp = await client.post("/v1/diagnoses", json=sha, headers=headers)
    assert resp.json()["code"] == "image_sha_mismatch"
    bad_crop = {"crop_id": str(uuid.uuid4()), "images": [{"blob_uri": photos[0]}]}
    resp = await client.post("/v1/diagnoses", json=bad_crop, headers=headers)
    assert resp.json()["code"] == "diagnosis_invalid"
    # an officer must name the farmer, and only their own
    officer = bearer(paddy.officer)
    body_no_farmer = {"crop_id": "unknown", "images": [{"blob_uri": photos[0]}]}
    resp = await client.post("/v1/diagnoses", json=body_no_farmer, headers=officer)
    assert resp.json()["code"] == "diagnosis_invalid"


async def test_crop_plot_supplies_crop_and_season(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
) -> None:
    from farmerapp.farmers.models import CropPlot, Farm

    plot = (
        (
            await db_session.execute(
                select(CropPlot)
                .join(Farm, Farm.id == CropPlot.farm_id)
                .where(Farm.farmer_id == paddy.farmer.id)
            )
        )
        .scalars()
        .first()
    )
    assert plot is not None
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, 120))
    body = await _ask(
        client,
        bearer(paddy.farmer_user),
        photos=[photo],
        crop_id="unknown",
        crop_plot_id=str(plot.id),
    )
    assert body["crop_plot_id"] == str(plot.id) and body["season"] == plot.season
    other = {
        "crop_id": "unknown",
        "crop_plot_id": str(uuid.uuid4()),
        "images": [{"blob_uri": photo}],
    }
    resp = await client.post("/v1/diagnoses", json=other, headers=bearer(paddy.farmer_user))
    assert resp.json()["code"] == "diagnosis_invalid"


async def test_scope_of_reads(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    world: Any,
) -> None:
    from farmerapp.auth.models import UserRole

    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, 130))
    body = await _ask(client, bearer(paddy.farmer_user), photos=[photo], crop_id=str(paddy.crop.id))
    path = f"/v1/diagnoses/{body['id']}"
    for role in ("owner", "agronomist", "tenant_admin", "auditor", "director"):
        resp = await client.get(path, headers=bearer(world.a.user(role)))
        assert resp.status_code == 200, role
    officers = [u for u in world.a.everyone if u.role == UserRole.FIELD_OFFICER]
    stranger = next(u for u in officers if u.id != paddy.officer.id)
    assert (await client.get(path, headers=bearer(stranger))).status_code == 404
    assert (await client.get(path, headers=bearer(paddy.officer))).status_code == 200
    listing = await client.get("/v1/diagnoses", headers=bearer(paddy.farmer_user))
    assert [i["id"] for i in listing.json()["items"]] == [body["id"]]
    filtered = await client.get(
        "/v1/diagnoses",
        params={"farmer_id": str(paddy.farmer.id), "status": ["answered"]},
        headers=bearer(paddy.officer),
    )
    assert [i["id"] for i in filtered.json()["items"]] == [body["id"]]
    assert (await client.get("/v1/diagnoses", headers=bearer(stranger))).json()["items"] == []
