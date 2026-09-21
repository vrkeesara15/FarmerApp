"""NF-012: the policy table says exactly what the spec sentence says, and covers everything.

"Raw location points 180 days; visit records 7 years; photos 3 years then archived;
 audit logs 1 year minimum; financial records 8 years."
"""

from __future__ import annotations

import re

import pytest

from farmerapp.db.base import Base
from farmerapp.db.rls import APPEND_ONLY_TABLES
from farmerapp.jobs.purge_audit_logs import DEFAULT_RETENTION_DAYS, MINIMUM_RETENTION_DAYS
from farmerapp.location.models import LOCATION_RETENTION_DAYS
from farmerapp.retention import POLICY, RetentionAction, covered_tables, policy_for
from scripts.terraform_env import INFRA

YEAR = 365


def test_the_five_spec_classes_are_all_there() -> None:
    assert [c.name for c in POLICY] == [
        "location_points",
        "photos",
        "audit_logs",
        "visit_records",
        "financial_records",
    ]


@pytest.mark.parametrize(
    ("name", "days", "action"),
    [
        ("location_points", 180, RetentionAction.PURGE),
        ("photos", 3 * YEAR, RetentionAction.ARCHIVE),
        ("audit_logs", 400, RetentionAction.PURGE),
        ("visit_records", 7 * YEAR, RetentionAction.PURGE),
        ("financial_records", 8 * YEAR, RetentionAction.RETAIN),
    ],
)
def test_each_window_is_the_spec_window(name: str, days: int, action: RetentionAction) -> None:
    entry = policy_for(name)
    assert entry.days == days
    assert entry.action is action
    assert entry.spec, "every class quotes the spec sentence it implements"


def test_the_windows_agree_with_the_jobs_that_already_own_them() -> None:
    """One number per class: the policy table cannot drift from the existing jobs."""
    assert policy_for("location_points").days == LOCATION_RETENTION_DAYS
    assert policy_for("audit_logs").days == DEFAULT_RETENTION_DAYS
    assert policy_for("audit_logs").days >= MINIMUM_RETENTION_DAYS >= YEAR


def test_financial_records_are_a_floor_and_nothing_deletes_them() -> None:
    entry = policy_for("financial_records")
    assert entry.is_floor
    assert entry.migrate_role
    assert "8 years" in entry.spec
    assert "Companies Act" in entry.note or "GST" in entry.note


def test_append_only_classes_are_marked_migrate_role() -> None:
    """The runtime role cannot DELETE from these; a sweep that tried would fail at runtime."""
    for entry in POLICY:
        if set(entry.tables) & APPEND_ONLY_TABLES:
            assert entry.migrate_role, f"{entry.name} touches an append-only table"


def test_every_table_named_by_the_policy_exists() -> None:
    known = set(Base.metadata.tables)
    assert covered_tables() <= known, covered_tables() - known


def test_visit_tables_are_ordered_children_first() -> None:
    """The sweep deletes in this order; a parent first would trip a foreign key."""
    tables = policy_for("visit_records").tables
    assert tables.index("visit") == len(tables) - 1


# --------------------------------------------------------------------------- photos: archive
def test_the_photo_bucket_really_archives_at_three_years() -> None:
    """NF-012 'photos 3 years then archived' is a bucket lifecycle rule, so assert the rule."""
    entry = policy_for("photos")
    assert entry.action is RetentionAction.ARCHIVE
    for env in ("dev", "stg", "prd"):
        text = (INFRA / "envs" / env / "main.tf").read_text()
        photos = re.search(r"photos\s*=\s*\{(.*?)\n    \}", text, re.S)
        assert photos is not None, env
        rules = photos.group(1)
        assert 'action_type = "SetStorageClass"' in rules
        archive = re.search(
            r'action_type\s*=\s*"SetStorageClass",\s*storage_class\s*=\s*"ARCHIVE",'
            r"\s*age_days\s*=\s*(\d+)",
            rules,
        )
        assert archive is not None, f"{env}: no ARCHIVE lifecycle rule on the photos bucket"
        assert int(archive.group(1)) == entry.days, (
            f"{env}: photos archive at {archive.group(1)} days, policy says {entry.days}"
        )


def test_the_photo_rows_are_never_deleted_by_the_lifecycle_rule() -> None:
    """The object goes cold; the row stays, because a 7-year visit record names it."""
    for env in ("dev", "stg", "prd"):
        text = (INFRA / "envs" / env / "main.tf").read_text()
        photos = re.search(r"photos\s*=\s*\{(.*?)\n    \}", text, re.S)
        assert photos is not None
        assert 'action_type = "Delete"' not in photos.group(1), (
            f"{env}: a Delete rule on the photos bucket would orphan visit_photo rows"
        )
