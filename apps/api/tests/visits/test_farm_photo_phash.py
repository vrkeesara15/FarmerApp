"""VA-F08 on farm photos by perceptual hash (Alembic 0023, ``farm_photo.phash``).

* The farm write paths (registration, farm add, farm edit) compute the pHash of each newly
  attached photo from the blob with the visit-photo helper; a missing or undecodable blob
  leaves it NULL.
* A farm photo that is another farmer's farm photo re-encoded / resized or slightly cropped
  (different bytes, a few bits of pHash) raises VA-F08 about the farmer of the new photo.
* ``backfill-farm-photo-phash`` fills rows from before the migration, runs VA-F08 on their
  farms and is idempotent.
"""

from __future__ import annotations

import contextlib
import hashlib
import io
import random
import uuid
from collections.abc import AsyncIterator
from typing import Any

import pytest
from httpx import AsyncClient
from PIL import Image, ImageDraw
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from typer.testing import CliRunner

from farmerapp.db.geo import offset
from farmerapp.db.session import tenant_scope
from farmerapp.farmers import photo_hash
from farmerapp.farmers.models import FarmPhoto
from farmerapp.flags.models import Flag
from farmerapp.jobs.cli import cli
from farmerapp.uploads.blobstore import blob_key
from farmerapp.visits.photos import phash
from tests.farmers.write_fixtures import BASE_LAT, BASE_LON
from tests.visits.test_flow import Flow, flow  # noqa: F401  (``flow`` is a fixture)


def field(seed: int) -> Image.Image:
    """A 640 x 480 'field' of coloured patches; different seeds are different fields."""
    rnd = random.Random(seed)
    image = Image.new("RGB", (640, 480), (90, 140, 60))
    draw = ImageDraw.Draw(image)
    for _ in range(40):
        x, y = rnd.randrange(640), rnd.randrange(480)
        w, h = rnd.randrange(20, 160), rnd.randrange(20, 120)
        draw.rectangle([x, y, x + w, y + h], fill=tuple(rnd.randrange(256) for _ in range(3)))
    return image


def jpg(image: Image.Image, quality: int) -> bytes:
    buf = io.BytesIO()
    image.save(buf, "JPEG", quality=quality)
    return buf.getvalue()


ORIGINAL = jpg(field(1), 92)
REENCODED = jpg(field(1).resize((600, 450)), 60)  # same field, smaller, lower quality
CROPPED = jpg(field(1).crop((8, 6, 632, 474)), 85)  # same field, edges trimmed
OTHER_FIELD = jpg(field(2), 90)


def bits(a: str, b: str) -> int:
    return bin(int(a, 16) ^ int(b, 16)).count("1")


def test_near_duplicates_are_close_in_phash() -> None:
    base = phash(ORIGINAL)
    assert base is not None
    for copy in (REENCODED, CROPPED):
        value = phash(copy)
        assert value is not None and copy != ORIGINAL
        assert bits(base, value) <= 6  # VA-F08 max_hamming_distance
    other = phash(OTHER_FIELD)
    assert other is not None and bits(base, other) > 6


async def _flags(session: AsyncSession, flow: Flow) -> list[Flag]:  # noqa: F811
    async with tenant_scope(session, flow.tenant_id):
        rows = await session.execute(
            select(Flag).where(Flag.rule_id == "VA-F08").order_by(Flag.created_at, Flag.id)
        )
        return list(rows.scalars())


async def _photos(session: AsyncSession, flow: Flow, farm_id: str) -> list[FarmPhoto]:  # noqa: F811
    async with tenant_scope(session, flow.tenant_id):
        rows = await session.execute(select(FarmPhoto).where(FarmPhoto.farm_id == farm_id))
        return list(rows.scalars())


async def _register(
    client: AsyncClient,
    flow: Flow,  # noqa: F811
    phone: str,
    east_m: float,
    photos: list[str],
) -> dict[str, Any]:
    at = offset(BASE_LON, BASE_LAT, east_m, 0)
    resp = await client.post(
        "/v1/farmers",
        json=flow.ctx.farmer(phone=phone, farms=[flow.ctx.farm(at=at, photos=photos)]),
        headers=flow.headers,
    )
    assert resp.status_code == 201, resp.text
    body: dict[str, Any] = resp.json()
    return body


async def test_registration_hashes_farm_photos_and_flags_a_reencoded_copy(
    client: AsyncClient,
    flow: Flow,  # noqa: F811
    db_session: AsyncSession,
) -> None:
    first = await _register(
        client, flow, "+919000177001", 3000, [await flow.put_blob(ORIGINAL, purpose="farm_photo")]
    )
    [stored] = await _photos(db_session, flow, first["farms"][0]["id"])
    assert stored.phash == phash(ORIGINAL)
    assert await _flags(db_session, flow) == []

    second = await _register(
        client, flow, "+919000177002", 6000, [await flow.put_blob(REENCODED, purpose="farm_photo")]
    )
    [flag] = await _flags(db_session, flow)
    assert str(flag.subject_id) == second["id"] and flag.subject_type == "farmer"
    metrics = flag.evidence["metrics"]
    assert metrics["match"] == "phash" and 0 < metrics["hamming_distance"] <= 6
    assert metrics["other_farmer_id"] == first["id"]
    assert {"type": "farm_photo", "id": str(stored.id)} in flag.evidence["records"]
    assert len(flag.evidence["photos"]) == 2

    # a different field for a third farmer: no new flag
    await _register(
        client,
        flow,
        "+919000177003",
        9000,
        [await flow.put_blob(OTHER_FIELD, purpose="farm_photo")],
    )
    assert len(await _flags(db_session, flow)) == 1


async def test_farm_add_and_edit_hash_new_photos(
    client: AsyncClient,
    flow: Flow,  # noqa: F811
    db_session: AsyncSession,
) -> None:
    first = await _register(
        client, flow, "+919000177011", 3000, [await flow.put_blob(ORIGINAL, purpose="farm_photo")]
    )
    # farm add for the flow's farmer with a cropped copy of first's photo
    cropped = await flow.put_blob(CROPPED, purpose="farm_photo")
    resp = await client.post(
        f"/v1/farmers/{flow.farmer_id}/farms",
        json=flow.ctx.farm(at=offset(BASE_LON, BASE_LAT, 0, 4000), photos=[cropped]),
        headers=flow.headers,
    )
    assert resp.status_code == 201, resp.text
    farm = resp.json()
    [photo] = await _photos(db_session, flow, farm["id"])
    assert photo.phash == phash(CROPPED)
    [flag] = await _flags(db_session, flow)
    assert flag.subject_id == flow.farmer_id
    assert flag.evidence["metrics"]["other_farmer_id"] == first["id"]

    # farm edit: a re-encoded copy added, plus a blob that is not an image and one that
    # does not exist in the store (both stored without a hash)
    reencoded = await flow.put_blob(REENCODED, purpose="farm_photo")
    garbage = await flow.put_blob(b"not an image", purpose="farm_photo")
    missing = f"gs://{flow.blobs.bucket}/{flow.tenant_id}/farm_photo/{'0' * 64}"
    resp = await client.patch(
        f"/v1/farms/{farm['id']}",
        json={"photos": [cropped, reencoded, garbage, missing]},
        headers=flow.headers,
    )
    assert resp.status_code == 200, resp.text
    hashes = {p.blob_uri: p.phash for p in await _photos(db_session, flow, farm["id"])}
    assert hashes[reencoded] == phash(REENCODED)
    assert hashes[garbage] is None and hashes[missing] is None
    assert len(await _flags(db_session, flow)) == 2  # one per new matching photo


def _provider(session: AsyncSession) -> Any:
    @contextlib.asynccontextmanager
    async def provide(tenant_id: uuid.UUID) -> AsyncIterator[AsyncSession]:
        async with tenant_scope(session, tenant_id):
            yield session

    return provide


async def test_backfill_hashes_old_rows_flags_and_is_idempotent(
    client: AsyncClient,
    flow: Flow,  # noqa: F811
    db_session: AsyncSession,
) -> None:
    def uri_of(data: bytes) -> str:
        key = blob_key(flow.tenant_id, "farm_photo", hashlib.sha256(data).hexdigest())
        return f"gs://{flow.blobs.bucket}/{key}"

    # rows from before 0023: the blobs are not readable at write time, so no hash, no flag
    garbage = b"still not an image"
    first = await _register(client, flow, "+919000177021", 3000, [uri_of(ORIGINAL)])
    second = await _register(
        client, flow, "+919000177022", 6000, [uri_of(CROPPED), uri_of(garbage)]
    )
    assert {p.phash for p in await _photos(db_session, flow, second["farms"][0]["id"])} == {None}
    assert await _flags(db_session, flow) == []
    for data in (ORIGINAL, CROPPED, garbage):
        assert await flow.put_blob(data, purpose="farm_photo") == uri_of(data)

    [report] = await photo_hash.backfill_farm_photo_phash(
        [flow.tenant_id], blobs=flow.blobs, batch_size=1, session_provider=_provider(db_session)
    )
    assert (report.scanned, report.hashed, report.unhashable) == (3, 2, 1)
    assert report.farms_checked == 2 and report.flags_raised == 2  # each farmer's photo
    assert [p.phash for p in await _photos(db_session, flow, first["farms"][0]["id"])] == [
        phash(ORIGINAL)
    ]
    flags = await _flags(db_session, flow)
    assert {str(f.subject_id) for f in flags} == {first["id"], second["id"]}

    [again] = await photo_hash.backfill_farm_photo_phash(
        [flow.tenant_id], blobs=flow.blobs, session_provider=_provider(db_session)
    )
    assert (again.scanned, again.hashed, again.unhashable) == (1, 0, 1)
    assert again.farms_checked == 0 and again.flags_raised == 0
    assert len(await _flags(db_session, flow)) == 2

    async with tenant_scope(db_session, flow.tenant_id):
        no_rules = await photo_hash.backfill_tenant(
            db_session, flow.tenant_id, blobs=flow.blobs, run_rules=False
        )
    assert no_rules.hashed == 0 and no_rules.flags_raised == 0


def test_cli_backfill(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[Any] = []
    tid = uuid.uuid4()

    async def fake(
        tenants: Any, *, blobs: Any, batch_size: int, run_rules: bool
    ) -> list[photo_hash.BackfillReport]:
        calls.append((list(tenants), batch_size, run_rules))
        return [photo_hash.BackfillReport(tid, scanned=3, hashed=2, unhashable=1)]

    monkeypatch.setattr(photo_hash, "backfill_farm_photo_phash", fake)
    runner = CliRunner()
    result = runner.invoke(
        cli,
        ["backfill-farm-photo-phash", "--tenant", str(tid), "--batch-size", "50", "--no-run-rules"],
    )
    assert result.exit_code == 0, result.output
    assert "hashed=2" in result.output and "unhashable=1" in result.output
    assert calls == [([tid], 50, False)]
    assert runner.invoke(cli, ["backfill-farm-photo-phash", "--tenant", "nope"]).exit_code != 0
