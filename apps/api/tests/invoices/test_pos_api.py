"""``POST /v1/stores/{id}/pos/sales`` and the invoice routes (ST-001).

Acceptance: "Invoice PDF matches GST format; shareable on WhatsApp" — the PDF text carries
the GSTIN, HSN, invoice number and totals (extracted with pypdf); share sends the link.
"""

from __future__ import annotations

import io
import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from httpx import AsyncClient
from pypdf import PdfReader
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.catalog.models import Product, Sku
from farmerapp.invoices.models import Invoice
from farmerapp.invoices.pdf import inr
from farmerapp.invoices.ports import PosOrderDraft
from farmerapp.orders.models import Order, OrderLine
from farmerapp.payments.models import Payment
from farmerapp.stock.ledger import stock_on_hand
from farmerapp.stock.models import StockBatch
from tests.payments.helpers import PayWorld


async def _stocked(pw: PayWorld) -> tuple[Sku, Product, Decimal]:
    batch = (
        await pw.session.execute(
            select(StockBatch)
            .where(StockBatch.store_id == pw.store.id, StockBatch.qty > 0)
            .order_by(StockBatch.qty.desc())
            .limit(1)
        )
    ).scalar_one()
    sku = await pw.session.get_one(Sku, batch.sku_id)
    product = await pw.session.get_one(Product, sku.product_id)
    return sku, product, await stock_on_hand(pw.session, pw.store.id, sku.id)


async def _sale(
    client: AsyncClient, pw: PayWorld, body: dict[str, Any], role: str = "store_manager"
) -> Any:
    return await client.post(
        f"/v1/stores/{pw.store.id}/pos/sales", json=body, headers=pw.headers(role)
    )


def _pdf_text(path: str) -> str:
    data = Path(urlparse(path).path).read_bytes()
    return "\n".join(page.extract_text() for page in PdfReader(io.BytesIO(data)).pages)


async def test_intra_state_sale_with_invoice_pdf_and_stock_out(
    client: AsyncClient, pw: PayWorld
) -> None:
    sku, product, on_hand = await _stocked(pw)
    product.hsn, product.gst_rate_bp = "38089199", 1800
    await pw.session.flush()
    resp = await _sale(
        client,
        pw,
        {
            "farmer_phone": pw.farmer.phone,
            "lines": [{"sku_id": str(sku.id), "qty": "1"}],
            "payment": {"mode": "card_terminal", "reference_note": "RRN 42"},
        },
    )
    assert resp.status_code == 201, resp.text
    out = resp.json()
    invoice = out["invoice"]
    assert invoice["supply_type"] == "intra"
    assert invoice["invoice_no"].startswith(f"FCC/{pw.store.code}/")
    assert invoice["invoice_no"].endswith("/000001")
    assert invoice["seller_gstin"].startswith("36") and invoice["buyer_name"] == pw.farmer.name
    (line,) = invoice["lines"]
    assert line["hsn"] == "38089199" and line["cgst_rate_bp"] == line["sgst_rate_bp"] == 900
    assert line["cgst_paise"] == line["sgst_paise"] and invoice["igst_paise"] == 0
    assert invoice["total_paise"] % 100 == 0
    assert (
        invoice["taxable_paise"]
        + invoice["cgst_paise"]
        + invoice["sgst_paise"]
        + invoice["round_off_paise"]
        == invoice["total_paise"]
    )
    assert invoice["amount_in_words"].startswith("Rupees ") and invoice["has_pdf"]

    order = await pw.session.get_one(Order, uuid.UUID(out["order_id"]))
    assert order.channel == "pos" and order.status == "handed_over"
    assert order.invoice_no == invoice["invoice_no"] and order.farmer_id == pw.farmer.id
    assert order.total_paise == invoice["taxable_paise"] + invoice["cgst_paise"] * 2
    lines = (
        (await pw.session.execute(select(OrderLine).where(OrderLine.order_id == order.id)))
        .scalars()
        .all()
    )
    assert len(lines) == 1 and lines[0].batch_id is not None
    assert await stock_on_hand(pw.session, pw.store.id, sku.id) == on_hand - 1

    assert out["payment"]["status"] == "paid"
    assert out["payment"]["amount_paise"] == invoice["total_paise"]

    fetched = await client.get(f"/v1/invoices/{invoice['id']}", headers=pw.headers("accountant"))
    assert fetched.status_code == 200 and fetched.json() == invoice
    pdf = await client.get(f"/v1/invoices/{invoice['id']}/pdf", headers=pw.headers("owner"))
    assert pdf.status_code == 200 and pdf.json()["expires_at"]
    text = _pdf_text(pdf.json()["url"])
    for expected in (
        "TAX INVOICE",
        invoice["seller_gstin"],
        "38089199",
        invoice["invoice_no"],
        inr(invoice["total_paise"]),
        inr(invoice["cgst_paise"]),
        "CGST",
        "SGST",
        "Amount in words",
    ):
        assert expected in text, expected
    assert pw.farmer.phone not in text  # PII: the phone is masked on the PDF


async def test_inter_state_buyer_pays_igst(client: AsyncClient, pw: PayWorld) -> None:
    sku, product, _ = await _stocked(pw)
    product.gst_rate_bp = 1200
    await pw.session.flush()
    resp = await _sale(
        client,
        pw,
        {
            "buyer_name": "Karnataka Agro Traders",
            "buyer_state": "Karnataka",
            "buyer_gstin": "29ABCDE1234F1Z5",
            "lines": [{"sku_id": str(sku.id), "qty": "1"}],
            "payment": {"mode": "cash", "receipt_uri": await pw.blob()},
        },
    )
    assert resp.status_code == 201, resp.text
    invoice = resp.json()["invoice"]
    assert invoice["supply_type"] == "inter" and invoice["place_of_supply"] == "Karnataka (29)"
    assert invoice["cgst_paise"] == invoice["sgst_paise"] == 0 and invoice["igst_paise"] > 0
    assert invoice["lines"][0]["igst_rate_bp"] == 1200
    assert resp.json()["payment"]["status"] == "pending_reconciliation"
    row = await pw.session.get_one(Invoice, uuid.UUID(invoice["id"]))
    assert row.pdf_uri is not None
    signed = pw.blobs.signed_url(row.pdf_uri, ttl=timedelta(minutes=1), now=datetime.now(UTC))
    text = _pdf_text(signed.url)
    assert "IGST" in text and "29ABCDE1234F1Z5" in text and "Inter-state" in text


async def test_numbers_are_sequential_and_a_failed_sale_leaves_no_gap(
    client: AsyncClient, pw: PayWorld
) -> None:
    sku, _product, on_hand = await _stocked(pw)
    base = {"payment": {"mode": "card_terminal", "reference_note": "x"}}
    first = await _sale(client, pw, {**base, "lines": [{"sku_id": str(sku.id), "qty": "1"}]})
    too_much = await _sale(
        client, pw, {**base, "lines": [{"sku_id": str(sku.id), "qty": str(on_hand + 5)}]}
    )
    assert too_much.status_code == 409 and too_much.json()["code"] == "insufficient_stock"
    second = await _sale(client, pw, {**base, "lines": [{"sku_id": str(sku.id), "qty": "1"}]})
    nos = [r.json()["invoice"]["invoice_no"] for r in (first, second)]
    assert [n.rsplit("/", 1)[1] for n in nos] == ["000001", "000002"], nos


async def test_walk_in_sale_and_share(client: AsyncClient, pw: PayWorld) -> None:
    sku, _product, _ = await _stocked(pw)
    resp = await _sale(
        client,
        pw,
        {
            "lines": [{"sku_id": str(sku.id), "qty": "1"}],
            "payment": {"mode": "card_terminal", "reference_note": "x"},
        },
        role="accountant",
    )
    assert resp.status_code == 201, resp.text
    invoice = resp.json()["invoice"]
    assert invoice["buyer_name"] == "Cash customer" and invoice["farmer_id"] is None
    share = f"/v1/invoices/{invoice['id']}/share"
    headers = pw.headers("store_manager")
    no_phone = await client.post(share, json={"channel": "whatsapp"}, headers=headers)
    assert no_phone.status_code == 422 and no_phone.json()["code"] == "phone_required"
    wa = await client.post(
        share, json={"channel": "whatsapp", "phone": "+919876500001"}, headers=headers
    )
    assert wa.status_code == 200 and wa.json()["to"] == "+91******0001"
    message = pw.messages.sent[-1]
    assert message.channel == "whatsapp" and message.template == "invoice_share"
    assert message.params["invoice_no"] == invoice["invoice_no"]
    assert message.params["url"].endswith(".pdf")


async def test_farmer_invoice_shared_by_sms_to_the_farmer(
    client: AsyncClient, pw: PayWorld
) -> None:
    sku, _product, _ = await _stocked(pw)
    resp = await _sale(
        client,
        pw,
        {
            "farmer_id": str(pw.farmer.id),
            "lines": [{"sku_id": str(sku.id), "qty": "1"}],
            "payment": {"mode": "card_terminal", "reference_note": "x"},
        },
    )
    invoice = resp.json()["invoice"]
    sms = await client.post(
        f"/v1/invoices/{invoice['id']}/share",
        json={"channel": "sms"},
        headers=pw.headers("owner"),
    )
    assert sms.status_code == 200, sms.text
    message = pw.messages.sent[-1]
    assert message.channel == "sms" and message.to == pw.farmer.phone
    assert invoice["invoice_no"] in message.body


async def test_validation_and_scope(client: AsyncClient, pw: PayWorld) -> None:
    sku, _product, _ = await _stocked(pw)
    pay = {"mode": "card_terminal", "reference_note": "x"}
    unknown = await _sale(
        client, pw, {"lines": [{"sku_id": str(uuid.uuid4()), "qty": "1"}], "payment": pay}
    )
    assert unknown.status_code == 422 and unknown.json()["code"] == "unknown_sku"
    nobody = await _sale(
        client,
        pw,
        {
            "farmer_phone": "+919999999990",
            "lines": [{"sku_id": str(sku.id), "qty": "1"}],
            "payment": pay,
        },
    )
    assert nobody.status_code == 404 and nobody.json()["code"] == "farmer_not_found"
    both = await _sale(
        client,
        pw,
        {
            "farmer_id": str(pw.farmer.id),
            "farmer_phone": pw.farmer.phone,
            "lines": [{"sku_id": str(sku.id), "qty": "1"}],
            "payment": pay,
        },
    )
    assert both.status_code == 422
    assert pw.other_store is not None
    elsewhere = await client.post(
        f"/v1/stores/{pw.other_store.id}/pos/sales",
        json={"lines": [{"sku_id": str(sku.id), "qty": "1"}], "payment": pay},
        headers=pw.headers("store_manager"),
    )
    assert elsewhere.status_code == 404
    missing = await client.get(f"/v1/invoices/{uuid.uuid4()}", headers=pw.headers("owner"))
    assert missing.status_code == 404


async def test_credit_sale_blocked_rolls_back_through_the_port(
    client: AsyncClient, pw: PayWorld
) -> None:
    """A fake OrderPort proves the POS only talks to orders through the port."""
    from tests.payments.helpers import Decision

    drafts: list[PosOrderDraft] = []

    class FakeOrders:
        async def create_pos_order(self, session: AsyncSession, draft: PosOrderDraft) -> Order:
            drafts.append(draft)
            order = Order(
                tenant_id=draft.tenant_id,
                farmer_id=draft.farmer_id,
                store_id=draft.store_id,
                channel="pos",
                status="handed_over",
                subtotal_paise=draft.subtotal_paise,
                discount_paise=0,
                tax_paise=draft.tax_paise,
                total_paise=draft.total_paise,
                placed_by=draft.placed_by,
            )
            session.add(order)
            await session.flush()
            return order

    pw.app.state.pos_orders = FakeOrders()
    sku, _product, _ = await _stocked(pw)
    ok = await _sale(
        client,
        pw,
        {
            "farmer_id": str(pw.farmer.id),
            "lines": [{"sku_id": str(sku.id), "qty": "2"}],
            "payment": {"mode": "credit"},
        },
    )
    assert ok.status_code == 201, ok.text
    assert len(drafts) == 1 and drafts[0].lines[0].qty == Decimal("2")
    assert pw.ledger.checks[-1]["amount_paise"] == ok.json()["invoice"]["total_paise"]
    payment = await pw.session.get_one(Payment, uuid.UUID(ok.json()["payment"]["payment_id"]))
    assert payment.mode == "credit" and payment.status == "paid"

    pw.ledger.decision = Decision(False, None, 100)
    blocked = await _sale(
        client,
        pw,
        {
            "farmer_id": str(pw.farmer.id),
            "lines": [{"sku_id": str(sku.id), "qty": "1"}],
            "payment": {"mode": "credit"},
        },
    )
    assert blocked.status_code == 409 and blocked.json()["code"] == "credit_limit_exceeded"
