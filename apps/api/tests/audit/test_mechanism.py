"""The generic mechanism: any mapped row carrying the base columns is audited on flush.

Proved with a scratch table that lives on its own metadata (so the RLS meta-test does not
see it) and is created/dropped by the owner role around the test.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime

import pytest
from sqlalchemy import String, text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from farmerapp.auth.models import User, UserRole
from farmerapp.db import audit
from farmerapp.db.base import BaseColumns
from farmerapp.db.models import AuditLog, Tenant
from farmerapp.db.rls import rls_statements
from farmerapp.db.session import set_tenant, tenant_scope
from farmerapp.jobs.seed import DEMO_TENANTS, SMALL, seed_demo
from tests.audit.conftest import audit_rows, one_audit_row


class ScratchBase(DeclarativeBase):
    pass


class Scratch(ScratchBase, BaseColumns):
    __tablename__ = "audit_scratch"

    label: Mapped[str] = mapped_column(String(50), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(16), nullable=True)
    token_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)


class Unaudited(ScratchBase, BaseColumns):
    __tablename__ = "audit_scratch_off"
    __audit__ = False

    label: Mapped[str] = mapped_column(String(50), nullable=False)


SCRATCH_DDL = (
    "CREATE TABLE audit_scratch (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), "
    "tenant_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), "
    "updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz, "
    "version integer NOT NULL DEFAULT 1, label varchar(50) NOT NULL, phone varchar(16), "
    "token_hash varchar(64))",
    "CREATE TABLE audit_scratch_off (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), "
    "tenant_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), "
    "updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz, "
    "version integer NOT NULL DEFAULT 1, label varchar(50) NOT NULL)",
)


@pytest.fixture
async def scratch_tables(migrate_engine: AsyncEngine) -> AsyncIterator[None]:
    async with migrate_engine.connect() as conn:
        await conn.execution_options(isolation_level="AUTOCOMMIT")
        for ddl in SCRATCH_DDL:
            await conn.execute(text(ddl))
        for table in ("audit_scratch", "audit_scratch_off"):
            for statement in rls_statements(table):
                await conn.execute(text(statement))
    try:
        yield
    finally:
        async with migrate_engine.connect() as conn:
            await conn.execution_options(isolation_level="AUTOCOMMIT")
            await conn.execute(text("DROP TABLE IF EXISTS audit_scratch, audit_scratch_off"))


ACTOR_ID = uuid.uuid4()


def _actor(tenant_id: uuid.UUID) -> audit.Actor:
    return audit.Actor(
        tenant_id=tenant_id,
        actor_id=ACTOR_ID,
        actor_role="owner",
        ip="198.51.100.7",
        device_id="dev-7",
        user_agent="pytest",
        trace_id="trace-7",
    )


async def test_scratch_model_create_update_delete_are_audited(
    scratch_tables: None, db_session: AsyncSession
) -> None:
    tenant_id = uuid.uuid4()
    await set_tenant(db_session, tenant_id)
    with audit.actor_scope(_actor(tenant_id)):
        row = Scratch(
            tenant_id=tenant_id, label="first", phone="+919876543210", token_hash="h" * 64
        )
        db_session.add(row)
        await db_session.flush()
        created = await one_audit_row(db_session, action="audit_scratch.create")
        assert created.entity == "audit_scratch" and created.entity_id == row.id
        assert created.tenant_id == tenant_id
        assert created.actor_id == ACTOR_ID and created.actor_role == "owner"
        assert (created.ip, created.device_id, created.user_agent, created.trace_id) == (
            "198.51.100.7",
            "dev-7",
            "pytest",
            "trace-7",
        )
        assert created.before is None
        assert created.after is not None
        assert created.after["id"] == str(row.id) and created.after["label"] == "first"
        assert created.after["phone"] == "+91******3210"  # masked
        assert "token_hash" not in created.after  # redacted
        assert "updated_at" not in created.after and "version" not in created.after

        row.label = "second"
        await db_session.flush()
        updated = await one_audit_row(db_session, action="audit_scratch.update")
        assert updated.before == {"id": str(row.id), "label": "first"}
        assert updated.after == {"id": str(row.id), "label": "second"}

        await db_session.delete(row)
        await db_session.flush()
        deleted = await one_audit_row(db_session, action="audit_scratch.delete")
        assert deleted.after is None
        assert deleted.before is not None and deleted.before["label"] == "second"
        assert deleted.before["phone"] == "+91******3210" and "token_hash" not in deleted.before


async def test_model_can_opt_out_of_auditing(
    scratch_tables: None, db_session: AsyncSession
) -> None:
    tenant_id = uuid.uuid4()
    await set_tenant(db_session, tenant_id)
    with audit.actor_scope(_actor(tenant_id)):
        db_session.add(Unaudited(tenant_id=tenant_id, label="quiet"))
        await db_session.flush()
    assert await audit_rows(db_session, entity="audit_scratch_off") == []


async def test_audit_rows_are_not_audited_themselves(db_session: AsyncSession) -> None:
    tenant_id = uuid.uuid4()
    await set_tenant(db_session, tenant_id)
    audit.record(
        db_session,
        action="test.event",
        entity="test",
        entity_id=uuid.uuid4(),
        tenant_id=tenant_id,
        after={"k": "v"},
    )
    await db_session.flush()
    rows = await audit_rows(db_session)
    assert [r.action for r in rows] == ["test.event"]


async def test_writes_without_actor_context_are_attributed_to_the_system(
    db_session: AsyncSession,
) -> None:
    assert audit.current_actor() is None
    tenant = Tenant(id=uuid.uuid4(), name="No Context Ltd")
    await set_tenant(db_session, tenant.id)
    db_session.add(tenant)
    db_session.add(User(tenant_id=tenant.id, phone="+919000000555", name="Nobody", role="owner"))
    await db_session.flush()
    for action in ("tenant.create", "user.create"):
        row = await one_audit_row(db_session, action=action)
        assert row.actor_id is None and row.actor_role == audit.SYSTEM_ROLE
        assert row.tenant_id == tenant.id
        assert row.ip is None and row.device_id is None and row.user_agent is None
    user_row = await one_audit_row(db_session, action="user.create")
    assert user_row.after is not None and user_row.after["phone"] == "+91******0555"


async def test_seed_creates_user_create_rows(db_session: AsyncSession) -> None:
    """The seed job runs as the system actor: ``user.create`` with ``before`` null."""
    result = await seed_demo(db_session, SMALL)
    for slug, tenant_id in result.tenants:
        async with tenant_scope(db_session, tenant_id):
            users = await audit_rows(db_session, action="user.create")
            demo = next(t for t in DEMO_TENANTS if t.slug == slug)
            assert len(users) == len(demo.all_users)
            assert all(r.before is None and r.after is not None for r in users)
            assert all(r.actor_id is None and r.actor_role == audit.SYSTEM_ROLE for r in users)
            assert {r.after["role"] for r in users if r.after} == {r.value for r in UserRole}
            tenants = await audit_rows(db_session, action="tenant.create")
            assert len(tenants) == 1 and tenants[0].entity_id == tenant_id
    # Re-running the (idempotent) seed changes nothing and audits nothing new.
    async with tenant_scope(db_session, result.tenant_id):
        before = len(await audit_rows(db_session))
    await seed_demo(db_session, SMALL)
    async with tenant_scope(db_session, result.tenant_id):
        assert len(await audit_rows(db_session, entity="user")) == len(DEMO_TENANTS[0].all_users)
        assert len(await audit_rows(db_session)) == before


async def test_actor_scope_nests_and_restores() -> None:
    outer = audit.system_actor(uuid.uuid4())
    inner = _actor(uuid.uuid4())
    assert audit.current_actor() is None
    with audit.actor_scope(outer):
        assert audit.current_actor() is outer
        with audit.actor_scope(inner):
            assert audit.current_actor() is inner
        assert audit.current_actor() is outer
    assert audit.current_actor() is None


def test_redaction_is_configured_in_one_place() -> None:
    assert {"code_hash", "token_hash"} <= audit.REDACTED_COLUMNS
    assert "phone" in audit.MASKED_COLUMNS
    payload = audit.redact(
        {
            "id": uuid.UUID(int=1),
            "phone": "+919876543210",
            "code_hash": "secret",
            "token_hash": "secret",
            "when": datetime(2026, 9, 17, tzinfo=UTC),
            "role": UserRole.OWNER,
            "n": 3,
        }
    )
    assert payload == {
        "id": "00000000-0000-0000-0000-000000000001",
        "phone": "+91******3210",
        "when": "2026-09-17T00:00:00+00:00",
        "role": "owner",
        "n": 3,
    }


def test_audit_log_model_is_lean() -> None:
    columns = {c.name for c in AuditLog.__table__.columns}
    assert columns == {
        "id",
        "tenant_id",
        "actor_id",
        "actor_role",
        "action",
        "entity",
        "entity_id",
        "before",
        "after",
        "ip",
        "device_id",
        "user_agent",
        "trace_id",
        "integrity",  # SEC-024: Play Integrity verdict of the request (Alembic 0024)
        "created_at",
    }
    assert getattr(AuditLog, "__audit__", True) is False


def test_record_needs_a_tenant() -> None:
    with pytest.raises(ValueError, match="tenant_id"):
        audit.record(
            object(), action="x.y", entity="x", entity_id=uuid.uuid4(), actor=audit.system_actor()
        )


def test_client_ip_and_phone_masking_edge_cases() -> None:
    from fastapi import Request

    def request(headers: list[tuple[bytes, bytes]], client: tuple[str, int] | None) -> Request:
        return Request(
            {"type": "http", "method": "GET", "path": "/", "headers": headers, "client": client}
        )

    assert audit.client_ip(request([], ("10.1.2.3", 1))) == "10.1.2.3"
    assert (
        audit.client_ip(request([(b"x-forwarded-for", b" , 10.0.0.1")], ("10.1.2.3", 1)))
        == "10.1.2.3"
    )
    assert (
        audit.client_ip(request([(b"x-forwarded-for", b"198.51.100.4, 10.0.0.1")], None))
        == "198.51.100.4"
    )
    assert audit.client_ip(request([], None)) is None
    assert audit.mask_phone("+9112") == "+91**"
    assert audit.mask_phone("12345") == "*1234"[:0] + "*2345"
