"""SEC-026 in the database: ciphertext at rest, lookups and uniqueness by hash, the audit
trail, the legacy (not yet backfilled) fallback and the idempotent, resumable backfill."""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any, cast

import pytest
from httpx import AsyncClient
from sqlalchemy import Table, select, text, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import User, UserRole
from farmerapp.auth.otp import find_user_by_phone
from farmerapp.db.models import AuditLog
from farmerapp.db.session import tenant_scope
from farmerapp.farmers.models import Farmer
from farmerapp.pii import crypto
from farmerapp.pii.backfill import backfill_tenant
from farmerapp.pii.crypto import FieldCipher, get_cipher, phone_hash
from farmerapp.pii.keys import load_or_create
from farmerapp.pii.lookup import phone_match
from farmerapp.pii.models import TenantDataKey
from tests.farmers.write_fixtures import WriteCtx

PHONE = "+919000199001"
FARMER = cast(Table, Farmer.__table__)


async def _register(client: AsyncClient, ctx: WriteCtx, **extra: Any) -> dict[str, Any]:
    resp = await client.post("/v1/farmers", json=ctx.farmer(**extra), headers=ctx.headers)
    assert resp.status_code == 201, resp.text
    body: dict[str, Any] = resp.json()
    return body


async def _raw(session: AsyncSession, table: str, row_id: uuid.UUID | str) -> Any:
    columns = "phone, phone_enc, phone_hash" + (
        ", landmark, landmark_enc" if table == "farmer" else ""
    )
    return (
        await session.execute(
            text(f'SELECT {columns} FROM "{table}" WHERE id = :id'), {"id": str(row_id)}
        )
    ).one()


@pytest.fixture
def savepoints(db_session: AsyncSession) -> Any:
    """``backfill_tenant(sessions=...)``: one savepoint per batch inside the test transaction."""

    @asynccontextmanager
    async def sessions(tenant_id: uuid.UUID) -> AsyncIterator[AsyncSession]:
        async with tenant_scope(db_session, tenant_id), db_session.begin_nested():
            yield db_session

    return sessions


# ------------------------------------------------------------------ at rest
async def test_phone_and_landmark_are_ciphertext_at_rest(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    body = await _register(client, ctx)
    assert body["phone"] == PHONE and body["landmark"] == "Near the temple"  # API: plaintext
    async with tenant_scope(db_session, ctx.tenant_id):
        raw = await _raw(db_session, "farmer", body["id"])
        assert raw.phone is None and raw.landmark is None  # no plaintext column written
        assert raw.phone_enc and PHONE.encode() not in bytes(raw.phone_enc)
        assert raw.landmark_enc and b"temple" not in bytes(raw.landmark_enc)
        assert raw.phone_hash == phone_hash(PHONE)
        cipher = get_cipher()
        assert cipher.decrypt(ctx.tenant_id, "farmer", "phone", bytes(raw.phone_enc)) == PHONE
        # The key is the tenant's: stored wrapped, never in plaintext.
        key = (
            await db_session.execute(
                select(TenantDataKey).where(TenantDataKey.tenant_id == ctx.tenant_id)
            )
        ).scalar_one()
        assert key.key_version == 1 and key.kek_backend == "local" and len(key.wrapped_key) > 32


async def test_updates_reencrypt_and_audit_rows_are_masked(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    body = await _register(client, ctx)
    resp = await client.patch(
        f"/v1/farmers/{body['id']}", json={"landmark": "By the tank"}, headers=ctx.headers
    )
    assert resp.status_code == 200 and resp.json()["landmark"] == "By the tank"
    async with tenant_scope(db_session, ctx.tenant_id):
        rows = (
            (
                await db_session.execute(
                    select(AuditLog)
                    .where(AuditLog.entity == "farmer", AuditLog.entity_id == uuid.UUID(body["id"]))
                    .order_by(AuditLog.created_at)
                )
            )
            .scalars()
            .all()
        )
    created, updated = rows[0], rows[-1]
    assert created.after is not None and updated.after is not None and updated.before is not None
    assert created.after["phone"] == "+91******9001" and created.after["landmark"] == "[encrypted]"
    assert (
        updated.after["landmark"] == "[encrypted]" and updated.before["landmark"] == "[encrypted]"
    )
    for row in rows:
        for payload in (row.before or {}, row.after or {}):
            assert not {"phone_enc", "phone_hash", "landmark_enc", "phone_plain"} & set(payload)
            assert "9000199001" not in str(payload) and "tank" not in str(payload)


async def test_same_value_write_is_not_a_change(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    body = await _register(client, ctx)
    async with tenant_scope(db_session, ctx.tenant_id):
        farmer = await db_session.get_one(Farmer, uuid.UUID(body["id"]))
        version = farmer.version
        farmer.landmark = "Near the temple"
        farmer.phone = PHONE
        await db_session.flush()
        assert farmer.version == version


# ------------------------------------------------------------------ lookups by hash
async def test_duplicate_checks_and_pos_lookup_use_the_hash(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    await _register(client, ctx)
    again = await client.post(
        "/v1/farmers", json=ctx.farmer(phone="9000199001"), headers=ctx.headers
    )
    assert again.status_code == 409 and again.json()["code"] == "farmer_phone_exists"
    staff = ctx.world.a.user(UserRole.STORE_MANAGER)
    as_staff = await client.post(
        "/v1/farmers", json=ctx.farmer(phone=staff.phone), headers=ctx.headers
    )
    assert as_staff.status_code == 422 and as_staff.json()["code"] == "farmer_phone_is_staff"
    async with tenant_scope(db_session, ctx.tenant_id):
        found = (
            await db_session.execute(select(Farmer).where(phone_match(Farmer, "09000199001")))
        ).scalar_one()
        assert found.phone == PHONE


async def test_phone_hash_is_unique_per_tenant_only(
    ctx: WriteCtx, db_session: AsyncSession
) -> None:
    tenant_a, tenant_b = ctx.world.a.tenant.id, ctx.world.b.tenant.id
    async with tenant_scope(db_session, tenant_b):
        db_session.add(User(tenant_id=tenant_b, phone="+919812345670", name="B", role="owner"))
        await db_session.flush()
    async with tenant_scope(db_session, tenant_a):
        db_session.add(User(tenant_id=tenant_a, phone="+919812345670", name="A", role="owner"))
        await db_session.flush()  # another tenant: fine
        with pytest.raises(IntegrityError, match="uq_user_tenant_id_phone_hash"):
            async with db_session.begin_nested():
                db_session.add(
                    User(tenant_id=tenant_a, phone="9812345670", name="A2", role="owner")
                )
                await db_session.flush()


async def test_login_finds_encrypted_and_legacy_users_by_hash(
    ctx: WriteCtx, db_session: AsyncSession
) -> None:
    officer = ctx.officer
    assert (await find_user_by_phone(db_session, officer.phone)) is not None
    # A row written by the previous release: plain phone only, no hash, no ciphertext.
    legacy_id = uuid.uuid4()
    async with tenant_scope(db_session, ctx.tenant_id):
        await db_session.execute(
            text(
                'INSERT INTO "user" (id, tenant_id, phone, name, role) '
                "VALUES (:id, :t, :p, 'Legacy', 'accountant')"
            ),
            {"id": str(legacy_id), "t": str(ctx.tenant_id), "p": "+919812300000"},
        )
    user = await find_user_by_phone(db_session, "+919812300000")
    assert user is not None and user.id == legacy_id and user.phone == "+919812300000"


# ------------------------------------------------------------------ keys
async def test_another_process_loads_the_same_tenant_key(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession
) -> None:
    body = await _register(client, ctx)
    async with tenant_scope(db_session, ctx.tenant_id):
        raw = await _raw(db_session, "farmer", body["id"])
    original = get_cipher()
    fresh = FieldCipher(original.wrapper)  # a new process: empty key cache, same KEK
    try:
        crypto.set_cipher(fresh)
        bind: Any = db_session.bind
        await load_or_create(bind.engine, ctx.tenant_id, fresh)
        assert fresh.decrypt(ctx.tenant_id, "farmer", "phone", bytes(raw.phone_enc)) == PHONE
    finally:
        crypto.set_cipher(original)


# ------------------------------------------------------------------ backfill (migrate step)
async def _make_legacy(session: AsyncSession, tenant_id: uuid.UUID) -> list[uuid.UUID]:
    """Turn the tenant's rows back into pre-0025 rows: plain values, no hash, no ciphertext."""
    async with tenant_scope(session, tenant_id):
        farmers = (await session.execute(select(Farmer).limit(3))).scalars().all()
        ids = [f.id for f in farmers]
        for f in farmers:
            phone, landmark = f.phone, f.landmark or "Old landmark"
            await session.execute(
                update(FARMER)
                .where(FARMER.c.id == f.id)
                .values(
                    phone=phone,
                    phone_enc=None,
                    phone_hash=None,
                    landmark=landmark,
                    landmark_enc=None,
                )
            )
        session.expire_all()
    return ids


async def test_backfill_encrypts_legacy_rows_idempotently(
    ctx: WriteCtx, db_session: AsyncSession, savepoints: Any
) -> None:
    tenant_id = ctx.tenant_id
    ids = await _make_legacy(db_session, tenant_id)
    first = await backfill_tenant(tenant_id, batch_size=2, sessions=savepoints)
    assert first.tables["farmer"].changed >= len(ids)
    assert first.tables["farmer"].remaining == 0 and first.tables["user"].remaining == 0
    async with tenant_scope(db_session, tenant_id):
        for fid in ids:
            raw = await _raw(db_session, "farmer", fid)
            assert raw.phone_enc is not None and raw.landmark_enc is not None
            assert raw.phone_hash == phone_hash(raw.phone)  # plain kept for rollback
            farmer = await db_session.get_one(Farmer, fid)
            assert farmer.phone == raw.phone
    second = await backfill_tenant(tenant_id, batch_size=2, sessions=savepoints)
    assert second.changed == 0 and second.remaining == 0  # idempotent

    cleared = await backfill_tenant(tenant_id, mode="clear", sessions=savepoints)
    assert cleared.changed >= len(ids) and cleared.remaining == 0
    async with tenant_scope(db_session, tenant_id):
        raw = await _raw(db_session, "farmer", ids[0])
        assert raw.phone is None and raw.landmark is None
    restored = await backfill_tenant(tenant_id, mode="restore", sessions=savepoints)
    assert restored.changed >= len(ids)
    async with tenant_scope(db_session, tenant_id):
        raw = await _raw(db_session, "farmer", ids[0])
        assert raw.phone is not None and raw.phone_hash == phone_hash(raw.phone)
        audit_rows = (
            (await db_session.execute(select(AuditLog).where(AuditLog.action == "pii.backfill")))
            .scalars()
            .all()
        )
        assert len(audit_rows) == 4 and audit_rows[0].actor_role == "system"


async def test_backfill_resumes_after_an_interruption(
    ctx: WriteCtx, db_session: AsyncSession, savepoints: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    tenant_id = ctx.tenant_id
    await _make_legacy(db_session, tenant_id)
    cipher = get_cipher()
    real = cipher.encrypt
    calls = {"n": 0}

    def flaky(*args: Any) -> bytes:
        calls["n"] += 1
        if calls["n"] == 3:
            raise RuntimeError("worker killed")
        return real(*args)

    monkeypatch.setattr(cipher, "encrypt", flaky)
    with pytest.raises(RuntimeError, match="worker killed"):
        await backfill_tenant(tenant_id, batch_size=1, sessions=savepoints)
    monkeypatch.setattr(cipher, "encrypt", real)
    done = await backfill_tenant(tenant_id, batch_size=1, sessions=savepoints)
    assert done.remaining == 0 and done.tables["farmer"].changed >= 1


async def test_backfill_counts_legacy_duplicates_as_conflicts(
    ctx: WriteCtx, db_session: AsyncSession, savepoints: Any
) -> None:
    tenant_id = ctx.tenant_id
    async with tenant_scope(db_session, tenant_id):
        farmers = (await db_session.execute(select(Farmer).limit(2))).scalars().all()
        keep, dup = farmers[0], farmers[1]
        await db_session.execute(
            update(FARMER)
            .where(FARMER.c.id == dup.id)
            .values(phone=keep.phone[3:], phone_enc=None, phone_hash=None)  # "98..." form
        )
    report = await backfill_tenant(tenant_id, sessions=savepoints)
    assert report.tables["farmer"].conflicts == 1 and report.tables["farmer"].remaining == 1


async def test_plaintext_writes_switch(
    client: AsyncClient, ctx: WriteCtx, db_session: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    """``PII_PLAINTEXT_WRITES=true`` (rollout safety) also fills the legacy column."""
    from farmerapp.settings import get_settings

    monkeypatch.setattr(get_settings(), "pii_plaintext_writes", True)
    body = await _register(client, ctx, phone="+919000199077")
    async with tenant_scope(db_session, ctx.tenant_id):
        raw = await _raw(db_session, "farmer", body["id"])
    assert raw.phone == "+919000199077" and raw.phone_enc is not None
    with pytest.raises(ValueError, match="PII_PLAINTEXT_WRITES"):
        await backfill_tenant(ctx.tenant_id, mode="clear")


def test_pii_backfill_command(monkeypatch: pytest.MonkeyPatch) -> None:
    from typer.testing import CliRunner

    from farmerapp.jobs.cli import cli
    from farmerapp.pii import backfill as backfill_mod

    seen: list[tuple[Any, ...]] = []
    tenant = uuid.uuid4()

    async def fake_run(tenant_ids: Any, *, mode: Any, batch_size: int) -> list[Any]:
        seen.append((tuple(tenant_ids), mode, batch_size))
        report = backfill_mod.BackfillReport(tenant_id=tenant_ids[0], mode=mode)
        report.tables["farmer"] = backfill_mod.TableReport(scanned=3, changed=2, conflicts=1)
        return [report]

    monkeypatch.setattr(backfill_mod, "run_backfill", fake_run)
    runner = CliRunner()
    result = runner.invoke(cli, ["pii-backfill", "--tenant-id", str(tenant), "--batch-size", "7"])
    assert result.exit_code == 0, result.output
    assert f"pii-backfill (encrypt): tenant={tenant} changed=2 remaining=0" in result.output
    assert "farmer scanned=3 changed=2 conflicts=1 remaining=0" in result.output
    for flag, mode in (("--clear-plaintext", "clear"), ("--restore-plaintext", "restore")):
        assert runner.invoke(cli, ["pii-backfill", "--tenant-id", str(tenant), flag]).exit_code == 0
        assert seen[-1][1] == mode
    both = runner.invoke(
        cli,
        ["pii-backfill", "--tenant-id", str(tenant), "--clear-plaintext", "--restore-plaintext"],
    )
    assert both.exit_code != 0
    assert seen[0] == ((tenant,), "encrypt", 7)
