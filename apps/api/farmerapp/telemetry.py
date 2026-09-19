"""OpenTelemetry tracing (NF-014): app -> API -> workers.

``configure_tracing(settings, service=...)`` installs a ``TracerProvider`` with the exporter
chosen by ``OTEL_EXPORTER``:

* ``gcp`` — Cloud Trace (``opentelemetry-exporter-gcp-trace``; the Cloud Run service
  account needs ``roles/cloudtrace.agent``), batch span processor;
* ``console`` — spans printed as JSON on stdout (local debugging);
* ``none`` (the default, and what tests run with) — no provider, no instrumentation: the
  request trace id still comes from the incoming ``traceparent`` / ``X-Cloud-Trace-Context``
  header and is still propagated to Pub/Sub (``inject_trace_attributes``), so logs of the API
  and the worker correlate even without spans.

``instrument_app`` / ``instrument_engine`` add the FastAPI (ASGI) and SQLAlchemy
instrumentation when tracing is on. W3C ``traceparent`` is the propagation format everywhere
(HTTP in, Pub/Sub message attributes out and back in the worker).

The trace id in every log line (``trace_id``, ``farmerapp.logging``) is the OTel trace id of
the current span whenever one is recording (``current_trace_id``), so Cloud Logging links log
lines to their Cloud Trace span (``logging.googleapis.com/trace``).
"""

from __future__ import annotations

import re
import secrets
from collections.abc import Iterator, Mapping, MutableMapping
from contextlib import contextmanager
from typing import Any

import structlog
from opentelemetry import context as otel_context
from opentelemetry import propagate, trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import (
    BatchSpanProcessor,
    ConsoleSpanExporter,
    SimpleSpanProcessor,
    SpanExporter,
)
from opentelemetry.sdk.trace.sampling import ParentBased, TraceIdRatioBased

from farmerapp.settings import Settings

TRACEPARENT = "traceparent"
_TRACEPARENT_RE = re.compile(r"^[0-9a-f]{2}-([0-9a-f]{32})-([0-9a-f]{16})-[0-9a-f]{2}$")
_HEX32 = re.compile(r"^[0-9a-f]{32}$")

_provider: TracerProvider | None = None


def tracing_enabled() -> bool:
    return _provider is not None


def build_exporter(settings: Settings) -> SpanExporter | None:
    if settings.otel_exporter == "console":
        return ConsoleSpanExporter()
    if settings.otel_exporter == "gcp":  # pragma: no cover - needs Google credentials
        from opentelemetry.exporter import cloud_trace

        exporter_cls: Any = cloud_trace.CloudTraceSpanExporter  # untyped library
        exporter: SpanExporter = exporter_cls(project_id=settings.gcp_project)
        return exporter
    return None


def configure_tracing(
    settings: Settings, *, service: str, exporter: SpanExporter | None = None
) -> TracerProvider | None:
    """Install the global tracer provider once per process; ``None`` when tracing is off.

    ``exporter`` overrides the configured one (tests pass an in-memory exporter)."""
    global _provider
    if _provider is not None:
        return _provider
    chosen = exporter if exporter is not None else build_exporter(settings)
    if chosen is None:
        return None
    provider = TracerProvider(
        resource=Resource.create(
            {
                "service.name": f"farmerapp-{service}",
                "service.namespace": "farmerapp",
                "deployment.environment": settings.app_env,
            }
        ),
        sampler=ParentBased(TraceIdRatioBased(settings.otel_sample_ratio)),
    )
    processor = (
        SimpleSpanProcessor(chosen)
        if exporter is not None or settings.otel_exporter == "console"
        else BatchSpanProcessor(chosen)
    )
    provider.add_span_processor(processor)
    trace.set_tracer_provider(provider)
    _provider = provider
    return provider


def reset_tracing_for_tests() -> None:
    """Forget the provider (tests that enable tracing call this in teardown)."""
    global _provider
    if _provider is not None:
        _provider.shutdown()
    _provider = None


def instrument_app(app: Any) -> None:
    if _provider is None:
        return
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

    FastAPIInstrumentor.instrument_app(app, tracer_provider=_provider, excluded_urls="/v1/health")


def instrument_engine(engine: Any) -> None:
    """SQLAlchemy spans for an ``AsyncEngine`` (its sync engine is what emits events)."""
    if _provider is None:
        return
    from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor

    SQLAlchemyInstrumentor().instrument(
        engine=getattr(engine, "sync_engine", engine), tracer_provider=_provider
    )


def tracer(name: str = "farmerapp") -> trace.Tracer:
    return trace.get_tracer(name, tracer_provider=_provider)


# --------------------------------------------------------------------------- trace ids
def current_trace_id() -> str | None:
    """Hex trace id of the active, valid span (OTel), else ``None``."""
    ctx = trace.get_current_span().get_span_context()
    if ctx.is_valid:
        return format(ctx.trace_id, "032x")
    return None


def trace_id_from_traceparent(value: str | None) -> str | None:
    if not value:
        return None
    match = _TRACEPARENT_RE.match(value.strip().lower())
    if match is None or match.group(1) == "0" * 32:
        return None
    return match.group(1)


def _log_trace_id() -> str | None:
    bound = structlog.contextvars.get_contextvars().get("trace_id")
    return bound if isinstance(bound, str) and _HEX32.match(bound) else None


def inject_trace_attributes(carrier: MutableMapping[str, str]) -> MutableMapping[str, str]:
    """Add the W3C ``traceparent`` of the current trace to ``carrier`` (Pub/Sub attributes).

    With tracing on, the OTel propagator writes the active span context. Without it, the
    request's log trace id (when it is a 32-hex W3C id) travels with a fresh parent id, so
    the worker's log lines carry the same ``trace_id`` as the API request that published."""
    if current_trace_id() is not None:
        propagate.inject(carrier)
        return carrier
    trace_id = _log_trace_id()
    if trace_id is not None:
        carrier[TRACEPARENT] = f"00-{trace_id}-{secrets.token_hex(8)}-01"
    return carrier


@contextmanager
def consumer_span(name: str, attributes: Mapping[str, str]) -> Iterator[str | None]:
    """Continue the trace carried by Pub/Sub ``attributes`` (worker side).

    Yields the trace id to log with: the consumer span's when tracing is on, else the one in
    the ``traceparent`` attribute (``None`` when the message carries none)."""
    carried = trace_id_from_traceparent(attributes.get(TRACEPARENT))
    if _provider is None:
        yield carried
        return
    parent = propagate.extract(dict(attributes))
    token = otel_context.attach(parent)
    try:
        with tracer("farmerapp.worker").start_as_current_span(
            name, kind=trace.SpanKind.CONSUMER, attributes={"messaging.system": "gcp_pubsub"}
        ):
            yield current_trace_id() or carried
    finally:
        otel_context.detach(token)


__all__ = [
    "TRACEPARENT",
    "build_exporter",
    "configure_tracing",
    "consumer_span",
    "current_trace_id",
    "inject_trace_attributes",
    "instrument_app",
    "instrument_engine",
    "reset_tracing_for_tests",
    "trace_id_from_traceparent",
    "tracer",
    "tracing_enabled",
]
