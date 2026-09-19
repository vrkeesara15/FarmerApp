"""Play Integrity verdicts: the request hash the app binds its token to, and the decision
over a decoded token payload (pure functions, no I/O)."""

from __future__ import annotations

import base64
import hashlib
from collections.abc import Collection, Mapping
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from typing import Any

#: A token older than this (``requestDetails.timestampMillis``) is stale (replayed).
MAX_TOKEN_AGE = timedelta(minutes=10)
PLAY_RECOGNIZED = "PLAY_RECOGNIZED"
MEETS_DEVICE_INTEGRITY = "MEETS_DEVICE_INTEGRITY"


class IntegrityStatus(StrEnum):
    VERIFIED = "verified"  # token decoded, bound to this request, genuine app on a genuine device
    FAILED = "failed"  # token decoded but a check failed (see reasons) -> VA-E01 signal
    UNAVAILABLE = "unavailable"  # the app said so (no Play services, quota, background sync)
    ABSENT = "absent"  # a sensitive action without any integrity header (old app, tampering)
    UNVERIFIED = "unverified"  # the server could not decide (verification off, API error)
    NOT_REQUIRED = "not_required"  # nothing sensitive in the request (e.g. a plain sync)


class IntegrityReason(StrEnum):
    PACKAGE_MISMATCH = "package_mismatch"
    REQUEST_HASH_MISMATCH = "request_hash_mismatch"
    STALE_TOKEN = "stale_token"  # nosec B105
    APP_NOT_RECOGNIZED = "app_not_recognized"
    DEVICE_INTEGRITY_MISSING = "device_integrity_missing"
    TOKEN_INVALID = "token_invalid"  # nosec B105
    VERIFICATION_OFF = "verification_off"
    VERIFIER_ERROR = "verifier_error"


#: Statuses that are an integrity signal for VA-E01 / the audit trail.
SIGNAL_STATUSES = frozenset({IntegrityStatus.FAILED, IntegrityStatus.ABSENT})


@dataclass(frozen=True)
class IntegrityVerdict:
    status: IntegrityStatus
    actions: tuple[str, ...] = ()
    reasons: tuple[str, ...] = ()
    package: str | None = None
    app_verdict: str | None = None
    device_verdicts: tuple[str, ...] = field(default_factory=tuple)

    @property
    def is_signal(self) -> bool:
        return self.status in SIGNAL_STATUSES

    def as_json(self) -> dict[str, Any]:
        return {
            "status": self.status.value,
            "actions": list(self.actions),
            "reasons": list(self.reasons),
            "package": self.package,
            "app_verdict": self.app_verdict,
            "device_verdicts": list(self.device_verdicts),
        }


def parse_actions(header: str | None) -> tuple[str, ...]:
    if not header:
        return ()
    return tuple(a.strip() for a in header.split(",") if a.strip())


def request_hash(method: str, path: str, body: bytes, actions: str) -> str:
    """``base64url(SHA-256(METHOD \\n path \\n hex(SHA-256(body)) \\n actions))``, unpadded —
    what the app puts in the token's ``requestHash`` (docs/prs/M5-mobile-security.md)."""
    material = "\n".join([method.upper(), path, hashlib.sha256(body).hexdigest(), actions])
    digest = hashlib.sha256(material.encode()).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode()


def evaluate(
    payload: Mapping[str, Any],
    *,
    expected_hash: str,
    packages: Collection[str],
    actions: tuple[str, ...],
    now: datetime,
    max_age: timedelta = MAX_TOKEN_AGE,
) -> IntegrityVerdict:
    """Decide over a decoded ``tokenPayloadExternal``."""
    details = payload.get("requestDetails") or {}
    app = payload.get("appIntegrity") or {}
    device = payload.get("deviceIntegrity") or {}
    package = details.get("requestPackageName")
    app_verdict = app.get("appRecognitionVerdict")
    device_verdicts = tuple(str(v) for v in device.get("deviceRecognitionVerdict") or ())
    reasons: list[str] = []
    if package not in packages:
        reasons.append(IntegrityReason.PACKAGE_MISMATCH)
    if details.get("requestHash") != expected_hash:
        reasons.append(IntegrityReason.REQUEST_HASH_MISMATCH)
    issued: datetime | None
    try:
        issued = datetime.fromtimestamp(int(str(details.get("timestampMillis"))) / 1000, tz=UTC)
    except (TypeError, ValueError, OverflowError):
        issued = None
    if issued is None or abs(now - issued) > max_age:
        reasons.append(IntegrityReason.STALE_TOKEN)
    if app_verdict != PLAY_RECOGNIZED:
        reasons.append(IntegrityReason.APP_NOT_RECOGNIZED)
    if MEETS_DEVICE_INTEGRITY not in device_verdicts:
        reasons.append(IntegrityReason.DEVICE_INTEGRITY_MISSING)
    return IntegrityVerdict(
        status=IntegrityStatus.FAILED if reasons else IntegrityStatus.VERIFIED,
        actions=actions,
        reasons=tuple(str(r) for r in reasons),
        package=str(package) if package else None,
        app_verdict=str(app_verdict) if app_verdict else None,
        device_verdicts=device_verdicts,
    )


__all__ = [
    "MAX_TOKEN_AGE",
    "SIGNAL_STATUSES",
    "IntegrityReason",
    "IntegrityStatus",
    "IntegrityVerdict",
    "evaluate",
    "parse_actions",
    "request_hash",
]
