"""Pub/Sub push envelope models.

Push delivery body::

    {"message": {"data": "<base64>", "attributes": {...}, "messageId": "..",
                 "publishTime": ".."}, "subscription": "projects/p/subscriptions/s"}
"""

from __future__ import annotations

import base64
import json
from typing import Any

from pydantic import BaseModel, Field

from farmerapp.worker.topics import Topic


class PubSubMessage(BaseModel):
    data: str = Field(default="", description="base64-encoded payload")
    attributes: dict[str, str] = Field(default_factory=dict)
    message_id: str = Field(default="", alias="messageId")
    publish_time: str = Field(default="", alias="publishTime")

    model_config = {"populate_by_name": True}

    def decoded(self) -> bytes:
        return base64.b64decode(self.data) if self.data else b""

    def json_body(self) -> dict[str, Any]:
        raw = self.decoded()
        if not raw:
            return {}
        parsed = json.loads(raw)
        if not isinstance(parsed, dict):
            raise ValueError("message payload must be a JSON object")
        return parsed


class PushEnvelope(BaseModel):
    message: PubSubMessage
    subscription: str = ""

    model_config = {"populate_by_name": True}

    def topic(self) -> Topic | None:
        """Topic from the ``topic`` attribute, else derived from the subscription name.

        Subscriptions are named ``<topic-with-dashes>-worker`` in Terraform
        (e.g. ``visit-created-worker`` -> ``visit.created``).
        """
        name = self.message.attributes.get("topic")
        if name is None and self.subscription:
            leaf = self.subscription.rsplit("/", 1)[-1]
            leaf = leaf.removesuffix("-worker").removesuffix("-push")
            name = leaf.replace("-", ".")
        try:
            return Topic(name) if name else None
        except ValueError:
            return None
