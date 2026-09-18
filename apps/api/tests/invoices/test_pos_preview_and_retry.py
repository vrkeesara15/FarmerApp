"""ST-001 server-side invoice preview (``POST /v1/stores/{id}/pos/preview``) and ST-007
credit approvals honoured on retry for POS sales and credit payments."""

from __future__ import annotations

import uuid
from typing import Any

from httpx import AsyncClient
from sqlalchemy import func, select

from farmerapp.invoices.models import Invoice, InvoiceCounter
from farmerapp.khata.models import CreditApprovalRequest, KhataEntry, khata_balance
from farmerapp.orders.models import Order
from farmerapp.payments.models import Payment
from farmerapp.stock.ledger import stock_on_hand
from farmerapp.stock.models import StockMovement
from tests.invoices.test_pos_api import _sale, _stocked
from tests.payments.helpers import PayWorld, request_transactions

TOTAL_KEYS = (
    "supply_type",
    "taxable_paise",
    "cgst_paise",
    "sgst_paise",
    "igst_paise",
    "round_off_paise",
    "total_paise",
    "amount_in_words",
    "seller_name",
    "seller_gstin",
    "seller_state",
    "seller_state_code",
    "buyer_name",
    "buyer_gstin",
    "buyer_state",
    "place_of_supply",
)


async def _preview(
    client: AsyncClient, pw: PayWorld, body: dict[str, Any], role: str = "store_manager"
) -> Any:
    return await client.post(
        f"/v1/stores/{pw.store.id}/pos/preview", json=body, headers=pw.headers(role)
    )


async def _counts(pw: PayWorld) -> tuple[int | None, ...]:
    out = []
    for model in (Order, Invoice, InvoiceCounter, Payment, StockMovement, KhataEntry):
        out.append(await pw.session.scalar(select(func.count()).select_from(model)))
    return tuple(out)


async def _preview_then_sell(client: AsyncClient, pw: PayWorld, body: dict[str, Any]) -> None:
    before = await _counts(pw)
    preview = await _preview(client, pw, body, role="accountant")
    assert preview.status_code == 200, preview.text
    shown = preview.json()
    assert await _counts(pw) == before  # nothing written, no invoice number taken
    again = await _preview(client, pw, body)
    assert again.json() == shown  # idempotent
    sale = await _sale(client, pw, body)
    assert sale.status_code == 201, sale.text
    invoice = sale.json()["invoice"]
    for key in TOTAL_KEYS:
        assert shown[key] == invoice[key], key
    assert shown["lines"] == invoice["lines"]
    assert (
        shown["tax_paise"] == invoice["cgst_paise"] + invoice["sgst_paise"] + invoice["igst_paise"]
    )
    assert shown["store_id"] == str(pw.store.id)
    assert sale.json()["payment"]["amount_paise"] == shown["total_paise"]


async def test_intra_state_preview_equals_the_sale(client: AsyncClient, pw: PayWorld) -> None:
    sku, product, _ = await _stocked(pw)
    product.hsn, product.gst_rate_bp = "31051000", 500  # 2.5 % + 2.5 %: paise round-off
    await pw.session.flush()
    body = {
        "farmer_id": str(pw.farmer.id),
        "lines": [{"sku_id": str(sku.id), "qty": "3"}],
        "payment": {"mode": "card_terminal", "reference_note": "RRN 7"},
    }
    preview = await _preview(client, pw, body)
    shown = preview.json()
    assert shown["supply_type"] == "intra" and shown["igst_paise"] == 0
    assert shown["cgst_paise"] == shown["sgst_paise"] > 0
    (line,) = shown["lines"]
    assert line["hsn"] == "31051000" and line["cgst_rate_bp"] == line["sgst_rate_bp"] == 250
    assert shown["total_paise"] % 100 == 0 and -50 <= shown["round_off_paise"] <= 50
    assert shown["amount_in_words"].startswith("Rupees ")
    assert shown["farmer_id"] == str(pw.farmer.id) and shown["buyer_name"] == pw.farmer.name
    await _preview_then_sell(client, pw, body)


async def test_inter_state_preview_equals_the_sale(client: AsyncClient, pw: PayWorld) -> None:
    sku, product, _ = await _stocked(pw)
    product.gst_rate_bp = 1200
    await pw.session.flush()
    body = {
        "buyer_name": "Karnataka Agro Traders",
        "buyer_state": "Karnataka",
        "buyer_gstin": "29ABCDE1234F1Z5",
        "lines": [{"sku_id": str(sku.id), "qty": "2"}],
        "payment": {"mode": "card_terminal", "reference_note": "RRN 8"},
    }
    shown = (await _preview(client, pw, body)).json()
    assert shown["supply_type"] == "inter" and shown["cgst_paise"] == shown["sgst_paise"] == 0
    assert shown["igst_paise"] > 0 and shown["lines"][0]["igst_rate_bp"] == 1200
    assert shown["place_of_supply"].startswith("Karnataka") and shown["farmer_id"] is None
    await _preview_then_sell(client, pw, body)


async def test_preview_validation_and_scope(client: AsyncClient, pw: PayWorld) -> None:
    sku, _product, on_hand = await _stocked(pw)
    body = {"lines": [{"sku_id": str(sku.id), "qty": "1"}], "payment": {"mode": "cash"}}
    # Credit with a walk-in buyer: same 422 as the sale.
    resp = await _preview(client, pw, {**body, "payment": {"mode": "credit"}})
    assert resp.status_code == 422 and resp.json()["code"] == "invalid_mode"
    resp = await _preview(
        client, pw, {**body, "lines": [{"sku_id": str(uuid.uuid4()), "qty": "1"}]}
    )
    assert resp.status_code == 422 and resp.json()["code"] == "unknown_sku"
    resp = await _preview(client, pw, {**body, "farmer_phone": "+919999999999"})
    assert resp.status_code == 404 and resp.json()["code"] == "farmer_not_found"
    for role in ("owner", "cluster_head", "field_officer", "farmer", "auditor"):
        resp = await _preview(client, pw, body, role=role)
        assert resp.status_code == 403, role
    if pw.other_store is not None:  # another store: outside the manager's scope
        resp = await client.post(
            f"/v1/stores/{pw.other_store.id}/pos/preview",
            json=body,
            headers=pw.headers("store_manager"),
        )
        assert resp.status_code == 404
    # A preview never checks or moves stock (the sale does): even more than on hand prices.
    resp = await _preview(
        client, pw, {**body, "lines": [{"sku_id": str(sku.id), "qty": str(on_hand + 5)}]}
    )
    assert resp.status_code == 200
    assert await stock_on_hand(pw.session, pw.store.id, sku.id) == on_hand


# --------------------------------------------------------------------------- ST-007 retry
async def _approve(client: AsyncClient, pw: PayWorld, request_id: str) -> None:
    resp = await client.post(
        f"/v1/credit-approvals/{request_id}/approve", headers=pw.headers("cluster_head")
    )
    assert resp.status_code == 200, resp.text


async def test_pos_credit_sale_retried_with_the_approval_goes_through_once(
    client: AsyncClient, pw: PayWorld
) -> None:
    request_transactions(pw)
    sku, _product, _ = await _stocked(pw)
    balance = await khata_balance(pw.session, pw.farmer.id, pw.store.id)
    await pw.set_limit(max(balance, 0) + 1)
    body: dict[str, Any] = {
        "farmer_id": str(pw.farmer.id),
        "lines": [{"sku_id": str(sku.id), "qty": "1"}],
        "payment": {"mode": "credit"},
    }
    blocked = await _sale(client, pw, body)
    assert blocked.status_code == 402, blocked.text
    problem = blocked.json()
    assert problem["code"] == "credit_limit_exceeded"
    request_id = problem["approval_request_id"]
    assert request_id is not None
    # Retrying with the id while pending refreshes the same request.
    pending = await _sale(client, pw, {**body, "credit_approval_request_id": request_id})
    assert pending.status_code == 402 and pending.json()["approval_request_id"] == request_id
    await _approve(client, pw, request_id)
    # Without the key the POS makes a new order id: still blocked.
    again = await _sale(client, pw, body)
    assert again.status_code == 402 and again.json()["approval_request_id"] != request_id
    ok = await _sale(client, pw, {**body, "credit_approval_request_id": request_id})
    assert ok.status_code == 201, ok.text
    out = ok.json()
    assert out["payment"]["mode"] == "credit" and out["payment"]["status"] == "paid"
    assert pw.ledger.checks[-1]["approval_request_id"] == uuid.UUID(request_id)
    request = await pw.session.get_one(CreditApprovalRequest, uuid.UUID(request_id))
    await pw.session.refresh(request)
    assert request.status == "consumed"
    assert request.consumed_by_order_id == uuid.UUID(out["order_id"])
    assert await khata_balance(pw.session, pw.farmer.id, pw.store.id) == (
        balance + out["invoice"]["total_paise"]
    )
    reuse = await _sale(client, pw, {**body, "credit_approval_request_id": request_id})
    assert reuse.status_code == 402 and reuse.json()["approval_request_id"] != request_id


async def test_credit_payment_retried_with_the_approval(client: AsyncClient, pw: PayWorld) -> None:
    request_transactions(pw)
    balance = await khata_balance(pw.session, pw.farmer.id, pw.store.id)
    await pw.set_limit(max(balance, 0) + 10_000)
    first = await pw.order(60_000)
    resp = await client.post(
        "/v1/payments",
        json={"order_id": str(first.id), "mode": "credit"},
        headers=pw.headers("store_manager"),
    )
    assert resp.status_code == 402
    request_id = resp.json()["approval_request_id"]
    await _approve(client, pw, request_id)
    # The approval travels with the farmer and store, not the order: a re-captured order
    # of the same amount (the first one was abandoned) is paid on credit with it, once.
    second = await pw.order(60_000)
    resp = await client.post(
        "/v1/payments",
        json={
            "order_id": str(second.id),
            "mode": "credit",
            "credit_approval_request_id": request_id,
        },
        headers=pw.headers("store_manager"),
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["status"] == "paid" and resp.json()["khata_entry_id"]
    request = await pw.session.get_one(CreditApprovalRequest, uuid.UUID(request_id))
    await pw.session.refresh(request)
    assert request.status == "consumed" and request.consumed_by_order_id == second.id
    third = await pw.order(60_000)
    resp = await client.post(
        "/v1/payments",
        json={
            "order_id": str(third.id),
            "mode": "credit",
            "credit_approval_request_id": request_id,
        },
        headers=pw.headers("store_manager"),
    )
    assert resp.status_code == 402
    # The first order's own approval was consumed by the second: it is blocked too.
    resp = await client.post(
        "/v1/payments",
        json={"order_id": str(first.id), "mode": "credit"},
        headers=pw.headers("store_manager"),
    )
    assert resp.status_code == 402
