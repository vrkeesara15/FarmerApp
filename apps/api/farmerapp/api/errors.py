"""RFC 9457 ``application/problem+json`` errors with a stable ``code`` (SPEC 8.3).

Shape::

    {
      "type": "https://farmerapp.dev/problems/not_found",
      "title": "Not Found",
      "status": 404,
      "detail": "...",
      "instance": "/v1/farmers/123",
      "code": "not_found",
      "trace_id": "..."
    }

``code`` is the machine-readable contract that clients switch on; ``title``/``detail`` are
human text and may change. Validation errors add ``errors`` (list of field problems).
"""

from __future__ import annotations

from http import HTTPStatus
from typing import Any

import structlog
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from farmerapp.logging import get_logger

PROBLEM_TYPE_BASE = "https://farmerapp.dev/problems/"
PROBLEM_MEDIA_TYPE = "application/problem+json"

_STATUS_CODES: dict[int, str] = {
    400: "bad_request",
    401: "unauthenticated",
    403: "forbidden",
    404: "not_found",
    405: "method_not_allowed",
    409: "conflict",
    412: "precondition_failed",
    413: "payload_too_large",
    415: "unsupported_media_type",
    422: "validation_error",
    429: "rate_limited",
    500: "internal_error",
    503: "unavailable",
}


class AppError(Exception):
    """Base for domain errors. Subclass with a fixed ``status`` and ``code``."""

    status: int = 400
    code: str = "bad_request"
    title: str | None = None

    def __init__(
        self,
        detail: str | None = None,
        *,
        code: str | None = None,
        status: int | None = None,
        extra: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(detail)
        self.detail = detail
        if code is not None:
            self.code = code
        if status is not None:
            self.status = status
        self.extra = extra or {}


class NotFoundError(AppError):
    status = 404
    code = "not_found"


class ConflictError(AppError):
    status = 409
    code = "conflict"


class ForbiddenError(AppError):
    status = 403
    code = "forbidden"


class UnauthenticatedError(AppError):
    status = 401
    code = "unauthenticated"


def code_for_status(status: int) -> str:
    return _STATUS_CODES.get(status, "error")


def problem_response(
    request: Request,
    *,
    status: int,
    code: str,
    detail: str | None = None,
    title: str | None = None,
    extra: dict[str, Any] | None = None,
) -> JSONResponse:
    try:
        phrase = HTTPStatus(status).phrase
    except ValueError:
        phrase = "Error"
    body: dict[str, Any] = {
        "type": PROBLEM_TYPE_BASE + code,
        "title": title or phrase,
        "status": status,
        "instance": request.url.path,
        "code": code,
    }
    if detail:
        body["detail"] = detail
    trace_id = structlog.contextvars.get_contextvars().get("trace_id")
    if trace_id:
        body["trace_id"] = trace_id
    if extra:
        body.update(extra)
    return JSONResponse(body, status_code=status, media_type=PROBLEM_MEDIA_TYPE)


def install_error_handlers(app: FastAPI) -> None:
    log = get_logger("farmerapp.api.errors")

    @app.exception_handler(AppError)
    async def _app_error(request: Request, exc: AppError) -> JSONResponse:
        return problem_response(
            request,
            status=exc.status,
            code=exc.code,
            detail=exc.detail,
            title=exc.title,
            extra=exc.extra,
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        detail = exc.detail if isinstance(exc.detail, str) else None
        resp = problem_response(
            request, status=exc.status_code, code=code_for_status(exc.status_code), detail=detail
        )
        if exc.headers:
            resp.headers.update(exc.headers)
        return resp

    @app.exception_handler(RequestValidationError)
    async def _validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
        errors = [
            {
                "loc": [str(p) for p in e.get("loc", ())],
                "msg": e.get("msg"),
                "type": e.get("type"),
            }
            for e in exc.errors()
        ]
        return problem_response(
            request,
            status=422,
            code="validation_error",
            detail="Request validation failed.",
            extra={"errors": errors},
        )

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
        log.exception("unhandled_error", path=request.url.path)
        return problem_response(
            request, status=500, code="internal_error", detail="Internal server error."
        )
