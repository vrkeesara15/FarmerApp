"""The versioned employee location policy text (FA-011 / VV-010; SPEC 13.2 screen A05).

The copy lives in ``location_policy_texts.json`` next to this module (an i18n file: four
short points per language — what is collected, only while on duty, why, who sees it),
keyed by version. **TODO-LEGAL**: placeholder until HR signs the written policy (SPEC 14.6
human gate); a change of wording is a *new* version, never an edit of one that has
acceptances.

The version the app must accept is the tenant setting ``location_policy_version``
(``farmerapp.tenants.settings``). ``policy_for(version)`` returns the text of that version
when this module knows it and otherwise the latest known text under the tenant's version
string (the wording HR signs off can be identical across tenant-specific version labels);
``text_hash`` binds version and text, so a bumped version always invalidates old
acceptances (VV-010) and an acceptance sent with a stale hash is refused.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Final

from farmerapp.location.models import LOCATION_POLICY_KEY

LANGUAGES: Final[tuple[str, ...]] = ("en", "te", "kn", "hi", "mr")
POINTS_PER_LANGUAGE: Final = 4
_TEXTS_PATH = Path(__file__).with_name("location_policy_texts.json")


@dataclass(frozen=True)
class LocationPolicy:
    version: str
    text: dict[str, list[str]]  # language -> the four points
    text_hash: str


@lru_cache(maxsize=1)
def known_versions() -> dict[str, dict[str, list[str]]]:
    """Every version in the texts file, validated (all languages, four points each)."""
    raw = json.loads(_TEXTS_PATH.read_text(encoding="utf-8"))
    versions: dict[str, dict[str, list[str]]] = {}
    for version, text in raw.items():
        if version.startswith("_"):
            continue
        missing = set(LANGUAGES) - set(text)
        if missing:
            raise ValueError(f"location policy {version}: missing languages {sorted(missing)}")
        for language in LANGUAGES:
            points = text[language]
            if len(points) != POINTS_PER_LANGUAGE or not all(p.strip() for p in points):
                raise ValueError(
                    f"location policy {version} [{language}]: {POINTS_PER_LANGUAGE} points needed"
                )
        versions[version] = {language: list(text[language]) for language in LANGUAGES}
    if not versions:
        raise ValueError("location policy texts file has no versions")
    return versions


def latest_known_version() -> str:
    return max(known_versions())  # versions are ``YYYY-MM-vN``: lexical order is time order


def text_hash(version: str, text: dict[str, list[str]]) -> str:
    """sha256 over the policy key, the version and the canonical JSON of the text."""
    canonical = json.dumps(text, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(f"{LOCATION_POLICY_KEY}:{version}\n{canonical}".encode()).hexdigest()


def policy_for(version: str) -> LocationPolicy:
    """The text served under ``version`` (a tenant's ``location_policy_version``)."""
    versions = known_versions()
    text = versions.get(version) or versions[latest_known_version()]
    return LocationPolicy(version=version, text=text, text_hash=text_hash(version, text))


__all__ = [
    "LANGUAGES",
    "POINTS_PER_LANGUAGE",
    "LocationPolicy",
    "known_versions",
    "latest_known_version",
    "policy_for",
    "text_hash",
]
