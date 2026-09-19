"""VA-005: an employee sees the flags about themselves, explains them while open, and sees
the outcome only once they are resolved; they never review their own flag."""

from __future__ import annotations

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.flags.models import FlagStatus
from farmerapp.flags.service import transition
from tests.authz.conftest import Bearer
from tests.flags.conftest import Flagged, make_flag


async def test_officer_sees_own_flags_outcome_only_after_resolution(
    client: AsyncClient, bearer: Bearer, flagged: Flagged, db_session: AsyncSession
) -> None:
    world = flagged.world
    flag = flagged.one("officer")
    officer = world.users["officer"]

    resp = await client.get("/v1/flags/mine", headers=bearer(officer))
    assert resp.status_code == 200, resp.text
    items = resp.json()["items"]
    assert [i["id"] for i in items] == [str(flag.id)]  # not officer2's, not farmer flags
    item = items[0]
    assert item["state"] == "open" and item["can_explain"] is True and item["outcome"] is None
    assert item["rule_id"] == "VA-F06" and item["rule_title"] == "Registration burst"
    assert "owner_id" not in item and "watchers" not in item

    # while open: explain it (the explanation is marked as the subject's)
    resp = await client.post(
        f"/v1/flags/mine/{flag.id}/explanations",
        json={"body": "Registration camp at the rythu vedika"},
        headers=bearer(officer),
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["is_subject_explanation"] is True

    # review happens: in review, escalated with an internal note - still "in review" to them
    cluster_head = world.users["cluster_head"]
    now = flag.created_at
    await transition(db_session, cluster_head, flag, FlagStatus.IN_REVIEW, None, now=now)
    await transition(db_session, cluster_head, flag, FlagStatus.ESCALATED, "HR please", now=now)
    detail = (await client.get(f"/v1/flags/mine/{flag.id}", headers=bearer(officer))).json()
    assert detail["state"] == "in_review" and detail["outcome"] is None
    assert "HR please" not in str(detail)
    assert [e["body"] for e in detail["explanations"]] == ["Registration camp at the rythu vedika"]
    assert all(r["summary"] == {} for r in detail["evidence"]["records"])  # ids only

    # resolved: the outcome appears, explanations close
    auditor = world.users["auditor"]
    await transition(
        db_session, auditor, flag, FlagStatus.RESOLVED_FIXED, "Camp confirmed; data fixed", now=now
    )
    resolved = (await client.get("/v1/flags/mine?state=resolved", headers=bearer(officer))).json()
    (item,) = resolved["items"]
    assert item["state"] == "resolved" and item["can_explain"] is False
    assert item["outcome"]["status"] == "resolved_fixed"
    assert item["outcome"]["label"] == "true_positive"
    assert item["outcome"]["note"] == "Camp confirmed; data fixed"
    still_open = (await client.get("/v1/flags/mine?state=open", headers=bearer(officer))).json()
    assert still_open["items"] == []
    resp = await client.post(
        f"/v1/flags/mine/{flag.id}/explanations", json={"body": "late"}, headers=bearer(officer)
    )
    assert resp.status_code == 409 and resp.json()["code"] == "flag_resolved"


async def test_others_cannot_see_or_explain(
    client: AsyncClient, bearer: Bearer, flagged: Flagged
) -> None:
    world = flagged.world
    flag = flagged.one("officer")
    other = world.users["officer2"]
    assert (await client.get(f"/v1/flags/mine/{flag.id}", headers=bearer(other))).status_code == 404
    resp = await client.post(
        f"/v1/flags/mine/{flag.id}/explanations", json={"body": "x"}, headers=bearer(other)
    )
    assert resp.status_code == 404
    # a reviewer's own /mine view does not list flags about other people
    mine = (await client.get("/v1/flags/mine", headers=bearer(world.users["owner"]))).json()
    assert mine["items"] == []


async def test_any_staff_subject_can_explain_and_never_review(
    client: AsyncClient, bearer: Bearer, flagged: Flagged, db_session: AsyncSession
) -> None:
    """A store manager (VA-E10 cash variance) or a cluster head can be the subject too."""
    world = flagged.world
    about_manager = await make_flag(db_session, world, "store_manager", rule_id="VA-E10")
    manager = world.users["store_manager"]
    listing = (await client.get("/v1/flags/mine", headers=bearer(manager))).json()
    assert [i["id"] for i in listing["items"]] == [str(about_manager.id)]
    resp = await client.post(
        f"/v1/flags/mine/{about_manager.id}/explanations",
        json={"body": "Counted twice; the bank slip is attached"},
        headers=bearer(manager),
    )
    assert resp.status_code == 201

    about_head = await make_flag(db_session, world, "cluster_head", rule_id="VA-E09")
    head = world.users["cluster_head"]
    resp = await client.post(
        f"/v1/flags/{about_head.id}/transition",
        json={"to": "in_review"},
        headers=bearer(head),
    )
    assert resp.status_code == 403 and resp.json()["code"] == "subject_cannot_review"
    detail = await client.get(f"/v1/flags/{about_head.id}", headers=bearer(head))
    assert detail.status_code == 200
    assert detail.json()["allowed_transitions"] == []
    assert detail.json()["automated_summary"] is None
