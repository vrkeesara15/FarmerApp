"""OPS-011: run dbt and turn its result into the one signal Cloud Monitoring can alert on.

SPEC 12.2 OPS-011 is "Datastream lag > 30 min; dbt run or test failure -> ticket to the data
owner". Datastream publishes its own metric, so the freshness half is a Cloud Monitoring alert
(infra/modules/monitoring/data.tf). dbt publishes nothing: it writes ``target/run_results.json``
and exits. This wrapper is the mechanism that closes the gap.

It runs the dbt command you give it, reads the artefact dbt leaves behind, and emits one
structured JSON line per invocation in exactly the shape the API's structlog lines use
(``event``, ``level``, ``severity``, ``timestamp``, ``service``), so the log-based metrics in
``infra/modules/monitoring/data.tf`` read it with no special cases:

===========================  =======  ==================================================
event                        level    carries
===========================  =======  ==================================================
``dbt_run_result``           info     command, target, status, models, errors, warnings,
                                      elapsed_s, invocation_id
``dbt_run_failed``           error    + failures[] (node, status, message), first_failure
``dbt_source_freshness``     info     source, max_loaded_at, staleness_s, state (per source)
``dbt_source_stale``         error    + warn_after_s / error_after_s (AN-010 thresholds)
===========================  =======  ==================================================

Where the line goes:

* **stdout**, always. That is what CI shows and what a Cloud Run job's stdout becomes.
* **Cloud Logging**, when ``DBT_CLOUD_LOG_PROJECT`` is set: the line is also written to
  ``projects/<project>/logs/dbt`` with the run's own credentials (Application Default
  Credentials -- in CI, the Workload Identity Federation token ci-dbt.yml already has). This
  is what makes a CI dbt failure reach the OPS-011 alert without a Cloud Run job existing
  yet. A failure to write is reported on stderr and never changes the exit code: an alerting
  side-channel must not break the build it is watching.

The exit code is always dbt's own, so this is a drop-in prefix:

    uv run python scripts/dbt_run.py build --target ci --fail-fast
    uv run python scripts/dbt_run.py source freshness --target dev

``--self-test`` runs the parser over synthetic artefacts and asserts the emitted lines; it
needs no dbt, no cloud and no credentials, and runs in ``make check-dbt`` and ci-dbt.yml.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

DBT_DIR = Path(__file__).resolve().parents[1]
SERVICE = "dbt"

#: dbt node statuses that mean "this did not work". ``warn`` is a test at warn severity: it
#: is a data-quality signal (AN-012), not a broken pipeline, so it is counted and reported
#: but does not raise the OPS-011 ticket.
FAILED_STATUSES = frozenset({"error", "fail", "runtime error"})
WARN_STATUSES = frozenset({"warn"})


# --------------------------------------------------------------------------- emitting


def _line(event: str, level: str, **fields: Any) -> dict[str, Any]:
    """One structured log line, shaped like the API's structlog output."""
    return {
        "event": event,
        "level": level,
        # Cloud Logging reads `severity` natively (so does Error Reporting); the API's
        # logging.py does the same, and the log-based metric filters rely on it.
        "severity": level.upper(),
        "timestamp": datetime.now(UTC).isoformat(),
        "service": SERVICE,
        **fields,
    }


class Emitter:
    """Writes lines to stdout and, when configured, to Cloud Logging."""

    def __init__(self, project: str | None = None) -> None:
        self.project = project or os.environ.get("DBT_CLOUD_LOG_PROJECT") or ""
        self.lines: list[dict[str, Any]] = []

    def __call__(self, line: dict[str, Any]) -> None:
        self.lines.append(line)
        print(json.dumps(line, default=str), flush=True)

    def flush_to_cloud(self) -> None:
        """Best effort: never raises, never changes the exit code."""
        if not self.project or not self.lines:
            return
        try:
            import google.auth  # noqa: PLC0415 - optional, only on the cloud path
            from google.auth.transport.requests import (  # noqa: PLC0415
                AuthorizedSession,
            )

            credentials, _ = google.auth.default(
                scopes=["https://www.googleapis.com/auth/logging.write"]
            )
            session = AuthorizedSession(credentials)
            response = session.post(
                "https://logging.googleapis.com/v2/entries:write",
                json={
                    "logName": f"projects/{self.project}/logs/{SERVICE}",
                    "resource": {"type": "global", "labels": {"project_id": self.project}},
                    "entries": [
                        {
                            "severity": line["severity"],
                            "timestamp": line["timestamp"],
                            "jsonPayload": line,
                        }
                        for line in self.lines
                    ],
                },
                timeout=30,
            )
            response.raise_for_status()
        except Exception as exc:  # noqa: BLE001 - the build must not fail over telemetry
            print(
                f"dbt_run: could not write to Cloud Logging ({exc}); "
                "the lines are on stdout above",
                file=sys.stderr,
            )


# --------------------------------------------------------------------------- parsing


def _artifact(path: Path) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def _message(result: dict[str, Any]) -> str:
    """The failure message, trimmed: a full SQL error is pages long."""
    message = (result.get("message") or "").strip().replace("\n", " ")
    return message[:500]


def run_results_lines(
    artifact: dict[str, Any] | None,
    *,
    command: str,
    target: str,
    elapsed_s: float,
    exit_code: int,
) -> list[dict[str, Any]]:
    """`dbt_run_result`, plus `dbt_run_failed` when anything errored."""
    results = list((artifact or {}).get("results", []))
    failures = [
        {
            "node": r.get("unique_id", "?"),
            "status": r.get("status", "?"),
            "message": _message(r),
        }
        for r in results
        if str(r.get("status", "")).lower() in FAILED_STATUSES
    ]
    warnings = [r for r in results if str(r.get("status", "")).lower() in WARN_STATUSES]
    invocation_id = (artifact or {}).get("metadata", {}).get("invocation_id", "")

    # dbt can fail before it writes an artefact at all (a parse error, a bad profile). The
    # exit code is then the only evidence, and it is still an OPS-011 failure.
    failed = bool(failures) or exit_code != 0

    common = {
        "command": command,
        "target": target,
        "invocation_id": invocation_id,
        "elapsed_s": round(elapsed_s, 3),
        "exit_code": exit_code,
        "nodes": len(results),
        "errors": len(failures),
        "warnings": len(warnings),
    }
    lines = [
        _line(
            "dbt_run_result",
            "error" if failed else "info",
            status="error" if failed else "ok",
            **common,
        )
    ]
    if failed:
        lines.append(
            _line(
                "dbt_run_failed",
                "error",
                # A label on the metric, so the alert can group by what broke first.
                first_failure=failures[0]["node"] if failures else "no-artifact",
                failures=failures,
                **common,
            )
        )
    return lines


def _seconds(threshold: dict[str, Any] | None) -> int | None:
    """An AN-010 freshness threshold ({count, period}) in seconds."""
    if not threshold:
        return None
    per = {"minute": 60, "hour": 3600, "day": 86400}.get(threshold.get("period", ""), 0)
    count = threshold.get("count")
    return int(count) * per if count and per else None


def sources_lines(
    artifact: dict[str, Any] | None, *, command: str, target: str
) -> list[dict[str, Any]]:
    """One `dbt_source_freshness` per source, plus `dbt_source_stale` for each error.

    AN-010 sets warn at 15 min and error at 30 min behind Postgres, which is the same 30 min
    SPEC 12.2 names for OPS-011 -- so a source in `error` here and a Datastream freshness
    alert are two views of the same outage, and the runbook says to check the stream first.
    """
    lines: list[dict[str, Any]] = []
    for result in (artifact or {}).get("results", []):
        name = ".".join(result.get("unique_id", "?").split(".")[-2:])
        criteria = result.get("criteria") or {}
        staleness = result.get("max_loaded_at_time_ago_in_s")
        state = str(result.get("status", "?")).lower()
        fields = {
            "command": command,
            "target": target,
            "source": name,
            "state": state,
            "max_loaded_at": result.get("max_loaded_at"),
            "warn_after_s": _seconds(criteria.get("warn_after")),
            "error_after_s": _seconds(criteria.get("error_after")),
        }
        if staleness is not None:
            fields["staleness_s"] = round(float(staleness))
        lines.append(_line("dbt_source_freshness", "info", **fields))
        if state in FAILED_STATUSES:
            lines.append(_line("dbt_source_stale", "error", **fields))
    return lines


# --------------------------------------------------------------------------- driving dbt


def _target_of(args: list[str]) -> str:
    if "--target" in args:
        index = args.index("--target")
        if index + 1 < len(args):
            return args[index + 1]
    return os.environ.get("DBT_TARGET", "default")


def _is_freshness(args: list[str]) -> bool:
    return "source" in args and "freshness" in args


def main(argv: list[str]) -> int:
    if argv[:1] == ["--self-test"]:
        return self_test()
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2

    target = _target_of(argv)
    command = " ".join(a for a in argv if not a.startswith("-"))
    emitter = Emitter()

    started = time.monotonic()
    completed = subprocess.run(["dbt", *argv], cwd=DBT_DIR, check=False)  # noqa: S603, S607
    elapsed = time.monotonic() - started

    artifact_dir = Path(os.environ.get("DBT_TARGET_PATH", DBT_DIR / "target"))
    if _is_freshness(argv):
        for line in sources_lines(
            _artifact(artifact_dir / "sources.json"), command=command, target=target
        ):
            emitter(line)
    for line in run_results_lines(
        _artifact(artifact_dir / "run_results.json"),
        command=command,
        target=target,
        elapsed_s=elapsed,
        exit_code=completed.returncode,
    ):
        emitter(line)

    emitter.flush_to_cloud()
    return completed.returncode


# --------------------------------------------------------------------------- self-test


def self_test() -> int:
    """Assert the parser over synthetic artefacts. No dbt, no cloud, no credentials."""
    ok = run_results_lines(
        {
            "metadata": {"invocation_id": "abc"},
            "results": [
                {"unique_id": "model.farmerapp.fct_visit", "status": "success"},
                {"unique_id": "test.farmerapp.not_null_x", "status": "pass"},
                {"unique_id": "test.farmerapp.range_y", "status": "warn", "message": "3 rows"},
            ],
        },
        command="build",
        target="ci",
        elapsed_s=1.5,
        exit_code=0,
    )
    assert [line["event"] for line in ok] == ["dbt_run_result"], ok
    assert ok[0]["status"] == "ok"
    assert ok[0]["severity"] == "INFO"
    assert ok[0]["warnings"] == 1, "a warn-severity test is reported, not escalated"
    assert ok[0]["errors"] == 0

    bad = run_results_lines(
        {
            "metadata": {"invocation_id": "def"},
            "results": [
                {"unique_id": "model.farmerapp.fct_visit", "status": "success"},
                {
                    "unique_id": "test.farmerapp.unique_order_id",
                    "status": "fail",
                    "message": "Got 2 results,\nconfigured to fail if != 0",
                },
                {"unique_id": "model.farmerapp.mart_x", "status": "error", "message": "boom"},
            ],
        },
        command="build",
        target="dev",
        elapsed_s=9.0,
        exit_code=1,
    )
    assert [line["event"] for line in bad] == ["dbt_run_result", "dbt_run_failed"], bad
    assert bad[1]["severity"] == "ERROR"
    assert bad[1]["errors"] == 2
    assert bad[1]["first_failure"] == "test.farmerapp.unique_order_id"
    assert "\n" not in bad[1]["failures"][0]["message"], "one line per log line"
    assert [f["node"] for f in bad[1]["failures"]] == [
        "test.farmerapp.unique_order_id",
        "model.farmerapp.mart_x",
    ]

    # dbt died before writing an artefact (parse error, bad profile): still a failure.
    crashed = run_results_lines(None, command="build", target="dev", elapsed_s=0.2, exit_code=2)
    assert [line["event"] for line in crashed] == ["dbt_run_result", "dbt_run_failed"], crashed
    assert crashed[1]["first_failure"] == "no-artifact"
    assert crashed[1]["nodes"] == 0

    fresh = sources_lines(
        {
            "results": [
                {
                    "unique_id": "source.farmerapp.farmerapp_raw.public_order",
                    "status": "pass",
                    "max_loaded_at": "2026-09-19T06:00:00Z",
                    "max_loaded_at_time_ago_in_s": 120.4,
                    "criteria": {
                        "warn_after": {"count": 15, "period": "minute"},
                        "error_after": {"count": 30, "period": "minute"},
                    },
                },
                {
                    "unique_id": "source.farmerapp.farmerapp_raw.public_visit",
                    "status": "error",
                    "max_loaded_at": "2026-09-19T03:00:00Z",
                    "max_loaded_at_time_ago_in_s": 10800.0,
                    "criteria": {
                        "warn_after": {"count": 15, "period": "minute"},
                        "error_after": {"count": 30, "period": "minute"},
                    },
                },
            ]
        },
        command="source freshness",
        target="dev",
    )
    assert [line["event"] for line in fresh] == [
        "dbt_source_freshness",
        "dbt_source_freshness",
        "dbt_source_stale",
    ], fresh
    assert fresh[0]["source"] == "farmerapp_raw.public_order"
    assert fresh[0]["staleness_s"] == 120
    # AN-010's thresholds must reach the log line: the alert quotes them back to the reader.
    assert fresh[0]["warn_after_s"] == 900
    assert fresh[0]["error_after_s"] == 1800
    assert fresh[2]["source"] == "farmerapp_raw.public_visit"
    assert fresh[2]["severity"] == "ERROR"

    # A freshness run whose source has no threshold configured is reported, not invented.
    none_configured = sources_lines(
        {"results": [{"unique_id": "source.farmerapp.farmerapp_raw.public_crop", "status": "pass"}]},
        command="source freshness",
        target="dev",
    )
    assert none_configured[0]["warn_after_s"] is None
    assert "staleness_s" not in none_configured[0]

    print("dbt_run self-test: 20 assertions passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
