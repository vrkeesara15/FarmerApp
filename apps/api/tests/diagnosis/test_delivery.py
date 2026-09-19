"""diagnosis.requested delivery: Pub/Sub publish + worker handler (retries, redelivery,
attempt cap), inline deferral, and the sync op / change feed for the apps."""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.diagnosis.encoder import EncoderError
from farmerapp.diagnosis.images import synthetic_leaf
from farmerapp.diagnosis.llm import LlmCallRecord, LlmTemporaryError
from farmerapp.diagnosis.models import Diagnosis, LlmCallLog
from farmerapp.diagnosis.services import DiagnosisServices
from farmerapp.diagnosis.thresholds import set_thresholds
from farmerapp.diagnosis.worker import DiagnosisNotReadyError, handle_diagnosis_message
from farmerapp.payments.publisher import RecordingPublisher, encode
from farmerapp.uploads.blobstore import BlobStore
from farmerapp.worker.messages import PubSubMessage
from farmerapp.worker.topics import Topic
from tests.authz.conftest import Bearer
from tests.diagnosis.conftest import Paddy, ScriptedLlm, put_photo

ZINC = "paddy_zinc_deficiency"


def _provider(session: AsyncSession) -> Any:
    @contextlib.asynccontextmanager
    async def provide(_tenant: uuid.UUID) -> AsyncIterator[AsyncSession]:
        async with session.begin_nested():
            yield session

    return provide


async def _queued(
    client: AsyncClient, bearer: Bearer, paddy: Paddy, blobs: BlobStore, variant: int
) -> dict[str, Any]:
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, variant))
    resp = await client.post(
        "/v1/diagnoses",
        json={"crop_id": str(paddy.crop.id), "images": [{"blob_uri": photo}]},
        headers=bearer(paddy.farmer_user),
    )
    assert resp.status_code == 202, resp.text
    body: dict[str, Any] = resp.json()
    return body


async def test_pubsub_delivery_and_worker(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
) -> None:
    publisher = RecordingPublisher()
    services.publisher = publisher
    body = await _queued(client, bearer, paddy, blobs, 300)
    assert body["status"] == "queued" and body["provisional"] and body["result"] is None
    ((topic, payload),) = publisher.messages
    assert topic == Topic.DIAGNOSIS_REQUESTED
    assert payload == {"tenant_id": str(paddy.farmer.tenant_id), "diagnosis_id": body["id"]}
    message = publisher.message()
    outcome = await handle_diagnosis_message(
        message, services=services, session_provider=_provider(db_session)
    )
    assert outcome == "processed"
    row = await db_session.get_one(Diagnosis, uuid.UUID(body["id"]))
    assert row.status == "answered" and row.attempts == 1
    # a redelivery of the same message is a no-op
    again = await handle_diagnosis_message(
        message, services=services, session_provider=_provider(db_session)
    )
    assert again == "skipped"


async def test_worker_edge_cases(services: DiagnosisServices, db_session: AsyncSession) -> None:
    provide = _provider(db_session)
    bad = PubSubMessage(data=encode({"diagnosis_id": "nope"}), message_id="1")
    assert await handle_diagnosis_message(bad, services=services, session_provider=provide) == (
        "ignored"
    )
    now = datetime(2026, 9, 19, 10, tzinfo=UTC)
    unknown = {"tenant_id": str(uuid.uuid4()), "diagnosis_id": str(uuid.uuid4())}
    young = PubSubMessage(data=encode(unknown), publishTime="2026-09-19T09:58:00Z")
    with pytest.raises(DiagnosisNotReadyError):
        await handle_diagnosis_message(young, services=services, session_provider=provide, now=now)
    old = PubSubMessage(data=encode(unknown), publishTime="2026-09-19T08:00:00Z")
    result = await handle_diagnosis_message(
        old, services=services, session_provider=provide, now=now
    )
    assert result == "ignored"


async def test_llm_outage_is_retried_then_becomes_unknown(
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
    publisher = RecordingPublisher()
    services.publisher = publisher
    body = await _queued(client, bearer, paddy, blobs, 301)
    call = LlmCallRecord(
        provider="scripted", model="scripted-llm", attempt=1, prompt={"text": "x"},
        outcome="rate_limited", latency_ms=3, error="429",
    )  # fmt: skip
    llm.error = LlmTemporaryError("rate limited", [call])
    provide = _provider(db_session)
    services.settings = services.settings.model_copy(update={"diagnosis_max_attempts": 2})
    with pytest.raises(LlmTemporaryError):
        await handle_diagnosis_message(
            publisher.message(), services=services, session_provider=provide
        )
    row = await db_session.get_one(Diagnosis, uuid.UUID(body["id"]))
    assert row.status == "queued" and row.attempts == 1
    logs = (await db_session.execute(select(LlmCallLog))).scalars().all()
    assert [log.outcome for log in logs] == ["rate_limited"]  # logged even though it failed
    # the second (final) delivery does not wait on the provider any longer
    assert (
        await handle_diagnosis_message(
            publisher.message(), services=services, session_provider=provide
        )
        == "processed"
    )
    await db_session.refresh(row)
    assert row.status == "provisional" and row.result is not None
    assert row.result["problem"] is None and row.attempts == 2


async def test_inline_deferral_keeps_the_diagnosis_queued(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    db_session: AsyncSession,
    llm: ScriptedLlm,
    app: FastAPI,
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
    llm.error = LlmTemporaryError("down", [])
    body = await _queued(client, bearer, paddy, blobs, 302)
    assert body["status"] == "queued"

    class Broken:
        info = services.encoder.info

        async def encode(self, images: Any) -> Any:
            raise EncoderError("down")

    services.encoder = Broken()
    body = await _queued(client, bearer, paddy, blobs, 303)
    assert body["status"] == "queued"


async def test_sync_create_and_change_feed(
    client: AsyncClient,
    bearer: Bearer,
    paddy: Paddy,
    services: DiagnosisServices,
    blobs: BlobStore,
    world: Any,
) -> None:
    photo = await put_photo(blobs, paddy.farmer.tenant_id, synthetic_leaf(ZINC, 310))
    entity_id = str(uuid.uuid4())
    op = {
        "op_id": str(uuid.uuid4()),
        "entity": "diagnosis",
        "action": "create",
        "entity_id": entity_id,
        "base_version": 0,
        "payload": {
            "farmer_id": str(paddy.farmer.id),
            "crop_id": str(paddy.crop.id),
            "images": [{"blob_uri": photo, "quality": {"passed": True, "blur_score": 212.5}}],
        },
        "client_ts": (datetime.now(UTC) - timedelta(hours=3)).isoformat(),
    }
    resp = await client.post(
        "/v1/sync",
        json={"device_id": "agent-1", "cursor": None, "ops": [op]},
        headers=bearer(paddy.officer),
    )
    assert resp.status_code == 200, resp.text
    (result,) = resp.json()["results"]
    assert result["status"] == "applied" and result["server"]["id"] == entity_id
    assert result["server"]["subject"] == "officer" and result["server"]["captured_at"]
    # a replayed create (new op id, same entity) is a conflict with the server row
    replay = {**op, "op_id": str(uuid.uuid4())}
    again = await client.post(
        "/v1/sync",
        json={"device_id": "agent-1", "cursor": None, "ops": [replay]},
        headers=bearer(paddy.officer),
    )
    assert again.json()["results"][0]["status"] == "conflict"
    # the answer reaches both apps through the feed
    for user in (paddy.farmer_user, paddy.officer):
        feed = await client.post(
            "/v1/sync",
            json={"device_id": "d", "cursor": None, "ops": []},
            headers=bearer(user),
        )
        entries = [c for c in feed.json()["changes"] if c["entity"] == "diagnosis"]
        assert [c["entity_id"] for c in entries] == [entity_id]
        assert entries[0]["data"]["status"] == "answered"
    officers = [u for u in world.a.everyone if u.role == "field_officer"]
    stranger = next(u for u in officers if u.id != paddy.officer.id)
    feed = await client.post(
        "/v1/sync", json={"device_id": "d", "cursor": None, "ops": []}, headers=bearer(stranger)
    )
    assert not [c for c in feed.json()["changes"] if c["entity"] == "diagnosis"]
    # devices never update or delete a diagnosis; a store manager cannot create one
    update = {**op, "op_id": str(uuid.uuid4()), "action": "update", "base_version": 1}
    resp = await client.post(
        "/v1/sync",
        json={"device_id": "agent-1", "cursor": None, "ops": [update]},
        headers=bearer(paddy.officer),
    )
    assert resp.json()["results"][0]["status"] == "rejected"
    manager = world.a.user("store_manager")
    create = {**op, "op_id": str(uuid.uuid4()), "entity_id": str(uuid.uuid4())}
    resp = await client.post(
        "/v1/sync",
        json={"device_id": "s", "cursor": None, "ops": [create]},
        headers=bearer(manager),
    )
    assert resp.json()["results"][0]["error"]["code"] == "forbidden"
