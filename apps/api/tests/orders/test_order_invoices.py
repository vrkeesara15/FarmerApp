"""GST invoices for officer / farmer-app orders (ST-001 "GST format applies to every sale",
FA-020 A57 "share invoice on WhatsApp"): an order that reaches ``handed_over`` / ``delivered``
gets exactly one invoice through the POS path (gapless per-store numbers, CGST / SGST vs
IGST, PDF), exposed as ``invoice_id`` on the order reads and in the sync change payload."""

from __future__ import annotations

import uuid
from typing import Any

from fastapi import FastAPI
from httpx import AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.auth.models import UserRole
from farmerapp.db.session import tenant_scope
from farmerapp.invoices.models import Invoice
from farmerapp.invoices.service import issue_order_invoice
from farmerapp.orders.models import Order
from tests.authz.conftest import Bearer, World
from tests.orders.helpers import place, receive


async def _move(
    client: AsyncClient, bearer: Bearer, world: World, order_id: str, status: str, expect: int = 200
) -> dict[str, Any]:
    resp = await client.post(
        f"/v1/orders/{order_id}/status",
        json={"status": status},
        headers=bearer(world.a.user(UserRole.STORE_MANAGER)),
    )
    assert resp.status_code == expect, resp.text
    out: dict[str, Any] = resp.json()
    return out


async def _invoices(db_session: AsyncSession, world: World, order_id: str) -> list[Invoice]:
    async with tenant_scope(db_session, world.a.tenant.id):
        rows = await db_session.execute(
            select(Invoice).where(Invoice.order_id == uuid.UUID(order_id))
        )
        return list(rows.scalars().all())


async def _pull(client: AsyncClient, headers: dict[str, str]) -> list[dict[str, Any]]:
    resp = await client.post(
        "/v1/sync", json={"device_id": "dev-inv", "cursor": None, "ops": []}, headers=headers
    )
    assert resp.status_code == 200, resp.text
    changes: list[dict[str, Any]] = resp.json()["changes"]
    return changes


async def _pos_sale(client: AsyncClient, bearer: Bearer, world: World) -> str:
    resp = await client.post(
        f"/v1/stores/{world.a.store_id}/pos/sales",
        json={
            "lines": [{"sku_id": str(world.a.sku_id), "qty": "1"}],
            "payment": {"mode": "card_terminal", "reference_note": "RRN 7"},
        },
        headers=bearer(world.a.user(UserRole.STORE_MANAGER)),
    )
    assert resp.status_code == 201, resp.text
    number: str = resp.json()["invoice"]["invoice_no"]
    return number


async def test_officer_order_handed_over_gets_exactly_one_invoice(
    app: FastAPI, client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=10)
    officer = bearer(world.a.user(UserRole.FIELD_OFFICER))
    order = await place(client, bearer, world, lines=[{"sku_id": str(world.a.sku_id), "qty": "3"}])
    assert order["channel"] == "officer" and order["invoice_id"] is None
    for status in ("packed", "ready"):
        moved = await _move(client, bearer, world, order["id"], status)
        assert moved["invoice_id"] is None and moved["invoice_no"] is None
    done = await _move(client, bearer, world, order["id"], "handed_over")
    (invoice,) = await _invoices(db_session, world, order["id"])
    assert done["invoice_id"] == str(invoice.id) and done["invoice_no"] == invoice.invoice_no
    assert invoice.invoice_no.endswith("/000001") and invoice.pdf_uri is not None
    # The invoice is what was charged: its total equals the order's total.
    assert invoice.total_paise == done["total_paise"]
    assert invoice.taxable_paise == done["subtotal_paise"]
    assert invoice.supply_type == "intra" and invoice.igst_paise == 0
    assert invoice.cgst_paise == invoice.sgst_paise
    assert invoice.farmer_id is not None and str(invoice.farmer_id) == order["farmer_id"]
    # The officer reads it on the order, in the list and in the change feed, and can share it.
    detail = await client.get(f"/v1/orders/{order['id']}", headers=officer)
    assert detail.json()["invoice_id"] == str(invoice.id)
    listing = await client.get("/v1/orders", headers=officer)
    row = next(o for o in listing.json()["items"] if o["id"] == order["id"])
    assert row["invoice_id"] == str(invoice.id)
    feed = [c for c in await _pull(client, officer) if c["entity"] == "order"]
    pulled = next(c for c in feed if c["entity_id"] == order["id"])
    assert pulled["data"]["invoice_id"] == str(invoice.id)
    assert pulled["data"]["status"] == "handed_over"
    fetched = await client.get(f"/v1/invoices/{invoice.id}", headers=officer)
    assert fetched.status_code == 200 and fetched.json()["invoice_no"] == invoice.invoice_no
    pdf = await client.get(f"/v1/invoices/{invoice.id}/pdf", headers=officer)
    assert pdf.status_code == 200 and pdf.json()["url"]

    # A repeated transition is refused and issues nothing; a retried issue returns the same.
    await _move(client, bearer, world, order["id"], "handed_over", expect=409)
    await _move(client, bearer, world, order["id"], "delivered", expect=409)
    async with tenant_scope(db_session, world.a.tenant.id):
        row_order = await db_session.get_one(Order, uuid.UUID(order["id"]))
        again = await issue_order_invoice(
            db_session,
            world.a.user(UserRole.STORE_MANAGER),
            row_order,
            blobs=app.state.blobs,
            now=invoice.issued_at,
        )
        assert again.id == invoice.id
    assert len(await _invoices(db_session, world, order["id"])) == 1


async def test_delivered_order_gets_an_invoice_and_cancelled_never_does(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=10)
    delivered = await place(
        client,
        bearer,
        world,
        fulfilment="delivery",
        lines=[{"sku_id": str(world.a.sku_id), "qty": "1"}],
    )
    cancelled = await place(
        client, bearer, world, lines=[{"sku_id": str(world.a.sku_id), "qty": "1"}]
    )
    for status in ("packed", "ready", "delivered"):
        out = await _move(client, bearer, world, delivered["id"], status)
    assert out["invoice_id"] is not None
    assert len(await _invoices(db_session, world, delivered["id"])) == 1
    await _move(client, bearer, world, cancelled["id"], "packed")
    gone = await _move(client, bearer, world, cancelled["id"], "cancelled")
    assert gone["invoice_id"] is None and gone["invoice_no"] is None
    assert await _invoices(db_session, world, cancelled["id"]) == []


async def test_numbering_stays_gapless_alongside_pos_sales(
    client: AsyncClient, world: World, bearer: Bearer, db_session: AsyncSession
) -> None:
    await receive(client, bearer, world, qty=20)
    first = await _pos_sale(client, bearer, world)
    order = await place(client, bearer, world, lines=[{"sku_id": str(world.a.sku_id), "qty": "2"}])
    for status in ("packed", "ready", "handed_over"):
        done = await _move(client, bearer, world, order["id"], status)
    third = await _pos_sale(client, bearer, world)
    numbers = [first, done["invoice_no"], third]
    assert [n.rsplit("/", 1)[1] for n in numbers] == ["000001", "000002", "000003"], numbers
    async with tenant_scope(db_session, world.a.tenant.id):
        count = await db_session.scalar(
            select(func.count()).select_from(Invoice).where(Invoice.store_id == world.a.store_id)
        )
    assert count == 3
