"""FastAPI app that receives Pub/Sub push deliveries.

Run with ``uvicorn farmerapp.worker.app:app``. Cloud Run authenticates pushes via the
subscription's OIDC token (verified by the platform when the service requires auth), so
the handler itself only validates the envelope and dispatches by topic.

Response semantics: 2xx acks; 4xx/5xx nacks and Pub/Sub retries, then dead-letters.
"""

from __future__ import annotations

from fastapi import APIRouter, FastAPI, Response, status

from farmerapp import __version__
from farmerapp.api.errors import AppError, install_error_handlers
from farmerapp.api.middleware import TraceMiddleware
from farmerapp.api.routes import health
from farmerapp.logging import configure_logging
from farmerapp.settings import Settings, get_settings
from farmerapp.worker.dispatch import dispatch
from farmerapp.worker.messages import PushEnvelope


class UnknownTopicError(AppError):
    status = 400
    code = "unknown_topic"


router = APIRouter(tags=["pubsub"])


@router.post("/push", operation_id="receivePush", status_code=status.HTTP_204_NO_CONTENT)
async def receive_push(envelope: PushEnvelope) -> Response:
    topic = envelope.topic()
    if topic is None:
        raise UnknownTopicError(
            f"Cannot resolve topic from subscription {envelope.subscription!r} "
            "or attributes; set the 'topic' attribute."
        )
    await dispatch(topic, envelope.message)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(level=settings.log_level, json_logs=settings.log_json, service="worker")
    app = FastAPI(title="FarmerApp worker", version=__version__, docs_url=None, redoc_url=None)
    app.add_middleware(TraceMiddleware)
    install_error_handlers(app)
    v1 = APIRouter(prefix="/v1")
    v1.include_router(health.router)
    app.include_router(v1)
    app.include_router(router)
    return app


app = create_app()
