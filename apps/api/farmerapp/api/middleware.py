"""Per-request trace id + structured access log.

Trace id resolution order: ``X-Cloud-Trace-Context`` (Cloud Run / load balancer),
``X-Request-Id`` (clients, tests), else a fresh UUID. The id is bound to structlog
contextvars for the whole request and echoed back as ``X-Request-Id``.
"""

from __future__ import annotations

import time
import uuid

import structlog
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

from farmerapp.db import audit
from farmerapp.logging import get_logger

TRACE_HEADER = "X-Request-Id"
CLOUD_TRACE_HEADER = "X-Cloud-Trace-Context"


def resolve_trace_id(request: Request) -> str:
    cloud = request.headers.get(CLOUD_TRACE_HEADER)
    if cloud:
        return cloud.split("/", 1)[0]
    return request.headers.get(TRACE_HEADER) or uuid.uuid4().hex


class TraceMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        trace_id = resolve_trace_id(request)
        structlog.contextvars.clear_contextvars()
        audit.clear_actor()  # FA-006: no actor until the auth dependency binds one
        structlog.contextvars.bind_contextvars(
            trace_id=trace_id, method=request.method, path=request.url.path
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
