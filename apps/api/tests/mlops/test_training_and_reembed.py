"""DX-012: training-set export (ml/ondevice manifest in the corpus bucket, stable split, no
personal data), re-embedding into staging, the kNN over staged vectors during the rollout, and
the atomic encoder flip."""

from __future__ import annotations

import csv
import importlib.util
import io
import json
import sys
from collections.abc import Sequence
from datetime import UTC, datetime
from pathlib import Path

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.db.models import AuditLog
from farmerapp.diagnosis.encoder import EncoderInfo, FakeEncoder
from farmerapp.diagnosis.images import synthetic_leaf
from farmerapp.diagnosis.knn import nearest
from farmerapp.diagnosis.models import CorpusImage, CorpusStatus
from farmerapp.mlops.models import CorpusEmbedding, EncoderActivation
from farmerapp.mlops.reembed import EncoderNotStagedError, activate_encoder, reembed_corpus
from farmerapp.mlops.training_export import FIELDS, export_training_set, split_for
from farmerapp.uploads.blobstore import BlobStore
from tests.authz.conftest import World
from tests.mlops.conftest import write_corpus_blobs

REPO = Path(__file__).resolve().parents[4]


# ------------------------------------------------------------------ export
async def test_export_training_set(
    db_session: AsyncSession, world: World, blobs: BlobStore
) -> None:
    now = datetime(2026, 9, 20, 22, 0, tzinfo=UTC)
    internal = await export_training_set(
        db_session, tenant_id=world.a.tenant.id, blobs=blobs, now=now
    )
    assert internal.images == 0  # the seeded corpus is the public bootstrap only
    report = await export_training_set(
        db_session,
        tenant_id=world.a.tenant.id,
        blobs=blobs,
        now=now,
        sources=("internal", "public"),
    )
    approved = await db_session.scalar(
        select(func.count())
        .select_from(CorpusImage)
        .where(
            CorpusImage.tenant_id == world.a.tenant.id,
            CorpusImage.status == CorpusStatus.APPROVED.value,
        )
    )
    assert report.images == approved and report.images > 0
    assert report.manifest_uri and report.manifest_uri.endswith(
        f"training/{world.a.tenant.id}/20260920/manifest.csv"
    )
    rows = list(csv.DictReader(io.StringIO((await blobs.get(report.manifest_uri)).decode())))
    assert tuple(rows[0]) == FIELDS and len(rows) == report.images
    assert {r["crop"] for r in rows} == {"paddy"} and {r["is_plant"] for r in rows} == {"1"}
    assert all(r["split"] == split_for(r["source"], r["key"]) for r in rows)
    text = (await blobs.get(report.manifest_uri)).decode()
    for farmer in world.a.farmers:  # no personal data in the export
        assert farmer.phone not in text and farmer.name not in text
    summary = json.loads(await blobs.get(report.summary_uri or ""))
    assert summary["images"] == report.images and summary["per_crop"] == {"paddy": report.images}


def test_split_matches_the_ondevice_pipeline() -> None:
    path = REPO / "ml" / "ondevice" / "ondevice" / "manifest.py"
    source = path.read_text()
    assert "def split_for(source: str, key: str" in source
    # Execute the ondevice function without importing its package (TensorFlow-free).
    namespace: dict[str, object] = {}
    start = source.index("def split_for")
    end = source.index("\ndef ", start + 1)
    exec("import hashlib\n" + source[start:end], namespace)
    ondevice_split = namespace["split_for"]
    for i in range(200):
        assert ondevice_split("corpus-internal", f"k{i}") == split_for("corpus-internal", f"k{i}")  # type: ignore[operator]
    assert importlib.util is not None and sys is not None


# ------------------------------------------------------------------ re-embedding
class VersionedFake:
    """The fake encoder under another version label (a "new" encoder with the same space)."""

    def __init__(self, version: str = "2") -> None:
        self._inner = FakeEncoder()
        self.info = EncoderInfo(self._inner.info.name, version)
        self.calls = 0

    async def encode(self, images: Sequence[bytes]) -> list[list[float]]:
        self.calls += 1
        return await self._inner.encode(images)


async def test_reembed_stage_rollout_and_atomic_flip(
    db_session: AsyncSession, world: World, blobs: BlobStore
) -> None:
    tid = world.a.tenant.id
    assert await write_corpus_blobs(db_session, blobs) > 0
    live = await db_session.scalar(
        select(func.count())
        .select_from(CorpusImage)
        .where(CorpusImage.tenant_id == tid, CorpusImage.status != "retired")
    )
    old = FakeEncoder().info
    new = VersionedFake("2")

    with pytest.raises(EncoderNotStagedError):
        await activate_encoder(db_session, tenant_id=tid, encoder=new.info)

    partial = await reembed_corpus(
        db_session, tenant_id=tid, encoder=new, blobs=blobs, batch_size=5, max_images=5
    )
    assert partial.embedded == 5 and partial.remaining == (live or 0) - 5
    report = await reembed_corpus(db_session, tenant_id=tid, encoder=new, blobs=blobs, batch_size=8)
    assert report.embedded == (live or 0) - 5 and report.remaining == 0
    assert report.missing_blobs == []
    again = await reembed_corpus(db_session, tenant_id=tid, encoder=new, blobs=blobs)
    assert again.embedded == 0  # resumable / idempotent

    # Rollout: the API pin moved to v2 before activation -> kNN answers from staging.
    query = (await FakeEncoder().encode([synthetic_leaf("paddy_bph", 990)]))[0]
    staged = await nearest(db_session, query, tenant_id=tid, crop_id=None, encoder=new.info, k=5)
    active = await nearest(db_session, query, tenant_id=tid, crop_id=None, encoder=old, k=5)
    assert [n.image_id for n in staged] == [n.image_id for n in active]
    assert staged and staged[0].similarity == pytest.approx(active[0].similarity, abs=1e-5)

    flipped = await activate_encoder(db_session, tenant_id=tid, encoder=new.info, note="test")
    assert flipped.images == live and flipped.previous == old.label
    labels = (
        await db_session.execute(
            select(CorpusImage.encoder_name, CorpusImage.encoder_version)
            .where(CorpusImage.tenant_id == tid, CorpusImage.status != "retired")
            .distinct()
        )
    ).all()
    assert [tuple(row) for row in labels] == [(new.info.name, "2")]
    kept = await db_session.scalar(
        select(func.count())
        .select_from(CorpusEmbedding)
        .where(CorpusEmbedding.encoder_version == old.version)
    )
    assert kept == live  # previous vectors kept for rollback
    after = await nearest(db_session, query, tenant_id=tid, crop_id=None, encoder=new.info, k=5)
    assert [n.image_id for n in after] == [n.image_id for n in active]
    activation = (await db_session.execute(select(EncoderActivation))).scalar_one()
    assert activation.images == live and activation.previous_version == old.version
    audit_row = (
        await db_session.execute(
            select(AuditLog).where(AuditLog.action == "corpus.encoder_activate")
        )
    ).scalar_one()
    assert audit_row.entity_id == activation.id

    # Rollback: activating the old version again is possible at once.
    back = await activate_encoder(db_session, tenant_id=tid, encoder=old)
    assert back.images == live


async def test_missing_blobs_are_reported(
    db_session: AsyncSession, world: World, tmp_path: Path
) -> None:
    from farmerapp.uploads.blobstore import LocalBlobStore

    empty = LocalBlobStore(tmp_path)  # no corpus bytes at all
    report = await reembed_corpus(
        db_session, tenant_id=world.a.tenant.id, encoder=VersionedFake("3"), blobs=empty
    )
    assert report.embedded == 0 and report.missing_blobs
    with pytest.raises(EncoderNotStagedError):
        await activate_encoder(
            db_session, tenant_id=world.a.tenant.id, encoder=EncoderInfo("fake-dct", "3")
        )
