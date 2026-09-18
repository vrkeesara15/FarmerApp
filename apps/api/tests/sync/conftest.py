"""Sync fixtures (FA-025 / NF-003): the write context of the farmers tests plus a builder for
``/v1/sync`` operations."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from httpx import AsyncClient

from tests.authz.conftest import bearer, world  # noqa: F401  (fixtures re-exported)
from tests.farmers.write_fixtures import WriteCtx, ctx  # noqa: F401  (fixture re-exported)

DEVICE = "device-sync-1"
T_CLIENT = datetime(2026, 9, 18, 8, 0, tzinfo=UTC)


def op(
    entity: str,
    action: str,
    payload: dict[str, Any],
    *,
    entity_id: uuid.UUID | str | None = None,
    base_version: int = 0,
    op_id: uuid.UUID | None = None,
    client_ts: datetime = T_CLIENT,
) -> dict[str, Any]:
    return {
        "op_id": str(op_id or uuid.uuid4()),
        "entity": entity,
        "action": action,
        "entity_id": str(entity_id or uuid.uuid4()),
        "base_version": base_version,
        "payload": payload,
        "client_ts": client_ts.isoformat(),
    }


async def sync(
    client: AsyncClient,
    write_ctx: WriteCtx,
    ops: list[dict[str, Any]],
    *,
    cursor: str | None = None,
    headers: dict[str, str] | None = None,
    device_id: str = DEVICE,
) -> dict[str, Any]:
    resp = await client.post(
        "/v1/sync",
        json={"device_id": device_id, "cursor": cursor, "ops": ops},
        headers=headers or write_ctx.headers,
    )
    assert resp.status_code == 200, resp.text
    body: dict[str, Any] = resp.json()
    assert len(body["results"]) == len(ops)
    return body
