"""DX-012 training-set export for the monthly on-device fine-tune.

``python -m farmerapp.jobs export-training-set --tenant …`` (weekly) writes, per tenant, the
approved corpus images (image and problem approved, not retired; ``source`` internal by
default: the agronomist-labelled field images) as a manifest in the corpus bucket::

    gs://<corpus>/training/<tenant_id>/<YYYYMMDD>/manifest.csv   (one row per image)
    gs://<corpus>/training/<tenant_id>/<YYYYMMDD>/summary.json   (counts per crop / problem)

The CSV speaks the ``ml/ondevice`` manifest dialect (``path, source, key, is_plant, crop,
orig_label, licence, split``) plus ``sha256, problem_code, part, severity, stage, region,
season``. ``path`` is the image's ``gs://`` URI; ``crop`` is mapped onto the on-device crop
labels (anything else becomes ``other``); ``split`` is the stable hash split of
``ml/ondevice/ondevice/manifest.py`` over (source, key) with ``key`` = the diagnosis the image
came from (else the image), so photos of one case never straddle train and test. No farmer,
phone, location or free text leaves the database.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import uuid
from collections import Counter
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import PestOrDisease
from farmerapp.db import audit
from farmerapp.db.session import job_session
from farmerapp.diagnosis.models import CorpusImage, CorpusProblem, CorpusSource, CorpusStatus
from farmerapp.logging import get_logger
from farmerapp.uploads.blobstore import BlobStore

log = get_logger("farmerapp.mlops.training_export")

#: ml/ondevice/ondevice/config.py CROP_LABELS (label order of the crop head).
ONDEVICE_CROP_LABELS = ("paddy", "cotton", "chilli", "maize", "tomato", "groundnut", "other")
FIELDS = (
    "path",
    "source",
    "key",
    "is_plant",
    "crop",
    "orig_label",
    "licence",
    "split",
    "sha256",
    "problem_code",
    "part",
    "severity",
    "stage",
    "region",
    "season",
)


def split_for(
    source: str, key: str, val_fraction: float = 0.15, test_fraction: float = 0.15
) -> str:
    """Same function as ``ml/ondevice/ondevice/manifest.py::split_for``."""
    digest = hashlib.sha256(f"{source}:{key}".encode()).digest()
    u = int.from_bytes(digest[:8], "big") / 2**64
    if u < test_fraction:
        return "test"
    if u < test_fraction + val_fraction:
        return "val"
    return "train"


@dataclass
class ExportReport:
    tenant_id: uuid.UUID
    manifest_uri: str | None = None
    summary_uri: str | None = None
    images: int = 0
    per_crop: dict[str, int] = field(default_factory=dict)
    per_split: dict[str, int] = field(default_factory=dict)


async def training_rows(
    session: AsyncSession, tenant_id: uuid.UUID, *, sources: Iterable[str]
) -> list[dict[str, str]]:
    stmt = (
        select(CorpusImage, Crop.code, PestOrDisease.code)
        .join(CorpusProblem, CorpusProblem.id == CorpusImage.problem_id)
        .join(Crop, Crop.id == CorpusImage.crop_id)
        .join(PestOrDisease, PestOrDisease.id == CorpusProblem.pest_or_disease_id)
        .where(
            CorpusImage.tenant_id == tenant_id,
            CorpusImage.deleted_at.is_(None),
            CorpusImage.status == CorpusStatus.APPROVED.value,
            CorpusProblem.status == CorpusStatus.APPROVED.value,
            CorpusProblem.deleted_at.is_(None),
            CorpusImage.source.in_(list(sources)),
        )
        .order_by(CorpusImage.id)
    )
    rows: list[dict[str, str]] = []
    for image, crop_code, problem_code in (await session.execute(stmt)).tuples():
        source = f"corpus-{image.source}"
        key = str(image.from_diagnosis_id or image.id)
        rows.append(
            {
                "path": image.blob_uri,
                "source": source,
                "key": key,
                "is_plant": "1",
                "crop": crop_code if crop_code in ONDEVICE_CROP_LABELS else "other",
                "orig_label": problem_code,
                "licence": "internal" if image.source == CorpusSource.INTERNAL.value else "public",
                "split": split_for(source, key),
                "sha256": image.sha256,
                "problem_code": problem_code,
                "part": image.part or "",
                "severity": image.severity or "",
                "stage": image.stage or "",
                "region": image.region or "",
                "season": image.season or "",
            }
        )
    return rows


def to_csv(rows: list[dict[str, str]]) -> bytes:
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=FIELDS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


async def export_training_set(
    session: AsyncSession,
    *,
    tenant_id: uuid.UUID,
    blobs: BlobStore,
    now: datetime | None = None,
    sources: Iterable[str] = (CorpusSource.INTERNAL.value,),
) -> ExportReport:
    now = now or datetime.now(UTC)
    rows = await training_rows(session, tenant_id, sources=sources)
    report = ExportReport(
        tenant_id=tenant_id,
        images=len(rows),
        per_crop=dict(sorted(Counter(r["crop"] for r in rows).items())),
        per_split=dict(sorted(Counter(r["split"] for r in rows).items())),
    )
    prefix = f"training/{tenant_id}/{now.strftime('%Y%m%d')}"
    report.manifest_uri = await blobs.put(
        f"{prefix}/manifest.csv", to_csv(rows), content_type="text/csv"
    )
    summary = {
        "tenant_id": str(tenant_id),
        "generated_at": now.isoformat(),
        "manifest": report.manifest_uri,
        "images": report.images,
        "per_crop": report.per_crop,
        "per_split": report.per_split,
        "per_problem": dict(sorted(Counter(r["problem_code"] for r in rows).items())),
        "sources": sorted(sources),
    }
    report.summary_uri = await blobs.put(
        f"{prefix}/summary.json",
        json.dumps(summary, indent=2).encode("utf-8"),
        content_type="application/json",
    )
    log.info(
        "training_set_exported",
        tenant_id=str(tenant_id),
        images=report.images,
        manifest=report.manifest_uri,
    )
    return report


async def run_export(
    tenant_ids: Iterable[uuid.UUID],
    *,
    blobs: BlobStore,
    sources: Iterable[str] = (CorpusSource.INTERNAL.value,),
) -> list[ExportReport]:
    reports: list[ExportReport] = []
    wanted = tuple(sources)
    for tenant_id in tenant_ids:
        with audit.actor_scope(audit.system_actor(tenant_id)):
            async with job_session(tenant_id) as session:
                reports.append(
                    await export_training_set(
                        session, tenant_id=tenant_id, blobs=blobs, sources=wanted
                    )
                )
    return reports


__all__ = [
    "FIELDS",
    "ONDEVICE_CROP_LABELS",
    "ExportReport",
    "export_training_set",
    "run_export",
    "split_for",
    "to_csv",
    "training_rows",
]
