"""Publishing to Pub/Sub topics (SPEC 8.3: webhooks are processed via Pub/Sub).

``Publisher.publish(topic, data)`` returns the message id. Adapters:

* ``PubSubRestPublisher`` — the Pub/Sub REST ``topics/{topic}:publish`` call. Locally it
  targets the emulator (``PUBSUB_EMULATOR_HOST``, no auth); in stg / prd the Cloud Run
  service account's token is added by ``token_provider`` (seam: the metadata-server token
  fetcher lands with the worker deployment, OPS-004).
* ``RecordingPublisher`` — keeps messages in memory (tests; the test then runs the worker
  handler in-process with the recorded message).

Every message carries the W3C ``traceparent`` of the publishing request as a message
attribute (NF-014, ``farmerapp.telemetry.inject_trace_attributes``); the worker continues
that trace (``farmerapp.worker.app``).

``payment_webhook_delivery = inline`` (the local / dev default) publishes nothing: the
verified event is applied in the request transaction (``farmerapp.payments.webhooks``).
"""

from __future__ import annotations

import base64
import json
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Any, Protocol

import httpx

from farmerapp.telemetry import inject_trace_attributes
from farmerapp.worker.messages import PubSubMessage
from farmerapp.worker.topics import Topic


class PublishError(RuntimeError):
    """The topic did not accept the message (the webhook answers 503 so the provider retries)."""


class Publisher(Protocol):
    async def publish(self, topic: Topic, data: dict[str, Any]) -> str: ...


def encode(data: dict[str, Any]) -> str:
    return base64.b64encode(json.dumps(data, separators=(",", ":")).encode()).decode()


def message_attributes(topic: Topic) -> dict[str, str]:
    """``topic`` plus the trace context (``traceparent``) of the current request."""
    attributes = {"topic": str(topic)}
    inject_trace_attributes(attributes)
    return attributes


class PubSubRestPublisher:
    def __init__(
        self,
        *,
        base_url: str,
        project: str,
        token_provider: Callable[[], Awaitable[str | None]] | None = None,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        base = base_url if base_url.startswith("http") else f"http://{base_url}"
        self._base = base.rstrip("/")
        self._project = project
        self._token_provider = token_provider
        self._client = client

    async def publish(self, topic: Topic, data: dict[str, Any]) -> str:
        name = str(topic).replace(".", "-")
        url = f"{self._base}/v1/projects/{self._project}/topics/{name}:publish"
        headers: dict[str, str] = {}
        if self._token_provider is not None:
            token = await self._token_provider()
            if token:
                headers["Authorization"] = f"Bearer {token}"
        body = {"messages": [{"data": encode(data), "attributes": message_attributes(topic)}]}
        try:
            if self._client is not None:
                resp = await self._client.post(url, json=body, headers=headers)
            else:
                async with httpx.AsyncClient(timeout=10.0) as client:
                    resp = await client.post(url, json=body, headers=headers)
            resp.raise_for_status()
            ids = resp.json().get("messageIds") or [""]
        except (httpx.HTTPError, ValueError) as exc:
            raise PublishError(f"publish to {topic} failed") from exc
        return str(ids[0])


@dataclass
class RecordingPublisher:
    messages: list[tuple[Topic, dict[str, Any]]] = field(default_factory=list)
    attributes: list[dict[str, str]] = field(default_factory=list)
    fail: bool = False

    async def publish(self, topic: Topic, data: dict[str, Any]) -> str:
        if self.fail:
            raise PublishError("recording publisher set to fail")
        self.messages.append((topic, data))
        self.attributes.append(message_attributes(topic))
        return str(len(self.messages))

    def message(self, index: int = -1) -> PubSubMessage:
        """The recorded message as the worker would receive it (push envelope ``message``)."""
        _, data = self.messages[index]
        return PubSubMessage(
            data=encode(data), attributes=dict(self.attributes[index]), message_id=str(index)
        )


__all__ = [
    "PubSubRestPublisher",
    "PublishError",
    "Publisher",
    "RecordingPublisher",
    "encode",
    "message_attributes",
]
