"""RFC 9457 problem+json shape with a stable ``code`` for every error path."""

from __future__ import annotations

from fastapi import FastAPI
from httpx import AsyncClient

from farmerapp.api.errors import PROBLEM_MEDIA_TYPE, ConflictError, NotFoundError


def _install_probe_routes(app: FastAPI) -> None:
    @app.get("/v1/_probe/not-found")
    async def _nf() -> None:
        raise NotFoundError("Farmer f1 not found")

    @app.get("/v1/_probe/conflict")
    async def _conflict() -> None:
        raise ConflictError("Duplicate phone", extra={"field": "phone"})

    @app.get("/v1/_probe/validate")
    async def _validate(n: int) -> dict[str, int]:
        return {"n": n}

    @app.get("/v1/_probe/boom")
    async def _boom() -> None:
        raise RuntimeError("kaboom")


def _assert_problem(resp_json: dict[str, object], *, status: int, code: str) -> None:
    assert resp_json["status"] == status
    assert resp_json["code"] == code
    assert resp_json["type"] == f"https://farmerapp.dev/problems/{code}"
    assert isinstance(resp_json["title"], str)
    assert isinstance(resp_json["instance"], str)
    assert isinstance(resp_json["trace_id"], str)


async def test_unknown_route_is_problem_json(client: AsyncClient) -> None:
    resp = await client.get("/v1/does-not-exist", headers={"X-Request-Id": "t1"})
    assert resp.status_code == 404
    assert resp.headers["content-type"].startswith(PROBLEM_MEDIA_TYPE)
    body = resp.json()
    _assert_problem(body, status=404, code="not_found")
    assert body["trace_id"] == "t1"


async def test_method_not_allowed(client: AsyncClient) -> None:
    resp = await client.post("/v1/health")
    assert resp.status_code == 405
    _assert_problem(resp.json(), status=405, code="method_not_allowed")


async def test_app_error_subclasses(app: FastAPI, client: AsyncClient) -> None:
    _install_probe_routes(app)

    resp = await client.get("/v1/_probe/not-found")
    body = resp.json()
    _assert_problem(body, status=404, code="not_found")
    assert body["detail"] == "Farmer f1 not found"
    assert body["instance"] == "/v1/_probe/not-found"

    resp = await client.get("/v1/_probe/conflict")
    body = resp.json()
    _assert_problem(body, status=409, code="conflict")
    assert body["field"] == "phone"


async def test_validation_error(app: FastAPI, client: AsyncClient) -> None:
    _install_probe_routes(app)
    resp = await client.get("/v1/_probe/validate", params={"n": "x"})
    assert resp.status_code == 422
    body = resp.json()
    _assert_problem(body, status=422, code="validation_error")
    assert body["errors"][0]["loc"] == ["query", "n"]


async def test_unhandled_exception_is_masked(app: FastAPI, client: AsyncClient) -> None:
    _install_probe_routes(app)
    resp = await client.get("/v1/_probe/boom")
    assert resp.status_code == 500
    body = resp.json()
    _assert_problem(body, status=500, code="internal_error")
    assert "kaboom" not in resp.text
