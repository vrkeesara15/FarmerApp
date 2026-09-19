"""Loading and creating the per-tenant data keys (SEC-026).

``ensure_tenant_key(session, tenant_id)`` runs from ``set_tenant`` (every request, job and
worker step binds its tenant through it). A cached tenant costs a dict lookup. Otherwise the
key rows are read — and, for a tenant without any, a first key is created — on a **separate
connection in its own committed transaction**, so

* a caller's transaction that later rolls back can never take a key with it that values
  were already encrypted under (the key row is committed before any value uses it);
* two processes racing to create the first key converge on one (``ON CONFLICT DO NOTHING``
  on ``(tenant_id, key_version)``, then everyone reads the winner);
* a failure here (a schema without the table, KMS down) never poisons the caller's
  transaction: it is logged, and only an actual encrypt / decrypt then fails loudly.
"""

from __future__ import annotations

import os
import uuid
from typing import Any, cast

from sqlalchemy import Table, select, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncConnection, AsyncEngine, AsyncSession

from farmerapp.logging import get_logger
from farmerapp.pii.crypto import KEY_BYTES, FieldCipher, dek_aad, get_cipher
from farmerapp.pii.models import TenantDataKey

log = get_logger("farmerapp.pii")

_TABLE = cast(Table, TenantDataKey.__table__)
_BIND = text("SELECT set_config('app.tenant_id', :tid, true)")
FIRST_VERSION = 1


def _engine_of(session: AsyncSession) -> AsyncEngine:
    bind: Any = session.bind
    if isinstance(bind, AsyncConnection):
        return bind.engine
    if isinstance(bind, AsyncEngine):
        return bind
    from farmerapp.db.session import get_engine

    return get_engine()


async def _load(conn: AsyncConnection, cipher: FieldCipher, tenant_id: uuid.UUID) -> int:
    rows = await conn.execute(
        select(_TABLE.c.key_version, _TABLE.c.wrapped_key).where(_TABLE.c.tenant_id == tenant_id)
    )
    loaded = 0
    for version, wrapped in rows.tuples():
        dek = await cipher.wrapper.unwrap(bytes(wrapped), dek_aad(tenant_id, version))
        cipher.load_key(tenant_id, version, dek)
        loaded += 1
    return loaded


async def load_or_create(
    engine: AsyncEngine, tenant_id: uuid.UUID, cipher: FieldCipher | None = None
) -> None:
    cipher = cipher or get_cipher()
    async with engine.connect() as conn:
        async with conn.begin():
            await conn.execute(_BIND, {"tid": str(tenant_id)})
            if await _load(conn, cipher, tenant_id):
                return
            dek = os.urandom(KEY_BYTES)
            wrapped = await cipher.wrapper.wrap(dek, dek_aad(tenant_id, FIRST_VERSION))
            await conn.execute(
                insert(_TABLE)
                .values(
                    id=uuid.uuid4(),
                    tenant_id=tenant_id,
                    key_version=FIRST_VERSION,
                    wrapped_key=wrapped,
                    kek_backend=cipher.wrapper.backend,
                    kek_name=cipher.wrapper.name,
                )
                .on_conflict_do_nothing(index_elements=["tenant_id", "key_version"])
            )
        async with conn.begin():
            await conn.execute(_BIND, {"tid": str(tenant_id)})
            await _load(conn, cipher, tenant_id)
    log.info("pii_data_key_ready", tenant_id=str(tenant_id), backend=cipher.wrapper.backend)


async def ensure_tenant_key(session: AsyncSession, tenant_id: uuid.UUID) -> None:
    cipher = get_cipher()
    if cipher.has_tenant(tenant_id):
        return
    try:
        await load_or_create(_engine_of(session), tenant_id, cipher)
    except Exception:  # never break the caller's transaction; encrypt/decrypt fail loudly
        log.warning("pii_data_key_unavailable", tenant_id=str(tenant_id), exc_info=True)


__all__ = ["FIRST_VERSION", "ensure_tenant_key", "load_or_create"]
