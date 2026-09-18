"""The ``payment`` sync op (FA-021 offline capture), the ``LedgerPort`` default and the
OPS-008 reconciliation job."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from typer.testing import CliRunner

from farmerapp.db.audit import system_actor
from farmerapp.jobs.cli import cli
from farmerapp.khata.credit import CreditDecision
from farmerapp.khata.ledger import InvalidKhataEntryError
from farmerapp.khata.models import CreditApprovalRequest, KhataEntry, khata_balance
from farmerapp.notifications.models import Notification
from farmerapp.payments import reconcile as reconcile_mod
from farmerapp.payments.day_close import ist_today
from farmerapp.payments.models import Payment
from farmerapp.payments.ports import KhataLedgerPort
from farmerapp.payments.providers import SettlementRecord
from farmerapp.payments.reconcile import reconcile_payments
from farmerapp.payments.sync_ops import PaymentSyncUnavailableError, create
from tests.payments.helpers import PayWorld


def _op(entity_id: uuid.UUID, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "op_id": str(uuid.uuid4()),
        "entity": "payment",
        "action": "create",
        "entity_id": str(entity_id),
        "base_version": 0,
        "payload": payload,
        "client_ts": datetime.now(UTC).isoformat(),
    }


async def _sync(client: AsyncClient, pw: PayWorld, ops: list[dict[str, Any]]) -> Any:
    resp = await client.post(
        "/v1/sync",
        json={"device_id": "officer-phone", "cursor": None, "ops": ops},
        headers=pw.headers("field_officer"),
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["results"]


# --------------------------------------------------------------------------- sync
async def test_officer_offline_cash_and_credit(client: AsyncClient, pw: PayWorld) -> None:
    officer = pw.user("field_officer")
    order = await pw.order(12_000, placed_by=officer)
    credit_order = await pw.order(8_000, placed_by=officer)
    cash_id, credit_id = uuid.uuid4(), uuid.uuid4()
    cash_op = _op(
        cash_id, {"order_id": str(order.id), "mode": "cash", "receipt_uri": await pw.blob()}
    )
    results = await _sync(
        client,
        pw,
        [cash_op, _op(credit_id, {"order_id": str(credit_order.id), "mode": "credit"})],
    )
    assert [r["status"] for r in results] == ["applied", "applied"], results
    assert results[0]["server"]["status"] == "pending_reconciliation"
    assert results[0]["server"]["amount_paise"] == 12_000
    payment = await pw.session.get_one(Payment, cash_id)
    assert payment.collected_by == officer.id
    assert (await pw.session.get_one(Payment, credit_id)).mode == "credit"

    replay = await _sync(client, pw, [cash_op])  # same op id: stored result
    assert replay[0]["status"] == "duplicate"
    again = await _sync(client, pw, [_op(cash_id, cash_op["payload"])])  # new op, same payment
    assert again[0]["status"] == "conflict" and again[0]["server"]["id"] == str(cash_id)


async def test_offline_upi_needs_the_network(client: AsyncClient, pw: PayWorld) -> None:
    order = await pw.order(1_000, placed_by=pw.user("field_officer"))
    results = await _sync(
        client, pw, [_op(uuid.uuid4(), {"order_id": str(order.id), "mode": "upi_qr"})]
    )
    assert results[0]["status"] == "rejected"
    assert results[0]["error"]["code"] == "requires_network"


async def test_offline_stale_amount_is_rejected(client: AsyncClient, pw: PayWorld) -> None:
    order = await pw.order(1_000, placed_by=pw.user("field_officer"))
    results = await _sync(
        client,
        pw,
        [
            _op(
                uuid.uuid4(),
                {
                    "order_id": str(order.id),
                    "mode": "cash",
                    "amount_paise": 900,
                    "receipt_uri": await pw.blob(),
                },
            )
        ],
    )
    assert results[0]["status"] == "rejected"
    assert results[0]["error"]["code"] == "amount_mismatch"


async def test_payment_updates_and_deletes_stay_unsupported(
    client: AsyncClient, pw: PayWorld
) -> None:
    op = {**_op(uuid.uuid4(), {}), "action": "update", "base_version": 1}
    results = await _sync(client, pw, [op])
    assert results[0]["status"] == "rejected"
    assert results[0]["error"]["code"] == "unsupported_action"


async def test_sync_op_without_payment_services(pw: PayWorld) -> None:
    with pytest.raises(PaymentSyncUnavailableError):
        await create(
            pw.session,
            pw.user("field_officer"),
            uuid.uuid4(),
            {},
            services=None,
            sms=None,
            whatsapp=None,
            blobs=None,
            now=datetime.now(UTC),
        )


# --------------------------------------------------------------------------- ports
async def test_offline_credit_beyond_the_limit_is_rejected_and_the_request_kept(
    client: AsyncClient, pw: PayWorld
) -> None:
    officer = pw.user("field_officer")
    balance = await khata_balance(pw.session, pw.farmer.id, pw.store.id)
    await pw.set_limit(max(balance, 0) + 1_000)
    order = await pw.order(8_000, placed_by=officer)
    payment_id = uuid.uuid4()
    results = await _sync(
        client, pw, [_op(payment_id, {"order_id": str(order.id), "mode": "credit"})]
    )
    assert results[0]["status"] == "rejected", results
    error = results[0]["error"]
    assert error["code"] == "credit_limit_exceeded" and error["status"] == 402
    request_id = uuid.UUID(error["errors"][0]["approval_request_id"])
    request = await pw.session.get_one(CreditApprovalRequest, request_id)
    assert request.status == "pending" and request.order_id == order.id
    assert request.requested_by == officer.id
    assert await pw.session.get(Payment, payment_id) is None
    assert await khata_balance(pw.session, pw.farmer.id, pw.store.id) == balance


async def test_default_ledger_port_is_the_khata_contract(pw: PayWorld) -> None:
    """``KhataLedgerPort`` delegates to ``khata.credit`` / ``khata.ledger`` (no fallback)."""
    port = KhataLedgerPort()
    actor = system_actor(pw.tenant_id)
    await pw.debit(10_000)
    before = await khata_balance(pw.session, pw.farmer.id, pw.store.id)
    ref = uuid.uuid4()
    entry = await port.post_credit(
        pw.session,
        tenant_id=pw.tenant_id,
        farmer_id=pw.farmer.id,
        store_id=pw.store.id,
        amount_paise=4_000,
        ref_type="payment",
        ref_id=ref,
        actor=actor,
    )
    assert (entry.type, entry.ref_id, entry.ref_type) == ("credit", ref, "payment")
    assert entry.note == "Payment received"
    assert await khata_balance(pw.session, pw.farmer.id, pw.store.id) == before - 4_000
    with pytest.raises(InvalidKhataEntryError):  # the real validation, not a lenient copy
        await port.post_credit(
            pw.session,
            tenant_id=pw.tenant_id,
            farmer_id=pw.farmer.id,
            store_id=pw.store.id,
            amount_paise=0,
            ref_type="payment",
            ref_id=ref,
            actor=actor,
        )
    order_id = uuid.uuid4()
    decision = await port.check_and_reserve_credit(
        pw.session,
        tenant_id=pw.tenant_id,
        farmer_id=pw.farmer.id,
        store_id=pw.store.id,
        amount_paise=2_500,
        order_id=order_id,
        actor=actor,
    )
    assert isinstance(decision, CreditDecision) and decision.allowed
    debit = await pw.session.get_one(KhataEntry, decision.khata_entry_id)
    assert (debit.type, debit.ref_type, debit.ref_id) == ("debit", "order", order_id)
    assert await khata_balance(pw.session, pw.farmer.id, pw.store.id) == before - 4_000 + 2_500


# --------------------------------------------------------------------------- OPS-008
async def test_reconcile_reports_mismatches_and_notifies_accountants(pw: PayWorld) -> None:
    now = datetime.now(UTC)
    today = ist_today(now)
    rows = []
    for ref, amount in (("pay_ok", 1_000), ("pay_short", 2_000), ("pay_lost", 3_000)):
        order = await pw.order(amount)
        payment = Payment(
            tenant_id=pw.tenant_id,
            order_id=order.id,
            store_id=pw.store.id,
            mode="upi_qr",
            provider="razorpay",
            amount_paise=amount,
            status="paid",
            provider_ref=ref,
            paid_at=now,
        )
        pw.session.add(payment)
        rows.append(payment)
    await pw.session.flush()
    pw.provider.settlements[today] = [
        SettlementRecord("pay_ok", 1_000, now),
        SettlementRecord("pay_short", 1_900, now, notes={"tenant_id": str(pw.tenant_id)}),
        SettlementRecord("pay_unknown", 500, now),
        SettlementRecord("pay_other_tenant", 700, now, notes={"tenant_id": str(uuid.uuid4())}),
    ]
    report = await reconcile_payments(pw.session, pw.tenant_id, today, pw.provider)
    kinds = sorted((m.kind, m.provider_ref) for m in report.mismatches)
    assert kinds == [
        ("amount_mismatch", "pay_short"),
        ("missing_in_settlement", "pay_lost"),
        ("missing_locally", "pay_unknown"),
    ]
    assert report.matched == 1 and report.settlements == 3 and report.paid_payments >= 3
    notes = (
        (
            await pw.session.execute(
                select(Notification).where(Notification.kind == "payment_reconciliation")
            )
        )
        .scalars()
        .all()
    )
    accountants = {u.id for u in pw.world.a.everyone if u.role == "accountant"}
    assert accountants and {n.user_id for n in notes} == accountants
    assert report.notified == len(accountants)
    assert notes[0].data["mismatches"]["amount_mismatch"] == 1

    quiet = await reconcile_payments(
        pw.session, pw.tenant_id, today.replace(year=2020), pw.provider, notify=True
    )
    assert quiet.mismatches == [] and quiet.notified == 0


def test_reconcile_cli_prints_the_report(monkeypatch: pytest.MonkeyPatch) -> None:
    tenant = uuid.uuid4()

    async def fake_run(tenant_ids: Any, day: Any, provider: Any) -> list[Any]:
        report = reconcile_mod.ReconcileReport(tenant_id=tenant_ids[0], day=day, settlements=1)
        report.mismatches.append(reconcile_mod.Mismatch("missing_locally", "pay_x"))
        return [report]

    monkeypatch.setattr(reconcile_mod, "run_reconcile", fake_run)
    result = CliRunner().invoke(
        cli, ["reconcile-payments", "--tenant-id", str(tenant), "--date", "2026-09-17"]
    )
    assert result.exit_code == 0, result.output
    assert f"tenant={tenant} date=2026-09-17" in result.output
    assert "missing_locally ref=pay_x" in result.output
    default = CliRunner().invoke(cli, ["reconcile-payments", "--tenant-id", str(tenant)])
    assert default.exit_code == 0 and "date=" in default.output
