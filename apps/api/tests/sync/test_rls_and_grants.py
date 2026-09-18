"""Every table added by migration 0006 is under RLS (meta-test), ``sync_change`` is
append-only for the app role, and none of the bookkeeping tables audits itself."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

from farmerapp.api.idempotency import IdempotencyKey
from farmerapp.db.base import Base
from farmerapp.db.rls import APPEND_ONLY_TABLES, rls_violations
from farmerapp.db.session import clear_tenant, tenant_scope
from farmerapp.farmers.models import FarmPhoto
from farmerapp.sync.models import SyncChange, SyncOp
from farmerapp.uploads.models import UploadChunk, UploadSession

NEW_TABLES = (
    "sync_op",
    "sync_change",
    "idempotency_key",
    "upload_session",
    "upload_chunk",
    "farm_photo",
)


def test_new_tables_are_mapped() -> None:
    assert set(NEW_TABLES) <= {t.name for t in Base.metadata.sorted_tables}
    assert "sync_change" in APPEND_ONLY_TABLES
    for model in (SyncOp, SyncChange, IdempotencyKey, UploadSession, UploadChunk):
        assert getattr(model, "__audit__", True) is False, model
    assert getattr(FarmPhoto, "__audit__", True) is True  # farm photos are data, audited


async def test_new_tables_pass_the_rls_meta_check(migrate_engine: AsyncEngine) -> None:
    async with migrate_engine.connect() as conn:
        assert await conn.run_sync(rls_violations, NEW_TABLES) == []


@pytest.mark.parametrize("table", NEW_TABLES)
async def test_rows_are_invisible_outside_their_tenant(
    db_session: AsyncSession, table: str
) -> None:
    tid = uuid.uuid4()
    async with tenant_scope(db_session, tid):
        await db_session.execute(
            text("INSERT INTO tenant (id, tenant_id, name) VALUES (:t, :t, 'RLS')"), {"t": tid}
        )
        if table == "sync_op":
            db_session.add(
                SyncOp(
                    tenant_id=tid,
                    op_id=uuid.uuid4(),
                    device_id="d",
                    actor_id=None,
                    entity="farmer",
                    action="create",
                    entity_id=uuid.uuid4(),
                    result={"status": "applied"},
                )
            )
        elif table == "sync_change":
            db_session.add(
                SyncChange(
                    tenant_id=tid, entity="farmer", entity_id=uuid.uuid4(), action="create",
                    version=1, changed_at=datetime.now(UTC),
                )
            )  # fmt: skip
        elif table == "idempotency_key":
            db_session.add(
                IdempotencyKey(
                    tenant_id=tid, actor_id=uuid.uuid4(), key="k", request_hash="h" * 64,
                    method="POST", path="/v1/x", status_code=201, response={},
                    expires_at=datetime.now(UTC) + timedelta(hours=1),
                )
            )  # fmt: skip
        elif table in ("upload_session", "upload_chunk"):
            upload = UploadSession(
                tenant_id=tid, actor_id=uuid.uuid4(), sha256="a" * 64, size_bytes=10,
                content_type="image/jpeg", purpose="farm_photo", chunk_size=262144, chunk_count=1,
                expires_at=datetime.now(UTC) + timedelta(minutes=15),
            )  # fmt: skip
            db_session.add(upload)
            await db_session.flush()
            if table == "upload_chunk":
                db_session.add(
                    UploadChunk(
                        tenant_id=tid,
                        upload_id=upload.id,
                        index=0,
                        sha256="b" * 64,
                        size=10,
                        data=b"0123456789",
                    )
                )
        else:
            pytest.skip("farm_photo needs a farm; covered by the write API tests")
        await db_session.flush()
        assert await db_session.scalar(text(f'SELECT count(*) FROM "{table}"')) == 1
    async with tenant_scope(db_session, uuid.uuid4()):
        assert await db_session.scalar(text(f'SELECT count(*) FROM "{table}"')) == 0
    await clear_tenant(db_session)
    assert await db_session.scalar(text(f'SELECT count(*) FROM "{table}"')) == 0


async def test_sync_change_is_append_only_for_the_app_role(db_session: AsyncSession) -> None:
    tid = uuid.uuid4()
    async with tenant_scope(db_session, tid):
        await db_session.execute(
            text("INSERT INTO tenant (id, tenant_id, name) VALUES (:t, :t, 'RLS')"), {"t": tid}
        )
        db_session.add(
            SyncChange(
                tenant_id=tid, entity="farmer", entity_id=uuid.uuid4(), action="create",
                version=1, changed_at=datetime.now(UTC),
            )
        )  # fmt: skip
        await db_session.flush()
        for statement in ("UPDATE sync_change SET version = 9", "DELETE FROM sync_change"):
            with pytest.raises(DBAPIError, match="permission denied"):
                async with db_session.begin_nested():
                    await db_session.execute(text(statement))
