"""RLS fixtures (FA-003 / SEC-012).

``two_tenants`` writes one tenant, user, OTP challenge and refresh token for tenant A and for
tenant B through the *app* role (each under its own tenant scope), then leaves the session
unscoped so every test states explicitly which tenant it acts as. ``world`` / ``bearer`` are
the SEC-006 fixtures (two seeded tenants, minted tokens) reused for the API-level proofs.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.session import clear_tenant, tenant_scope
from tests.authz.conftest import bearer, world  # noqa: F401  (fixtures re-exported)

NOW = datetime(2026, 9, 17, 9, 0, tzinfo=UTC)


@dataclass(frozen=True)
class TenantRows:
    tenant_id: uuid.UUID
    user_id: uuid.UUID
    phone: str
    otp_id: uuid.UUID
    refresh_id: uuid.UUID
    token_hash: str


@dataclass(frozen=True)
class TwoTenants:
    a: TenantRows
    b: TenantRows

    def rows(self, tenant: str) -> TenantRows:
        return self.a if tenant == "a" else self.b


TABLES = ("tenant", "user", "otp_challenge", "refresh_token")


async def _write_tenant(session: AsyncSession, label: str, phone: str) -> TenantRows:
    rows = TenantRows(
        tenant_id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        phone=phone,
        otp_id=uuid.uuid4(),
        refresh_id=uuid.uuid4(),
        token_hash=uuid.uuid4().hex + uuid.uuid4().hex,
    )
    async with tenant_scope(session, rows.tenant_id):
        await session.execute(
            text("INSERT INTO tenant (id, tenant_id, name, slug) VALUES (:t, :t, :n, :s)"),
            {"t": rows.tenant_id, "n": f"Tenant {label}", "s": f"rls-{label}"},
        )
        await session.execute(
            text(
                'INSERT INTO "user" (id, tenant_id, phone, name, role, created_at) '
                "VALUES (:u, :t, :p, :n, 'owner', :c)"
            ),
            {"u": rows.user_id, "t": rows.tenant_id, "p": phone, "n": f"Owner {label}", "c": NOW},
        )
        await session.execute(
            text(
                "INSERT INTO otp_challenge (id, tenant_id, phone, purpose, code_hash, expires_at, "
                "window_started_at, channel, user_id) VALUES "
                "(:o, :t, :p, 'login', 'x', :e, :w, 'sms', :u)"
            ),
            {
                "o": rows.otp_id,
                "t": rows.tenant_id,
                "p": phone,
                "e": NOW + timedelta(minutes=5),
                "w": NOW,
                "u": rows.user_id,
            },
        )
        await session.execute(
            text(
                "INSERT INTO refresh_token (id, tenant_id, user_id, family_id, token_hash, "
                "expires_at) VALUES (:r, :t, :u, :f, :h, :e)"
            ),
            {
                "r": rows.refresh_id,
                "t": rows.tenant_id,
                "u": rows.user_id,
                "f": uuid.uuid4(),
                "h": rows.token_hash,
                "e": NOW + timedelta(days=30),
            },
        )
    return rows


@pytest.fixture
async def two_tenants(db_session: AsyncSession) -> TwoTenants:
    a = await _write_tenant(db_session, "a", "+919000000001")
    b = await _write_tenant(db_session, "b", "+919100000001")
    await clear_tenant(db_session)
    return TwoTenants(a=a, b=b)
