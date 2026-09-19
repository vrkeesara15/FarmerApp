"""AN-015 weekly owner PDF (render + Monday 08:00 IST schedule), ST-004 stock alerts and
reorder levels, ST-008 accounting export (golden CSV columns, balanced vouchers, XML)."""

from __future__ import annotations

import csv
import io
import uuid
import xml.etree.ElementTree as ET
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any

from httpx import AsyncClient
from pypdf import PdfReader
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.exports import accounting
from farmerapp.exports.cron import IST
from farmerapp.exports.email import FakeEmailSender
from farmerapp.exports.jobs import SCHEDULES, accounting_export
from farmerapp.exports.owner_weekly import (
    WEEKLY_OWNER_CRON,
    next_delivery,
    report_week,
    send_weekly_owner_report,
)
from farmerapp.flags.analytics import FLAG_TABLE_COUNTS
from farmerapp.flags.models import Flag
from farmerapp.invoices.models import Invoice
from farmerapp.notifications.models import Notification
from farmerapp.orders.models import OrderStatusEvent
from farmerapp.payments.models import Payment
from farmerapp.stock import alerts
from farmerapp.stock.models import StockMovement
from farmerapp.tenants.settings import AccountingSettings
from farmerapp.uploads.blobstore import LocalBlobStore
from tests.analytics.builders import Mini, ist
from tests.authz.conftest import Bearer
from tests.growth.conftest import headers

MONDAY_8 = datetime(2026, 9, 21, 8, 0, tzinfo=IST)


# --------------------------------------------------------------------------- AN-015
def test_weekly_schedule_is_monday_0800_ist() -> None:
    assert WEEKLY_OWNER_CRON == SCHEDULES["weekly-owner-report"] == "0 8 * * 1"
    fire = next_delivery(datetime(2026, 9, 19, 12, tzinfo=IST))  # a Saturday
    assert fire.astimezone(IST) == MONDAY_8
    assert report_week(MONDAY_8) == (date(2026, 9, 14), date(2026, 9, 20))
    assert report_week(MONDAY_8 - timedelta(minutes=1)) == (date(2026, 9, 7), date(2026, 9, 13))
    assert report_week(MONDAY_8 + timedelta(days=2)) == (date(2026, 9, 14), date(2026, 9, 20))


async def _flag(m: Mini, title: str, severity: str, opened: datetime) -> None:
    await m.add(
        Flag(
            tenant_id=m.tid,
            rule_id="VA-F01",
            rule_version=1,
            subject_type="farmer",
            subject_id=m.farmers["f1"].id,
            severity=severity,
            title=title,
            evidence={},
            raised_by_mode="batch",
            sla_due_at=opened + timedelta(days=2),
            dedupe_key=f"VA-F01:{uuid.uuid4()}",
            created_at=opened,
        )
    )


async def test_weekly_owner_pdf_has_the_kpis_and_top_flags(
    mini: Mini, db_session: AsyncSession, tmp_path: Any
) -> None:
    m = mini
    m.tenant.settings = {"reports": {"weekly_owner_emails": ["owner@example.com"]}}
    await db_session.flush()
    await m.sale("N1", "f1", ist(date(2026, 9, 15), 11), [("own", 2, 1000), ("multi", 1, 1000)])
    await m.visit("o1", "f1", ist(date(2026, 9, 16), 10), score=85)
    opened = ist(date(2026, 9, 10), 9)
    for i, sev in enumerate(("low", "high", "medium", "high", "low", "medium", "low")):
        await _flag(m, f"Flag number {i} {sev}", sev, opened + timedelta(hours=i))
    email = FakeEmailSender()
    store = LocalBlobStore(tmp_path)
    result = await send_weekly_owner_report(
        db_session, tenant_id=m.tid, now=MONDAY_8, flags=FLAG_TABLE_COUNTS, store=store, email=email
    )
    assert result.status == "sent" and result.week_start == date(2026, 9, 14)
    [message] = email.sent
    assert message.to == ("owner@example.com",)
    [pdf] = message.attachments
    assert pdf.content_type == "application/pdf"
    reader = PdfReader(io.BytesIO(pdf.content))
    assert len(reader.pages) == 1  # a one-page report
    text = reader.pages[0].extract_text()
    for label in ("Revenue", "Own-brand share", "Credit outstanding", "Verified visits",
                  "Active farmers", "Open validation flags"):  # fmt: skip
        assert label in text, label
    assert "Rs 30.00" in text  # revenue of the week (3,000 paise)
    assert "66.7%" in text  # own-brand share 2000 / 3000
    assert "14 Sep 2026 - 20 Sep 2026" in text
    # Top five: the two high, then the two medium, then the oldest low.
    shown = [f"Flag number {i}" for i in (1, 3, 2, 5, 0)]
    for title in shown:
        assert title in text, title
    assert "Flag number 4" not in text and "Flag number 6" not in text
    assert text.index("Flag number 1") < text.index("Flag number 2") < text.index("Flag number 0")
    assert await store.exists(f"gs://local/{m.tid}/reports/weekly_owner/2026-09-14.pdf")
    again = await send_weekly_owner_report(
        db_session, tenant_id=m.tid, now=MONDAY_8 + timedelta(hours=1), flags=FLAG_TABLE_COUNTS,
        store=store, email=email,
    )  # fmt: skip
    assert again.status == "already_sent" and len(email.sent) == 1


async def test_weekly_report_without_recipients_is_recorded(
    mini: Mini, db_session: AsyncSession, tmp_path: Any
) -> None:
    email = FakeEmailSender()
    result = await send_weekly_owner_report(
        db_session, tenant_id=mini.tid, now=MONDAY_8, flags=FLAG_TABLE_COUNTS,
        store=LocalBlobStore(tmp_path), email=email,
    )  # fmt: skip
    assert result.status == "no_recipients" and email.sent == []


# --------------------------------------------------------------------------- ST-004
async def _alerts(session: AsyncSession, kind: str) -> list[dict[str, Any]]:
    rows = (
        await session.execute(
            select(Notification).where(Notification.kind == kind).order_by(Notification.id)
        )
    ).scalars()
    return [dict(n.data) | {"user_id": n.user_id} for n in rows]


async def test_low_stock_and_expiry_alerts_are_deduplicated(
    client: AsyncClient, mini: Mini, bearer: Bearer, db_session: AsyncSession
) -> None:
    m = mini
    now = ist(date(2026, 9, 20), 1, 30)
    # Mini: 10 of each SKU per store. N1: own below its level 12 (explicit), multi at the
    # default 10 (not below). S1: default lowered to 5 by nothing -> not low.
    put = await client.put(
        f"/v1/stores/{m.stores['N1'].id}/reorder-levels",
        json={"items": [{"sku_id": str(m.skus["own"].id), "reorder_level": "12"}]},
        headers=headers(bearer, m.user("store_manager")),
    )
    assert put.status_code == 200, put.text
    assert put.json()["default_reorder_level"] == 10
    other = await client.put(
        f"/v1/stores/{m.stores['S1'].id}/reorder-levels",
        json={"items": [{"sku_id": str(m.skus["own"].id), "reorder_level": "1"}]},
        headers=headers(bearer, m.user("store_manager")),
    )
    assert other.status_code == 404  # not their store
    # Expiry: N1 multi batch in 45 days (60-day band), S1 own batch in 20 days (30-day band).
    m.batches[("N1", "multi")].expiry = date(2026, 9, 20) + timedelta(days=45)
    m.batches[("S1", "own")].expiry = date(2026, 9, 20) + timedelta(days=20)
    m.batches[("N2", "own")].expiry = date(2026, 9, 20) + timedelta(days=90)  # outside
    await db_session.flush()
    report = await alerts.stock_alerts(db_session, tenant_id=m.tid, now=now)
    assert [(low.store_id, low.sku_id) for low in report.low] == [
        (m.stores["N1"].id, m.skus["own"].id)
    ]
    assert sorted((e.threshold, e.days_left) for e in report.expiring) == [(30, 20), (60, 45)]
    low = await _alerts(db_session, alerts.LOW_STOCK_KIND)
    assert [(a["store_code"], a["reorder_level"], a["user_id"]) for a in low] == [
        ("N1", "12.000", m.user("store_manager").id)
    ]
    expiry = await _alerts(db_session, alerts.EXPIRY_KIND)
    assert {(a["store_code"], a["threshold_days"]) for a in expiry} == {("N1", 60), ("S1", 30)}
    # S1 has no store manager: its cluster head (South has none in Mini) -> the owner.
    s1 = next(a for a in expiry if a["store_code"] == "S1")
    assert s1["user_id"] == m.user("owner").id
    # The next night: nothing new. Then the N1 batch crosses 30 days -> one more alert.
    again = await alerts.stock_alerts(db_session, tenant_id=m.tid, now=now + timedelta(days=1))
    assert again.notifications == 0 and again.deduplicated == 3
    later = await alerts.stock_alerts(db_session, tenant_id=m.tid, now=now + timedelta(days=15))
    assert later.notifications == 1
    # A restock clears the low-stock dedupe: after a receipt, dropping low again re-alerts.
    await m.add(
        StockMovement(
            tenant_id=m.tid, store_id=m.stores["N1"].id, sku_id=m.skus["own"].id,
            batch_id=m.batches[("N1", "own")].id, kind="receipt", qty=Decimal(1),
            created_at=datetime.now(UTC),
        )
    )  # fmt: skip
    restocked = await alerts.stock_alerts(db_session, tenant_id=m.tid, now=now + timedelta(days=16))
    assert restocked.notifications == 1 and len(await _alerts(db_session, "stock_low")) == 2
    listed = await client.get(
        f"/v1/stores/{m.stores['N1'].id}/reorder-levels",
        headers=headers(bearer, m.user("accountant")),
    )
    assert listed.json()["items"] == [{"sku_id": str(m.skus["own"].id), "reorder_level": "12.000"}]


def test_threshold_bands() -> None:
    assert alerts.threshold_for(61, [60, 30]) is None
    assert alerts.threshold_for(60, [60, 30]) == 60
    assert alerts.threshold_for(30, [60, 30]) == 30
    assert alerts.threshold_for(-3, [60, 30]) == 30  # already expired


# --------------------------------------------------------------------------- ST-008
GOLDEN_TALLY_HEADER = (
    "Voucher Date,Voucher Type,Voucher Number,Reference,Party Ledger,Party GSTIN,"
    "Place of Supply,Ledger,Dr/Cr,Amount,HSN,GST Rate,Taxable Value,Narration"
)
GOLDEN_ZOHO_HEADER = (
    "Invoice Date,Invoice Number,Invoice Status,Customer Name,GST Treatment,"
    "GST Identification Number (GSTIN),Place of Supply,Item Name,HSN/SAC,Quantity,Usage unit,"
    "Item Price,Item Tax,Item Tax %,Item Tax Type,Adjustment,Adjustment Description,"
    "Currency Code,Notes"
)
DAY = date(2026, 9, 18)


def _line(sl: int, hsn: str, qty: str, unit: int, taxable: int, rate: int) -> dict[str, Any]:
    half = rate // 2
    tax_half = taxable * half // 10000
    return {
        "sl": sl, "sku_id": str(uuid.uuid4()), "description": f"Item {sl}", "hsn": hsn,
        "qty": qty, "unit": "l", "unit_price_paise": unit, "taxable_paise": taxable,
        "gst_rate_bp": rate, "cgst_rate_bp": half, "cgst_paise": tax_half, "sgst_rate_bp": half,
        "sgst_paise": tax_half, "igst_rate_bp": 0, "igst_paise": 0,
        "total_paise": taxable + 2 * tax_half,
    }  # fmt: skip


async def _invoice(m: Mini, no: str, at: datetime, *, status: str = "delivered") -> Invoice:
    order = await m.sale("N1", "f1", at, [("own", 1, 100000)], status=status)
    lines = [_line(1, "3808", "2", 50000, 100000, 1800), _line(2, "3101", "1", 20000, 20000, 500)]
    taxable = 120000
    cgst = sgst = 9000 + 500
    raw = taxable + cgst + sgst
    rounded = (raw + 50) // 100 * 100
    inv = Invoice(
        tenant_id=m.tid, order_id=order.id, store_id=m.stores["N1"].id,
        farmer_id=m.farmers["f1"].id, invoice_no=no, financial_year="2026-27",
        seq=int(no.split("/")[-1]), issued_at=at, seller_name="Future Crop Care",
        seller_gstin="36AAAAA0000A1Z5", seller_address="Warangal", seller_state="Telangana",
        seller_state_code="36", buyer_name="Farmer F1", buyer_state="Telangana",
        place_of_supply="Telangana (36)", supply_type="intra", taxable_paise=taxable,
        cgst_paise=cgst, sgst_paise=sgst, igst_paise=0, round_off_paise=rounded - raw,
        total_paise=rounded, amount_in_words="x", lines=lines,
    )  # fmt: skip
    await m.add(inv)
    return inv


async def accounting_day(m: Mini) -> None:
    at = ist(DAY, 11)
    await _invoice(m, "N1/2026-27/1", at)
    cancelled = await _invoice(
        m, "N1/2026-27/2", ist(DAY - timedelta(days=2), 11), status="cancelled"
    )
    await m.add(
        OrderStatusEvent(
            tenant_id=m.tid, order_id=cancelled.order_id, from_status="delivered",
            to_status="cancelled", created_at=ist(DAY, 15),
        ),
        Payment(
            tenant_id=m.tid, farmer_id=m.farmers["f1"].id, store_id=m.stores["N1"].id,
            mode="upi_qr", provider="razorpay", provider_ref="pay_123", amount_paise=139000,
            status="paid", paid_at=ist(DAY, 12),
        ),
        Payment(
            tenant_id=m.tid, farmer_id=m.farmers["f1"].id, store_id=m.stores["N1"].id,
            mode="credit", amount_paise=5000, status="paid", paid_at=ist(DAY, 12),
        ),
    )  # fmt: skip


async def test_tally_csv_golden_columns_and_balanced_vouchers(
    mini: Mini, db_session: AsyncSession
) -> None:
    await accounting_day(mini)
    data = await accounting.load_day(db_session, mini.stores["N1"], DAY)
    assert (len(data.invoices), len(data.credit_notes), len(data.receipts)) == (1, 1, 1)
    acc = AccountingSettings()
    vouchers = accounting.vouchers(data, acc)
    assert [v.kind for v in vouchers] == ["Sales", "Credit Note", "Receipt"]
    assert all(v.balanced() for v in vouchers)
    sale = vouchers[0]
    entries = [(e.ledger, "Dr" if e.debit else "Cr", e.amount_paise) for e in sale.entries]
    assert entries == [
        ("Farmer F1", "Dr", 139000),
        ("Sales @ 5%", "Cr", 20000),
        ("Sales @ 18%", "Cr", 100000),
        ("Output CGST @ 2.5%", "Cr", 500),
        ("Output CGST @ 9%", "Cr", 9000),
        ("Output SGST @ 2.5%", "Cr", 500),
        ("Output SGST @ 9%", "Cr", 9000),
    ]  # 1,39,000.00 exactly: no round-off line
    note = vouchers[1]
    assert note.number == "CN-N1/2026-27/2" and note.entries[0].debit is False
    rows = accounting.tally_rows(data, acc)
    from farmerapp.exports.writers import write_csv

    out, _ = write_csv(accounting.TALLY_COLUMNS, rows)
    text = out.read().decode("utf-8-sig")
    assert text.splitlines()[0] == GOLDEN_TALLY_HEADER
    table = list(csv.DictReader(io.StringIO(text)))
    first = table[0]
    assert (first["Voucher Date"], first["Voucher Type"], first["Voucher Number"]) == (
        "18-09-2026", "Sales", "N1/2026-27/1",
    )  # fmt: skip
    assert (first["Ledger"], first["Dr/Cr"], first["Amount"]) == ("Farmer F1", "Dr", "1390.00")
    hsn = [r for r in table if r["Voucher Type"] == "Sales" and r["HSN"]]
    assert [(r["HSN"], r["GST Rate"], r["Taxable Value"]) for r in hsn] == [
        ("3101", "5", "200.00"),
        ("3808", "18", "1000.00"),
    ]
    receipt = [r for r in table if r["Voucher Type"] == "Receipt"]
    assert [(r["Ledger"], r["Dr/Cr"], r["Amount"]) for r in receipt] == [
        ("UPI Collections", "Dr", "1390.00"),
        ("Farmer F1", "Cr", "1390.00"),
    ]
    zoho, _ = write_csv(accounting.ZOHO_COLUMNS, accounting.zoho_rows(data))
    ztext = zoho.read().decode("utf-8-sig")
    assert ztext.splitlines()[0] == GOLDEN_ZOHO_HEADER
    zrows = list(csv.DictReader(io.StringIO(ztext)))
    assert [(r["Invoice Number"], r["HSN/SAC"], r["Item Tax"]) for r in zrows] == [
        ("N1/2026-27/1", "3808", "GST18"),
        ("N1/2026-27/1", "3101", "GST5"),
    ]
    xml = accounting.tally_xml(data, acc, "Future Crop Care")
    root = ET.fromstring(xml)
    kinds = [v.get("VCHTYPE") for v in root.iter("VOUCHER")]
    assert kinds == ["Sales", "Credit Note", "Receipt"]
    for voucher in root.iter("VOUCHER"):
        total = sum(Decimal(a.text or "0") for a in voucher.iter("AMOUNT"))
        assert total == 0  # Tally: debits negative, credits positive, net zero


async def test_daily_accounting_export_job(
    mini: Mini, db_session: AsyncSession, tmp_path: Any
) -> None:
    await accounting_day(mini)
    mini.tenant.settings = {"reports": {"accounting_emails": ["accounts@example.com"]}}
    await db_session.flush()
    email = FakeEmailSender()
    store = LocalBlobStore(tmp_path)
    report = await accounting_export(
        db_session, tenant_id=mini.tid, day=DAY, store=store, email=email
    )
    assert report.stores == ["N1", "N2", "S1"] and report.vouchers == 3
    n1 = next(msg for msg in email.sent if msg.subject.startswith("N1"))
    assert [a.filename for a in n1.attachments] == [
        "tally-N1-2026-09-18.csv",
        "tally-N1-2026-09-18.xml",
        "zoho-N1-2026-09-18.csv",
    ]
    assert await store.exists(
        f"gs://local/{mini.tid}/accounting/N1/2026-09-18/tally-N1-2026-09-18.csv"
    )
    again = await accounting_export(
        db_session, tenant_id=mini.tid, day=DAY, store=store, email=email
    )
    assert again.already_sent == 3 and len(email.sent) == 3


async def test_accounting_export_through_the_exports_api(
    client: AsyncClient, mini: Mini, bearer: Bearer, step_up: Bearer
) -> None:
    await accounting_day(mini)
    accountant = headers(bearer, mini.user("accountant"), step_up)
    filters = {"store_id": str(mini.stores["N1"].id), "date": DAY.isoformat()}
    for resource, fmt in (("tally", "csv"), ("tally_xml", "xml"), ("zoho", "xlsx")):
        resp = await client.post(
            "/v1/exports", json={"resource": resource, "format": fmt, "filters": filters},
            headers=accountant,
        )  # fmt: skip
        assert resp.status_code == 201, resp.text
        assert resp.json()["filename"] == f"{resource}-2026-09-18.{fmt}"
    manager = headers(bearer, mini.user("store_manager"), step_up)
    other = await client.post(
        "/v1/exports",
        json={"resource": "tally", "filters": {**filters, "store_id": str(mini.stores["S1"].id)}},
        headers=manager,
    )
    assert other.status_code == 404  # not the store manager's store
