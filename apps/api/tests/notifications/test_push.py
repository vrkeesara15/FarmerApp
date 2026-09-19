"""FA-007 acceptance: "notification delivered and listed in inbox" (with the fake sender).

Push tokens, the ``notify.send`` worker handler (and the sweeper), retries / failure /
unregistered tokens / lost devices, deep links, the inbox endpoints and the offline inbox in
the sync feed. The FCM HTTP v1 adapter is tested against a mocked transport; a real device
receiving a push is a human gate.
"""

from __future__ import annotations

import contextlib
import json
import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta

import httpx
import pytest
from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import Device, DeviceStatus
from farmerapp.notifications.delivery import (
    ROUTES,
    SessionProvider,
    backoff,
    deep_link,
    deliver_pending,
    handle_notify_message,
)
from farmerapp.notifications.models import Notification, PushToken
from farmerapp.notifications.push import (
    DisabledPushSender,
    FakePushSender,
    FcmPushSender,
    PushMessage,
    build_push_sender,
    fcm_body,
)
from farmerapp.notifications.service import notify
from farmerapp.payments.publisher import encode
from farmerapp.sync.models import SyncChange
from farmerapp.worker.messages import PubSubMessage
from tests.analytics.builders import Mini
from tests.authz.conftest import Bearer
from tests.field_tokens import mint_bearer


@pytest.fixture
def bearer(app: FastAPI) -> Bearer:
    return mint_bearer(app)


NOW = datetime(2026, 9, 21, 5, 0, tzinfo=UTC)
TOKEN_A = "fcm-token-device-a-" + "x" * 40
TOKEN_B = "fcm-token-device-b-" + "y" * 40


@pytest.fixture
async def mini(db_session: AsyncSession) -> Mini:
    return await Mini.create(db_session)


def provider(session: AsyncSession) -> SessionProvider:
    """``session_provider`` for the worker handler: the test's own transaction."""

    @contextlib.asynccontextmanager
    async def _session(_tenant: uuid.UUID) -> AsyncIterator[AsyncSession]:
        yield session

    return _session


def message(tenant_id: uuid.UUID, notification_id: uuid.UUID | None = None) -> PubSubMessage:
    data: dict[str, str] = {"tenant_id": str(tenant_id)}
    if notification_id is not None:
        data["notification_id"] = str(notification_id)
    return PubSubMessage(data=encode(data), attributes={"topic": "notify.send"}, message_id="1")


async def register(client: AsyncClient, headers: dict[str, str], token: str) -> httpx.Response:
    return await client.post(
        "/v1/devices/me/push-token",
        json={"token": token, "platform": "android", "app_version": "0.7.0"},
        headers={**headers, "X-Device-Id": "device-a"},
    )


async def test_notification_delivered_and_listed_in_inbox(
    client: AsyncClient, bearer: Bearer, mini: Mini, db_session: AsyncSession
) -> None:
    officer = mini.user("o1")
    headers = bearer(officer)
    resp = await register(client, headers, TOKEN_A)
    assert resp.status_code == 200, resp.text
    assert resp.json()["token_suffix"] == TOKEN_A[-6:] and resp.json()["active"] is True
    assert TOKEN_A not in resp.text  # never echoed

    row = notify(
        db_session,
        tenant_id=mini.tid,
        user_id=officer.id,
        kind="order_status",
        data={"order_id": uuid.uuid4(), "status": "packed"},
        body="order.status.packed",
    )
    await db_session.flush()
    assert row.delivery_status == "pending"

    sender = FakePushSender()
    report = await handle_notify_message(
        message(mini.tid, row.id), sender=sender, session_provider=provider(db_session), now=NOW
    )
    assert report is not None and report.delivered == 1
    await db_session.refresh(row)
    assert row.delivery_status == "delivered" and row.delivered_at == NOW and row.attempts == 1
    assert len(sender.sent) == 1
    pushed = sender.sent[0]
    assert pushed.token == TOKEN_A and pushed.title_key == "notification.order_status.title"
    assert pushed.data["route"] == f"/orders/{row.data['order_id']}"
    assert pushed.data["notification_id"] == str(row.id)
    assert all(isinstance(v, str) for v in pushed.data.values())

    # Listed in the inbox, unread; then read.
    inbox = await client.get("/v1/notifications", headers=headers)
    assert inbox.status_code == 200, inbox.text
    body = inbox.json()
    assert body["unread"] == 1
    assert [n["id"] for n in body["items"]] == [str(row.id)]
    item = body["items"][0]
    assert item["delivery_status"] == "delivered" and item["route"].startswith("/orders/")
    resp = await client.post(f"/v1/notifications/{row.id}/read", headers=headers)
    assert resp.status_code == 200 and resp.json()["read_at"] is not None
    assert (await client.get("/v1/notifications", headers=headers)).json()["unread"] == 0

    # Somebody else's notification is a 404; their inbox does not show it.
    other = bearer(mini.user("o2"))
    assert (await client.post(f"/v1/notifications/{row.id}/read", headers=other)).status_code == 404
    assert (await client.get("/v1/notifications", headers=other)).json()["items"] == []


async def test_inbox_pagination_unread_filter_and_read_all(
    client: AsyncClient, bearer: Bearer, mini: Mini, db_session: AsyncSession
) -> None:
    officer = mini.user("o1")
    for i in range(5):
        db_session.add(
            Notification(
                tenant_id=mini.tid,
                user_id=officer.id,
                kind="duty_auto_ended",
                title_key="t",
                body_key="b",
                data={},
                created_at=NOW + timedelta(minutes=i),
            )
        )
    await db_session.flush()
    headers = bearer(officer)
    first = (await client.get("/v1/notifications", params={"limit": 3}, headers=headers)).json()
    assert len(first["items"]) == 3 and first["next_cursor"]
    times = [i["created_at"] for i in first["items"]]
    assert times == sorted(times, reverse=True)  # newest first
    rest = (
        await client.get(
            "/v1/notifications",
            params={"limit": 3, "cursor": first["next_cursor"]},
            headers=headers,
        )
    ).json()
    assert len(rest["items"]) == 2 and rest["next_cursor"] is None
    resp = await client.post("/v1/notifications/read-all", headers=headers)
    assert resp.json() == {"marked": 5}
    unread = await client.get("/v1/notifications", params={"unread_only": "true"}, headers=headers)
    assert unread.json()["items"] == [] and unread.json()["unread"] == 0


async def test_retries_back_off_then_fail(db_session: AsyncSession, mini: Mini) -> None:
    officer = mini.user("o1")
    db_session.add(
        PushToken(
            tenant_id=mini.tid,
            user_id=officer.id,
            token=TOKEN_A,
            platform="android",
            last_registered_at=NOW,
        )
    )
    row = notify(db_session, tenant_id=mini.tid, user_id=officer.id, kind="beat_plan_ready")
    await db_session.flush()
    sender = FakePushSender(script={TOKEN_A: "retryable"})

    report = await deliver_pending(db_session, sender, tenant_id=mini.tid, now=NOW, max_attempts=3)
    assert report.retrying == 1
    assert row.delivery_status == "pending" and row.attempts == 1
    assert row.next_attempt_at == NOW + timedelta(minutes=1)
    # Not due yet: nothing happens.
    again = await deliver_pending(db_session, sender, tenant_id=mini.tid, now=NOW, max_attempts=3)
    assert again.handled == 0
    later = NOW + timedelta(minutes=1)
    await deliver_pending(db_session, sender, tenant_id=mini.tid, now=later, max_attempts=3)
    assert row.attempts == 2 and row.next_attempt_at == later + timedelta(minutes=2)
    last = later + timedelta(minutes=2)
    await deliver_pending(db_session, sender, tenant_id=mini.tid, now=last, max_attempts=3)
    assert row.delivery_status == "failed" and row.attempts == 3 and row.last_error
    assert backoff(10) == timedelta(hours=1)


async def test_unregistered_tokens_are_disabled_and_lost_devices_skipped(
    db_session: AsyncSession, mini: Mini
) -> None:
    officer = mini.user("o1")
    db_session.add_all(
        [
            PushToken(
                tenant_id=mini.tid,
                user_id=officer.id,
                token=TOKEN_A,
                platform="android",
                device_id="old-phone",
                last_registered_at=NOW,
            ),
            PushToken(
                tenant_id=mini.tid,
                user_id=officer.id,
                token=TOKEN_B,
                platform="android",
                device_id="lost-phone",
                last_registered_at=NOW,
            ),
            Device(
                tenant_id=mini.tid,
                user_id=officer.id,
                device_id="lost-phone",
                first_seen=NOW,
                last_seen=NOW,
                status=DeviceStatus.LOST.value,
            ),
        ]
    )
    row = notify(db_session, tenant_id=mini.tid, user_id=officer.id, kind="flag_assigned")
    await db_session.flush()
    sender = FakePushSender(script={TOKEN_A: "unregistered"})
    await deliver_pending(db_session, sender, tenant_id=mini.tid, now=NOW)
    assert [m.token for m in sender.attempts] == [TOKEN_A]  # the lost phone never gets it
    assert row.delivery_status == "failed"
    token = await db_session.scalar(select(PushToken).where(PushToken.token == TOKEN_A))
    assert token is not None and token.disabled_at == NOW
    assert token.disabled_reason == "unregistered"


async def test_no_device_is_inbox_only(db_session: AsyncSession, mini: Mini) -> None:
    row = notify(db_session, tenant_id=mini.tid, user_id=mini.user("o2").id, kind="x_unknown")
    await db_session.flush()
    report = await deliver_pending(db_session, FakePushSender(), tenant_id=mini.tid, now=NOW)
    assert report.no_device == 1 and row.delivery_status == "no_device"
    assert deep_link(row)["route"] == "/inbox"


async def test_token_moves_with_the_login_and_logout_removes_it(
    client: AsyncClient, bearer: Bearer, mini: Mini, db_session: AsyncSession
) -> None:
    assert (await register(client, bearer(mini.user("o1")), TOKEN_A)).status_code == 200
    assert (await register(client, bearer(mini.user("o2")), TOKEN_A)).status_code == 200
    rows = (await db_session.execute(select(PushToken).where(PushToken.token == TOKEN_A))).all()
    assert len(rows) == 1 and rows[0][0].user_id == mini.user("o2").id
    resp = await client.post(
        "/v1/devices/me/push-token/remove",
        json={"token": TOKEN_A},
        headers=bearer(mini.user("o1")),
    )
    assert resp.json() == {"removed": 0}  # not o1's any more
    resp = await client.post(
        "/v1/devices/me/push-token/remove",
        json={"token": TOKEN_A},
        headers=bearer(mini.user("o2")),
    )
    assert resp.json() == {"removed": 1}


async def test_worker_message_handling(db_session: AsyncSession, mini: Mini) -> None:
    bad = PubSubMessage(data=encode({"nope": 1}), message_id="x")
    assert await handle_notify_message(bad, sender=FakePushSender()) is None
    officer = mini.user("o1")
    db_session.add(
        PushToken(
            tenant_id=mini.tid,
            user_id=officer.id,
            token=TOKEN_A,
            platform="android",
            last_registered_at=NOW,
        )
    )
    notify(db_session, tenant_id=mini.tid, user_id=officer.id, kind="duty_auto_ended")
    notify(db_session, tenant_id=mini.tid, user_id=officer.id, kind="beat_plan_ready")
    await db_session.flush()
    report = await handle_notify_message(  # tenant-wide drain
        message(mini.tid), sender=FakePushSender(), session_provider=provider(db_session), now=NOW
    )
    assert report is not None and report.delivered == 2

    from farmerapp.notifications.delivery import NotifyRetryError

    row = notify(db_session, tenant_id=mini.tid, user_id=officer.id, kind="flag_escalated")
    await db_session.flush()
    with pytest.raises(NotifyRetryError):  # a single row with only retryable failures: nack
        await handle_notify_message(
            message(mini.tid, row.id),
            sender=DisabledPushSender(),
            session_provider=provider(db_session),
            now=NOW,
        )


async def test_notifications_are_in_the_sync_feed(
    client: AsyncClient, bearer: Bearer, mini: Mini, db_session: AsyncSession
) -> None:
    officer = mini.user("o1")
    row = notify(db_session, tenant_id=mini.tid, user_id=officer.id, kind="beat_plan_ready")
    notify(db_session, tenant_id=mini.tid, user_id=mini.user("o2").id, kind="beat_plan_ready")
    await db_session.flush()
    changes = (
        (await db_session.execute(select(SyncChange).where(SyncChange.entity == "notification")))
        .scalars()
        .all()
    )
    assert {c.action for c in changes} == {"create"} and len(changes) == 2

    resp = await client.post(
        "/v1/sync", json={"device_id": "d1", "cursor": None, "ops": []}, headers=bearer(officer)
    )
    assert resp.status_code == 200, resp.text
    feed = [c for c in resp.json()["changes"] if c["entity"] == "notification"]
    assert [c["entity_id"] for c in feed] == [str(row.id)]  # only the officer's own
    cursor = resp.json()["cursor"]

    # Offline read receipt: an update op sets read_at.
    op = {
        "op_id": str(uuid.uuid4()),
        "entity": "notification",
        "action": "update",
        "entity_id": str(row.id),
        "base_version": 1,
        "payload": {"read_at": NOW.isoformat()},
        "client_ts": NOW.isoformat(),
    }
    resp = await client.post(
        "/v1/sync", json={"device_id": "d1", "cursor": cursor, "ops": [op]}, headers=bearer(officer)
    )
    result = resp.json()["results"][0]
    assert result["status"] == "applied", result
    assert result["server"]["read_at"] is not None
    feed = [c for c in resp.json()["changes"] if c["entity"] == "notification"]
    assert feed and feed[0]["action"] == "update"


async def test_fcm_sender_maps_responses() -> None:
    seen: list[dict[str, object]] = []
    replies = iter(
        [
            httpx.Response(200, json={"name": "projects/p/messages/1"}),
            httpx.Response(
                404,
                json={
                    "error": {
                        "status": "NOT_FOUND",
                        "details": [{"errorCode": "UNREGISTERED"}],
                    }
                },
            ),
            httpx.Response(429, json={"error": {"status": "RESOURCE_EXHAUSTED"}}),
            httpx.Response(503, json={"error": {"status": "UNAVAILABLE"}}),
            httpx.Response(403, json={"error": {"status": "PERMISSION_DENIED"}}),
            httpx.Response(400, json={"error": {"status": "INVALID_ARGUMENT"}}),
        ]
    )

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["authorization"] == "Bearer oauth-token"
        assert request.url.path == "/v1/projects/demo-project/messages:send"
        seen.append(json.loads(request.content))
        return next(replies)

    async def token() -> str:
        return "oauth-token"

    sender = FcmPushSender(
        project="demo-project",
        token_provider=token,
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )
    msg = PushMessage(token=TOKEN_A, title_key="t.k", body_key="b.k", data={"route": "/inbox"})
    outcomes = [(await sender.send(msg)).outcome for _ in range(6)]
    assert outcomes == ["ok", "unregistered", "retryable", "retryable", "error", "unregistered"]
    body = seen[0]["message"]
    assert isinstance(body, dict)
    assert body["token"] == TOKEN_A and body["data"] == {"route": "/inbox"}
    assert body["android"]["notification"]["title_loc_key"] == "t.k"

    def broken(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("down")

    offline = FcmPushSender(
        project="p",
        token_provider=token,
        client=httpx.AsyncClient(transport=httpx.MockTransport(broken)),
    )
    assert (await offline.send(msg)).outcome == "retryable"
    assert fcm_body(msg)["message"]["apns"]["payload"]["aps"]["alert"]["loc-key"] == "b.k"


def test_deep_links_and_sender_factory() -> None:
    row = Notification(
        id=uuid.uuid4(),
        tenant_id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        kind="visit_confirm_request",
        title_key="t",
        body_key="b",
        data={"visit_id": "v1", "confirmation_id": "c1", "nested": {"x": 1}},
    )
    link = deep_link(row)
    assert link["route"] == "/visits/v1/confirm" and "nested" not in link
    assert {
        "diagnosis_reviewed",
        "order_status",
        "credit_approval_decided",
        "flag_assigned",
    } <= set(ROUTES)
    assert isinstance(build_push_sender("fake", "p"), FakePushSender)
    assert isinstance(build_push_sender("off", "p"), DisabledPushSender)


async def test_worker_dispatches_notify_send() -> None:
    from farmerapp.worker.dispatch import HANDLERS
    from farmerapp.worker.topics import Topic

    await HANDLERS[Topic.NOTIFY_SEND](PubSubMessage(data=encode({"x": 1}), message_id="m"))


async def test_credit_decision_notifies_the_requesting_officer(
    db_session: AsyncSession, mini: Mini
) -> None:
    from farmerapp.khata.credit import decide
    from farmerapp.khata.models import CreditApprovalRequest

    request = CreditApprovalRequest(
        tenant_id=mini.tid,
        farmer_id=mini.farmers["f1"].id,
        store_id=mini.stores["N1"].id,
        amount_paise=10_000,
        balance_paise=0,
        limit_paise=5_000,
        shortfall_paise=5_000,
        requested_by=mini.user("o1").id,
        status="pending",
    )
    await mini.add(request)
    await decide(db_session, mini.user("cluster_head"), request, approve=True, note=None)
    row = await db_session.scalar(
        select(Notification).where(Notification.kind == "credit_approval_decided")
    )
    assert row is not None and row.user_id == mini.user("o1").id
    assert row.data["approval_id"] == str(request.id)
    assert deep_link(row)["route"] == f"/credit-approvals/{request.id}"
    assert row.body_key == "notification.credit_approval_decided.body.approved"
