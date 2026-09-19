"""M4 event rules on the visit write path (SPEC 6.1), in the request's transaction:

* check-in with FA-028 issues -> VA-E01 (one flag per officer and day),
* a photo whose EXIF GPS is far from the check-in, or reused from another visit -> VA-E08,
* the same photo on a visit to another farmer -> VA-F08 (farmer data, store manager),
* confirmation and check-out publish their events (no rule subscribes to confirmations; the
  check-out re-runs VA-E08, deduped per visit).
"""

from __future__ import annotations

import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.geo import offset
from farmerapp.db.session import tenant_scope
from farmerapp.flags.models import Flag
from farmerapp.visits import events
from tests.farmers.write_fixtures import BASE_LAT, BASE_LON
from tests.visits.test_flow import (  # noqa: F401  (``flow`` is a fixture)
    FAR,
    Flow,
    _check_out,
    _confirm_by_sms,
    _photo,
    _visit,
    flow,
    jpeg,
)


async def _flags(session: AsyncSession, flow: Flow, rule_id: str) -> list[Flag]:  # noqa: F811
    async with tenant_scope(session, flow.tenant_id):
        rows = await session.execute(
            select(Flag).where(Flag.rule_id == rule_id).order_by(Flag.created_at, Flag.id)
        )
        return list(rows.scalars())


async def test_check_in_integrity_raises_one_va_e01_per_officer_day(
    client: AsyncClient,
    flow: Flow,  # noqa: F811
    db_session: AsyncSession,
) -> None:
    clean = await _visit(client, flow)
    assert await _flags(db_session, flow, "VA-E01") == []
    mocked = await _visit(
        client, flow, integrity={"is_mock": True, "is_rooted": False, "clock_drift_s": 12}
    )
    [flag] = await _flags(db_session, flow, "VA-E01")
    assert flag.subject_id == flow.officer.id and flag.raised_by_mode == "event"
    assert flag.owner_role == UserRole.CLUSTER_HEAD.value and flag.watchers
    assert {"type": "visit", "id": mocked["id"]} in flag.evidence["records"]
    assert {"type": "visit", "id": clean["id"]} not in flag.evidence["records"]
    await _visit(client, flow, integrity={"is_rooted": True})
    assert len(await _flags(db_session, flow, "VA-E01")) == 1  # same officer, same day


async def test_photo_integrity_and_reuse_raise_va_e08(
    client: AsyncClient,
    flow: Flow,  # noqa: F811
    db_session: AsyncSession,
) -> None:
    first = await _visit(client, flow)
    resp = await _photo(client, flow, first["id"], jpeg(3), at=FAR)  # EXIF GPS ~ 560 m away
    assert resp.status_code == 201, resp.text
    [gps] = await _flags(db_session, flow, "VA-E08")
    assert gps.evidence["metrics"]["reasons"] == ["exif_gps_mismatch"]
    assert gps.evidence["photos"] == [resp.json()["blob_uri"]]
    assert len(gps.evidence["map"]["points"]) == 2  # check-in + EXIF position

    second = await _visit(client, flow)
    resp = await _photo(client, flow, second["id"], jpeg(3))  # the same bytes again
    assert resp.status_code == 201 and "duplicate_photo" in resp.json()["photo_flags"]
    flags = await _flags(db_session, flow, "VA-E08")
    [reuse] = [f for f in flags if f.evidence["metrics"]["reasons"] == ["duplicate_photo"]]
    assert {"type": "visit", "id": first["id"]} in reuse.evidence["records"]
    assert reuse.dedupe_key.endswith(f"visit:{second['id']}")
    assert await _flags(db_session, flow, "VA-F08") == []  # same farmer: not farmer data

    # confirmation and check-out publish their events; the open VA-E08 flag is not repeated
    seen: list[Any] = []
    for kind in (events.VisitConfirmed, events.VisitCheckedOut):
        events.bus.subscribe(kind, seen.append)
    try:
        await _confirm_by_sms(client, flow, second["id"])
        resp = await _check_out(client, flow, second["id"])
        assert resp.status_code == 200, resp.text
    finally:
        for kind in (events.VisitConfirmed, events.VisitCheckedOut):
            events.bus.unsubscribe(kind, seen.append)
    assert [type(e) for e in seen] == [events.VisitConfirmed, events.VisitCheckedOut]
    assert seen[0].channel == "sms_otp" and seen[1].visit_id == uuid.UUID(second["id"])
    assert len(await _flags(db_session, flow, "VA-E08")) == 2


async def test_same_photo_for_another_farmer_raises_va_f08(
    client: AsyncClient,
    flow: Flow,  # noqa: F811
    db_session: AsyncSession,
) -> None:
    corner = offset(BASE_LON, BASE_LAT, 2000, 0)
    resp = await client.post(
        "/v1/farmers",
        json=flow.ctx.farmer(
            phone="+919000199555", farms=[flow.ctx.farm(acres=1.0, at=corner, name="Second")]
        ),
        headers=flow.headers,
    )
    assert resp.status_code == 201, resp.text
    other = resp.json()
    first = await _visit(client, flow)
    assert (await _photo(client, flow, first["id"], jpeg(5))).status_code == 201

    inside = offset(corner[0], corner[1], 30, 30)
    second = await _visit(
        client,
        flow,
        at=inside,
        farmer_id=other["id"],
        farm_id=other["farms"][0]["id"],
    )
    resp = await _photo(client, flow, second["id"], jpeg(5), at=inside)
    assert resp.status_code == 201, resp.text
    [flag] = await _flags(db_session, flow, "VA-F08")
    assert str(flag.subject_id) == other["id"] and flag.subject_type == "farmer"
    assert flag.owner_role == UserRole.STORE_MANAGER.value and flag.watchers
    metrics = flag.evidence["metrics"]
    assert metrics["hamming_distance"] == 0 and metrics["match"] == "phash"
    assert metrics["other_farmer_id"] == str(flow.farmer_id)
    assert len(flag.evidence["photos"]) == 2
