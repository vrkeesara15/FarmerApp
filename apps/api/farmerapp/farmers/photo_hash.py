"""VA-F08: perceptual hashes of farm photos (``farm_photo.phash``).

* ``farm_photo_phash(blobs, uri)`` — reads the uploaded blob and returns its 64-bit pHash
  (the visit-photo helper ``visits.photos.phash``: Pillow + imagehash, 16 hex chars), or
  ``None`` when the blob is missing or not a decodable image. Called by the farm write paths
  (registration, farm add / edit, their sync ops) for every newly attached photo.
* ``backfill_farm_photo_phash(tenant_ids, blobs=...)`` — ``python -m farmerapp.jobs
  backfill-farm-photo-phash --tenant ...``: fills ``phash`` on the tenant's live farm photos
  that have none (rows from before Alembic 0023), keyset-paged by id, one transaction per
  tenant, then runs the VA-F08 event rules (``farm.photo``) on the farms whose photos got a
  hash, so near-duplicates already on file are flagged. Idempotent: only NULL hashes are
  touched and the flag dedupe key never duplicates an open flag; blobs that are missing or
  undecodable stay NULL and are counted.
"""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.farmers.models import Farm, FarmPhoto
from farmerapp.logging import get_logger
from farmerapp.uploads.blobstore import BlobNotFoundError, BlobStore
from farmerapp.visits.photos import phash

log = get_logger("farmerapp.farmers.photo_hash")

FARM_PHOTO_TOPIC = "farm.photo"
BACKFILL_BATCH = 200

SessionProvider = Callable[[uuid.UUID], contextlib.AbstractAsyncContextManager[AsyncSession]]


async def farm_photo_phash(blobs: BlobStore, uri: str) -> str | None:
    """The pHash of the blob at ``uri``; ``None`` when missing or not an image."""
    try:
        data = await blobs.get(uri)
    except (BlobNotFoundError, ValueError):
        log.warning("farm_photo_blob_missing", blob_uri=uri)
        return None
    return phash(data)


@dataclass
class BackfillReport:
    tenant_id: uuid.UUID
    scanned: int = 0
    hashed: int = 0
    unhashable: int = 0  # blob missing or not a decodable image: left NULL
    farms_checked: int = 0
    flags_raised: int = 0


async def backfill_tenant(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    blobs: BlobStore,
    batch_size: int = BACKFILL_BATCH,
    run_rules: bool = True,
    now: datetime | None = None,
) -> BackfillReport:
    from farmerapp.rules import engine as rules_engine

    report = BackfillReport(tenant_id=tenant_id)
    farms: set[uuid.UUID] = set()
    after: uuid.UUID | None = None
    while True:
        stmt = (
            select(FarmPhoto)
            .join(Farm, Farm.id == FarmPhoto.farm_id)
            .where(
                FarmPhoto.tenant_id == tenant_id,
                FarmPhoto.phash.is_(None),
                FarmPhoto.deleted_at.is_(None),
                Farm.deleted_at.is_(None),
            )
            .order_by(FarmPhoto.id)
            .limit(batch_size)
        )
        if after is not None:
            stmt = stmt.where(FarmPhoto.id > after)
        rows = list((await session.execute(stmt)).scalars())
        if not rows:
            break
        for photo in rows:
            report.scanned += 1
            value = await farm_photo_phash(blobs, photo.blob_uri)
            if value is None:
                report.unhashable += 1
                continue
            photo.phash = value
            report.hashed += 1
            farms.add(photo.farm_id)
        after = rows[-1].id
        await session.flush()
    if run_rules and farms:
        ordered = sorted(farms, key=str)
        run = await rules_engine.emit(session, tenant_id, FARM_PHOTO_TOPIC, ordered, now=now)
        report.farms_checked = len(ordered)
        report.flags_raised = run.total_raised
    log.info(
        "farm_photo_phash_backfill",
        tenant_id=str(tenant_id),
        scanned=report.scanned,
        hashed=report.hashed,
        unhashable=report.unhashable,
        farms_checked=report.farms_checked,
        flags_raised=report.flags_raised,
    )
    return report


async def backfill_farm_photo_phash(
    tenant_ids: Iterable[uuid.UUID],
    *,
    blobs: BlobStore,
    batch_size: int = BACKFILL_BATCH,
    run_rules: bool = True,
    session_provider: SessionProvider = job_session,
) -> list[BackfillReport]:
    reports: list[BackfillReport] = []
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with session_provider(tenant_id) as session:
                reports.append(
                    await backfill_tenant(
                        session,
                        tenant_id,
                        blobs=blobs,
                        batch_size=batch_size,
                        run_rules=run_rules,
                    )
                )
    return reports


__all__ = [
    "BackfillReport",
    "backfill_farm_photo_phash",
    "backfill_tenant",
    "farm_photo_phash",
]
