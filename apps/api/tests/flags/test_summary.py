"""AN-009 data quality summary: ``GET /v1/flags/summary``."""

from __future__ import annotations

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.rules.schema import Subject
from tests.authz.conftest import Bearer
from tests.flags.conftest import Flagged, make_flag


async def resolve(
    client: AsyncClient, bearer: Bearer, flagged: Flagged, flag_id: str, to: str
) -> None:
    headers = bearer(flagged.world.users["owner"])
    first = await client.post(
        f"/v1/flags/{flag_id}/transition", json={"to": "in_review"}, headers=headers
    )
    assert first.status_code == 200, first.text
    done = await client.post(
        f"/v1/flags/{flag_id}/transition",
        json={"to": to, "note": "Checked with the officer."},
        headers=headers,
    )
    assert done.status_code == 200, done.text


async def test_summary_volume_resolution_and_repeats(
    client: AsyncClient, bearer: Bearer, flagged: Flagged, db_session: AsyncSession
) -> None:
    # One VA-F06 flag is a false positive, one VA-F03 flag a real fix.
    f06 = flagged.about("officer")[0]
    f03 = next(f for f in flagged.flags if f.rule_id == "VA-F03")
    await resolve(client, bearer, flagged, str(f06.id), "resolved_valid")
    await resolve(client, bearer, flagged, str(f03.id), "resolved_fixed")
    # A second flag on the same officer makes them a repeat subject.
    await make_flag(db_session, flagged.world, "officer", key="second")
    await db_session.flush()

    resp = await client.get("/v1/flags/summary", headers=bearer(flagged.world.users["owner"]))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["days"] == 90
    assert body["total"] == 7 and body["resolved"] == 2
    assert body["open"] == 5
    assert body["by_severity"] == {"high": 3, "medium": 4}
    assert set(body["by_subject_type"]) == {Subject.EMPLOYEE.value, Subject.FARMER.value}
    assert body["false_positive_rate"] == 0.5  # one of the two resolutions
    assert body["median_resolution_hours"] is not None
    assert body["p90_resolution_hours"] >= body["median_resolution_hours"]

    rules = {r["rule_id"]: r for r in body["by_rule"]}
    assert rules["VA-F06"]["total"] == 3 and rules["VA-F06"]["resolved"] == 1
    assert rules["VA-F06"]["false_positives"] == 1
    assert rules["VA-F06"]["false_positive_rate"] == 1.0
    assert rules["VA-F06"]["precision"] == 0.0  # VA-006: the one resolution was wrong
    assert rules["VA-F06"]["precision_resolved"] == 1
    assert rules["VA-F03"]["precision"] == 1.0
    assert rules["VA-F03"]["title"]
    assert body["by_rule"][0]["total"] >= body["by_rule"][-1]["total"]  # busiest first

    repeats = {(r["subject_type"], r["subject_id"]): r for r in body["repeat_subjects"]}
    officer = repeats[("employee", str(flagged.world.refs["officer"]))]
    assert officer["flags"] == 2 and officer["rules"] == ["VA-F06"]
    assert officer["open_flags"] == 1  # the first one was resolved
    assert body["repeat_min"] == 2
    assert body["precision_floor"] == 0.30 and body["precision_window_weeks"] == 4


async def test_summary_window_excludes_older_flags(
    client: AsyncClient, bearer: Bearer, flagged: Flagged
) -> None:
    resp = await client.get(
        "/v1/flags/summary?days=1", headers=bearer(flagged.world.users["owner"])
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["days"] == 1 and body["total"] == 0  # the fixtures were raised earlier
    assert body["by_rule"] == [] and body["repeat_subjects"] == []
    assert body["median_resolution_hours"] is None


async def test_summary_is_scoped_like_the_inbox(
    client: AsyncClient, bearer: Bearer, flagged: Flagged
) -> None:
    """WC-010 scope: a store manager sees only their store's farmer-data flags."""
    owner = (
        await client.get("/v1/flags/summary", headers=bearer(flagged.world.users["owner"]))
    ).json()
    manager = (
        await client.get("/v1/flags/summary", headers=bearer(flagged.world.users["store_manager"]))
    ).json()
    assert manager["total"] < owner["total"]
    assert all(r["rule_id"] == "VA-F03" for r in manager["by_rule"])


@pytest.mark.parametrize(
    ("who", "status"),
    [("owner", 200), ("auditor", 200), ("store_manager", 200), ("officer", 403)],
)
async def test_summary_roles(
    client: AsyncClient, bearer: Bearer, flagged: Flagged, who: str, status: int
) -> None:
    resp = await client.get("/v1/flags/summary", headers=bearer(flagged.world.users[who]))
    assert resp.status_code == status
