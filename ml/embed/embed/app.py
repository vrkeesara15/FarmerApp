"""The ``embed`` service (Cloud Run, ingress internal) — contract in docs/prs/M6-diagnosis-api.md.

``POST /v1/embed``::

    {"model": "siglip-base-patch16-224", "version": "2024-01", "images": [{"b64": "<JPEG bytes>"}]}
    -> 200 {"model": ..., "version": ..., "dim": 768, "vectors": [[...768 floats, unit norm]]}

``GET /healthz`` -> 200 once the model is loaded; ``GET /info`` -> ``{name, version, dim, revision,
weights_sha256, device, max_batch, max_image_bytes}``.

Errors are RFC 9457 ``application/problem+json`` with a stable ``code``: 409 ``model_mismatch``
(the request pins another model / version — vectors of two encoders are never mixed), 413
``image_too_large`` / ``request_too_large``, 422 ``validation_error`` (shape, 1..max_batch images),
``invalid_base64``, ``unreadable_image`` (with the image ``index``).

Authentication is Cloud Run's: ingress internal plus ``roles/run.invoker`` for the caller's service
account; Cloud Run verifies the OIDC identity token (audience = the service URL) before a request
reaches this process, so the app does not re-verify it.
"""

from __future__ import annotations

import base64
import binascii
import logging
import os
import time
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field
from starlette.concurrency import run_in_threadpool

from embed import spec
from embed.encoder import Encoder, UnreadableImageError, decode_rgb

log = logging.getLogger("embed")


@dataclass(frozen=True)
class Settings:
    model_dir: Path = Path("/opt/model")
    device: str = "cpu"
    threads: int | None = None
    max_batch: int = 8
    max_image_bytes: int = 8 * 1024 * 1024

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> Settings:
        env = dict(os.environ if env is None else env)
        threads = env.get("EMBED_THREADS")
        return cls(
            model_dir=Path(env.get("EMBED_MODEL_DIR", "/opt/model")),
            device=env.get("EMBED_DEVICE", "cpu"),
            threads=int(threads) if threads else None,
            max_batch=int(env.get("EMBED_MAX_BATCH", "8")),
            max_image_bytes=int(env.get("EMBED_MAX_IMAGE_BYTES", str(8 * 1024 * 1024))),
        )

    @property
    def max_request_bytes(self) -> int:
        # base64 is 4/3 of the bytes; 64 KiB slack for the JSON envelope.
        return self.max_batch * (self.max_image_bytes * 4 // 3 + 4) + 64 * 1024


class ImageIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    b64: str = Field(min_length=1)


class EmbedRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    model: str
    version: str
    images: list[ImageIn] = Field(min_length=1)


class EmbedResponse(BaseModel):
    model: str
    version: str
    dim: int
    vectors: list[list[float]]


class Problem(Exception):
    def __init__(self, status: int, code: str, title: str, **extra: Any) -> None:
        super().__init__(title)
        self.status, self.code, self.title, self.extra = status, code, title, extra


def problem_response(status: int, code: str, title: str, **extra: Any) -> JSONResponse:
    body = {"type": f"urn:farmerapp:embed:{code}", "title": title, "status": status, "code": code, **extra}
    return JSONResponse(body, status_code=status, media_type="application/problem+json")


def create_app(
    settings: Settings | None = None,
    encoder_factory: Callable[[Settings], Encoder] | None = None,
) -> FastAPI:
    settings = settings or Settings.from_env()

    def default_factory(s: Settings) -> Encoder:
        return Encoder.load(s.model_dir, device=s.device, threads=s.threads)

    factory = encoder_factory or default_factory

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        started = time.perf_counter()
        # Loaded before uvicorn binds the port, so Cloud Run's TCP startup probe passes only when ready.
        app.state.encoder = factory(settings)
        info = app.state.encoder.info
        log.info(
            "model_loaded name=%s version=%s revision=%s device=%s load_ms=%.0f",
            info.name,
            info.version,
            info.revision,
            info.device,
            (time.perf_counter() - started) * 1000,
        )
        yield

    app = FastAPI(title="FarmerApp embed", version="1.0.0", lifespan=lifespan, docs_url=None, redoc_url=None)
    app.state.settings = settings

    @app.exception_handler(Problem)
    async def _problem(_: Request, exc: Problem) -> JSONResponse:
        return problem_response(exc.status, exc.code, exc.title, **exc.extra)

    @app.exception_handler(RequestValidationError)
    async def _invalid(_: Request, exc: RequestValidationError) -> JSONResponse:
        errors = [{"loc": list(e.get("loc", ())), "msg": e.get("msg", "")} for e in exc.errors()]
        return problem_response(422, "validation_error", "Request body is invalid", errors=errors)

    @app.middleware("http")
    async def _limit_body(request: Request, call_next: Any) -> Any:
        length = request.headers.get("content-length")
        if length is not None and length.isdigit() and int(length) > settings.max_request_bytes:
            return problem_response(
                413, "request_too_large", "Request body too large", max_bytes=settings.max_request_bytes
            )
        return await call_next(request)

    @app.get("/healthz")
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/info")
    async def info(request: Request) -> dict[str, Any]:
        i = request.app.state.encoder.info
        return {
            "name": i.name,
            "version": i.version,
            "dim": i.dim,
            "revision": i.revision,
            "weights_sha256": i.weights_sha256,
            "device": i.device,
            "max_batch": settings.max_batch,
            "max_image_bytes": settings.max_image_bytes,
        }

    @app.post("/v1/embed", response_model=EmbedResponse)
    async def embed(body: EmbedRequest, request: Request) -> EmbedResponse:
        encoder: Encoder = request.app.state.encoder
        i = encoder.info
        if body.model != i.name or body.version != i.version:
            raise Problem(
                409,
                "model_mismatch",
                f"This service serves {i.name}@{i.version}, not {body.model}@{body.version}",
                served={"model": i.name, "version": i.version, "dim": i.dim},
            )
        if len(body.images) > settings.max_batch:
            raise Problem(
                422,
                "validation_error",
                f"At most {settings.max_batch} images per request",
                max_batch=settings.max_batch,
            )
        blobs: list[bytes] = []
        for index, item in enumerate(body.images):
            if len(item.b64) > settings.max_image_bytes * 4 // 3 + 4:
                raise Problem(
                    413, "image_too_large", "Image too large", index=index, max_bytes=settings.max_image_bytes
                )
            try:
                data = base64.b64decode(item.b64, validate=True)
            except (binascii.Error, ValueError) as exc:
                raise Problem(422, "invalid_base64", "Image is not valid base64", index=index) from exc
            if len(data) > settings.max_image_bytes:
                raise Problem(
                    413, "image_too_large", "Image too large", index=index, max_bytes=settings.max_image_bytes
                )
            blobs.append(data)

        def run() -> Any:
            images = []
            for index, data in enumerate(blobs):
                try:
                    images.append(decode_rgb(data))
                except UnreadableImageError as exc:
                    raise Problem(422, "unreadable_image", "Image could not be decoded", index=index) from exc
            return encoder.encode_images(images)

        started = time.perf_counter()
        vectors = await run_in_threadpool(run)
        log.info("embedded images=%d ms=%.1f", len(blobs), (time.perf_counter() - started) * 1000)
        return EmbedResponse(model=i.name, version=i.version, dim=i.dim, vectors=vectors.tolist())

    return app


def app_from_env() -> FastAPI:
    """``uvicorn --factory embed.app:app_from_env``."""
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"), format="%(levelname)s %(name)s %(message)s"
    )
    return create_app()


__all__ = ["EmbedRequest", "EmbedResponse", "Settings", "create_app", "app_from_env", "spec"]
