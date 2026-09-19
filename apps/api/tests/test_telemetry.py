"""NF-014: OpenTelemetry traces app -> API -> worker, and the log trace id is the trace id.

Tracing is off in the test suite (``OTEL_EXPORTER=none``); these tests switch it on with an
in-memory exporter and switch it off again."""

from __future__ import annotations

import base64
import json
from collections.abc import Iterator
from typing import Any

import pytest
import structlog
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from sqlalchemy.ext.asyncio import AsyncEngine

from farmerapp import telemetry
from farmerapp.api.app import create_app
from farmerapp.db.session import get_session
from farmerapp.payments.publisher import RecordingPublisher, message_attributes
from farmerapp.settings import get_settings
from farmerapp.worker.app import create_app as create_worker
from farmerapp.worker.topics import Topic
from tests.logcontract import capture, json_events, one_event

TRACE = "0af7651916cd43dd8448eb211c80319c"
PARENT = "b7ad6b7169203331"


@pytest.fixture
def spans() -> Iterator[InMemorySpanExporter]:
    exporter = InMemorySpanExporter()
    telemetry.reset_tracing_for_tests()
    provider = telemetry.configure_tracing(get_settings(), service="api", exporter=exporter)
    assert provider is not None and telemetry.tracing_enabled()
    yield exporter
    SQLAlchemyInstrumentor().uninstrument()
    telemetry.reset_tracing_for_tests()


def test_tracing_is_off_by_default() -> None:
    assert get_settings().otel_exporter == "none"
    assert telemetry.build_exporter(get_settings()) is None
    assert not telemetry.tracing_enabled()


async def test_request_span_sql_spans_and_log_trace_id_agree(
    spans: InMemorySpanExporter,
    db_session: Any,
    app_engine: AsyncEngine,
    caplog: pytest.LogCaptureFixture,
) -> None:
    capture(caplog)
    app = create_app()

    async def _override() -> Any:
        yield db_session

    app.dependency_overrides[get_session] = _override
    SQLAlchemyInstrumentor().uninstrument()  # create_app instrumented the process engine
    telemetry.instrument_engine(app_engine)
    try:
        async with AsyncClient(
            transport=ASGITransport(app=app, raise_app_exceptions=False), base_url="http://t"
        ) as client:
            resp = await client.post(
                "/v1/auth/otp/send",
                json={"phone": "+919999999999"},
                headers={"traceparent": f"00-{TRACE}-{PARENT}-01"},
            )
        assert resp.status_code in (202, 404, 422), resp.text
    finally:
        FastAPIInstrumentor.uninstrument_app(app)
    assert resp.headers["X-Request-Id"] == TRACE  # the incoming W3C trace continues
    finished = spans.get_finished_spans()
    server = [s for s in finished if s.kind == trace.SpanKind.SERVER]
    assert server and all(format(s.context.trace_id, "032x") == TRACE for s in server)
    assert server[0].parent is not None and format(server[0].parent.span_id, "016x") == PARENT
    sql = [s for s in finished if s.attributes and s.attributes.get("db.system")]
    assert sql, "SQLAlchemy spans are recorded"
    assert all(format(s.context.trace_id, "032x") == TRACE for s in sql)
    access = one_event(caplog, "request")
    assert access["trace_id"] == TRACE


def test_publisher_injects_the_active_span_and_the_worker_continues_it(
    spans: InMemorySpanExporter,
) -> None:
    tracer = telemetry.tracer("test")
    with tracer.start_as_current_span("api request") as producer:
        attributes = message_attributes(Topic.PAYMENT_WEBHOOK)
        producer_trace = format(producer.get_span_context().trace_id, "032x")
    assert attributes["topic"] == "payment.webhook"
    assert telemetry.trace_id_from_traceparent(attributes["traceparent"]) == producer_trace
    with telemetry.consumer_span("pubsub.process payment.webhook", attributes) as trace_id:
        assert trace_id == producer_trace
        assert telemetry.current_trace_id() == producer_trace
    consumer = next(s for s in spans.get_finished_spans() if s.kind == trace.SpanKind.CONSUMER)
    assert consumer.parent is not None
    assert consumer.parent.span_id == producer.get_span_context().span_id


def test_without_tracing_the_log_trace_id_still_travels() -> None:
    structlog.contextvars.bind_contextvars(trace_id=TRACE)
    try:
        attributes = message_attributes(Topic.NOTIFY_SEND)
    finally:
        structlog.contextvars.unbind_contextvars("trace_id")
    assert telemetry.trace_id_from_traceparent(attributes["traceparent"]) == TRACE
    with telemetry.consumer_span("x", attributes) as trace_id:
        assert trace_id == TRACE
    with telemetry.consumer_span("x", {"topic": "notify.send"}) as none:
        assert none is None
    # A non-W3C request id (X-Request-Id "abc") is not forged into a traceparent.
    structlog.contextvars.bind_contextvars(trace_id="abc")
    try:
        assert "traceparent" not in message_attributes(Topic.NOTIFY_SEND)
    finally:
        structlog.contextvars.unbind_contextvars("trace_id")


async def test_recording_publisher_keeps_the_attributes() -> None:
    recorder = RecordingPublisher()
    structlog.contextvars.bind_contextvars(trace_id=TRACE)
    try:
        await recorder.publish(Topic.PAYMENT_WEBHOOK, {"event_id": "e"})
    finally:
        structlog.contextvars.unbind_contextvars("trace_id")
    message = recorder.message()
    assert message.attributes["topic"] == "payment.webhook"
    assert TRACE in message.attributes["traceparent"]


async def test_worker_logs_with_the_publishers_trace_id(caplog: pytest.LogCaptureFixture) -> None:
    capture(caplog)
    worker: FastAPI = create_worker()
    envelope = {
        "message": {
            "data": base64.b64encode(json.dumps({}).encode()).decode(),
            # order.created still has the no-op handler (notify.send delivers pushes, FA-007).
            "attributes": {"topic": "order.created", "traceparent": f"00-{TRACE}-{PARENT}-01"},
            "messageId": "m1",
        },
        "subscription": "",
    }
    transport = ASGITransport(app=worker, raise_app_exceptions=False)
    async with AsyncClient(transport=transport, base_url="http://worker") as client:
        resp = await client.post("/push", json=envelope)
    assert resp.status_code == 204
    dispatch = one_event(caplog, "dispatch")
    assert dispatch["trace_id"] == TRACE
    assert json_events(caplog, "handler_noop")[-1]["trace_id"] == TRACE


def test_trace_parsing_edge_cases() -> None:
    assert telemetry.trace_id_from_traceparent(None) is None
    assert telemetry.trace_id_from_traceparent("garbage") is None
    assert telemetry.trace_id_from_traceparent(f"00-{'0' * 32}-{PARENT}-01") is None
    assert telemetry.trace_id_from_traceparent(f"00-{TRACE.upper()}-{PARENT}-01") == TRACE
    console_settings = get_settings().model_copy(update={"otel_exporter": "console"})
    console = telemetry.build_exporter(console_settings)
    assert console is not None
