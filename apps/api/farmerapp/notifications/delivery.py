"""FA-007 push delivery of ``notification`` rows to the user's active devices.

Every row any job or write path adds (VV-007 duty auto end, OPS-006 / OPS-007 alerts, flag
routing, diagnosis results, order status, credit approvals, visit confirmation prompts, ...)
starts ``pending``. Delivery pushes it to each **active** push token of the user — not
disabled, and not on a device reported ``lost`` or ``revoked`` (SEC-025) — with a data
payload the apps deep-link from (``deep_link``):

* at least one token accepted -> ``delivered`` (``delivered_at``);
* no active token -> ``no_device`` (the in-app inbox still lists it);
* only retryable failures (429 / 5xx / network / push off) -> stays ``pending`` with
  ``attempts + 1`` and ``next_attempt_at`` backed off (1, 2, 4, 8 ... minutes, capped at an
  hour); after ``NOTIFY_MAX_ATTEMPTS`` -> ``failed`` with ``last_error``;
* a token FCM calls ``UNREGISTERED`` is disabled on the spot.

Entry points: the ``notify.send`` worker handler (``handle_notify_message``: payload
``{"tenant_id", "notification_id"?}`` — one row, or every due row of the tenant) and the
``deliver-notifications`` job (the sweeper, every minute in Cloud Scheduler). Rows are locked
``FOR UPDATE SKIP LOCKED``, so the two never push the same row twice at once.
"""

from __future__ import annotations

import contextlib
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import Device, DeviceStatus
from farmerapp.db.session import job_session
from farmerapp.logging import get_logger
from farmerapp.notifications.models import DeliveryStatus, Notification, PushToken
from farmerapp.notifications.push import PushMessage, PushSender
from farmerapp.worker.messages import PubSubMessage

log = get_logger("farmerapp.notifications.delivery")

BACKOFF_BASE = timedelta(minutes=1)
BACKOFF_MAX = timedelta(hours=1)
DRAIN_LIMIT = 200

SessionProvider = Callable[[uuid.UUID], contextlib.AbstractAsyncContextManager[AsyncSession]]

#: Where the apps open a notification (FA-007 deep links). ``{name}`` placeholders come from
#: the row's ``data``; a missing id falls back to the inbox.
ROUTES: dict[str, str] = {
    "visit_confirm_request": "/visits/{visit_id}/confirm",
    "diagnosis_ready": "/diagnoses/{diagnosis_id}",
    "diagnosis_reviewed": "/diagnoses/{diagnosis_id}",
    "diagnosis_expert_requested": "/diagnoses/{diagnosis_id}",
    "order_status": "/orders/{order_id}",
    "credit_approval_decided": "/credit-approvals/{approval_id}",
    "flag_assigned": "/flags/{flag_id}",
    "flag_escalated": "/flags/{flag_id}",
    "duty_auto_ended": "/duty",
    "officer_sync_silence": "/field-team/{officer_id}",
    "travel_claim_submitted": "/travel/claims/{claim_id}",
    "travel_claim_decided": "/travel/claims/{claim_id}",
    "beat_plan_ready": "/beat/{date}",
}
INBOX_ROUTE = "/inbox"


def deep_link(row: Notification) -> dict[str, str]:
    """FCM data payload (string values only): ids of the row plus ``route``."""
    data: dict[str, Any] = dict(row.data or {})
    payload = {
        k: str(v) for k, v in data.items() if isinstance(v, str | int | float | bool | uuid.UUID)
    }
    template = ROUTES.get(row.kind)
    route = INBOX_ROUTE
    if template is not None:
        try:
            route = template.format(**payload)
        except (KeyError, IndexError):
            route = INBOX_ROUTE
    payload.update(
        {
            "notification_id": str(row.id),
            "kind": row.kind,
            "title_key": row.title_key,
            "body_key": row.body_key,
            "route": route,
        }
    )
    return payload


def backoff(attempts: int) -> timedelta:
    delay: timedelta = BACKOFF_BASE * (2 ** max(attempts - 1, 0))
    return min(delay, BACKOFF_MAX)


def _mask(token: str) -> str:
    return f"...{token[-6:]}"


async def active_tokens(
    session: AsyncSession, tenant_id: uuid.UUID, user_id: uuid.UUID
) -> list[PushToken]:
    """The user's enabled tokens, minus those on a lost / revoked device."""
    blocked = select(Device.device_id).where(
        Device.tenant_id == tenant_id,
        Device.user_id == user_id,
        Device.status.in_([DeviceStatus.LOST.value, DeviceStatus.REVOKED.value]),
    )
    rows = await session.execute(
        select(PushToken)
        .where(
            PushToken.tenant_id == tenant_id,
            PushToken.user_id == user_id,
            PushToken.disabled_at.is_(None),
            PushToken.deleted_at.is_(None),
            or_(PushToken.device_id.is_(None), PushToken.device_id.not_in(blocked)),
        )
        .order_by(PushToken.last_registered_at.desc())
    )
    return list(rows.scalars())


@dataclass
class DeliveryReport:
    delivered: int = 0
    no_device: int = 0
    retrying: int = 0
    failed: int = 0
    notification_ids: list[uuid.UUID] = field(default_factory=list)

    @property
    def handled(self) -> int:
        return self.delivered + self.no_device + self.retrying + self.failed


async def deliver_one(
    session: AsyncSession,
    sender: PushSender,
    row: Notification,
    *,
    now: datetime,
    max_attempts: int,
) -> str:
    """Push one pending row; returns its new ``delivery_status``."""
    tokens = await active_tokens(session, row.tenant_id, row.user_id)
    if not tokens:
        row.delivery_status = DeliveryStatus.NO_DEVICE.value
        row.next_attempt_at = None
        await session.flush()
        return row.delivery_status
    data = deep_link(row)
    ok = 0
    errors: list[str] = []
    retryable = False
    for token in tokens:
        result = await sender.send(
            PushMessage(
                token=token.token,
                title_key=row.title_key,
                body_key=row.body_key,
                data=data,
                platform=token.platform,
            )
        )
        if result.outcome == "ok":
            ok += 1
            continue
        errors.append(f"{result.outcome}:{result.detail or ''}"[:60])
        if result.outcome == "unregistered":
            token.disabled_at = now
            token.disabled_reason = "unregistered"
            log.info("push_token_disabled", token=_mask(token.token), user_id=str(row.user_id))
        elif result.outcome == "retryable":
            retryable = True
    row.attempts += 1
    if ok:
        row.delivery_status = DeliveryStatus.DELIVERED.value
        row.delivered_at = now
        row.next_attempt_at = None
        row.last_error = None
    elif retryable and row.attempts < max_attempts:
        row.next_attempt_at = now + backoff(row.attempts)
        row.last_error = "; ".join(errors)[:200]
    else:
        row.delivery_status = DeliveryStatus.FAILED.value
        row.next_attempt_at = None
        row.last_error = ("; ".join(errors) or "no token accepted the message")[:200]
    await session.flush()
    log.info(
        "notification_push",
        notification_id=str(row.id),
        kind=row.kind,
        status=row.delivery_status,
        attempts=row.attempts,
        tokens=len(tokens),
        accepted=ok,
    )
    return row.delivery_status


def _count(report: DeliveryReport, status: str, row: Notification) -> None:
    report.notification_ids.append(row.id)
    if status == DeliveryStatus.DELIVERED:
        report.delivered += 1
    elif status == DeliveryStatus.NO_DEVICE:
        report.no_device += 1
    elif status == DeliveryStatus.FAILED:
        report.failed += 1
    else:
        report.retrying += 1


def _due(tenant_id: uuid.UUID, now: datetime) -> list[Any]:
    return [
        Notification.tenant_id == tenant_id,
        Notification.delivery_status == DeliveryStatus.PENDING.value,
        or_(Notification.next_attempt_at.is_(None), Notification.next_attempt_at <= now),
    ]


async def deliver_pending(
    session: AsyncSession,
    sender: PushSender,
    *,
    tenant_id: uuid.UUID,
    now: datetime | None = None,
    max_attempts: int = 5,
    notification_id: uuid.UUID | None = None,
    limit: int = DRAIN_LIMIT,
) -> DeliveryReport:
    """Deliver the tenant's due pending rows (or just ``notification_id``)."""
    now = now or datetime.now(UTC)
    stmt = select(Notification).where(*_due(tenant_id, now))
    if notification_id is not None:
        stmt = stmt.where(Notification.id == notification_id)
    stmt = stmt.order_by(Notification.created_at, Notification.id).limit(limit)
    rows = (await session.execute(stmt.with_for_update(skip_locked=True))).scalars().all()
    report = DeliveryReport()
    for row in rows:
        _count(
            report, await deliver_one(session, sender, row, now=now, max_attempts=max_attempts), row
        )
    return report


class NotifyRetryError(RuntimeError):
    """A single-row delivery hit only retryable failures: nack so Pub/Sub redelivers."""


async def handle_notify_message(
    message: PubSubMessage,
    *,
    sender: PushSender,
    max_attempts: int = 5,
    session_provider: SessionProvider = job_session,
    now: datetime | None = None,
) -> DeliveryReport | None:
    """``notify.send``: ``{"tenant_id", "notification_id"?}``. A malformed payload is acked."""
    try:
        body = message.json_body()
        tenant_id = uuid.UUID(str(body["tenant_id"]))
        raw_id = body.get("notification_id")
        notification_id = uuid.UUID(str(raw_id)) if raw_id else None
    except (ValueError, KeyError, TypeError):
        log.warning("notify_message_invalid", message_id=message.message_id)
        return None
    async with session_provider(tenant_id) as session:
        report = await deliver_pending(
            session,
            sender,
            tenant_id=tenant_id,
            now=now,
            max_attempts=max_attempts,
            notification_id=notification_id,
        )
    if notification_id is not None and report.retrying:
        raise NotifyRetryError(str(notification_id))  # committed above; Pub/Sub backs off
    return report


__all__ = [
    "INBOX_ROUTE",
    "ROUTES",
    "DeliveryReport",
    "NotifyRetryError",
    "active_tokens",
    "backoff",
    "deep_link",
    "deliver_one",
    "deliver_pending",
    "handle_notify_message",
]
