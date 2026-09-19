"""FastAPI application factory for the ``api`` deployable.

Run locally with ``uvicorn farmerapp.api.app:app --reload``.
"""

from __future__ import annotations

import asyncio
import contextlib
from collections.abc import AsyncIterator

from fastapi import APIRouter, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from farmerapp import __version__
from farmerapp.analytics import router as analytics_routes
from farmerapp.api.errors import PROBLEM_MEDIA_TYPE, install_error_handlers
from farmerapp.api.middleware import TraceMiddleware
from farmerapp.api.routes import health
from farmerapp.audit import router as audit_routes
from farmerapp.auth import router as auth_routes
from farmerapp.auth.deps import AuthServices, build_auth_services, tick
from farmerapp.auth.policy import install_policies
from farmerapp.auth.scheduler import InProcessScheduler
from farmerapp.catalog import router as catalog_routes
from farmerapp.db import models as _models  # noqa: F401  (registers models + audit listener)
from farmerapp.duty import router as duty_routes
from farmerapp.farmers import router as farmer_routes
from farmerapp.invoices import router as invoice_routes
from farmerapp.khata import router as khata_routes
from farmerapp.location import batch_router as location_batch_routes
from farmerapp.location import router as location_routes
from farmerapp.logging import configure_logging, get_logger
from farmerapp.orders import payment_events as order_payment_events
from farmerapp.orders import router as order_routes
from farmerapp.payments import day_close as day_close_routes
from farmerapp.payments import router as payment_routes
from farmerapp.payments import webhooks as webhook_routes
from farmerapp.payments.service import PaymentServices, build_payment_services
from farmerapp.policies import router as policy_routes
from farmerapp.settings import Settings, get_settings
from farmerapp.stock import router as stock_routes
from farmerapp.sync import router as sync_routes
from farmerapp.uploads import router as upload_routes
from farmerapp.uploads.blobstore import BlobStore, build_blob_store
from farmerapp.users import router as user_routes
from farmerapp.visits import router as visit_routes

API_PREFIX = "/v1"
SCHEDULER_INTERVAL_S = 1.0

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


async def _scheduler_loop(scheduler: InProcessScheduler) -> None:
    """Local/dev only: run delayed auth tasks (OTP delivery checks) in-process every second."""
    log = get_logger("farmerapp.api.scheduler")
    while True:
        await asyncio.sleep(SCHEDULER_INTERVAL_S)
        try:
            await tick(scheduler)
        except Exception:
            log.exception("scheduler_tick_failed")


@contextlib.asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncIterator[None]:
    services: AuthServices = app.state.auth
    task: asyncio.Task[None] | None = None
    if isinstance(services.scheduler, InProcessScheduler):
        task = asyncio.create_task(_scheduler_loop(services.scheduler))
    try:
        yield
    finally:
        if task is not None:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task


def create_app(
    settings: Settings | None = None,
    *,
    auth_services: AuthServices | None = None,
    blob_store: BlobStore | None = None,
    payment_services: PaymentServices | None = None,
) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(level=settings.log_level, json_logs=settings.log_json, service="api")

    app = FastAPI(
        lifespan=_lifespan,
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
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=[
            "Authorization",
            "Content-Type",
            "Idempotency-Key",
            "X-Request-Id",
            "X-Device-Id",
            "X-Chunk-Sha256",
        ],
        expose_headers=["X-Request-Id"],
    )
    install_error_handlers(app)
    app.state.auth = auth_services or build_auth_services(settings)
    app.state.blobs = blob_store or build_blob_store(settings)  # NF-003 / SEC-016
    app.state.payments = payment_services or build_payment_services(settings)  # FA-021
    order_payment_events.register()  # FA-020 x FA-021: a captured payment advances its order

    v1 = APIRouter(prefix=API_PREFIX)
    v1.include_router(health.router)
    v1.include_router(auth_routes.router)
    v1.include_router(auth_routes.me_router)
    v1.include_router(user_routes.router)
    v1.include_router(farmer_routes.router)
    v1.include_router(farmer_routes.farm_router)
    v1.include_router(farmer_routes.plot_router)
    v1.include_router(visit_routes.router)
    v1.include_router(location_routes.duty_router)
    v1.include_router(location_routes.officer_router)
    v1.include_router(duty_routes.router)
    v1.include_router(location_batch_routes.batch_router)
    v1.include_router(policy_routes.router)
    v1.include_router(sync_routes.router)
    v1.include_router(upload_routes.router)
    v1.include_router(upload_routes.blob_router)
    v1.include_router(audit_routes.router)
    # M3: catalogue, stock, orders, payments, khata (read endpoints; writes are the loop's).
    v1.include_router(catalog_routes.router)
    v1.include_router(stock_routes.router)
    v1.include_router(order_routes.router)
    v1.include_router(payment_routes.router)
    v1.include_router(khata_routes.router)
    # FA-021 / SEC-023 / ST-001 / ST-002 / ST-006: collection, webhooks, POS + GST invoices,
    # day summary and day close.
    v1.include_router(webhook_routes.router)
    v1.include_router(invoice_routes.pos_router)
    v1.include_router(invoice_routes.router)
    v1.include_router(day_close_routes.router)
    # M4: analytics read API (AN-001 .. AN-003, AN-011, WC-001 .. WC-004).
    v1.include_router(analytics_routes.router)
    app.include_router(v1)

    # FA-002: refuse to start unless every route declares a role policy (or is public), and
    # write the policies into the OpenAPI contract (x-roles / x-public / x-self).
    install_policies(app)
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
