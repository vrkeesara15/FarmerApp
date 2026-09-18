from __future__ import annotations

import asyncio

import pytest
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


async def test_cors_preflight_for_console_origin(client: AsyncClient) -> None:
    resp = await client.options(
        "/v1/auth/otp/send",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    assert resp.status_code == 200
    assert resp.headers["access-control-allow-origin"] == "http://localhost:3000"
    assert resp.headers["access-control-allow-credentials"] == "true"


async def test_lifespan_runs_the_scheduler_loop(
    app: FastAPI, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Local runs tick the in-process scheduler; the task is cancelled on shutdown."""
    from farmerapp.api import app as app_mod

    calls: list[object] = []

    async def fake_tick(scheduler: object, *_: object) -> int:
        calls.append(scheduler)
        return 0

    monkeypatch.setattr(app_mod, "tick", fake_tick)
    monkeypatch.setattr(app_mod, "SCHEDULER_INTERVAL_S", 0.01)
    async with app.router.lifespan_context(app):
        await asyncio.sleep(0.1)
    assert calls and calls[0] is app.state.auth.scheduler
    n = len(calls)
    await asyncio.sleep(0.05)
    assert len(calls) == n  # loop stopped with the app
