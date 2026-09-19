"""WC-010 backend: ``/v1/flags`` reads, scope per role, the SPEC 6.1 state machine, comments
(VA-005 explanation) and assignment."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.flags.models import FlagEvent, FlagStatus
from farmerapp.notifications.models import Notification
from farmerapp.tenants.models import Cluster
from tests.authz.conftest import Bearer
from tests.flags.conftest import Flagged, make_flag
from tests.rules.harness import add_user


async def _get(client: AsyncClient, bearer: Bearer, flagged: Flagged, who: str, url: str) -> dict:  # type: ignore[type-arg]
    resp = await client.get(url, headers=bearer(flagged.world.users[who]))
    assert resp.status_code == 200, resp.text
    body: dict = resp.json()  # type: ignore[type-arg]
    return body


# --------------------------------------------------------------------------- list
async def test_owner_inbox_counts_filters_and_pages(
    client: AsyncClient, bearer: Bearer, flagged: Flagged, db_session: AsyncSession
) -> None:
    body = await _get(client, bearer, flagged, "owner", "/v1/flags")
    assert body["counts"] == {
        "total": 6,
        "by_severity": {"high": 2, "medium": 4},
        "by_rule": {"VA-F06": 2, "VA-F03": 4},
    }
    assert len(body["items"]) == 6 and body["next_cursor"] is None
    item = body["items"][0]
    assert item["status"] == "open" and item["sla_due_at"] and "evidence" not in item

    high = await _get(client, bearer, flagged, "owner", "/v1/flags?severity=high")
    assert {i["rule_id"] for i in high["items"]} == {"VA-F06"}
    by_rule = await _get(client, bearer, flagged, "owner", "/v1/flags?rule_id=VA-F03")
    assert by_rule["counts"]["total"] == 4
    employees = await _get(client, bearer, flagged, "owner", "/v1/flags?subject_type=employee")
    assert employees["counts"]["total"] == 2
    open_ = await _get(client, bearer, flagged, "owner", "/v1/flags?status=open&status=in_review")
    assert open_["counts"]["total"] == 6
    none = await _get(client, bearer, flagged, "owner", "/v1/flags?status=resolved_valid")
    assert none["items"] == [] and none["counts"]["total"] == 0

    mine = await _get(client, bearer, flagged, "auditor", "/v1/flags?owner=me")
    assert mine["counts"]["by_rule"] == {"VA-F06": 2}  # watcher of the high severity flags

    late = flagged.one("officer")
    late.sla_due_at = datetime.now(UTC) - timedelta(hours=1)
    for flag in flagged.flags:
        if flag is not late:
            flag.sla_due_at = datetime.now(UTC) + timedelta(days=30)
    await db_session.flush()
    overdue = await _get(client, bearer, flagged, "owner", "/v1/flags?overdue=true")
    assert [i["id"] for i in overdue["items"]] == [str(late.id)]
    assert overdue["items"][0]["overdue"] is True
    on_time = await _get(client, bearer, flagged, "owner", "/v1/flags?overdue=false")
    assert on_time["counts"]["total"] == 5

    first = await _get(client, bearer, flagged, "owner", "/v1/flags?limit=4")
    assert len(first["items"]) == 4 and first["next_cursor"]
    second = await _get(
        client, bearer, flagged, "owner", f"/v1/flags?limit=4&cursor={first['next_cursor']}"
    )
    assert len(second["items"]) == 2 and second["next_cursor"] is None
    ids = [i["id"] for i in first["items"] + second["items"]]
    assert len(set(ids)) == 6


async def test_scope_per_role(
    client: AsyncClient, bearer: Bearer, flagged: Flagged, db_session: AsyncSession
) -> None:
    cluster_head = await _get(client, bearer, flagged, "cluster_head", "/v1/flags")
    assert cluster_head["counts"]["total"] == 6  # own cluster: officers and farmers of c1
    manager = await _get(client, bearer, flagged, "store_manager", "/v1/flags")
    assert manager["counts"]["by_rule"] == {"VA-F03": 4}  # farmer-data flags of the store
    officer = await _get(client, bearer, flagged, "officer", "/v1/flags")
    assert [i["subject_id"] for i in officer["items"]] == [str(flagged.world.refs["officer"])]
    officer2 = await _get(client, bearer, flagged, "officer2", "/v1/flags")
    assert [i["subject_id"] for i in officer2["items"]] == [str(flagged.world.refs["officer2"])]

    world = flagged.world
    other = Cluster(tenant_id=world.tenant_id, name="C2")
    db_session.add(other)
    await db_session.flush()
    world.refs["c2"] = other.id
    await add_user(db_session, world, "ch2", UserRole.CLUSTER_HEAD, cluster="c2")
    await add_user(db_session, world, "sm_none", UserRole.STORE_MANAGER)
    await add_user(db_session, world, "ch_none", UserRole.CLUSTER_HEAD)
    for who in ("ch2", "sm_none", "ch_none"):
        body = await _get(client, bearer, flagged, who, "/v1/flags")
        assert body["counts"]["total"] == 0, who
    flag = flagged.one("left")
    resp = await client.get(f"/v1/flags/{flag.id}", headers=bearer(world.users["ch2"]))
    assert resp.status_code == 404
    resp = await client.get(
        f"/v1/flags/{flagged.one('officer').id}", headers=bearer(world.users["officer2"])
    )
    assert resp.status_code == 404


# --------------------------------------------------------------------------- detail
async def test_detail_has_evidence_history_and_signed_photos(
    client: AsyncClient, bearer: Bearer, flagged: Flagged, db_session: AsyncSession
) -> None:
    world = flagged.world
    overlap = flagged.one("left")
    body = await _get(client, bearer, flagged, "store_manager", f"/v1/flags/{overlap.id}")
    types = {r["type"] for r in body["evidence"]["records"]}
    assert types == {"farmer", "farm"}
    farmer = next(r for r in body["evidence"]["records"] if r["id"] == str(world.refs["left"]))
    assert farmer["summary"]["name"] == "Ramesh" and "phone" not in farmer["summary"]
    farm = next(r for r in body["evidence"]["records"] if r["id"] == str(world.refs["farm_left"]))
    assert farm["summary"]["area_acres"] == 1.0
    assert body["evidence"]["map"]["polygons"][0]["type"] == "Polygon"
    assert body["evidence"]["metrics"]["reasons"] == ["farm_overlap"]
    assert [e["kind"] for e in body["events"]] == ["created"]
    assert body["allowed_transitions"] == ["in_review"]

    uri = f"gs://local/{world.tenant_id}/visit_photo/{'a' * 64}"
    photo_flag = await make_flag(db_session, world, "officer", photos=[uri, "not-a-blob-uri"])
    photo_flag.evidence = {
        **photo_flag.evidence,
        "records": [
            *photo_flag.evidence["records"],
            {"type": "store", "id": str(world.refs["s1"])},
            {"type": "visit", "id": str(world.refs["s1"])},  # unknown visit: empty summary
            {"type": "farm", "id": str(world.refs["s1"])},
            {"type": "farmer", "id": str(world.refs["s1"])},
            {"type": "user", "id": "not-a-uuid"},
            {"type": "crop", "id": str(world.refs["s1"])},
        ],
    }
    await db_session.flush()
    body = await _get(client, bearer, flagged, "owner", f"/v1/flags/{photo_flag.id}")
    photos = body["evidence"]["photos"]
    assert photos[0]["blob_uri"] == uri and photos[0]["signed_url"]
    assert photos[1] == {
        "blob_uri": "not-a-blob-uri",
        "signed_url": None,
        "signed_url_expires_at": None,
    }
    summaries = [r["summary"] for r in body["evidence"]["records"]]
    assert summaries[0]["role"] == "field_officer"
    assert summaries[1] == {"code": "S1", "name": "Store 1"}
    assert summaries[2:] == [{}, {}, {}, {}, {}]

    subject_view = await _get(client, bearer, flagged, "officer", f"/v1/flags/{photo_flag.id}")
    assert all(r["summary"] == {} for r in subject_view["evidence"]["records"])
    assert subject_view["allowed_transitions"] == []


# --------------------------------------------------------------------------- transitions
async def test_state_machine_labels_and_notes(
    client: AsyncClient, bearer: Bearer, flagged: Flagged, db_session: AsyncSession
) -> None:
    world = flagged.world
    flag = flagged.one("left")
    headers = bearer(world.users["store_manager"])
    url = f"/v1/flags/{flag.id}/transition"

    resp = await client.post(url, json={"to": "resolved_valid", "note": "fine"}, headers=headers)
    assert resp.status_code == 409 and resp.json()["code"] == "invalid_transition"
    assert resp.json()["allowed"] == ["in_review"]

    resp = await client.post(url, json={"to": "in_review"}, headers=headers)
    assert resp.status_code == 200 and resp.json()["status"] == "in_review"

    resp = await client.post(url, json={"to": "resolved_valid", "note": " "}, headers=headers)
    assert resp.status_code == 409 and resp.json()["reason"] == "note_required"

    resp = await client.post(
        url, json={"to": "resolved_valid", "note": "Brothers share the plot"}, headers=headers
    )
    body = resp.json()
    assert resp.status_code == 200, body
    assert body["status"] == "resolved_valid" and body["resolved_at"]
    assert body["resolved_by"] == str(world.refs["store_manager"])
    assert body["resolution_note"] == "Brothers share the plot"
    assert body["allowed_transitions"] == []
    assert [(e["kind"], e["label"]) for e in body["events"]] == [
        ("created", None),
        ("transition", None),
        ("transition", "false_positive"),
    ]

    resp = await client.post(url, json={"to": "in_review"}, headers=headers)
    assert resp.status_code == 409
    resp = await client.post(
        f"/v1/flags/{flag.id}/comments", json={"body": "late"}, headers=headers
    )
    assert resp.status_code == 409 and resp.json()["code"] == "flag_resolved"

    officer = await client.post(
        f"/v1/flags/{flagged.one('officer').id}/transition",
        json={"to": "in_review"},
        headers=bearer(world.users["officer"]),
    )
    assert officer.status_code == 403


async def test_escalation_hands_the_flag_to_an_auditor(
    client: AsyncClient, bearer: Bearer, flagged: Flagged, db_session: AsyncSession
) -> None:
    world = flagged.world
    flag = flagged.one("right")
    assert flag.owner_id == world.refs["store_manager"]
    headers = bearer(world.users["store_manager"])
    url = f"/v1/flags/{flag.id}/transition"
    await client.post(url, json={"to": "in_review"}, headers=headers)
    resp = await client.post(
        url, json={"to": "escalated", "note": "Needs a site visit"}, headers=headers
    )
    body = resp.json()
    assert resp.status_code == 200, body
    assert body["status"] == "escalated"
    assert body["owner_id"] == str(world.refs["auditor"]) and body["owner_role"] == "auditor"
    note = (
        await db_session.execute(
            select(Notification).where(
                Notification.user_id == world.refs["auditor"],
                Notification.kind == "flag_escalated",
            )
        )
    ).scalar_one()
    assert note.data["flag_id"] == str(flag.id)
    assert note.title_key == "notification.flag_escalated.title"

    # The store manager no longer owns it, but the farmer-data flag is still in their store.
    resp = await client.post(
        url,
        json={"to": "resolved_action", "note": "Boundary re-walked"},
        headers=bearer(world.users["auditor"]),
    )
    assert resp.status_code == 200
    labels = (
        (
            await db_session.execute(
                select(FlagEvent.label).where(
                    FlagEvent.flag_id == flag.id, FlagEvent.label.is_not(None)
                )
            )
        )
        .scalars()
        .all()
    )
    assert labels == ["true_positive"]

    # Escalating a flag already owned by an auditor keeps the owner.
    other = flagged.one("bowtie")
    other.owner_id, other.owner_role = world.refs["auditor"], UserRole.AUDITOR.value
    other.status = FlagStatus.IN_REVIEW.value
    await db_session.flush()
    resp = await client.post(
        f"/v1/flags/{other.id}/transition",
        json={"to": "escalated", "note": "HR"},
        headers=bearer(world.users["owner"]),
    )
    assert resp.json()["owner_id"] == str(world.refs["auditor"])


# --------------------------------------------------------------------------- comments
async def test_subject_explains_and_reviewers_discuss(
    client: AsyncClient, bearer: Bearer, flagged: Flagged
) -> None:
    world = flagged.world
    flag = flagged.one("officer")
    url = f"/v1/flags/{flag.id}/comments"
    resp = await client.post(
        url,
        json={"body": "Registration camp at the rythu vedika"},
        headers=bearer(world.users["officer"]),
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["is_subject_explanation"] is True
    resp = await client.post(
        url, json={"body": "Checking the camp photos"}, headers=bearer(world.users["cluster_head"])
    )
    assert resp.status_code == 201 and resp.json()["is_subject_explanation"] is False
    resp = await client.post(url, json={"body": "me too"}, headers=bearer(world.users["officer2"]))
    assert resp.status_code == 404
    resp = await client.post(url, json={"body": ""}, headers=bearer(world.users["officer"]))
    assert resp.status_code == 422
    detail = await _get(client, bearer, flagged, "officer", f"/v1/flags/{flag.id}")
    assert [c["is_subject_explanation"] for c in detail["comments"]] == [True, False]


# --------------------------------------------------------------------------- assign
async def test_assign(
    client: AsyncClient, bearer: Bearer, flagged: Flagged, db_session: AsyncSession
) -> None:
    world = flagged.world
    flag = flagged.one("officer")
    url = f"/v1/flags/{flag.id}/assign"
    headers = bearer(world.users["owner"])
    resp = await client.post(
        url,
        json={"user_id": str(world.refs["auditor"]), "note": "Please take this"},
        headers=headers,
    )
    body = resp.json()
    assert resp.status_code == 200, body
    assert body["owner_id"] == str(world.refs["auditor"]) and body["owner_role"] == "auditor"
    assert body["events"][-1]["kind"] == "assigned"
    assert body["events"][-1]["from_owner_id"] == str(world.refs["cluster_head"])

    for bad in (world.refs["officer2"], world.refs["c1"]):
        resp = await client.post(url, json={"user_id": str(bad)}, headers=headers)
        assert resp.status_code == 422 and resp.json()["code"] == "assignee_invalid"

    about_manager = await make_flag(db_session, world, "store_manager")
    resp = await client.post(
        f"/v1/flags/{about_manager.id}/assign",
        json={"user_id": str(world.refs["store_manager"])},
        headers=headers,
    )
    assert resp.status_code == 422

    about_manager.status = FlagStatus.IN_REVIEW.value
    await db_session.flush()
    await client.post(
        f"/v1/flags/{about_manager.id}/transition",
        json={"to": "resolved_fixed", "note": "done"},
        headers=headers,
    )
    resp = await client.post(
        f"/v1/flags/{about_manager.id}/assign",
        json={"user_id": str(world.refs["auditor"])},
        headers=headers,
    )
    assert resp.status_code == 409 and resp.json()["code"] == "flag_resolved"
