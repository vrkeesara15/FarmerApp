"""NF-012 retention policy: the spec's five classes, written once, in code.

    "Raw location points 180 days; visit records 7 years; photos 3 years then archived;
     audit logs 1 year minimum; financial records 8 years."

Every class names the tables it covers, the column that dates a row, the window, and what
happens at the end of it. Three things read this table: the sweep job
(``farmerapp.retention.sweep``), the retention document (``docs/retention.md``) and the tests
(``tests/retention/``), so the three can never drift apart:
``test_the_retention_document_covers_every_class`` fails when the doc omits a class, and
``test_every_table_named_by_the_policy_exists`` fails when a class names a table that has
gone away.

The reverse direction is *not* enforced: nothing yet fails when a new personal-data table is
added and forgotten here. Adding that check means agreeing which tables hold personal data,
which is a judgement call — until then, adding a table to the right class is a review
responsibility, and ``docs/retention.md`` says so.

Actions
-------
``PURGE``    rows past the window are deleted (the sweep does it, with ``--apply``).
``ARCHIVE``  the object moves to a colder storage class and the row stays: for photos this
             is a GCS lifecycle rule (``SetStorageClass ARCHIVE`` at 1095 days, asserted
             against the real ``.tf`` by ``tests/retention/test_policy.py``), not something
             the app does.
``RETAIN``   the window is a *floor*, not a deadline: nothing may be deleted before it, and
             this codebase deletes it at no point after either. The sweep reports how many
             rows are past the floor and stops there, with or without ``--apply``.

Who deletes
-----------
The runtime role may not delete from append-only tables (``audit_log``, ``khata_entry`` …;
``farmerapp.db.rls.APPEND_ONLY_TABLES``), so those classes are ``migrate_role=True``: the
sweep counts them and says what a migrate-role run would remove, and the deletion itself is a
Cloud Run Job execution with the migrate identity (docs/runbooks/retention.md). Everything
else the sweep can delete itself.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

__all__ = [
    "POLICY",
    "RetentionAction",
    "RetentionClass",
    "covered_tables",
    "policy_for",
]

YEAR = 365


class RetentionAction(StrEnum):
    PURGE = "purge"
    ARCHIVE = "archive"
    RETAIN = "retain"


@dataclass(frozen=True)
class RetentionClass:
    #: Key used on the command line and in the report.
    name: str
    #: SPEC wording this implements.
    spec: str
    #: Tables the class covers, ordered children first (the sweep deletes in this order).
    tables: tuple[str, ...]
    #: Column that dates a row for this class.
    date_column: str
    #: The window in days.
    days: int
    action: RetentionAction
    #: Only the migrate role may delete these rows (append-only under RLS).
    migrate_role: bool = False
    #: Where the action actually happens when it is not this job.
    owner: str = "farmerapp.retention.sweep"
    note: str = ""

    @property
    def is_floor(self) -> bool:
        """RETAIN windows are minimums: deleting earlier is the violation."""
        return self.action is RetentionAction.RETAIN


POLICY: tuple[RetentionClass, ...] = (
    RetentionClass(
        name="location_points",
        spec="Raw location points 180 days",
        tables=("location_point",),
        date_column="ts",
        days=180,
        action=RetentionAction.PURGE,
        owner="python -m farmerapp.jobs purge-location-points",
        note=(
            "Daily partitions: the dedicated job aggregates into location_daily_agg and drops "
            "whole partitions, which is cheaper than a DELETE. The sweep only reports the "
            "count so one command can answer 'are we compliant?' for every class."
        ),
    ),
    RetentionClass(
        name="photos",
        spec="Photos 3 years then archived",
        tables=("farm_photo", "visit_photo"),
        date_column="created_at",
        days=3 * YEAR,
        action=RetentionAction.ARCHIVE,
        owner="GCS lifecycle rule on the photos bucket (infra/envs/*/main.tf)",
        note=(
            "SetStorageClass ARCHIVE at 1095 days (NEARLINE at 90). The database row stays: a "
            "seven-year visit record must still name its photo. Nothing is deleted here."
        ),
    ),
    RetentionClass(
        name="audit_logs",
        spec="Audit logs 1 year minimum",
        tables=("audit_log",),
        date_column="created_at",
        days=400,
        action=RetentionAction.PURGE,
        migrate_role=True,
        owner="python -m farmerapp.jobs purge-audit-logs",
        note=(
            "400 days = a year plus a margin for the archival step. The minimum is 365 and "
            "purge_audit_logs refuses a shorter window."
        ),
    ),
    RetentionClass(
        name="visit_records",
        spec="Visit records 7 years",
        tables=("visit_confirmation", "visit_photo", "visit"),
        date_column="created_at",
        days=7 * YEAR,
        action=RetentionAction.PURGE,
        note=(
            "A visit is evidence of advice given; it outlives the farmer's account (an erasure "
            "anonymises the farmer, it does not drop the visit — docs/dpdp.md)."
        ),
    ),
    RetentionClass(
        name="financial_records",
        spec="Financial records 8 years",
        tables=("invoice", "payment", "order_line", "order", "khata_entry", "day_close"),
        date_column="created_at",
        days=8 * YEAR,
        action=RetentionAction.RETAIN,
        migrate_role=True,
        note=(
            "Section 128 of the Companies Act and the GST rules; the DPDP erasure right yields "
            "to it (the documented exception in docs/dpdp.md). Nothing in this codebase deletes "
            "these rows — the sweep reports how many are past the floor and stops there."
        ),
    ),
)

#: NF-012 covers these classes and no others; the spec sentence is the contract.
CLASS_NAMES = tuple(c.name for c in POLICY)


def policy_for(name: str) -> RetentionClass:
    for entry in POLICY:
        if entry.name == name:
            return entry
    raise KeyError(f"unknown retention class {name!r} (have: {', '.join(CLASS_NAMES)})")


def covered_tables() -> frozenset[str]:
    return frozenset(table for entry in POLICY for table in entry.tables)
