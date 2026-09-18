from __future__ import annotations

from fastapi import FastAPI
from httpx import AsyncClient

from farmerapp import __version__


async def test_health_ok(client: AsyncClient) -> None:
    resp = await client.get("/v1/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body == {"status": "ok", "service": "api", "version": __version__, "env": "test"}


async def test_trace_id_echoed_and_generated(client: AsyncClient) -> None:
    resp = await client.get("/v1/health", headers={"X-Request-Id": "abc-123"})
    assert resp.headers["X-Request-Id"] == "abc-123"

    resp = await client.get("/v1/health", headers={"X-Cloud-Trace-Context": "trace42/span;o=1"})
    assert resp.headers["X-Request-Id"] == "trace42"

    resp = await client.get("/v1/health")
    assert len(resp.headers["X-Request-Id"]) == 32


def test_openapi_is_3_1(app: FastAPI) -> None:
    schema = app.openapi()
    assert schema["openapi"] == "3.1.0"
    assert "/v1/health" in schema["paths"]
    assert "Problem" in schema["components"]["schemas"]
