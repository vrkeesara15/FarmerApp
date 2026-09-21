"""NF-013 data-principal rights end to end: access, correction, erasure, grievance.

Each right is exercised the way a real request arrives: the principal asks in the app
(``/v1/me/*``), staff act on it in the console (``/v1/admin/data-requests/*``), and the
outcome is auditable. The erasure test is the important one — it proves the two obligations
that pull against each other are both honoured: the person stops being identifiable, and the
financial records stay for eight years (NF-012).
"""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import RefreshToken, User, UserRole, UserStatus
from farmerapp.db.models import AuditLog
from farmerapp.farmers.models import Farmer
from farmerapp.privacy.erasure import ERASED_NAME, retained_classes
from farmerapp.privacy.export import SECTIONS
from farmerapp.privacy.models import DataRequest, DataRequestType
from farmerapp.privacy.router import CORRECTABLE_FIELDS
from tests.authz.conftest import Bearer, World


def _problem(resp: Any, status: int, code: str) -> dict[str, Any]:
    assert resp.status_code == status, resp.text
    body: dict[str, Any] = resp.json()
    assert body["code"] == code
    return body


# --------------------------------------------------------------------------- grievance contact
async def test_the_grievance_contact_is_public(client: AsyncClient) -> None:
    """A data principal must be able to find out whom to complain to without signing in."""
    resp = await client.get("/v1/privacy/contact")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["officer_name"] and body["email"] and body["phone"]
    assert body["response_days"] == 30
    assert set(body["rights"]) == {"access", "correction", "erasure", "grievance"}


# --------------------------------------------------------------------------- access
async def test_a_farmer_exports_their_own_data(
    client: AsyncClient, bearer: Bearer, world: World
) -> None:
    farmer_user = world.a.user(UserRole.FARMER)
    resp = await client.get("/v1/me/data-export", headers=bearer(farmer_user))
    assert resp.status_code == 200, resp.text
    document = resp.json()

    assert document["account"]["id"] == str(farmer_user.id)
    assert document["account"]["phone"] == farmer_user.phone, "the principal sees their own phone"
    assert document["farmer"] is not None
    assert document["farmer"]["name"]
    assert "financial records" in document["notice"].lower()
    for section in SECTIONS:
        assert section.name in document, section.name
    assert set(document["counts"]) == {s.name for s in SECTIONS}


async def test_the_export_never_leaks_ciphertext_or_hashes(
    client: AsyncClient, bearer: Bearer, world: World
) -> None:
    resp = await client.get("/v1/me/data-export", headers=bearer(world.a.user(UserRole.FARMER)))
    body = resp.text
    for forbidden in ("phone_enc", "phone_hash", "landmark_enc", "code_hash", "token_hash"):
        assert forbidden not in body, forbidden


async def test_a_staff_export_serves_an_access_ticket(
    client: AsyncClient, bearer: Bearer, world: World, db_session: AsyncSession
) -> None:
    farmer_user = world.a.user(UserRole.FARMER)
    admin = world.a.user(UserRole.TENANT_ADMIN)
    row = DataRequest(
        tenant_id=farmer_user.tenant_id,
        type=DataRequestType.ACCESS.value,
        user_id=farmer_user.id,
        status="received",
        due_by=farmer_user.created_at,
    )
    db_session.add(row)
    await db_session.flush()

    resp = await client.get(f"/v1/admin/data-requests/{row.id}/export", headers=bearer(admin))
    assert resp.status_code == 200, resp.text
    assert resp.json()["account"]["id"] == str(farmer_user.id)

    # An officer may not read another principal's export.
    officer = world.a.user(UserRole.FIELD_OFFICER)
    forbidden = await client.get(
        f"/v1/admin/data-requests/{row.id}/export", headers=bearer(officer)
    )
    assert forbidden.status_code == 403


async def test_the_export_is_audited(
    client: AsyncClient, bearer: Bearer, world: World, db_session: AsyncSession
) -> None:
    await client.get("/v1/me/data-export", headers=bearer(world.a.user(UserRole.FARMER)))
    actions = (
        (await db_session.execute(select(AuditLog.action).where(AuditLog.action.like("privacy.%"))))
        .scalars()
        .all()
    )
    assert "privacy.access_export" in actions


# --------------------------------------------------------------------------- correction
async def test_a_farmer_asks_for_a_correction_and_staff_apply_it(
    client: AsyncClient, bearer: Bearer, world: World, db_session: AsyncSession, step_up: Bearer
) -> None:
    farmer_user = world.a.user(UserRole.FARMER)
    farmer_user_id = farmer_user.id
    admin = world.a.user(UserRole.TENANT_ADMIN)

    asked = await client.post(
        "/v1/me/correction-request",
        json={"changes": {"name": "Ramesh Kumar Reddy"}, "reason": "My name is spelt wrong"},
        headers=bearer(farmer_user),
    )
    assert asked.status_code == 201, asked.text
    ticket_id = asked.json()["ticket_id"]
    assert asked.json()["type"] == "correction"

    listing = (
        await client.get("/v1/admin/data-requests?type=correction", headers=bearer(admin))
    ).json()
    assert listing["items"][0]["requested_changes"] == {"name": "Ramesh Kumar Reddy"}

    applied = await client.post(
        f"/v1/admin/data-requests/{ticket_id}/apply-correction",
        headers=bearer(admin) | step_up(admin),
    )
    assert applied.status_code == 200, applied.text
    assert applied.json()["applied"] == {"name": "Ramesh Kumar Reddy"}
    assert applied.json()["request"]["status"] == "completed"

    db_session.expire_all()
    farmer = (
        await db_session.execute(select(Farmer).where(Farmer.user_id == farmer_user_id))
    ).scalar_one()
    assert farmer.name == "Ramesh Kumar Reddy"

    actions = (
        (await db_session.execute(select(AuditLog.action).where(AuditLog.action.like("privacy.%"))))
        .scalars()
        .all()
    )
    assert "privacy.correction_applied" in actions


async def test_applying_a_correction_needs_re_auth(
    client: AsyncClient, bearer: Bearer, world: World
) -> None:
    farmer_user = world.a.user(UserRole.FARMER)
    admin = world.a.user(UserRole.TENANT_ADMIN)
    ticket = (
        await client.post(
            "/v1/me/correction-request",
            json={"changes": {"language": "hi"}},
            headers=bearer(farmer_user),
        )
    ).json()
    resp = await client.post(
        f"/v1/admin/data-requests/{ticket['ticket_id']}/apply-correction", headers=bearer(admin)
    )
    _problem(resp, 401, "step_up_required")


@pytest.mark.parametrize(
    "changes",
    [
        {"role": "owner"},
        {"status": "active"},
        {"village_id": "00000000-0000-0000-0000-000000000000"},
        {"name": ""},
        {"name": "x" * 201},
        # Closed sets are checked here, not at flush time: a value that would trip a CHECK
        # constraint must be a 422 to the principal, never a 500 to the admin who applies it.
        {"land_ownership": "banana"},
        {"language": "fr"},
        {"phone": "not-a-number"},
        {"phone": "+15551230000"},
    ],
)
async def test_a_correction_cannot_ask_for_anything_else(
    client: AsyncClient, bearer: Bearer, world: World, changes: dict[str, str]
) -> None:
    """SEC-022: a correction ticket is not an authorisation to edit arbitrary columns."""
    resp = await client.post(
        "/v1/me/correction-request",
        json={"changes": changes},
        headers=bearer(world.a.user(UserRole.FARMER)),
    )
    _problem(resp, 422, "validation_error")


def test_the_correctable_fields_are_the_principals_own() -> None:
    assert {"name", "phone", "landmark", "language", "land_ownership"} == CORRECTABLE_FIELDS


def test_every_export_section_names_a_real_table_and_column() -> None:
    """A renamed column would make the export silently 500; fail here instead."""
    from farmerapp.db.base import Base

    for section in SECTIONS:
        table = Base.metadata.tables.get(section.table)
        assert table is not None, section.table
        assert section.key in table.columns, f"{section.table}.{section.key}"
        assert section.order_by in table.columns, f"{section.table}.{section.order_by}"
        assert section.key_of in {"farmer", "user", "farms"}, section.key_of
        assert section.note, f"{section.name} must say what it is"


# --------------------------------------------------------------------------- grievance
async def test_a_grievance_becomes_a_ticket_in_the_staff_queue(
    client: AsyncClient, bearer: Bearer, world: World
) -> None:
    farmer_user = world.a.user(UserRole.FARMER)
    raised = await client.post(
        "/v1/me/grievance",
        json={"subject": "Marketing SMS after I withdrew consent", "message": "I still get them."},
        headers=bearer(farmer_user),
    )
    assert raised.status_code == 201, raised.text
    assert raised.json()["type"] == "grievance"

    admin = world.a.user(UserRole.TENANT_ADMIN)
    listing = (
        await client.get("/v1/admin/data-requests?type=grievance", headers=bearer(admin))
    ).json()
    assert listing["items"][0]["subject"] == "Marketing SMS after I withdrew consent"
    assert listing["items"][0]["message"] == "I still get them."

    mine = (await client.get("/v1/me/data-requests", headers=bearer(farmer_user))).json()
    assert {t["type"] for t in mine} == {"grievance"}


async def test_a_grievance_needs_a_subject_and_a_message(
    client: AsyncClient, bearer: Bearer, world: World
) -> None:
    resp = await client.post(
        "/v1/me/grievance",
        json={"subject": "x", "message": ""},
        headers=bearer(world.a.user(UserRole.FARMER)),
    )
    _problem(resp, 422, "validation_error")


# --------------------------------------------------------------------------- erasure
async def test_erasure_anonymises_the_principal_and_keeps_the_financial_records(
    client: AsyncClient, bearer: Bearer, world: World, db_session: AsyncSession, step_up: Bearer
) -> None:
    farmer_user = world.a.user(UserRole.FARMER)
    farmer_user_id = farmer_user.id
    admin = world.a.user(UserRole.TENANT_ADMIN)
    orders_before = await db_session.scalar(text('SELECT count(*) FROM "order"'))
    payments_before = await db_session.scalar(text("SELECT count(*) FROM payment"))

    ticket = (
        await client.post(
            "/v1/me/deletion-request",
            json={"reason": "Stopped farming"},
            headers=bearer(farmer_user),
        )
    ).json()

    erased = await client.post(
        f"/v1/admin/data-requests/{ticket['ticket_id']}/erase",
        headers=bearer(admin) | step_up(admin),
    )
    assert erased.status_code == 200, erased.text
    body = erased.json()
    assert "farmer.name" in body["erased"] and "user.phone" in body["erased"]
    kept = {r["record_class"] for r in body["retained"]}
    assert "financial_records" in kept
    financial = next(r for r in body["retained"] if r["record_class"] == "financial_records")
    assert financial["until_days"] == 8 * 365
    assert body["request"]["status"] == "completed"
    assert body["request"]["erasure_report"]["erased"]

    db_session.expire_all()
    farmer = (
        await db_session.execute(select(Farmer).where(Farmer.user_id == farmer_user_id))
    ).scalar_one()
    assert farmer.name == ERASED_NAME
    assert farmer.landmark is None
    assert farmer.consent_marketing is False
    assert farmer.phone.startswith("+9170000")

    user = await db_session.get_one(User, farmer_user_id)
    assert user.name == ERASED_NAME
    assert user.status == UserStatus.DISABLED

    # The books still balance.
    assert await db_session.scalar(text('SELECT count(*) FROM "order"')) == orders_before
    assert await db_session.scalar(text("SELECT count(*) FROM payment")) == payments_before


async def test_erasure_revokes_every_session(
    client: AsyncClient, bearer: Bearer, world: World, db_session: AsyncSession, step_up: Bearer
) -> None:
    """SEC-020 / SEC-025: an erased account cannot be refreshed back into."""
    farmer_user = world.a.user(UserRole.FARMER)
    admin = world.a.user(UserRole.TENANT_ADMIN)
    ticket = (
        await client.post("/v1/me/deletion-request", json={}, headers=bearer(farmer_user))
    ).json()
    await client.post(
        f"/v1/admin/data-requests/{ticket['ticket_id']}/erase",
        headers=bearer(admin) | step_up(admin),
    )
    live = (
        (
            await db_session.execute(
                select(RefreshToken).where(
                    RefreshToken.user_id == farmer_user.id, RefreshToken.revoked_at.is_(None)
                )
            )
        )
        .scalars()
        .all()
    )
    assert live == []


async def test_erasure_is_idempotent_and_needs_a_deletion_ticket(
    client: AsyncClient, bearer: Bearer, world: World, step_up: Bearer
) -> None:
    farmer_user = world.a.user(UserRole.FARMER)
    admin = world.a.user(UserRole.TENANT_ADMIN)
    grievance = (
        await client.post(
            "/v1/me/grievance",
            json={"subject": "Wrong ticket type", "message": "erase must refuse this"},
            headers=bearer(farmer_user),
        )
    ).json()
    wrong = await client.post(
        f"/v1/admin/data-requests/{grievance['ticket_id']}/erase",
        headers=bearer(admin) | step_up(admin),
    )
    _problem(wrong, 409, "invalid_transition")

    ticket = (
        await client.post("/v1/me/deletion-request", json={}, headers=bearer(farmer_user))
    ).json()
    first = await client.post(
        f"/v1/admin/data-requests/{ticket['ticket_id']}/erase",
        headers=bearer(admin) | step_up(admin),
    )
    assert first.status_code == 200
    again = await client.post(
        f"/v1/admin/data-requests/{ticket['ticket_id']}/erase",
        headers=bearer(admin) | step_up(admin),
    )
    _problem(again, 409, "invalid_transition")


async def test_erasure_needs_re_auth(client: AsyncClient, bearer: Bearer, world: World) -> None:
    farmer_user = world.a.user(UserRole.FARMER)
    ticket = (
        await client.post("/v1/me/deletion-request", json={}, headers=bearer(farmer_user))
    ).json()
    resp = await client.post(
        f"/v1/admin/data-requests/{ticket['ticket_id']}/erase",
        headers=bearer(world.a.user(UserRole.TENANT_ADMIN)),
    )
    _problem(resp, 401, "step_up_required")


# --------------------------------------------------------------------------- the exceptions
async def test_staff_can_read_what_an_erasure_must_keep(
    client: AsyncClient, bearer: Bearer, world: World
) -> None:
    """The operator sees the NF-012 exceptions before they confirm an erasure."""
    resp = await client.get(
        "/v1/admin/data-requests/retention-exceptions",
        headers=bearer(world.a.user(UserRole.OWNER)),
    )
    assert resp.status_code == 200, resp.text
    classes = {row["record_class"]: row for row in resp.json()}
    assert classes["financial_records"]["until_days"] == 8 * 365
    assert classes["visit_records"]["until_days"] == 7 * 365
    assert classes["audit_logs"]["until_days"] >= 365


def test_the_retained_classes_come_from_the_retention_policy() -> None:
    names = {r.record_class for r in retained_classes()}
    assert {"financial_records", "visit_records", "audit_logs"} <= names
    assert "photos" not in names, "photos are archived, not retained against an erasure"
