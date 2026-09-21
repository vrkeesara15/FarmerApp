"""NF-013 right of access: everything the tenant holds about one data principal, as JSON.

``build_export(session, actor, farmer_id=None)`` returns a document a farmer can read and
keep: their account, their farmer record, their farms and crop plots, their consent history,
the visits made to them, their orders, payments and khata entries, their crop-doctor
diagnoses, and every data request they have raised. Two callers:

* ``GET /v1/me/data-export`` — the principal themselves, in the app (FM-015 sits next to it).
* ``GET /v1/admin/data-requests/{id}/export`` — staff serving an ``access`` ticket for a
  principal who asked through the console or by phone.

Both read *only* rows that belong to the principal and only in the caller's tenant (RLS is
already bound). Sections are declarative (:data:`SECTIONS`): a new table that holds personal
data is added here, and ``tests/privacy/test_export.py`` fails until the new section names
what it exposes. Encrypted columns are decrypted for the principal's own record (that is the
point of the right) and the internal ciphertext / hash columns are never exposed.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.farmers.models import Farmer
from farmerapp.logging import get_logger

log = get_logger("farmerapp.privacy.export")

__all__ = ["SECTIONS", "ExportSection", "build_export"]

#: Columns no export ever contains: ciphertext, search hashes and soft-delete bookkeeping.
HIDDEN_SUFFIXES = ("_enc", "_hash")
HIDDEN_COLUMNS = frozenset({"tenant_id", "version", "deleted_at", "code_hash", "token_hash"})


@dataclass(frozen=True)
class ExportSection:
    """One list in the export document."""

    name: str
    table: str
    #: Column that links a row to the principal.
    key: str
    #: What ``key`` holds: ``farmer`` = the farmer record's id, ``user`` = the account id,
    #: ``farms`` = one of the principal's farm ids (a sub-select on ``farm``).
    key_of: str
    order_by: str = "created_at"
    note: str = ""


SECTIONS: tuple[ExportSection, ...] = (
    ExportSection("farms", "farm", "farmer_id", "farmer", note="FA-013 land parcels"),
    ExportSection("crop_plots", "crop_plot", "farm_id", "farms", note="FA-014 crops sown"),
    ExportSection(
        "consent_records",
        "consent_record",
        "subject_id",
        "farmer",
        note="FM-002 grants and withdrawals, append-only",
    ),
    ExportSection("visits", "visit", "farmer_id", "farmer", note="FA-015 visits made to you"),
    ExportSection("orders", "order", "farmer_id", "farmer", note="ST-002 purchases"),
    ExportSection("payments", "payment", "farmer_id", "farmer", note="FA-021 payments"),
    ExportSection("khata_entries", "khata_entry", "farmer_id", "farmer", note="FA-022 credit"),
    ExportSection("diagnoses", "diagnosis", "farmer_id", "farmer", note="DX-001 crop doctor"),
    ExportSection(
        "data_requests", "data_request", "user_id", "user", note="NF-013 your own requests"
    ),
)


def _quote(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def _public(row: Any) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for column, value in row._mapping.items():
        name = str(column)
        if name in HIDDEN_COLUMNS or name.endswith(HIDDEN_SUFFIXES):
            continue
        out[name] = value.isoformat() if isinstance(value, datetime) else value
    return out


async def _rows(
    session: AsyncSession, section: ExportSection, key: uuid.UUID
) -> list[dict[str, Any]]:
    # nosec B608 (both): identifiers come from the reviewed export sections and go through
    # _quote; every value is a bound parameter.
    where = (
        f"{_quote(section.key)} IN (SELECT id FROM farm WHERE farmer_id = :key)"  # nosec B608
        if section.key_of == "farms"
        else f"{_quote(section.key)} = :key"
    )
    stmt = text(
        f"SELECT * FROM {_quote(section.table)} WHERE {where} ORDER BY {_quote(section.order_by)}"  # nosec B608
    )
    result = await session.execute(stmt, {"key": key})
    return [_public(row) for row in result]


def _account(user: User) -> dict[str, Any]:
    return {
        "id": str(user.id),
        "name": user.name,
        "phone": user.phone,
        "role": user.role,
        "status": user.status,
        "language": user.language,
        "created_at": user.created_at.isoformat() if user.created_at else None,
    }


def _farmer(farmer: Farmer) -> dict[str, Any]:
    return {
        "id": str(farmer.id),
        "name": farmer.name,
        "phone": farmer.phone,
        "phone_verified": farmer.phone_verified,
        "village_id": str(farmer.village_id),
        "landmark": farmer.landmark,
        "language": farmer.language,
        "consent_marketing": farmer.consent_marketing,
        "consent_version": farmer.consent_version,
        "land_ownership": farmer.land_ownership,
        "source": farmer.source,
        "registered_by": str(farmer.registered_by) if farmer.registered_by else None,
        "created_at": farmer.created_at.isoformat() if farmer.created_at else None,
    }


async def resolve_farmer(session: AsyncSession, user: User) -> Farmer | None:
    """The farmer record of an account, if the principal is a farmer."""
    if UserRole(user.role) != UserRole.FARMER:
        return None
    stmt = text("SELECT id FROM farmer WHERE user_id = :uid AND deleted_at IS NULL LIMIT 1")
    farmer_id = await session.scalar(stmt, {"uid": user.id})
    return await session.get(Farmer, farmer_id) if farmer_id else None


async def build_export(
    session: AsyncSession,
    *,
    user: User,
    farmer: Farmer | None,
    sections: Sequence[ExportSection] = SECTIONS,
    now: datetime | None = None,
) -> dict[str, Any]:
    """The access-right document for one principal. Empty sections are kept, so the reader
    can see that a category exists and holds nothing."""
    document: dict[str, Any] = {
        "generated_at": (now or datetime.now(UTC)).isoformat(),
        "tenant_id": str(user.tenant_id),
        "notice": (
            "Everything this company holds about you, as of the time above. Financial records "
            "(orders, payments, khata entries) are kept for eight years even after an erasure "
            "request, because Indian tax and company law requires it."
        ),
        "account": _account(user),
        "farmer": _farmer(farmer) if farmer is not None else None,
    }
    counts: dict[str, int] = {}
    for section in sections:
        key = user.id if section.key_of == "user" else (farmer.id if farmer else None)
        rows = await _rows(session, section, key) if key is not None else []
        document[section.name] = rows
        counts[section.name] = len(rows)
    document["counts"] = counts
    log.info(
        "data_export_built",
        tenant_id=str(user.tenant_id),
        user_id=str(user.id),
        farmer_id=str(farmer.id) if farmer else None,
        sections=len(sections),
        rows=sum(counts.values()),
    )
    return document
