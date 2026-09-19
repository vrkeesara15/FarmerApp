"""AN-002 / WC-002 field team scorecard and officer profile (``Mini`` tenant)."""

from __future__ import annotations

from datetime import date
from typing import Any

import pytest
from httpx import AsyncClient

from tests.analytics.builders import Mini, ist
from tests.analytics.conftest import get
from tests.analytics.test_owner_home import FROM, TO
from tests.analytics.test_owner_home import build as build_home
from tests.authz.conftest import Bearer


async def build(m: Mini) -> None:
    await build_home(m)
    # A new registration by O1 in range, one before it.
    await m.farmer("f4", "N1", "o1", None, created_at=ist(date(2026, 8, 5), 9))
    # Collections: O1 collected 1,500 in range and 900 before.
    await m.payment("N1", "f1", "o1", 1_500, ist(date(2026, 8, 6), 12))
    await m.payment("N1", "f1", "o1", 900, ist(date(2026, 7, 6), 12))
    # O2 went back on duty that evening and never ended it (open session, same duty day).
    await m.duty("o2", ist(date(2026, 8, 4), 19), None, km="0")
    await m.session.flush()


def rows(body: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {r["name"]: r for r in body["items"]}


async def test_scorecard_columns(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    await build(mini)
    resp = await get(client, bearer, mini.user("owner"), "/field-team", from_=FROM, to=TO)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["location_visible"] is True
    assert body["filters"]["from"] == "2026-08-01"
    assert [r["name"] for r in body["items"]] == ["User o2", "User o1"]
    o1 = rows(body)["User o1"]
    assert o1["rank"] == 2
    assert o1["duty_days"] == 2
    assert o1["visits"] == 2
    assert o1["verified_visits"] == 1
    assert o1["verified_visits_per_day"] == pytest.approx(0.5)
    assert o1["unique_farmers_reached"] == 1
    assert o1["new_registrations"] == 1
    assert o1["confirmation_rate"] == pytest.approx(0.5)
    assert o1["avg_time_on_farm_s"] == 20 * 60
    assert o1["time_on_farm_s"] == 20 * 60
    assert o1["km_per_day"] == pytest.approx(10.0)
    # F1 bought the day after a verified visit; F2 was visited (partial) and did not convert.
    assert (o1["converted_farmers"], o1["visited_farmers"]) == (1, 2)
    assert o1["conversion_rate"] == pytest.approx(0.5)
    assert o1["collections_paise"] == 1_500
    assert o1["flags"] == 0
    assert [p["value"] for p in o1["trend"]] == [1, 0]
    assert [p["start"] for p in o1["trend"]] == ["2026-08-01", "2026-08-08"]
    o2 = rows(body)["User o2"]
    assert o2["rank"] == 1
    assert o2["duty_days"] == 1  # two sessions, one IST day
    assert o2["conversion_rate"] == pytest.approx(1.0)
    assert o2["avg_time_on_farm_s"] == 20 * 60


async def test_store_manager_never_gets_location_figures(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    await build(mini)
    resp = await get(client, bearer, mini.user("store_manager"), "/field-team", from_=FROM, to=TO)
    body = resp.json()
    assert body["location_visible"] is False
    assert [r["name"] for r in body["items"]] == ["User o1"]
    assert body["items"][0]["km_per_day"] is None
    assert body["items"][0]["verified_visits"] == 1

    profile = await get(
        client, bearer, mini.user("store_manager"), f"/officers/{mini.user('o1').id}",
        from_=FROM, to=TO,
    )  # fmt: skip
    assert profile.status_code == 200
    assert profile.json()["location_visible"] is False
    assert all(d["km"] is None for d in profile.json()["duty_days"])
    assert profile.json()["scorecard"]["km_per_day"] is None


@pytest.mark.parametrize(("role", "names"), [("o1", ["User o1"]), ("cluster_head", ["User o1"])])
async def test_scorecard_scope(
    client: AsyncClient, bearer: Bearer, mini: Mini, role: str, names: list[str]
) -> None:
    await build(mini)
    resp = await get(client, bearer, mini.user(role), "/field-team", from_=FROM, to=TO)
    body = resp.json()
    assert [r["name"] for r in body["items"]] == names
    assert body["items"][0]["km_per_day"] == pytest.approx(10.0)


async def test_field_officer_cannot_name_a_colleague(
    client: AsyncClient, bearer: Bearer, mini: Mini
) -> None:
    o1, o2 = mini.user("o1"), mini.user("o2")
    resp = await get(client, bearer, o1, "/field-team", officer_id=o2.id)
    assert resp.status_code == 404
    resp = await get(client, bearer, o1, "/field-team", officer_id=o1.id)
    assert resp.status_code == 200
    resp = await get(client, bearer, o1, f"/officers/{o2.id}")
    assert resp.status_code == 404


@pytest.mark.parametrize("role", ["accountant", "agronomist", "farmer_user"])
async def test_scorecard_forbidden(
    client: AsyncClient, bearer: Bearer, mini: Mini, role: str
) -> None:
    resp = await get(client, bearer, mini.user(role), "/field-team")
    assert resp.status_code == 403


async def test_officer_profile(client: AsyncClient, bearer: Bearer, mini: Mini) -> None:
    await build(mini)
    owner = mini.user("owner")
    resp = await get(client, bearer, owner, f"/officers/{mini.user('o1').id}", from_=FROM, to=TO)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["name"] == "User o1"
    assert body["store_name"] == "Store N1"
    assert body["on_duty"] is False
    assert body["scorecard"]["verified_visits"] == 1
    assert [d["day"] for d in body["duty_days"]] == ["2026-08-03", "2026-08-02"]
    assert body["duty_days"][1]["km"] == pytest.approx(10.0)
    assert body["duty_days"][1]["verified_visits"] == 1
    assert body["duty_days"][1]["time_on_farm_s"] == 1_200
    assert [v["farmer_name"] for v in body["recent_visits"]] == ["Farmer F2", "Farmer F1"]

    resp = await get(client, bearer, owner, f"/officers/{mini.user('o2').id}", from_=FROM, to=TO)
    assert resp.json()["on_duty"] is True
    assert resp.json()["duty_days"][0]["end_at"] is None

    # Cluster head (north) cannot see the southern officer.
    head = mini.user("cluster_head")
    resp = await get(client, bearer, head, f"/officers/{mini.user('o2').id}")
    assert resp.status_code == 404
    resp = await get(client, bearer, owner, f"/officers/{mini.user('owner').id}")
    assert resp.status_code == 404  # not a field officer
