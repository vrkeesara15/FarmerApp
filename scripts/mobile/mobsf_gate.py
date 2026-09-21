#!/usr/bin/env python3
"""SEC-008 — turn a MobSF report_json into a pass/fail gate.

    scripts/mobile/mobsf_gate.py mobsf-report.json
    MOBSF_HIGH_LIMIT=0 scripts/mobile/mobsf_gate.py mobsf-report.json

Reads the JSON that `POST /api/v1/report_json` returns (MobSF 3.x/4.x) and
fails when the release carries more high-severity findings than
MOBSF_HIGH_LIMIT (default 0) or any possible hardcoded secret.

Every section MobSF names differently across versions is read defensively:
a missing or reshaped key degrades to "no findings from that section" rather
than a traceback, and the sections actually found are printed so a silent
"0 findings because the key moved" is visible in the log.

Secret values are never printed — only the finding's section, a short SHA-256
fingerprint and the length, so the CI log cannot become the leak. Open the
uploaded mobsf-report.json to see the value.

How to read the report: docs/runbooks/mobile-security-scan.md
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from typing import Any

HIGH = {"high", "critical"}


def _as_list(value: Any) -> list[Any]:
    """MobSF returns dicts keyed by rule id in some sections, lists in others."""
    if isinstance(value, dict):
        return list(value.values())
    if isinstance(value, list):
        return value
    return []


def _section(report: dict, *names: str) -> Any:
    for name in names:
        if name in report:
            return report[name]
    return None


def _severity(entry: Any) -> str:
    if not isinstance(entry, dict):
        return ""
    meta = entry.get("metadata") if isinstance(entry.get("metadata"), dict) else {}
    sev = entry.get("severity") or entry.get("level") or meta.get("severity")
    return str(sev or "").lower()


def _title(entry: Any) -> str:
    if isinstance(entry, dict):
        meta = entry.get("metadata") if isinstance(entry.get("metadata"), dict) else {}
        for key in ("title", "name", "rule", "description", "issue"):
            value = entry.get(key) or meta.get(key)
            if value:
                return " ".join(str(value).split())[:160]
    return " ".join(str(entry).split())[:160]


def collect_high(report: dict) -> tuple[list[tuple[str, str]], list[str]]:
    """-> ([(section, title)] of high findings, [sections actually present])."""
    found: list[tuple[str, str]] = []
    present: list[str] = []

    # appsec.high is MobSF's own curated list; when it exists it is the most
    # faithful reading of "high" and needs no severity filtering.
    appsec = _section(report, "appsec") or {}
    if isinstance(appsec, dict) and isinstance(appsec.get("high"), list):
        present.append("appsec.high")
        found += [("appsec", _title(f)) for f in appsec["high"]]

    for label, section, key in (
        ("code_analysis", _section(report, "code_analysis"), "findings"),
        ("manifest_analysis", _section(report, "manifest_analysis"), "manifest_findings"),
        ("network_security", _section(report, "network_security"), "network_findings"),
        ("binary_analysis", _section(report, "binary_analysis"), None),
    ):
        if isinstance(section, dict):
            entries = _as_list(section.get(key)) if key else _as_list(section)
        else:
            entries = _as_list(section)
        if not entries:
            continue
        present.append(label)
        found += [(label, _title(e)) for e in entries if _severity(e) in HIGH]

    # certificate_analysis.certificate_findings is a list of [severity, title, ...]
    cert = _section(report, "certificate_analysis")
    if isinstance(cert, dict):
        findings = cert.get("certificate_findings")
        if isinstance(findings, list) and findings:
            present.append("certificate_analysis")
            for f in findings:
                if isinstance(f, list | tuple) and f and str(f[0]).lower() in HIGH:
                    found.append(("certificate_analysis", " ".join(str(x) for x in f[1:])[:160]))
                elif _severity(f) in HIGH:
                    found.append(("certificate_analysis", _title(f)))

    return found, present


def collect_secrets(report: dict) -> list[str]:
    """Possible hardcoded secrets, as opaque fingerprints (never the value)."""
    raw: list[Any] = []
    for key in ("secrets", "possible_secrets"):
        raw += _as_list(_section(report, key))
    appsec = _section(report, "appsec")
    if isinstance(appsec, dict):
        for bucket in ("hotspot", "warning"):
            for item in _as_list(appsec.get(bucket)):
                if isinstance(item, dict) and "secret" in str(item.get("title", "")).lower():
                    raw += _as_list(item.get("description")) or [item.get("description")]

    out: list[str] = []
    for item in raw:
        if item is None:
            continue
        text = item if isinstance(item, str) else json.dumps(item, sort_keys=True)
        digest = hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:12]
        out.append(f"sha256:{digest} ({len(text)} chars)")
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as fh:
            report = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"::error::MobSF report {argv[1]} is unreadable: {exc}")
        return 1
    if not isinstance(report, dict) or not report:
        print(f"::error::MobSF report {argv[1]} is empty or not an object — the scan did not run")
        return 1

    appsec = report.get("appsec") if isinstance(report.get("appsec"), dict) else {}
    score = appsec.get("security_score", report.get("security_score", "n/a"))
    grade = appsec.get("app_sec_grade") or appsec.get("grade") or ""

    high, present = collect_high(report)
    secrets = collect_secrets(report)
    limit = int(os.environ.get("MOBSF_HIGH_LIMIT", "0"))

    print(f"MobSF appsec score: {score}{f' (grade {grade})' if grade else ''}")
    print(f"MobSF sections read: {', '.join(present) or 'NONE'}")
    print(f"MobSF: {len(high)} high finding(s) (limit {limit}), {len(secrets)} possible secret(s)")
    if not present:
        print("::error::no recognised findings section in the report — MobSF's schema changed; "
              "refusing to report a clean scan")
        return 1

    for section, title in high[:25]:
        print(f"  HIGH  [{section}] {title}")
    if len(high) > 25:
        print(f"  ... and {len(high) - 25} more")
    for fingerprint in secrets[:25]:
        print(f"  SECRET  {fingerprint}  (value withheld; see mobsf-report.json)")
    if len(secrets) > 25:
        print(f"  ... and {len(secrets) - 25} more")

    if len(high) > limit:
        print(f"::error::SEC-008: {len(high)} high-severity MobSF finding(s), limit is {limit}")
    if secrets:
        print(f"::error::SEC-008: MobSF found {len(secrets)} possible hardcoded secret(s)")
    if len(high) > limit or secrets:
        print("Triage: docs/runbooks/mobile-security-scan.md#a-gate-fired")
        return 1

    print("MobSF gate: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
