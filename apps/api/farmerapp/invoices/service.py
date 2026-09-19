"""GST invoices and the POS sale (ST-001).

``pos_preview`` (``POST /v1/stores/{id}/pos/preview``) runs the same ``draft_sale`` (store,
buyer, server prices, ``gst.compute_invoice``) and returns the invoice it would issue without
writing anything or taking an invoice number.

``pos_sale`` runs in one transaction: resolve the store (caller's scope), the buyer (farmer
by id or phone, else walk-in), price every line server-side (store price list, else MRP),
compute GST (``farmerapp.invoices.gst``), persist the ``pos`` order through the
``OrderPort`` (stock sale movements), take the next gapless invoice number, snapshot the
``invoice`` row, render the PDF into the blob store and collect the payment through
``farmerapp.payments.service.create_payment`` (amount = the invoice's rounded total). Any
failure — no stock, provider down — rolls the whole sale back, invoice number included.

A **credit** sale asks the credit gate (``khata.credit.check_and_reserve_credit`` through
the ``LedgerPort``) first, for the invoice total and a pre-assigned order id, before anything
else is written. Allowed: the gate posted the khata debit and the payment links it.
Blocked: nothing but the approval request is written and ``CreditBlocked`` is returned —
the route answers 402 ``credit_limit_exceeded`` without raising so the request commits.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, replace
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import AppError, NotFoundError
from farmerapp.auth.models import User
from farmerapp.auth.providers import ProviderError, mask_phone
from farmerapp.auth.scope import order_filters
from farmerapp.catalog.models import Product, Sku
from farmerapp.catalog.pricing import prices_for, resolved_price
from farmerapp.db.models.tenant import Tenant
from farmerapp.farmers.models import Farmer
from farmerapp.invoices.gst import InvoiceTotals, LineInput, compute_invoice, supply_type
from farmerapp.invoices.models import Invoice
from farmerapp.invoices.numbering import financial_year, format_invoice_no, next_seq
from farmerapp.invoices.pdf import render_invoice_pdf
from farmerapp.invoices.ports import OrderPort, PosOrderDraft, PosOrderLine
from farmerapp.invoices.schemas import (
    InvoiceLineOut,
    InvoiceOut,
    InvoiceShareIn,
    InvoiceShareOut,
    PosPreviewOut,
    PosSaleIn,
    PosSaleOut,
    SignedUrlOut,
)
from farmerapp.invoices.words import amount_in_words
from farmerapp.logging import get_logger
from farmerapp.orders.models import Order, OrderLine
from farmerapp.payments.config import IST, payment_settings, state_code
from farmerapp.payments.day_close import visible_store
from farmerapp.payments.models import PaymentMode
from farmerapp.payments.schemas import PaymentCreate
from farmerapp.payments.service import (
    CreditBlocked,
    InvalidModeError,
    Messaging,
    PaymentServices,
    PhoneRequiredError,
    ProviderUnavailableError,
    Target,
    actor_of,
    create_payment,
)
from farmerapp.tenants.models import Store, Village
from farmerapp.uploads.blobstore import BlobStore

log = get_logger("farmerapp.invoices")

WALK_IN_BUYER = "Cash customer"
INVOICE_SHARE_TEMPLATE = "invoice_share"  # WhatsApp template (registration is human work)
INVOICE_SHARE_SMS = "Invoice {no} for Rs {amount} from {seller}: {url}"  # DLT template body
PDF_CONTENT_TYPE = "application/pdf"


class UnknownSkuError(AppError):
    status = 422
    code = "unknown_sku"


class FarmerNotFoundError(NotFoundError):
    code = "farmer_not_found"


@dataclass(frozen=True)
class Buyer:
    farmer: Farmer | None
    name: str
    phone: str | None
    state: str
    gstin: str | None


# --------------------------------------------------------------------------- lookups
async def visible_invoice(session: AsyncSession, actor: User, invoice_id: uuid.UUID) -> Invoice:
    row = (
        await session.execute(
            select(Invoice)
            .join(Order, Order.id == Invoice.order_id)
            .where(Invoice.id == invoice_id, Invoice.deleted_at.is_(None), *order_filters(actor))
        )
    ).scalar_one_or_none()
    if row is None:
        raise NotFoundError("Invoice not found.")
    return row


async def _buyer(session: AsyncSession, actor: User, store: Store, body: PosSaleIn) -> Buyer:
    farmer: Farmer | None = None
    if body.farmer_id is not None or body.farmer_phone is not None:
        stmt = select(Farmer).where(
            Farmer.tenant_id == actor.tenant_id, Farmer.deleted_at.is_(None)
        )
        stmt = stmt.where(
            Farmer.id == body.farmer_id
            if body.farmer_id is not None
            else Farmer.phone == body.farmer_phone
        )
        farmer = (await session.execute(stmt.limit(1))).scalar_one_or_none()
        if farmer is None:
            raise FarmerNotFoundError("No farmer with that id / phone in this tenant.")
    state = body.buyer_state
    if state is None and farmer is not None:
        village = await session.get(Village, farmer.village_id)
        state = village.state if village is not None else None
    return Buyer(
        farmer=farmer,
        name=body.buyer_name or (farmer.name if farmer is not None else WALK_IN_BUYER),
        phone=farmer.phone if farmer is not None else body.payment.phone,
        state=state or store.state,
        gstin=body.buyer_gstin,
    )


async def _priced_lines(
    session: AsyncSession, store: Store, body: PosSaleIn, now: datetime
) -> list[LineInput]:
    sku_ids = list(dict.fromkeys(line.sku_id for line in body.lines))
    rows = (
        await session.execute(
            select(Sku, Product)
            .join(Product, Product.id == Sku.product_id)
            .where(
                Sku.id.in_(sku_ids),
                Sku.deleted_at.is_(None),
                Sku.active.is_(True),
                Product.deleted_at.is_(None),
            )
        )
    ).all()
    by_id = {sku.id: (sku, product) for sku, product in rows}
    missing = [str(s) for s in sku_ids if s not in by_id]
    if missing:
        raise UnknownSkuError(f"Unknown or inactive SKU(s): {', '.join(missing)}.")
    prices = await prices_for(session, sku_ids, store.id, now.astimezone(IST).date())
    out: list[LineInput] = []
    for line in body.lines:
        sku, product = by_id[line.sku_id]
        pack = f"{sku.pack_size_value.normalize():f} {sku.pack_size_unit}"
        out.append(
            LineInput(
                sku_id=sku.id,
                description=f"{product.name} {pack}",
                hsn=product.hsn,
                qty=line.qty,
                unit="pc",
                unit_price_paise=resolved_price(prices.get(sku.id), sku.mrp_paise),
                gst_rate_bp=product.gst_rate_bp,
            )
        )
    return out


# --------------------------------------------------------------------------- issue
async def issue_invoice(
    session: AsyncSession,
    *,
    tenant: Tenant,
    store: Store,
    order: Order,
    buyer: Buyer,
    totals: InvoiceTotals,
    actor: User,
    blobs: BlobStore,
    now: datetime,
) -> Invoice:
    settings = payment_settings(tenant.settings)
    fy = financial_year(now.astimezone(IST).date())
    seq = await next_seq(session, tenant_id=tenant.id, store_id=store.id, fy=fy)
    prefix = settings.invoice_prefix or (tenant.slug or "INV").upper()[:8]
    invoice = Invoice(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        order_id=order.id,
        store_id=store.id,
        farmer_id=buyer.farmer.id if buyer.farmer is not None else None,
        invoice_no=format_invoice_no(prefix, store.code, fy, seq),
        financial_year=fy,
        seq=seq,
        issued_at=now,
        seller_name=settings.legal_name or tenant.name,
        seller_gstin=settings.gstin_for(store.state),
        seller_address=f"{store.name}, {store.district}, {store.state}",
        seller_state=store.state,
        seller_state_code=state_code(store.state),
        buyer_name=buyer.name,
        buyer_phone=buyer.phone,
        buyer_gstin=buyer.gstin,
        buyer_state=buyer.state,
        place_of_supply=f"{buyer.state} ({state_code(buyer.state)})",
        supply_type=totals.supply_type.value,
        taxable_paise=totals.taxable_paise,
        cgst_paise=totals.cgst_paise,
        sgst_paise=totals.sgst_paise,
        igst_paise=totals.igst_paise,
        round_off_paise=totals.round_off_paise,
        total_paise=totals.total_paise,
        amount_in_words=amount_in_words(totals.total_paise),
        lines=[line.as_json() for line in totals.lines],
        created_by=actor.id,
    )
    session.add(invoice)
    order.invoice_no = invoice.invoice_no
    order.invoice_id = invoice.id
    await session.flush()
    await ensure_pdf(invoice, blobs)
    await session.flush()
    return invoice


async def issue_order_invoice(
    session: AsyncSession, actor: User, order: Order, *, blobs: BlobStore, now: datetime
) -> Invoice:
    """The GST invoice of an officer / farmer-app / queued order that reached ``handed_over``
    or ``delivered`` (ST-001: the GST format applies to every sale; FA-020 A57 shares it).

    Idempotent: an order that already has an invoice (the POS sale, an earlier transition, a
    retried request) gets that one back; ``uq_invoice_order_id`` backs this up. Otherwise it
    runs the POS path — ``issue_invoice``: gapless per-store number, CGST / SGST vs IGST,
    snapshot and PDF — from the order's own lines (prices and GST rates as placed). The
    order's total is what was charged (payment, khata debit), so the invoice total is kept
    equal to it: the round-off line absorbs the paisa the separate CGST / SGST halves may
    differ by, instead of rounding to the rupee after the money was taken."""
    existing = (
        await session.execute(
            select(Invoice).where(
                Invoice.tenant_id == order.tenant_id,
                Invoice.order_id == order.id,
                Invoice.deleted_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if existing is not None:
        order.invoice_no, order.invoice_id = existing.invoice_no, existing.id
        return existing
    store = await session.get_one(Store, order.store_id)
    tenant = await session.get_one(Tenant, order.tenant_id)
    farmer = await session.get(Farmer, order.farmer_id) if order.farmer_id is not None else None
    state: str | None = None
    if farmer is not None:
        village = await session.get(Village, farmer.village_id)
        state = village.state if village is not None else None
    buyer = Buyer(
        farmer=farmer,
        name=farmer.name if farmer is not None else WALK_IN_BUYER,
        phone=farmer.phone if farmer is not None else None,
        state=state or store.state,
        gstin=None,
    )
    rows = (
        await session.execute(
            select(OrderLine, Sku, Product)
            .join(Sku, Sku.id == OrderLine.sku_id)
            .join(Product, Product.id == Sku.product_id)
            .where(OrderLine.order_id == order.id, OrderLine.deleted_at.is_(None))
            .order_by(OrderLine.created_at, OrderLine.id)
        )
    ).all()
    lines = [
        LineInput(
            sku_id=sku.id,
            description=f"{product.name} {sku.pack_size_value.normalize():f} {sku.pack_size_unit}",
            hsn=product.hsn,
            qty=line.qty,
            unit="pc",
            unit_price_paise=line.unit_price_paise,
            gst_rate_bp=line.gst_rate_bp,
        )
        for line, sku, product in rows
    ]
    totals = compute_invoice(lines, supply_type(store.state, buyer.state))
    charged = order.total_paise
    round_off = charged - totals.exact_total_paise
    totals = replace(totals, round_off_paise=round_off, total_paise=charged)
    invoice = await issue_invoice(
        session,
        tenant=tenant,
        store=store,
        order=order,
        buyer=buyer,
        totals=totals,
        actor=actor,
        blobs=blobs,
        now=now,
    )
    log.info(
        "order_invoice_issued",
        order_id=str(order.id),
        invoice_no=invoice.invoice_no,
        total_paise=invoice.total_paise,
    )
    return invoice


async def ensure_pdf(invoice: Invoice, blobs: BlobStore) -> str:
    if invoice.pdf_uri is None:
        key = f"{invoice.tenant_id}/invoice/{invoice.id}.pdf"
        invoice.pdf_uri = await blobs.put(
            key, render_invoice_pdf(invoice), content_type=PDF_CONTENT_TYPE
        )
    return invoice.pdf_uri


async def pdf_url(
    invoice: Invoice, blobs: BlobStore, *, ttl_seconds: int, now: datetime
) -> SignedUrlOut:
    uri = await ensure_pdf(invoice, blobs)
    signed = blobs.signed_url(uri, ttl=timedelta(seconds=ttl_seconds), now=now)
    return SignedUrlOut(url=signed.url, expires_at=signed.expires_at)


async def share_invoice(
    session: AsyncSession,
    invoice: Invoice,
    body: InvoiceShareIn,
    *,
    messaging: Messaging,
    blobs: BlobStore,
    ttl_seconds: int,
    now: datetime,
) -> InvoiceShareOut:
    phone = body.phone or invoice.buyer_phone
    if phone is None and invoice.farmer_id is not None:
        farmer = await session.get(Farmer, invoice.farmer_id)
        phone = farmer.phone if farmer is not None else None
    if phone is None:
        raise PhoneRequiredError("Sharing a walk-in invoice needs `phone`.")
    link = await pdf_url(invoice, blobs, ttl_seconds=ttl_seconds, now=now)
    await session.flush()
    amount = f"{invoice.total_paise // 100}.{invoice.total_paise % 100:02d}"
    try:
        if body.channel == "whatsapp":
            await messaging.whatsapp.send_whatsapp(
                phone,
                INVOICE_SHARE_TEMPLATE,
                {"invoice_no": invoice.invoice_no, "amount": amount, "url": link.url},
            )
        else:
            await messaging.sms.send_sms(
                phone,
                INVOICE_SHARE_SMS.format(
                    no=invoice.invoice_no, amount=amount, seller=invoice.seller_name, url=link.url
                ),
            )
    except ProviderError as exc:
        raise ProviderUnavailableError("The message could not be sent; try again.") from exc
    log.info("invoice_shared", invoice_id=str(invoice.id), channel=body.channel)
    return InvoiceShareOut(
        channel=body.channel, to=mask_phone(phone), url_expires_at=link.expires_at
    )


# --------------------------------------------------------------------------- POS
@dataclass(frozen=True)
class SaleDraft:
    """Everything the invoice of a POS sale is computed from (nothing written yet)."""

    store: Store
    tenant: Tenant
    buyer: Buyer
    totals: InvoiceTotals


async def draft_sale(
    session: AsyncSession, actor: User, store_id: uuid.UUID, body: PosSaleIn, now: datetime
) -> SaleDraft:
    """Resolve the store (caller's scope), the buyer and the server prices and compute the GST
    invoice (``gst.compute_invoice``). Read-only: shared by the sale and its preview, so a
    preview's totals are the sale's totals."""
    store = await visible_store(session, actor, store_id)
    tenant = await session.get_one(Tenant, actor.tenant_id)
    buyer = await _buyer(session, actor, store, body)
    if body.payment.mode == PaymentMode.CREDIT and buyer.farmer is None:
        raise InvalidModeError("Credit is for an order of a known farmer, not for dues.")
    lines = await _priced_lines(session, store, body, now)
    totals = compute_invoice(lines, supply_type(store.state, buyer.state))
    return SaleDraft(store=store, tenant=tenant, buyer=buyer, totals=totals)


async def pos_preview(
    session: AsyncSession, actor: User, store_id: uuid.UUID, body: PosSaleIn, *, now: datetime
) -> PosPreviewOut:
    """The invoice ``pos_sale`` would issue for ``body`` — no order, stock movement, invoice
    number, credit check or payment (ST-001 tablet preview)."""
    draft = await draft_sale(session, actor, store_id, body, now)
    store, buyer, totals = draft.store, draft.buyer, draft.totals
    settings = payment_settings(draft.tenant.settings)
    return PosPreviewOut(
        store_id=store.id,
        farmer_id=buyer.farmer.id if buyer.farmer is not None else None,
        seller_name=settings.legal_name or draft.tenant.name,
        seller_gstin=settings.gstin_for(store.state),
        seller_state=store.state,
        seller_state_code=state_code(store.state),
        buyer_name=buyer.name,
        buyer_gstin=buyer.gstin,
        buyer_state=buyer.state,
        place_of_supply=f"{buyer.state} ({state_code(buyer.state)})",
        supply_type=totals.supply_type.value,
        taxable_paise=totals.taxable_paise,
        cgst_paise=totals.cgst_paise,
        sgst_paise=totals.sgst_paise,
        igst_paise=totals.igst_paise,
        tax_paise=totals.tax_paise,
        round_off_paise=totals.round_off_paise,
        total_paise=totals.total_paise,
        amount_in_words=amount_in_words(totals.total_paise),
        lines=[InvoiceLineOut.model_validate(line.as_json()) for line in totals.lines],
    )


async def pos_sale(
    session: AsyncSession,
    actor: User,
    store_id: uuid.UUID,
    body: PosSaleIn,
    *,
    orders: OrderPort,
    services: PaymentServices,
    messaging: Messaging,
    blobs: BlobStore,
    now: datetime,
) -> PosSaleOut | CreditBlocked:
    draft = await draft_sale(session, actor, store_id, body, now)
    store, tenant, buyer, totals = draft.store, draft.tenant, draft.buyer, draft.totals
    order_id = uuid.uuid4()
    credit = None
    if body.payment.mode == PaymentMode.CREDIT and buyer.farmer is not None:
        # (draft_sale already refused credit for a walk-in buyer.)
        credit = await services.ledger.check_and_reserve_credit(
            session,
            tenant_id=actor.tenant_id,
            farmer_id=buyer.farmer.id,
            store_id=store.id,
            amount_paise=totals.total_paise,
            order_id=order_id,
            actor=actor_of(actor),
            approval_request_id=body.credit_approval_request_id,
        )
        if not credit.allowed:
            return CreditBlocked(credit)
    order = await orders.create_pos_order(
        session,
        PosOrderDraft(
            tenant_id=actor.tenant_id,
            store_id=store.id,
            farmer_id=buyer.farmer.id if buyer.farmer is not None else None,
            lines=tuple(
                PosOrderLine(
                    sku_id=line.sku_id,
                    qty=line.qty,
                    unit_price_paise=line.unit_price_paise,
                    gst_rate_bp=line.gst_rate_bp,
                    line_total_paise=line.taxable_paise,
                    label_claim_id=wanted.label_claim_id,
                )
                for line, wanted in zip(totals.lines, body.lines, strict=True)
            ),
            subtotal_paise=totals.taxable_paise,
            tax_paise=totals.tax_paise,
            placed_by=actor.id,
            at=now,
            order_id=order_id,
        ),
    )
    invoice = await issue_invoice(
        session,
        tenant=tenant,
        store=store,
        order=order,
        buyer=buyer,
        totals=totals,
        actor=actor,
        blobs=blobs,
        now=now,
    )
    payment = await create_payment(
        session,
        actor,
        PaymentCreate(
            order_id=order.id,
            mode=body.payment.mode,
            receipt_uri=body.payment.receipt_uri,
            reference_note=body.payment.reference_note,
            channel=body.payment.channel,
            phone=body.payment.phone,
        ),
        services=services,
        messaging=messaging,
        blobs=blobs,
        now=now,
        target=Target(
            store_id=store.id,
            farmer_id=order.farmer_id,
            order=order,
            due_paise=invoice.total_paise,  # the rounded invoice total is what is collected
        ),
        credit=credit,
    )
    if isinstance(payment, CreditBlocked):  # pragma: no cover - the gate ran above
        raise RuntimeError("credit was reserved before the sale")
    log.info(
        "pos_sale",
        order_id=str(order.id),
        invoice_no=invoice.invoice_no,
        total_paise=invoice.total_paise,
        mode=body.payment.mode.value,
    )
    return PosSaleOut(order_id=order.id, invoice=InvoiceOut.from_row(invoice), payment=payment)


__all__ = [
    "Buyer",
    "FarmerNotFoundError",
    "SaleDraft",
    "UnknownSkuError",
    "draft_sale",
    "ensure_pdf",
    "issue_invoice",
    "issue_order_invoice",
    "pdf_url",
    "pos_preview",
    "pos_sale",
    "share_invoice",
    "visible_invoice",
]
