"""WC-103 backend: audit log filters for the C103 viewer and the step-up CSV export."""

from __future__ import annotations

import csv
import io
import uuid
from datetime import timedelta

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.audit.router import EXPORT_COLUMNS
from farmerapp.auth.clock import FakeClock
from farmerapp.auth.models import User
from farmerapp.db import audit
from farmerapp.db.models import Tenant
from tests.admin.conftest import Mint, audit_rows, problem

KNOWN = uuid.UUID("abcdef01-2345-6789-abcd-ef0123456789")


async def _seed(session: AsyncSession, tenant: Tenant, owner: User, officer: User) -> None:
    owner_actor = audit.Actor(tenant_id=tenant.id, actor_id=owner.id, actor_role="owner")
    officer_actor = audit.Actor(
        tenant_id=tenant.id, actor_id=officer.id, actor_role="field_officer"
    )
    audit.record(
        session,
        action="user.update",
        entity="user",
        entity_id=KNOWN,
        actor=owner_actor,
        after={"note": '=HYPERLINK("http://evil")'},
    )
    audit.record(
        session, action="user.force_logout", entity="user", entity_id=officer.id, actor=owner_actor
    )
    audit.record(
        session, action="visit.create", entity="visit", entity_id=uuid.uuid4(), actor=officer_actor
    )
    await session.flush()


async def test_filters(
    client: AsyncClient,
    tenant: Tenant,
    owner: User,
    officer: User,
    auditor: User,
    bearer: Mint,
    db_session: AsyncSession,
) -> None:
    await _seed(db_session, tenant, owner, officer)
    headers = bearer(auditor)

    async def actions(**params: str) -> list[str]:
        resp = await client.get("/v1/audit-logs", params=params, headers=headers)
        assert resp.status_code == 200, resp.text
        return sorted(item["action"] for item in resp.json()["items"])

    assert await actions(actor_role="field_officer") == ["visit.create"]
    # fixtures created the users (``user.create``); the prefix matches them too
    assert set(await actions(action="user.")) == {"user.create", "user.force_logout", "user.update"}
    assert await actions(action="user.update") == ["user.update"]
    assert await actions(q="abcdef01") == ["user.update"]
    assert await actions(q="ABCDEF01-2345") == ["user.update"]
    assert await actions(actor_id=str(owner.id), entity="user") == [
        "user.force_logout",
        "user.update",
    ]
    resp = await client.get("/v1/audit-logs", params={"q": "x%"}, headers=headers)
    assert resp.status_code == 422  # free text is an id fragment, never a pattern


async def test_export_csv_needs_step_up_and_is_audited(
    client: AsyncClient,
    tenant: Tenant,
    owner: User,
    officer: User,
    auditor: User,
    bearer: Mint,
    admin_headers: Mint,
    db_session: AsyncSession,
    clock: FakeClock,
) -> None:
    await _seed(db_session, tenant, owner, officer)
    problem(
        await client.get("/v1/audit-logs/export", headers=bearer(auditor)), 401, "step_up_required"
    )

    resp = await client.get(
        "/v1/audit-logs/export",
        params={"action": "user.", "actor_id": str(owner.id)},
        headers=admin_headers(auditor),
    )
    assert resp.status_code == 200, resp.text
    assert resp.headers["content-type"].startswith("text/csv")
    assert "attachment" in resp.headers["content-disposition"]
    rows = list(csv.reader(io.StringIO(resp.text)))
    assert tuple(rows[0]) == EXPORT_COLUMNS
    body = rows[1:]
    assert sorted(r[1] for r in body) == ["user.force_logout", "user.update"]
    update = next(r for r in body if r[1] == "user.update")
    after = update[EXPORT_COLUMNS.index("after")]
    assert after.startswith('{"note": "=HYPERLINK')  # JSON starts with "{": not a formula
    assert update[EXPORT_COLUMNS.index("entity_id")] == str(KNOWN)

    (row,) = await audit_rows(db_session, action="audit_log.export")
    assert row.actor_id == auditor.id
    assert row.after == {"filters": {"action": "user.", "actor_id": str(owner.id)}, "rows": 2}

    # date range: nothing after tomorrow
    resp = await client.get(
        "/v1/audit-logs/export",
        params={"from": (clock.now() + timedelta(days=3650)).isoformat()},
        headers=admin_headers(auditor),
    )
    assert resp.status_code == 200 and len(list(csv.reader(io.StringIO(resp.text)))) == 1


def test_formula_cells_are_neutralised() -> None:
    from farmerapp.audit.router import _cell

    assert _cell("=1+1") == "'=1+1"
    assert _cell("-5") == "'-5"
    assert _cell("@SUM") == "'@SUM"
    assert _cell("plain") == "plain"
    assert _cell(None) == ""
    assert _cell({"a": 1}) == '{"a": 1}'
