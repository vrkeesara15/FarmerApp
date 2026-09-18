"""The first migration must install the extensions and the tenant table (SPEC 8.2)."""

from __future__ import annotations

import uuid

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.models import Tenant
from farmerapp.db.session import set_tenant

BASE_COLUMNS = {"id", "tenant_id", "created_at", "updated_at", "deleted_at", "version"}
TENANT_COLUMNS = BASE_COLUMNS | {"name", "plan", "branding", "settings", "slug"}
USER_COLUMNS = BASE_COLUMNS | {
    "phone",
    "name",
    "role",
    "store_id",
    "cluster_id",
    "language",
    "status",
    "device_id",
}
OTP_COLUMNS = BASE_COLUMNS | {
    "phone",
    "purpose",
    "code_hash",
    "expires_at",
    "attempts",
    "resend_count",
    "window_started_at",
    "channel",
    "sms_sent_at",
    "whatsapp_sent_at",
    "delivered_at",
    "consumed_at",
    "locked_until",
    "provider_ref",
    "user_id",
    "device_id",
}
REFRESH_COLUMNS = BASE_COLUMNS | {
    "user_id",
    "family_id",
    "token_hash",
    "device_id",
    "device_name",
    "expires_at",
    "revoked_at",
    "replaced_by",
}


async def test_extensions_installed(db_session: AsyncSession) -> None:
    rows = await db_session.execute(
        text("SELECT extname FROM pg_extension WHERE extname IN ('postgis','vector','pg_trgm')")
    )
    assert {r[0] for r in rows} == {"postgis", "vector", "pg_trgm"}


async def test_tenant_has_base_columns(db_session: AsyncSession) -> None:
    rows = await db_session.execute(
        text(
            "SELECT column_name, data_type, is_nullable FROM information_schema.columns "
            "WHERE table_name = 'tenant'"
        )
    )
    cols = {name: (dtype, nullable) for name, dtype, nullable in rows}
    assert set(cols) == TENANT_COLUMNS
    assert cols["id"] == ("uuid", "NO")
    assert cols["tenant_id"] == ("uuid", "NO")
    assert cols["created_at"][0] == "timestamp with time zone"
    assert cols["updated_at"][0] == "timestamp with time zone"
    assert cols["deleted_at"] == ("timestamp with time zone", "YES")
    assert cols["version"] == ("integer", "NO")
    assert cols["branding"][0] == "jsonb"
    assert cols["settings"][0] == "jsonb"


async def test_tenant_insert_defaults_and_rollback(db_session: AsyncSession) -> None:
    tenant = Tenant(name="FCC")
    db_session.add(tenant)
    await db_session.flush()
    assert tenant.tenant_id == tenant.id
    assert tenant.version == 1
    assert tenant.created_at is not None
    assert tenant.deleted_at is None

    tenant.name = "FCC Agro"
    await db_session.flush()
    await db_session.refresh(tenant)
    assert tenant.version == 2
    assert tenant.plan == "pilot"
    assert tenant.branding == {} and tenant.settings == {}

    await set_tenant(db_session, tenant.id)
    bound = await db_session.scalar(text("SELECT current_setting('app.tenant_id', true)"))
    assert bound == str(tenant.id)

    found = await db_session.scalar(select(Tenant).where(Tenant.id == tenant.id))
    assert found is not None


async def test_set_tenant_none_is_noop(db_session: AsyncSession) -> None:
    await set_tenant(db_session, None)
    bound = await db_session.scalar(text("SELECT current_setting('app.tenant_id', true)"))
    assert bound in (None, "")


async def test_previous_test_rows_were_rolled_back(db_session: AsyncSession) -> None:
    count = await db_session.scalar(select(text("count(*)")).select_from(Tenant))
    assert count == 0
    assert uuid.UUID(int=0)  # keep uuid import meaningful for readers


async def _columns(db_session: AsyncSession, table: str) -> set[str]:
    rows = await db_session.execute(
        text("SELECT column_name FROM information_schema.columns WHERE table_name = :t"),
        {"t": table},
    )
    return {r[0] for r in rows}


async def test_0002_auth_tables(db_session: AsyncSession) -> None:
    """FA-001 migration: user, otp_challenge, refresh_token (all with the base columns)."""
    assert await _columns(db_session, "user") == USER_COLUMNS
    assert await _columns(db_session, "otp_challenge") == OTP_COLUMNS
    assert await _columns(db_session, "refresh_token") == REFRESH_COLUMNS
    constraints = await db_session.execute(
        text(
            "SELECT conname FROM pg_constraint WHERE conrelid IN "
            "('\"user\"'::regclass, 'refresh_token'::regclass, 'tenant'::regclass)"
        )
    )
    names = {r[0] for r in constraints}
    assert "uq_user_tenant_id" in names  # (tenant_id, phone)
    assert "uq_refresh_token_token_hash" in names
    assert "uq_tenant_slug" in names
    assert "ck_user_role" in names and "ck_user_status" in names
