"""NF-013: the parts of DPDP compliance that live in prose, checked like code.

The Act asks for things a test suite cannot prove — a notice, a lawful basis written down, a
breach-notification runbook that has been rehearsed. What a test *can* do is refuse to let
those documents quietly disappear or lose the clauses an auditor will look for, and keep them
pointing at the code that implements them. That is what this file does; the substance is a
legal review (SPEC 14.6).
"""

from __future__ import annotations

from pathlib import Path

import pytest

from farmerapp.privacy.erasure import retained_classes
from farmerapp.privacy.models import DataRequestType
from farmerapp.retention import POLICY, RetentionClass

DOCS = Path(__file__).resolve().parents[4] / "docs"
DPDP = DOCS / "dpdp.md"
RETENTION = DOCS / "retention.md"
BREACH = DOCS / "runbooks" / "suspected-data-breach.md"
ERASURE = DOCS / "runbooks" / "data-subject-erasure.md"


def _text(path: Path) -> str:
    assert path.exists(), f"{path.relative_to(DOCS.parent)} is missing"
    return path.read_text()


# --------------------------------------------------------------------------- the note
def test_the_dpdp_note_covers_every_right_the_api_serves() -> None:
    text = _text(DPDP).lower()
    for right in DataRequestType:
        assert right.value in text, f"docs/dpdp.md says nothing about {right.value}"
    assert "erasure" in text


def test_the_dpdp_note_names_the_lawful_basis_for_both_kinds_of_principal() -> None:
    text = _text(DPDP)
    assert "consent" in text.lower(), "farmers: consent (FM-002)"
    assert "legitimate use" in text.lower(), "employees: legitimate use, section 7(i)"
    assert "on duty" in text.lower(), "FA-010: location only on duty"


def test_the_dpdp_note_documents_the_two_foreign_egress_paths() -> None:
    """NF-011: the LLM and the weather call are the two, and the note must say what they carry."""
    text = _text(DPDP)
    assert "asia-south1" in text and "asia-south2" in text
    for destination in ("Anthropic", "Open-Meteo"):
        assert destination in text, destination
    assert "EXIF" in text, "the note must say the photo is stripped"
    assert "grid cell" in text, "the note must say the forecast gets a grid cell, not a farm"
    assert "ROAD_SNAPPER" in text, "the reviewed, switched-off third path is disclosed"


def test_the_dpdp_note_records_the_erasure_exception() -> None:
    text = _text(DPDP)
    assert "the-erasure-exception" in text, "the anchor the runbook links to"
    for entry in retained_classes():
        assert entry.record_class.replace("_", " ") in text.lower().replace("_", " "), (
            f"docs/dpdp.md does not explain why {entry.record_class} survives an erasure"
        )
    assert "Companies Act" in text and "GST" in text


def test_the_dpdp_note_links_the_breach_runbook() -> None:
    assert "suspected-data-breach.md" in _text(DPDP)


def test_the_dpdp_note_lists_what_is_still_a_human_gate() -> None:
    text = _text(DPDP)
    assert "human gate" in text.lower()
    assert "TODO-LEGAL" in text, "the notice and consent copy are a legal review"


# --------------------------------------------------------------------------- retention
@pytest.mark.parametrize("entry", POLICY, ids=[c.name for c in POLICY])
def test_the_retention_document_covers_every_class(entry: RetentionClass) -> None:
    text = _text(RETENTION)
    name = entry.name
    assert f"`{name}`" in text, f"docs/retention.md does not list {name}"
    assert str(entry.days) in text, f"docs/retention.md omits the {name} window"


def test_the_retention_document_says_the_sweep_is_a_dry_run_by_default() -> None:
    text = _text(RETENTION).lower()
    assert "dry run is the default" in text
    assert "--apply" in text


# --------------------------------------------------------------------------- breach runbook
def test_the_breach_runbook_exists_and_carries_the_dpdp_clauses() -> None:
    """NF-013 asks for a breach notification runbook; these are the clauses an auditor reads."""
    text = _text(BREACH)
    assert "Data Protection Board" in text, "who must be notified"
    assert "72 hours" in text or "72 h" in text, "the detailed report deadline"
    assert "Data Principal" in text, "each affected principal must be told"
    assert "Owner:" in text, "every runbook names an owner"
    assert "Severity:" in text
    assert "Detection:" in text
    assert "## Verification" in text
    assert "## Follow-up" in text


def test_the_breach_runbook_commits_to_the_yearly_rehearsal() -> None:
    """SPEC 11.4: the incident response runbook is tested once a year."""
    text = _text(BREACH).lower()
    assert "once a year" in text or "yearly" in text or "annual" in text
    assert "rehearsal log" in text, "the runbook must have somewhere to record each drill"


def test_the_breach_runbook_is_listed_in_the_runbook_index() -> None:
    index = _text(DOCS / "runbooks" / "README.md")
    assert "suspected-data-breach.md" in index
    assert "data-subject-erasure.md" in index


# --------------------------------------------------------------------------- erasure runbook
def test_the_erasure_runbook_describes_the_automated_run() -> None:
    text = _text(ERASURE)
    assert "/erase" in text, "the runbook must name the endpoint that does the work"
    assert "retention-exceptions" in text or "retained" in text.lower()
    assert "the-erasure-exception" in text, "it links the reasons, it does not restate them"
    assert "retention-sweep" in text, "the operator verifies compliance afterwards"
