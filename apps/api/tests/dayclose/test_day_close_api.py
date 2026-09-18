"""Day-end totals (ST-002) and the store day close (ST-006, VA-E10 hook).

Acceptance: "Day-end totals by mode" and "Variance over threshold flags auditor".
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

from httpx import AsyncClient
from sqlalchemy import select

from farmerapp.db.models.tenant import Tenant
from farmerapp.notifications.models import Notification
from farmerapp.payments.day_close import day_bounds, ist_today
from farmerapp.payments.events import CashVarianceDetected
from farmerapp.payments.models import Payment
from tests.payments.helpers import PayWorld


def _today() -> date:
    return ist_today(datetime.now(UTC))


async def _collect(client: AsyncClient, pw: PayWorld, body: dict[str, Any]) -> dict[str, Any]:
    resp = await client.post("/v1/payments", json=body, headers=pw.headers("store_manager"))
    assert resp.status_code == 201, resp.text
    data: dict[str, Any] = resp.json()
    return data


async def _cash(client: AsyncClient, pw: PayWorld, paise: int) -> dict[str, Any]:
    order = await pw.order(paise)
    return await _collect(
        client, pw, {"order_id": str(order.id), "mode": "cash", "receipt_uri": await pw.blob()}
    )


def _close(pw: PayWorld, day: date, counted: int, slip: str | None, **extra: Any) -> dict[str, Any]:
    body: dict[str, Any] = {"business_date": day.isoformat(), "cash_counted_paise": counted}
    if slip:
        body["deposit_slip_uri"] = slip
    return {**body, **extra}


async def _auditor_notes(pw: PayWorld) -> list[Notification]:
    return list(
        (
            await pw.session.execute(
                select(Notification).where(Notification.kind == "day_close_variance")
            )
        )
        .scalars()
        .all()
    )


async def test_day_summary_totals_by_mode(client: AsyncClient, pw: PayWorld) -> None:
    await _cash(client, pw, 10_000)
    await _cash(client, pw, 5_050)
    card_order = await pw.order(20_000)
    await _collect(
        client,
        pw,
        {"order_id": str(card_order.id), "mode": "card_terminal", "reference_note": "RRN"},
    )
    credit_order = await pw.order(7_000)
    await _collect(client, pw, {"order_id": str(credit_order.id), "mode": "credit"})
    waiting_order = await pw.order(3_000)
    await _collect(client, pw, {"order_id": str(waiting_order.id), "mode": "upi_qr"})
    refunded_order = await pw.order(1_000)
    refunded = await _collect(
        client,
        pw,
        {"order_id": str(refunded_order.id), "mode": "card_terminal", "reference_note": "R2"},
    )
    row = await pw.session.get_one(Payment, uuid.UUID(refunded["payment_id"]))
    row.status = "refunded"
    await pw.session.flush()

    resp = await client.get(
        f"/v1/stores/{pw.store.id}/day-summary",
        params={"date": _today().isoformat()},
        headers=pw.headers("store_manager"),
    )
    assert resp.status_code == 200, resp.text
    summary = resp.json()
    by_mode = {m["mode"]: m for m in summary["by_mode"]}
    assert set(by_mode) == {"upi_qr", "payment_link", "cash", "card_terminal", "credit"}
    assert by_mode["cash"] == {"mode": "cash", "count": 2, "amount_paise": 15_050}
    assert by_mode["card_terminal"]["amount_paise"] == 20_000
    assert by_mode["credit"]["amount_paise"] == 7_000
    assert by_mode["upi_qr"]["count"] == 0
    assert summary["total_received_paise"] == 35_050  # credit is not money received
    assert summary["waiting"] == {"count": 1, "amount_paise": 3_000}
    assert summary["refunds"] == {"count": 1, "amount_paise": 1_000}
    assert summary["expected_cash_paise"] == 15_050
    assert summary["cash_pending_reconciliation_paise"] == 15_050
    assert summary["day_close"] is None and summary["timezone"] == "Asia/Kolkata"

    default_day = await client.get(
        f"/v1/stores/{pw.store.id}/day-summary", headers=pw.headers("auditor")
    )
    assert default_day.status_code == 200
    assert default_day.json()["business_date"] == _today().isoformat()


async def test_close_reconciles_cash_and_small_variance_does_not_flag(
    client: AsyncClient, pw: PayWorld, events: list[Any]
) -> None:
    first = await _cash(client, pw, 10_000)
    await _cash(client, pw, 2_500)
    slip = await pw.blob("receipt")
    resp = await client.post(
        f"/v1/stores/{pw.store.id}/day-close",
        json=_close(pw, _today(), 12_400, slip, notes="short by a coin"),
        headers=pw.headers("store_manager"),
    )
    assert resp.status_code == 201, resp.text
    close = resp.json()
    assert close["cash_expected_paise"] == 12_500 and close["variance_paise"] == -100
    assert close["variance_flagged"] is False and close["status"] == "closed"
    assert close["closed_by"] == str(pw.user("store_manager").id)
    payment = await pw.session.get_one(Payment, uuid.UUID(first["payment_id"]))
    assert payment.status == "reconciled" and str(payment.day_close_id) == close["id"]
    assert await _auditor_notes(pw) == []
    assert not [e for e in events if isinstance(e, CashVarianceDetected)]

    again = await client.post(
        f"/v1/stores/{pw.store.id}/day-close",
        json=_close(pw, _today(), 12_500, slip),
        headers=pw.headers("store_manager"),
    )
    assert again.status_code == 409 and again.json()["code"] == "day_already_closed"

    summary = await client.get(
        f"/v1/stores/{pw.store.id}/day-summary", headers=pw.headers("store_manager")
    )
    assert summary.json()["day_close"]["id"] == close["id"]
    assert summary.json()["cash_pending_reconciliation_paise"] == 0
    assert summary.json()["expected_cash_paise"] == 12_500  # reconciled cash still counts


async def test_variance_over_threshold_flags_the_auditors(
    client: AsyncClient, pw: PayWorld, events: list[Any]
) -> None:
    await _cash(client, pw, 100_000)
    resp = await client.post(
        f"/v1/stores/{pw.store.id}/day-close",
        json=_close(pw, _today(), 40_000, await pw.blob()),
        headers=pw.headers("store_manager"),
    )
    assert resp.status_code == 201, resp.text
    close = resp.json()
    assert close["variance_paise"] == -60_000 and close["variance_flagged"] is True
    notes = await _auditor_notes(pw)
    auditors = {u.id for u in pw.world.a.everyone if u.role == "auditor"}
    assert {n.user_id for n in notes} == auditors and auditors
    assert notes[0].data["variance_paise"] == -60_000
    assert notes[0].data["threshold_paise"] == 50_000
    assert notes[0].title_key == "notification.day_close_variance.title"
    detected = [e for e in events if isinstance(e, CashVarianceDetected)]
    assert len(detected) == 1 and detected[0].variance_paise == -60_000
    assert detected[0].store_id == pw.store.id


async def test_tenant_threshold_is_configurable(client: AsyncClient, pw: PayWorld) -> None:
    tenant = await pw.session.get_one(Tenant, pw.tenant_id)
    tenant.settings = {**tenant.settings, "day_close_variance_threshold_paise": 50}
    await pw.session.flush()
    await _cash(client, pw, 1_000)
    resp = await client.post(
        f"/v1/stores/{pw.store.id}/day-close",
        json=_close(pw, _today(), 1_100, await pw.blob()),
        headers=pw.headers("store_manager"),
    )
    assert resp.json()["variance_paise"] == 100 and resp.json()["variance_flagged"] is True


async def test_reopen_needs_a_cluster_head_and_the_next_close_updates_the_row(
    client: AsyncClient, pw: PayWorld
) -> None:
    cash = await _cash(client, pw, 8_000)
    closed = await client.post(
        f"/v1/stores/{pw.store.id}/day-close",
        json=_close(pw, _today(), 8_000, await pw.blob()),
        headers=pw.headers("store_manager"),
    )
    close_id = closed.json()["id"]
    url = f"/v1/stores/{pw.store.id}/day-close/{close_id}/reopen"
    manager = await client.post(
        url, json={"reason": "recount"}, headers=pw.headers("store_manager")
    )
    assert manager.status_code == 403

    head = await client.post(url, json={"reason": "recount"}, headers=pw.headers("cluster_head"))
    assert head.status_code == 200, head.text
    assert head.json()["status"] == "reopened" and head.json()["reopen_reason"] == "recount"
    payment = await pw.session.get_one(Payment, uuid.UUID(cash["payment_id"]))
    assert payment.status == "pending_reconciliation" and payment.day_close_id is None
    twice = await client.post(url, json={"reason": "again"}, headers=pw.headers("owner"))
    assert twice.status_code == 409 and twice.json()["code"] == "day_close_not_closed"

    reclosed = await client.post(
        f"/v1/stores/{pw.store.id}/day-close",
        json=_close(pw, _today(), 7_900, await pw.blob()),
        headers=pw.headers("store_manager"),
    )
    assert reclosed.status_code == 201, reclosed.text
    assert reclosed.json()["id"] == close_id and reclosed.json()["status"] == "closed"
    assert reclosed.json()["variance_paise"] == -100
    await pw.session.refresh(payment)
    assert payment.status == "reconciled"

    unknown = await client.post(
        f"/v1/stores/{pw.store.id}/day-close/{uuid.uuid4()}/reopen",
        json={"reason": "wrong day"},
        headers=pw.headers("owner"),
    )
    assert unknown.status_code == 404


async def test_close_validation(client: AsyncClient, pw: PayWorld) -> None:
    url = f"/v1/stores/{pw.store.id}/day-close"
    headers = pw.headers("store_manager")
    no_slip = await client.post(url, json=_close(pw, _today(), 100, None), headers=headers)
    assert no_slip.status_code == 422 and no_slip.json()["code"] == "deposit_slip_required"
    bad_slip = await client.post(
        url, json=_close(pw, _today(), 100, "gs://local/nope/x"), headers=headers
    )
    assert bad_slip.status_code == 422 and bad_slip.json()["code"] == "invalid_blob"
    future = await client.post(
        url, json=_close(pw, _today() + timedelta(days=2), 0, None), headers=headers
    )
    assert future.status_code == 422 and future.json()["code"] == "future_business_date"
    empty_day = await client.post(url, json=_close(pw, date(2026, 1, 5), 0, None), headers=headers)
    assert empty_day.status_code == 201 and empty_day.json()["cash_expected_paise"] == 0
    assert pw.other_store is not None
    elsewhere = await client.post(
        f"/v1/stores/{pw.other_store.id}/day-close",
        json=_close(pw, _today(), 0, None),
        headers=headers,
    )
    assert elsewhere.status_code == 404
    summary = await client.get(f"/v1/stores/{pw.other_store.id}/day-summary", headers=headers)
    assert summary.status_code == 404


def test_business_day_is_an_ist_calendar_day() -> None:
    start, end = day_bounds(date(2026, 9, 18))
    assert start == datetime(2026, 9, 17, 18, 30, tzinfo=UTC)
    assert end - start == timedelta(days=1)
    assert ist_today(datetime(2026, 9, 18, 18, 45, tzinfo=UTC)) == date(2026, 9, 19)
