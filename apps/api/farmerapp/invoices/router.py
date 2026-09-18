"""Invoice and POS routes (ST-001).

* ``POST /v1/stores/{id}/pos/sales`` (store manager own store, accountant) — counter sale:
  ``pos`` order handed over, stock out, GST invoice + PDF, payment, in one transaction.
* ``POST /v1/stores/{id}/pos/preview`` (same roles and body) — the invoice the sale would
  issue (same ``gst.py`` path), without writing anything or taking an invoice number.
* ``GET /v1/invoices/{id}`` — the invoice JSON (scope of its order).
* ``GET /v1/invoices/{id}/pdf`` — a signed URL to the PDF (15 min, SEC-016).
* ``POST /v1/invoices/{id}/share`` — send the PDF link by WhatsApp or SMS.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, Request, status
from fastapi.responses import JSONResponse

from farmerapp.api.errors import problem_responses
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User
from farmerapp.auth.policy import Role, require_roles
from farmerapp.invoices.ports import OrderPort
from farmerapp.invoices.schemas import (
    InvoiceOut,
    InvoiceShareIn,
    InvoiceShareOut,
    PosPreviewOut,
    PosSaleIn,
    PosSaleOut,
    SignedUrlOut,
)
from farmerapp.invoices.service import (
    pdf_url,
    pos_preview,
    pos_sale,
    share_invoice,
    visible_invoice,
)
from farmerapp.khata.credit import credit_blocked_response
from farmerapp.orders.pos import OrdersPosPort
from farmerapp.payments.service import (
    CreditBlocked,
    Messaging,
    PaymentServices,
    get_payment_services,
)
from farmerapp.settings import get_settings
from farmerapp.uploads.blobstore import BlobStore
from farmerapp.uploads.router import get_blob_store

POS_ROLES = (Role.STORE_MANAGER, Role.ACCOUNTANT)
INVOICE_READ_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.AUDITOR,
    Role.ACCOUNTANT,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.FIELD_OFFICER,
    Role.FARMER,
)
INVOICE_SHARE_ROLES = (Role.OWNER, Role.ACCOUNTANT, Role.CLUSTER_HEAD, Role.STORE_MANAGER)


def get_order_port(request: Request) -> OrderPort:
    port: OrderPort | None = getattr(request.app.state, "pos_orders", None)
    return port or OrdersPosPort()


pos_router = APIRouter(prefix="/stores", tags=["pos"])
router = APIRouter(prefix="/invoices", tags=["invoices"])


@pos_router.post(
    "/{id}/pos/sales",
    operation_id="createPosSale",
    summary="Counter sale with GST invoice and payment (ST-001)",
    status_code=status.HTTP_201_CREATED,
    response_model=PosSaleOut,
    responses=problem_responses(
        (404, "not_found"),
        (404, "farmer_not_found"),
        (409, "insufficient_stock"),
        (402, "credit_limit_exceeded"),
        (422, "unknown_sku"),
        (422, "sku_not_recommendable"),
        (422, "receipt_required"),
        (422, "reference_required"),
        (422, "invalid_blob"),
        (422, "invalid_mode"),
        (502, "provider_error"),
    ),
)
async def create_pos_sale(
    id: uuid.UUID,
    body: PosSaleIn,
    request: Request,
    actor: Annotated[User, require_roles(*POS_ROLES)],
    session: DbSession,
    auth: Services,
    services: Annotated[PaymentServices, Depends(get_payment_services)],
    blobs: Annotated[BlobStore, Depends(get_blob_store)],
    orders: Annotated[OrderPort, Depends(get_order_port)],
) -> PosSaleOut | JSONResponse:
    sale = await pos_sale(
        session,
        actor,
        id,
        body,
        orders=orders,
        services=services,
        messaging=Messaging(sms=auth.sms, whatsapp=auth.whatsapp),
        blobs=blobs,
        now=auth.clock.now(),
    )
    if isinstance(sale, CreditBlocked):
        # Returned, not raised: the credit approval request must commit (ST-007).
        return credit_blocked_response(request, sale.decision)
    return sale


@pos_router.post(
    "/{id}/pos/preview",
    operation_id="previewPosSale",
    summary="GST invoice preview for a counter sale; writes nothing (ST-001)",
    response_model=PosPreviewOut,
    responses=problem_responses(
        (404, "not_found"),
        (404, "farmer_not_found"),
        (422, "unknown_sku"),
        (422, "invalid_mode"),
    ),
)
async def preview_pos_sale(
    id: uuid.UUID,
    body: PosSaleIn,
    actor: Annotated[User, require_roles(*POS_ROLES)],
    session: DbSession,
    auth: Services,
) -> PosPreviewOut:
    return await pos_preview(session, actor, id, body, now=auth.clock.now())


@router.get(
    "/{id}",
    operation_id="getInvoice",
    summary="A GST invoice (lines with HSN and tax split)",
    response_model=InvoiceOut,
    responses=problem_responses((404, "not_found")),
)
async def get_invoice(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*INVOICE_READ_ROLES)],
    session: DbSession,
) -> InvoiceOut:
    return InvoiceOut.from_row(await visible_invoice(session, actor, id))


@router.get(
    "/{id}/pdf",
    operation_id="getInvoicePdf",
    summary="Signed URL to the invoice PDF",
    response_model=SignedUrlOut,
    responses=problem_responses((404, "not_found")),
)
async def get_invoice_pdf(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*INVOICE_READ_ROLES)],
    session: DbSession,
    auth: Services,
    blobs: Annotated[BlobStore, Depends(get_blob_store)],
) -> SignedUrlOut:
    invoice = await visible_invoice(session, actor, id)
    out = await pdf_url(
        invoice, blobs, ttl_seconds=get_settings().signed_url_ttl_seconds, now=auth.clock.now()
    )
    await session.flush()
    return out


@router.post(
    "/{id}/share",
    operation_id="shareInvoice",
    summary="Send the invoice PDF link by WhatsApp or SMS",
    response_model=InvoiceShareOut,
    responses=problem_responses(
        (404, "not_found"), (422, "phone_required"), (502, "provider_error")
    ),
)
async def post_invoice_share(
    id: uuid.UUID,
    body: InvoiceShareIn,
    actor: Annotated[User, require_roles(*INVOICE_SHARE_ROLES)],
    session: DbSession,
    auth: Services,
    blobs: Annotated[BlobStore, Depends(get_blob_store)],
) -> InvoiceShareOut:
    invoice = await visible_invoice(session, actor, id)
    return await share_invoice(
        session,
        invoice,
        body,
        messaging=Messaging(sms=auth.sms, whatsapp=auth.whatsapp),
        blobs=blobs,
        ttl_seconds=get_settings().signed_url_ttl_seconds,
        now=auth.clock.now(),
    )


__all__ = [
    "INVOICE_READ_ROLES",
    "INVOICE_SHARE_ROLES",
    "POS_ROLES",
    "get_order_port",
    "pos_router",
    "router",
]
