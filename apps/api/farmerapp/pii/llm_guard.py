"""SEC-027 / NF-011: the one guard every LLM call goes through.

Three call sites send data to a model — the DX-004 diagnosis fallback
(``farmerapp.diagnosis.llm``), the VA-004 flag review agent
(``farmerapp.flags.review_agent``) and the AN-016 question writer (``farmerapp.nlq.llm``) —
and all three must obey the same rule: *the prompt carries crop context, a schema and record
ids, never a person*. Before this module each site had its own idea of what that meant. Now
they build their prompt text, hand it to :func:`guard_prompt`, and the call is refused
(``PromptPiiError``) when anything person-shaped survives.

What the guard rejects in prompt text:

* e-mail addresses;
* phone-like digit runs (10-15 digits, ``+91`` and separators tolerated) that are not part
  of a record id — record ids (UUIDs) are explicitly allowed and are how the model is meant
  to refer to anything;
* Aadhaar-shaped numbers (12 digits, ``1234 5678 9012``);
* decimal coordinate pairs (a farm's position is never crop context, NF-011).

What the guard rejects in prompt *structure*: a mapping key that names a person or a
contact detail (:data:`PII_KEYS`, ``*_name``, anything containing ``phone``). ``scrub``
removes those keys and masks phone-like runs; the guard is the assertion that the scrubbing
actually happened, so a future prompt that adds a field is a failing test, not a leak.

The allow-lists :data:`DIAGNOSIS_PROMPT_FIELDS`, :data:`FLAG_BUNDLE_KEYS` and
:data:`NLQ_PROMPT_FIELDS` pin the shape of each prompt. ``tests/pii/test_llm_guard.py``
compares them against the real request dataclasses and the real evidence bundle, so adding a
field to any of them without reviewing it here fails CI.

Images take the other half of SEC-027: ``farmerapp.diagnosis.images.strip_for_llm``
re-encodes every photo from pixels, so no EXIF block (GPS position, device serial, capture
time) reaches the provider. :func:`assert_no_exif` is the assertion for that step.
"""

from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from typing import Any

__all__ = [
    "DIAGNOSIS_PROMPT_FIELDS",
    "FLAG_BUNDLE_KEYS",
    "NLQ_PROMPT_FIELDS",
    "PII_KEYS",
    "PromptPiiError",
    "assert_no_exif",
    "findings",
    "guard_prompt",
    "is_pii_key",
    "mask_text",
    "scrub",
]


class PromptPiiError(ValueError):
    """A prompt (or a prompt payload) still carries personal data. The call is refused."""

    def __init__(self, where: str, reasons: Sequence[str]) -> None:
        self.where = where
        self.reasons = list(reasons)
        super().__init__(f"{where}: prompt carries personal data ({', '.join(self.reasons)})")


# --------------------------------------------------------------------------- key names
#: Mapping keys that name a person or a contact detail; dropped by :func:`scrub`.
PII_KEYS = frozenset(
    {
        "address",
        "code",
        "device",
        "device_id",
        "email",
        "landmark",
        "mobile",
        "name",
        "names",
        "otp",
        "phone",
        "phone_number",
        "phones",
    }
)


def is_pii_key(key: str) -> bool:
    lowered = key.lower()
    if lowered.endswith("_last4"):  # already masked to four digits
        return False
    return (
        lowered in PII_KEYS
        or lowered.endswith("_name")
        or lowered.endswith("_names")
        or "phone" in lowered
    )


# --------------------------------------------------------------------------- text patterns
UUID_RE = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
PHONE_RE = re.compile(r"\+?\d[\d \-]{7,}\d")
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")
AADHAAR_RE = re.compile(r"\b\d{4}[ \-]?\d{4}[ \-]?\d{4}\b")
#: A decimal coordinate pair: 17.3850, 78.4867 (a position is never crop context, NF-011).
COORD_RE = re.compile(r"-?\d{1,3}\.\d{4,}\s*[,;]\s*-?\d{1,3}\.\d{4,}")
#: Digits of a masked phone (``******1234``) are not a finding.
MASKED_RE = re.compile(r"\*{2,}\d{2,4}")

#: Minimum digits that make a run phone-like (Indian mobiles are 10).
PHONE_MIN_DIGITS = 10


def _mask_digits(text: str) -> str:
    def mask(match: re.Match[str]) -> str:
        digits = re.sub(r"\D", "", match.group(0))
        if len(digits) < PHONE_MIN_DIGITS:  # dates (2026-09-18) and short numbers are not phones
            return match.group(0)
        return "******" + digits[-4:]

    return PHONE_RE.sub(mask, text)


def mask_text(text: str) -> str:
    """Mask phone-like digit runs, leaving record ids (UUIDs) untouched (SEC-027)."""
    out: list[str] = []
    last = 0
    for match in UUID_RE.finditer(text):
        out.append(_mask_digits(text[last : match.start()]))
        out.append(match.group(0))
        last = match.end()
    out.append(_mask_digits(text[last:]))
    return "".join(out)


def scrub(value: Any) -> Any:
    """Drop PII keys and mask phone numbers anywhere in a JSON value (SEC-027)."""
    if isinstance(value, Mapping):
        return {str(k): scrub(v) for k, v in value.items() if not is_pii_key(str(k))}
    if isinstance(value, list | tuple):
        return [scrub(v) for v in value]
    if isinstance(value, str):
        return mask_text(value)
    return value


def _without_ids(text: str) -> str:
    """The text with record ids and already-masked runs blanked out."""
    return MASKED_RE.sub(" ", UUID_RE.sub(" ", text))


def _text_findings(text: str) -> list[str]:
    stripped = _without_ids(text)
    found: list[str] = []
    if EMAIL_RE.search(stripped):
        found.append("email address")
    if AADHAAR_RE.search(stripped):
        found.append("Aadhaar-shaped number")
    if COORD_RE.search(stripped):
        found.append("coordinate pair")
    for match in PHONE_RE.finditer(stripped):
        if len(re.sub(r"\D", "", match.group(0))) >= PHONE_MIN_DIGITS:
            found.append("phone-like digit run")
            break
    return found


def findings(payload: Any, *, path: str = "") -> list[str]:
    """Every reason ``payload`` may not be sent to a model. Empty means it is clean."""
    found: list[str] = []
    if isinstance(payload, Mapping):
        for key, value in payload.items():
            here = f"{path}.{key}" if path else str(key)
            if is_pii_key(str(key)):
                found.append(f"key {here!r}")
                continue
            found.extend(findings(value, path=here))
    elif isinstance(payload, list | tuple):
        for index, value in enumerate(payload):
            found.extend(findings(value, path=f"{path}[{index}]"))
    elif isinstance(payload, str):
        where = f" in {path!r}" if path else ""
        found.extend(f"{reason}{where}" for reason in _text_findings(payload))
    return found


def guard_prompt(payload: Any, *, where: str) -> None:
    """Refuse to send ``payload`` to a model when it still carries personal data.

    ``where`` names the call site in the error and the log (``diagnosis.fallback``,
    ``flags.summary``). Raises :class:`PromptPiiError`; callers treat that as a bug, not as a
    provider error — it means the prompt builder changed without a review here.
    """
    found = findings(payload)
    if found:
        raise PromptPiiError(where, sorted(set(found)))


#: JPEG/PNG markers whose presence means metadata survived the re-encode.
_EXIF_MARKERS = (b"Exif\x00\x00", b"http://ns.adobe.com/xap/", b"eXIf", b"GPS")


def assert_no_exif(data: bytes, *, where: str = "image") -> None:
    """SEC-027: the bytes sent to a model carry no EXIF / XMP block.

    ``farmerapp.diagnosis.images.strip_for_llm`` re-encodes from pixels, so this only ever
    fires when a call site forgets to use it.
    """
    head = data[:65_536]
    hits = [marker.decode("latin-1") for marker in _EXIF_MARKERS if marker in head]
    if hits:
        raise PromptPiiError(where, [f"image metadata block {hit!r}" for hit in hits])


# --------------------------------------------------------------------------- prompt shapes
#: DX-004: the only fields of ``farmerapp.diagnosis.llm.LlmRequest``. Crop context and the
#: corpus candidates; nothing that identifies a farmer, an officer or a place finer than a
#: district. Adding a field here is the review gate (tests/pii/test_llm_guard.py).
DIAGNOSIS_PROMPT_FIELDS = frozenset(
    {"images", "crop", "district", "season", "crop_stage", "candidates"}
)

#: VA-004: the only top-level keys of the flag evidence bundle
#: (``farmerapp.flags.review_agent.build_bundle``).
FLAG_BUNDLE_KEYS = frozenset(
    {"rule", "severity", "subject", "raised_at", "records", "metrics", "map", "photos"}
)

#: AN-016: the only fields of ``farmerapp.nlq.llm.NlqRequest``. The owner's question, the
#: **schema** of the authorised views (column names and meanings — never a row, never a
#: value), the caller's role and scope in words (never an id), and today's date. No row the
#: query returns ever goes back to a model. Adding a field here is the review gate
#: (tests/pii/test_llm_guard.py compares it against the real dataclass).
NLQ_PROMPT_FIELDS = frozenset({"question", "schema", "role", "scope", "today"})
