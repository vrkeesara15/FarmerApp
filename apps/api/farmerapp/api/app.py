"""FastAPI application factory for the ``api`` deployable.

Run locally with ``uvicorn farmerapp.api.app:app --reload``.
"""

from __future__ import annotations

from fastapi import APIRouter, FastAPI

from farmerapp import __version__
from farmerapp.api.errors import PROBLEM_MEDIA_TYPE, install_error_handlers
from farmerapp.api.middleware import TraceMiddleware
from farmerapp.api.routes import health
from farmerapp.logging import configure_logging
from farmerapp.settings import Settings, get_settings

API_PREFIX = "/v1"

_PROBLEM_SCHEMA = {
    "type": "object",
    "required": ["type", "title", "status", "code"],
    "properties": {
        "type": {"type": "string", "format": "uri"},
        "title": {"type": "string"},
        "status": {"type": "integer"},
        "detail": {"type": "string"},
        "instance": {"type": "string"},
        "code": {"type": "string", "description": "Stable machine-readable error code."},
        "trace_id": {"type": "string"},
        "errors": {"type": "array", "items": {"type": "object"}},
    },
}


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(level=settings.log_level, json_logs=settings.log_json, service="api")

    app = FastAPI(
        title="FarmerApp API",
        version=__version__,
        openapi_version="3.1.0",
        description="FarmerApp REST API. Errors are RFC 9457 problem+json with a stable `code`.",
        docs_url="/docs" if settings.is_local else None,
        redoc_url=None,
        responses={
            "default": {
                "description": "Error (RFC 9457 problem+json)",
                "content": {
                    PROBLEM_MEDIA_TYPE: {"schema": {"$ref": "#/components/schemas/Problem"}}
                },
            }
        },
    )
    app.add_middleware(TraceMiddleware)
    install_error_handlers(app)

    v1 = APIRouter(prefix=API_PREFIX)
    v1.include_router(health.router)
    app.include_router(v1)

    _register_problem_schema(app)
    return app


def _register_problem_schema(app: FastAPI) -> None:
    """Add the Problem schema to components so the default error response resolves."""
    original = app.openapi

    def custom_openapi() -> dict[str, object]:
        if app.openapi_schema:
            return app.openapi_schema
        schema = original()
        components = schema.setdefault("components", {})
        if not isinstance(components, dict):
            raise TypeError("openapi components must be a mapping")
        components.setdefault("schemas", {})["Problem"] = _PROBLEM_SCHEMA
        app.openapi_schema = schema
        return schema

    app.openapi = custom_openapi  # type: ignore[method-assign]


app = create_app()
