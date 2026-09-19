"""Structured JSON logging with a per-request trace id.

Every log line carries ``service``, ``severity`` (Cloud Logging) and, inside a request,
``trace_id`` bound via structlog contextvars (the OpenTelemetry trace id when tracing is on;
jobs and worker spans get it from the active span). The events and fields the log-based
metrics read are listed in ``docs/runbooks/observability.md``. Stdlib loggers (uvicorn,
sqlalchemy, alembic) are routed through the same renderer so container output is uniformly
JSON.
"""

from __future__ import annotations

import logging
import sys
from typing import Any

import structlog

_CONFIGURED = False


def configure_logging(*, level: str = "INFO", json_logs: bool = True, service: str = "api") -> None:
    """Idempotent: configure structlog + stdlib logging once per process."""
    global _CONFIGURED
    if _CONFIGURED:
        return

    shared_processors: list[Any] = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        _add_service(service),
        _add_severity,
        _add_otel_trace_id,
    ]
    renderer: Any = (
        structlog.processors.JSONRenderer() if json_logs else structlog.dev.ConsoleRenderer()
    )

    structlog.configure(
        processors=[
            *shared_processors,
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    formatter = structlog.stdlib.ProcessorFormatter(
        foreign_pre_chain=shared_processors,
        processors=[structlog.stdlib.ProcessorFormatter.remove_processors_meta, renderer],
    )
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level.upper())
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logging.getLogger(name).handlers[:] = []
        logging.getLogger(name).propagate = True

    _CONFIGURED = True


def _add_service(service: str) -> Any:
    def processor(_logger: Any, _method: str, event_dict: dict[str, Any]) -> dict[str, Any]:
        event_dict.setdefault("service", service)
        return event_dict

    return processor


def _add_severity(_logger: Any, method: str, event_dict: dict[str, Any]) -> dict[str, Any]:
    """Cloud Logging severity (``INFO`` / ``WARNING`` / ``ERROR``...) mirroring ``level``, so
    severity filters and Error Reporting pick errors up natively."""
    level = event_dict.get("level") or method
    event_dict.setdefault("severity", str(level).upper())
    return event_dict


def _add_otel_trace_id(_logger: Any, _method: str, event_dict: dict[str, Any]) -> dict[str, Any]:
    """Outside a request (jobs, worker spans) the active OTel span supplies ``trace_id``."""
    if "trace_id" not in event_dict:
        from farmerapp.telemetry import current_trace_id

        trace_id = current_trace_id()
        if trace_id is not None:
            event_dict["trace_id"] = trace_id
    return event_dict


def get_logger(name: str | None = None) -> structlog.stdlib.BoundLogger:
    logger: structlog.stdlib.BoundLogger = structlog.get_logger(name)
    return logger
