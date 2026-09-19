"""WC-007 corpus manager: problems, images (uploads + server embedding), the status
workflow with approvals and corpus versions, immutability of approved entries."""

from __future__ import annotations

import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import PestOrDisease
from farmerapp.diagnosis.images import synthetic_leaf
from farmerapp.diagnosis.models import CorpusImage
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.uploads.blobstore import BlobStore
from tests.authz.conftest import Bearer
from tests.diagnosis.conftest import Paddy


async def _pest(session: AsyncSession, code: str) -> PestOrDisease:
    return (
        await session.execute(select(PestOrDisease).where(PestOrDisease.code == code))
    ).scalar_one()


async def _crop(session: AsyncSession, code: str) -> Crop:
    return (await session.execute(select(Crop).where(Crop.code == code))).scalar_one()


async def _upload(blobs: BlobStore, tenant_id: uuid.UUID, data: bytes) -> str:
    import hashlib

    sha = hashlib.sha256(data).hexdigest()
    return await blobs.put(f"{tenant_id}/corpus/{sha}", data, content_type="image/jpeg")


async def test_problem_lifecycle_and_versions(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
) -> None:
    headers = bearer(paddy.agronomist)
    maize = await _crop(db_session, "maize")
    pest = await _pest(db_session, "maize_zinc_deficiency")
    create = {
        "pest_or_disease_id": str(pest.id),
        "crop_id": str(maize.id),
        "names": {"en": "Zinc deficiency", "te": "జింక్ లోపం"},
        "symptoms": {"en": ["White bands between veins"]},
        "cultural_practices": {"en": ["Apply zinc sulphate at sowing"]},
    }
    resp = await client.post("/v1/corpus/problems", json=create, headers=headers)
    assert resp.status_code == 201, resp.text
    problem: dict[str, Any] = resp.json()
    assert problem["status"] == "draft" and problem["source"] == "internal"
    assert problem["pest_code"] == "maize_zinc_deficiency" and problem["problem_type"] == "nutrient"
    assert problem["labelled_by"] == str(paddy.agronomist.id)
    pid = problem["id"]
    dup = await client.post("/v1/corpus/problems", json=create, headers=headers)
    assert dup.status_code == 409 and dup.json()["code"] == "corpus_problem_exists"
    # images: upload, the server embeds with the pinned encoder
    tid = paddy.farmer.tenant_id
    uri = await _upload(blobs, tid, synthetic_leaf("maize_zinc_deficiency", 1))
    image = await client.post(
        f"/v1/corpus/problems/{pid}/images",
        json={"blob_uri": uri, "part": "leaf", "severity": "medium", "region": "Warangal"},
        headers=headers,
    )
    assert image.status_code == 201, image.text
    img = image.json()
    assert img["status"] == "draft" and img["encoder_name"] == "fake-dct"
    assert img["crop_id"] == str(maize.id)
    row = await db_session.get_one(CorpusImage, uuid.UUID(img["id"]))
    assert len(row.embedding) == 768
    again = await client.post(
        f"/v1/corpus/problems/{pid}/images", json={"blob_uri": uri}, headers=headers
    )
    assert again.status_code == 409 and again.json()["code"] == "corpus_image_exists"
    # edit while draft; the workflow
    patched = await client.patch(
        f"/v1/corpus/problems/{pid}",
        json={"names": {"en": "Zinc deficiency (khaira)"}, "notes": "field notes"},
        headers=headers,
    )
    assert patched.json()["names"]["en"] == "Zinc deficiency (khaira)"
    no_en = await client.patch(
        f"/v1/corpus/problems/{pid}", json={"names": {"te": "x"}}, headers=headers
    )
    assert no_en.status_code == 422
    skip = await client.post(
        f"/v1/corpus/problems/{pid}/transition", json={"to": "approved"}, headers=headers
    )
    assert skip.status_code == 409 and skip.json()["code"] == "invalid_transition"
    for to in ("reviewed",):
        resp = await client.post(
            f"/v1/corpus/problems/{pid}/transition", json={"to": to}, headers=headers
        )
        assert resp.json()["status"] == to and resp.json()["reviewed_by"]
    await client.post(
        f"/v1/corpus/images/{img['id']}/transition", json={"to": "reviewed"}, headers=headers
    )
    before = (await client.get("/v1/corpus/versions", headers=headers)).json()["current"]
    approval = await client.post(
        "/v1/corpus/approvals",
        json={"problem_ids": [pid], "image_ids": [img["id"]], "note": "week 38"},
        headers=headers,
    )
    assert approval.status_code == 201, approval.text
    version = approval.json()
    assert version["version"] == before + 1
    assert version["changes"]["problems"] == [pid] and version["changes"]["images"] == [img["id"]]
    approved = (await client.get(f"/v1/corpus/problems/{pid}", headers=headers)).json()
    assert approved["status"] == "approved" and approved["approved_by"] == str(paddy.agronomist.id)
    assert approved["approved_in_version"] == version["version"]
    assert approved["image_counts"] == {"approved": 1}
    # approved entries are immutable; retiring bumps the version again
    locked = await client.patch(
        f"/v1/corpus/problems/{pid}", json={"notes": "late edit"}, headers=headers
    )
    assert locked.status_code == 409 and locked.json()["code"] == "corpus_entry_locked"
    retired = await client.post(
        f"/v1/corpus/problems/{pid}/transition", json={"to": "retired"}, headers=headers
    )
    assert retired.json()["status"] == "retired" and retired.json()["retired_at"]
    versions = (await client.get("/v1/corpus/versions", headers=headers)).json()
    assert versions["current"] == before + 2
    assert versions["items"][0]["changes"]["retired"] == [pid]
    closed = await client.post(
        f"/v1/corpus/problems/{pid}/images",
        json={"blob_uri": await _upload(blobs, tid, synthetic_leaf("maize_zinc_deficiency", 2))},
        headers=headers,
    )
    assert closed.status_code == 409
    # a retired problem frees the crop x pest slot for a new entry
    assert (
        await client.post("/v1/corpus/problems", json=create, headers=headers)
    ).status_code == 201


async def test_single_image_approval_and_listings(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    world: Any,
) -> None:
    headers = bearer(paddy.agronomist)
    zinc = paddy.problems["paddy_zinc_deficiency"]
    uri = await _upload(blobs, paddy.farmer.tenant_id, synthetic_leaf("paddy_zinc_deficiency", 50))
    img = (
        await client.post(
            f"/v1/corpus/problems/{zinc.id}/images", json={"blob_uri": uri}, headers=headers
        )
    ).json()
    await client.post(
        f"/v1/corpus/images/{img['id']}/transition", json={"to": "reviewed"}, headers=headers
    )
    approved = await client.post(
        f"/v1/corpus/images/{img['id']}/transition",
        json={"to": "approved", "note": "one more"},
        headers=headers,
    )
    assert approved.json()["status"] == "approved" and approved.json()["approved_in_version"] == 2
    retired = await client.post(
        f"/v1/corpus/images/{img['id']}/transition", json={"to": "retired"}, headers=headers
    )
    assert retired.json()["status"] == "retired"
    listing = (
        await client.get(
            "/v1/corpus/problems",
            params={"crop_id": str(paddy.crop.id), "status": ["approved"], "source": "public"},
            headers=bearer(world.a.owner),
        )
    ).json()
    assert listing["corpus_version"] == 3
    assert {p["id"] for p in listing["items"]} == {str(p.id) for p in paddy.problems.values()}
    images = (
        await client.get(
            f"/v1/corpus/problems/{zinc.id}/images",
            params={"status": ["approved"], "limit": 3},
            headers=headers,
        )
    ).json()
    assert len(images["items"]) == 3 and images["next_cursor"]
    assert images["items"][0]["signed_url"]
    assert (
        await client.get(f"/v1/corpus/problems/{uuid.uuid4()}", headers=headers)
    ).status_code == 404
    denied = await client.post("/v1/corpus/approvals", json={"problem_ids": []}, headers=headers)
    assert denied.status_code == 422
    farmer = await client.get("/v1/corpus/problems", headers=bearer(paddy.farmer_user))
    assert farmer.status_code == 403
    owner_write = await client.post(
        f"/v1/corpus/images/{img['id']}/transition",
        json={"to": "draft"},
        headers=bearer(world.a.owner),
    )
    assert owner_write.status_code == 403


async def test_problem_validation(
    client: AsyncClient, bearer: Bearer, paddy: Paddy, db_session: AsyncSession
) -> None:
    headers = bearer(paddy.agronomist)
    cotton = await _crop(db_session, "cotton")
    paddy_pest = await _pest(db_session, "paddy_bph")
    wrong_crop = {
        "pest_or_disease_id": str(paddy_pest.id),
        "crop_id": str(cotton.id),
        "names": {"en": "BPH"},
    }
    resp = await client.post("/v1/corpus/problems", json=wrong_crop, headers=headers)
    assert resp.status_code == 422 and resp.json()["code"] == "corpus_problem_invalid"
    unknown = {**wrong_crop, "pest_or_disease_id": str(uuid.uuid4())}
    assert (
        await client.post("/v1/corpus/problems", json=unknown, headers=headers)
    ).status_code == 422
    no_crop = {**wrong_crop, "crop_id": str(uuid.uuid4())}
    assert (
        await client.post("/v1/corpus/problems", json=no_crop, headers=headers)
    ).status_code == 422
    bad_lang = {**wrong_crop, "names": {"en": "x", "fr": "y"}}
    assert (
        await client.post("/v1/corpus/problems", json=bad_lang, headers=headers)
    ).status_code == 422
    missing_blob = await client.post(
        f"/v1/corpus/problems/{paddy.problems['paddy_bph'].id}/images",
        json={"blob_uri": f"gs://local/{paddy.farmer.tenant_id}/corpus/none"},
        headers=headers,
    )
    assert missing_blob.status_code == 422
