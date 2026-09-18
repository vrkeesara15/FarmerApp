from __future__ import annotations

import base64
import json
from collections.abc import AsyncIterator

import pytest
from httpx import ASGITransport, AsyncClient

from farmerapp.worker import dispatch as dispatch_mod
from farmerapp.worker.app import create_app
from farmerapp.worker.messages import PubSubMessage, PushEnvelope
from farmerapp.worker.topics import Topic


def _envelope(
    topic: str | None, subscription: str, payload: dict[str, object]
) -> dict[str, object]:
    data = base64.b64encode(json.dumps(payload).encode()).decode()
    attrs = {"topic": topic} if topic else {}
    return {
        "message": {"data": data, "attributes": attrs, "messageId": "m1", "publishTime": "t"},
        "subscription": subscription,
    }


@pytest.fixture
async def worker_client() -> AsyncIterator[AsyncClient]:
    transport = ASGITransport(app=create_app(), raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://worker") as c:
        yield c


def test_every_topic_has_a_handler() -> None:
    assert set(dispatch_mod.HANDLERS) == set(Topic)


def test_topic_resolution() -> None:
    env = PushEnvelope.model_validate(
        _envelope(None, "projects/p/subscriptions/visit-created-worker", {"a": 1})
    )
    assert env.topic() == Topic.VISIT_CREATED
    assert env.message.json_body() == {"a": 1}

    env = PushEnvelope.model_validate(_envelope("notify.send", "", {}))
    assert env.topic() == Topic.NOTIFY_SEND

    env = PushEnvelope.model_validate(_envelope("nope", "", {}))
    assert env.topic() is None
    assert PubSubMessage().json_body() == {}
    with pytest.raises(ValueError, match="JSON object"):
        PubSubMessage(data=base64.b64encode(b"[1]").decode()).json_body()


async def test_push_dispatches_all_topics(worker_client: AsyncClient) -> None:
    for topic in Topic:
        resp = await worker_client.post("/push", json=_envelope(str(topic), "", {"x": 1}))
        assert resp.status_code == 204, topic


async def test_push_unknown_topic_is_nacked(worker_client: AsyncClient) -> None:
    resp = await worker_client.post(
        "/push", json=_envelope(None, "projects/p/subscriptions/mystery", {})
    )
    assert resp.status_code == 400
    assert resp.json()["code"] == "unknown_topic"


async def test_worker_health(worker_client: AsyncClient) -> None:
    resp = await worker_client.get("/v1/health")
    assert resp.status_code == 200
