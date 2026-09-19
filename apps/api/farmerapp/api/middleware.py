"""Per-request trace id + structured access log (NF-014).

Trace id resolution order: the active OpenTelemetry span (``farmerapp.telemetry``; when
tracing is on the FastAPI instrumentation opens it from the incoming ``traceparent``), the
W3C ``traceparent`` header, ``X-Cloud-Trace-Context`` (Cloud Run / load balancer),
``X-Request-Id`` (clients, tests), else a fresh 32-hex id. The id is bound to structlog
contextvars for the whole request (every log line carries ``trace_id``), echoed back as
``X-Request-Id`` and, in GCP, bound as ``logging.googleapis.com/trace`` so Cloud Logging
links the lines to the Cloud Trace span.
"""

from __future__ import annotations

import time
import uuid

import structlog
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

from farmerapp import telemetry
from farmerapp.db import audit
from farmerapp.logging import get_logger
from farmerapp.settings import get_settings

TRACE_HEADER = "X-Request-Id"
CLOUD_TRACE_HEADER = "X-Cloud-Trace-Context"
CLOUD_LOGGING_TRACE_KEY = "logging.googleapis.com/trace"


def resolve_trace_id(request: Request) -> str:
    otel = telemetry.current_trace_id()
    if otel is not None:
        return otel
    carried = telemetry.trace_id_from_traceparent(request.headers.get(telemetry.TRACEPARENT))
    if carried is not None:
        return carried
    cloud = request.headers.get(CLOUD_TRACE_HEADER)
    if cloud:
        return cloud.split("/", 1)[0]
    return request.headers.get(TRACE_HEADER) or uuid.uuid4().hex


def trace_log_fields(trace_id: str) -> dict[str, str]:
    """``trace_id`` plus the Cloud Logging trace link when traces go to Cloud Trace."""
    fields = {"trace_id": trace_id}
    settings = get_settings()
    if settings.otel_exporter == "gcp":
        fields[CLOUD_LOGGING_TRACE_KEY] = f"projects/{settings.gcp_project}/traces/{trace_id}"
    return fields


class TraceMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        trace_id = resolve_trace_id(request)
        structlog.contextvars.clear_contextvars()
        audit.clear_actor()  # FA-006: no actor until the auth dependency binds one
        structlog.contextvars.bind_contextvars(
            **trace_log_fields(trace_id), method=request.method, path=request.url.path
        )
        log = get_logger("farmerapp.api.access")
        start = time.perf_counter()
        try:
            response = await call_next(request)
        finally:
            elapsed_ms = round((time.perf_counter() - start) * 1000, 2)
            structlog.contextvars.bind_contextvars(duration_ms=elapsed_ms)
        response.headers[TRACE_HEADER] = trace_id
        log.info("request", status=response.status_code)
        structlog.contextvars.clear_contextvars()
        return response
