"""OPS-008: a reconciliation mismatch opens a finance ticket — a flag with the system rule id
``OPS-008`` about the tenant, owned by an auditor, watched by the accountants — plus a
notification to every accountant; accountants see the tickets they watch in the inbox."""

from __future__ import annotations

from datetime import UTC, datetime

from httpx import AsyncClient
from sqlalchemy import select

from farmerapp.auth.models import UserRole
from farmerapp.flags.models import Flag, FlagEvent
from farmerapp.notifications.models import Notification
from farmerapp.payments.day_close import ist_today
from farmerapp.payments.models import Payment
from farmerapp.payments.providers import SettlementRecord
from farmerapp.payments.reconcile import FINANCE_RULE_ID, reconcile_payments
from tests.payments.helpers import PayWorld


async def _mismatched_day(pw: PayWorld) -> tuple[datetime, Payment]:
    now = datetime.now(UTC)
    order = await pw.order(5_000)
    payment = Payment(
        tenant_id=pw.tenant_id,
        order_id=order.id,
        store_id=pw.store.id,
        mode="upi_qr",
        provider="razorpay",
        amount_paise=5_000,
        status="paid",
        provider_ref="pay_short_ticket",
        paid_at=now,
    )
    pw.session.add(payment)
    await pw.session.flush()
    pw.provider.settlements[ist_today(now)] = [
        SettlementRecord("pay_short_ticket", 4_900, now),
        SettlementRecord("pay_ghost_ticket", 700, now),
    ]
    return now, payment


async def test_mismatch_opens_one_finance_ticket_per_day(pw: PayWorld) -> None:
    now, payment = await _mismatched_day(pw)
    day = ist_today(now)
    report = await reconcile_payments(pw.session, pw.tenant_id, day, pw.provider, now=now)
    assert report.flag_id is not None
    flag = await pw.session.get_one(Flag, report.flag_id)
    assert flag.rule_id == FINANCE_RULE_ID == "OPS-008" and flag.rule_version == 1
    assert (flag.subject_type, flag.subject_id) == ("tenant", pw.tenant_id)
    assert flag.severity == "high" and flag.raised_by_mode == "batch" and flag.status == "open"
    assert flag.owner_role in ("auditor", "owner")
    accountants = {u.id for u in pw.world.a.everyone if u.role == UserRole.ACCOUNTANT}
    assert accountants and accountants <= set(flag.watchers)
    assert flag.dedupe_key == f"OPS-008:tenant:{pw.tenant_id}:{day.isoformat()}"
    metrics = flag.evidence["metrics"]
    assert metrics["counts"] == {"amount_mismatch": 1, "missing_locally": 1}
    kinds = {m["kind"]: m for m in metrics["mismatches"]}
    assert kinds["amount_mismatch"]["ours_paise"] == 5_000
    assert kinds["amount_mismatch"]["theirs_paise"] == 4_900
    assert {"type": "payment", "id": str(payment.id)} in flag.evidence["records"]
    created = (
        await pw.session.execute(select(FlagEvent).where(FlagEvent.flag_id == flag.id))
    ).scalar_one()
    assert created.kind == "created"
    notes = (
        (
            await pw.session.execute(
                select(Notification).where(Notification.kind == "payment_reconciliation")
            )
        )
        .scalars()
        .all()
    )
    assert {n.user_id for n in notes} == accountants
    assert all(n.data["flag_id"] == str(flag.id) for n in notes)

    # Same day again: the open ticket is not duplicated and nobody is notified twice.
    again = await reconcile_payments(pw.session, pw.tenant_id, day, pw.provider, now=now)
    assert again.mismatches and again.flag_id is None and again.notified == 0
    tickets = (
        (await pw.session.execute(select(Flag).where(Flag.rule_id == FINANCE_RULE_ID)))
        .scalars()
        .all()
    )
    assert len(tickets) == 1


async def test_accountants_see_the_finance_tickets_they_watch(
    client: AsyncClient, pw: PayWorld
) -> None:
    now, _ = await _mismatched_day(pw)
    report = await reconcile_payments(
        pw.session, pw.tenant_id, ist_today(now), pw.provider, now=now
    )
    inbox = await client.get("/v1/flags", headers=pw.headers(UserRole.ACCOUNTANT))
    assert inbox.status_code == 200, inbox.text
    assert [item["id"] for item in inbox.json()["items"]] == [str(report.flag_id)]
    detail = await client.get(f"/v1/flags/{report.flag_id}", headers=pw.headers("accountant"))
    assert detail.status_code == 200
    summaries = [r for r in detail.json()["evidence"]["records"] if r["type"] == "payment"]
    assert summaries  # accountants read ids; reviewers get payment summaries
    comment = await client.post(
        f"/v1/flags/{report.flag_id}/comments",
        json={"body": "Razorpay support ticket raised"},
        headers=pw.headers(UserRole.ACCOUNTANT),
    )
    assert comment.status_code == 201, comment.text
    # Accountants review nothing: transitions stay with the reviewers.
    move = await client.post(
        f"/v1/flags/{report.flag_id}/transition",
        json={"to": "in_review"},
        headers=pw.headers(UserRole.ACCOUNTANT),
    )
    assert move.status_code == 403
    auditor_view = await client.get(
        f"/v1/flags/{report.flag_id}", headers=pw.headers(UserRole.AUDITOR)
    )
    payment_records = [
        r for r in auditor_view.json()["evidence"]["records"] if r["type"] == "payment"
    ]
    assert payment_records[0]["summary"]["amount_paise"] == 5_000
