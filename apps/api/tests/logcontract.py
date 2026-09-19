"""Helpers for the structured-log contract tests (docs/runbooks/observability.md).

The log-based metrics in ``infra/modules/monitoring/log_metrics.tf`` read fields of the JSON
line (``jsonPayload.<field>``). These helpers capture the structlog event dicts that reach the
stdlib handlers (what ``farmerapp.logging`` renders as one JSON object per line), render them
with the production JSON renderer and hand back the parsed JSON, so a test asserts exactly
what Cloud Logging will store.
"""

from __future__ import annotations

import json
import logging
from typing import Any

import pytest
import structlog

from farmerapp.logging import configure_logging

_RENDER = structlog.processors.JSONRenderer()


def capture(caplog: pytest.LogCaptureFixture) -> None:
    """Route INFO+ of every logger into ``caplog`` (structlog configured as in production)."""
    configure_logging(json_logs=False)
    caplog.set_level(logging.INFO)


def json_events(caplog: pytest.LogCaptureFixture, event: str) -> list[dict[str, Any]]:
    """Every captured ``event`` as the JSON object Cloud Logging stores."""
    out: list[dict[str, Any]] = []
    for record in caplog.records:
        msg = record.msg
        if isinstance(msg, dict) and msg.get("event") == event:
            rendered = _RENDER(None, "info", dict(msg))
            out.append(json.loads(str(rendered)))
    return out


def one_event(caplog: pytest.LogCaptureFixture, event: str) -> dict[str, Any]:
    found = json_events(caplog, event)
    assert found, f"no {event!r} log line"
    return found[-1]


def assert_fields(line: dict[str, Any], **types: type | tuple[type, ...]) -> None:
    """Every field is present with its JSON type (``int`` is never a bool here)."""
    for name, kind in types.items():
        assert name in line, f"{line.get('event')}: missing {name!r} in {sorted(line)}"
        value = line[name]
        assert (isinstance(value, kind) and not isinstance(value, bool)) or kind is bool, (
            f"{line.get('event')}.{name} = {value!r} is not {kind}"
        )
    for always in ("event", "level", "severity", "timestamp", "service", "logger"):
        assert always in line, f"{line.get('event')}: missing {always!r}"
    assert line["severity"] == str(line["level"]).upper()


__all__ = ["assert_fields", "capture", "json_events", "one_event"]
