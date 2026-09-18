"""``/v1/catalog`` — products with SKUs, SKU detail with label claims, approved claims
(WC-005, FA-020, DX-007, FM-005).

Every role may read the catalogue (staff sell from it, the farmer app shows it). Prices come
from ``farmerapp.catalog.pricing`` for the requested store (tenant default otherwise) and
fall back to the MRP; stock on hand (sum of the ST-003 ledger) is added when ``store_id`` is
given. Label claims are the DX-007 guardrail: only **approved** claims are returned, except
to the agronomist and the owner who maintain them (WC-005) and see drafts / retired ones.
"""

from __future__ import annotations

import uuid
from datetime import date
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import or_, select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.api.pagination import Page
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import Role, require_roles
from farmerapp.catalog.models import (
    ClaimStatus,
    LabelClaim,
    PestOrDisease,
    Product,
    ProductCategory,
    Sku,
)
from farmerapp.catalog.pricing import prices_for, resolved_price
from farmerapp.catalog.schemas import (
    LabelClaimOut,
    LabelClaimPage,
    ProductOut,
    ProductPage,
    ProductWithSkusOut,
    SkuDetailOut,
    SkuOut,
)
from farmerapp.stock.ledger import stock_on_hand_by_sku
from farmerapp.tenants.models import Store

router = APIRouter(prefix="/catalog", tags=["catalog"])

CATALOG_ROLES = tuple(Role)
#: Roles that maintain label claims (WC-005) and therefore see drafts and retired ones.
CLAIM_DRAFT_ROLES = frozenset({UserRole.AGRONOMIST, UserRole.OWNER})


def _sees_drafts(actor: User) -> bool:
    return UserRole(actor.role) in CLAIM_DRAFT_ROLES


async def _store_or_404(session: DbSession, actor: User, store_id: uuid.UUID | None) -> None:
    if store_id is None:
        return
    found = await session.scalar(
        select(Store.id).where(
            Store.id == store_id, Store.tenant_id == actor.tenant_id, Store.deleted_at.is_(None)
        )
    )
    if found is None:
        raise NotFoundError("Store not found.")


async def _sku_outs(
    session: DbSession,
    skus: list[Sku],
    *,
    store_id: uuid.UUID | None,
    at: date,
) -> dict[uuid.UUID, SkuOut]:
    ids = [s.id for s in skus]
    prices = await prices_for(session, ids, store_id, at)
    stock = await stock_on_hand_by_sku(session, store_id, ids) if store_id is not None else {}
    return {
        s.id: SkuOut.from_row(
            s,
            price_paise=resolved_price(prices.get(s.id), s.mrp_paise),
            stock_qty=stock.get(s.id, Decimal(0)) if store_id is not None else None,
        )
        for s in skus
    }


@router.get(
    "/products",
    operation_id="listProducts",
    summary="Products with their SKUs, prices and (per store) stock; oldest first",
    response_model=ProductPage,
    responses=problem_responses((400, "invalid_cursor"), (404, "not_found")),
)
async def list_products(
    actor: Annotated[User, require_roles(*CATALOG_ROLES)],
    session: DbSession,
    services: Services,
    page: Page,
    q: Annotated[
        str | None, Query(max_length=100, description="Name / brand / ingredient.")
    ] = None,
    category: Annotated[ProductCategory | None, Query()] = None,
    own_brand: Annotated[bool | None, Query()] = None,
    store_id: Annotated[
        uuid.UUID | None, Query(description="Adds the store price and stock on hand.")
    ] = None,
    include_inactive: Annotated[bool, Query()] = False,
) -> ProductPage:
    await _store_or_404(session, actor, store_id)
    stmt = select(Product).where(Product.tenant_id == actor.tenant_id, Product.deleted_at.is_(None))
    if not include_inactive:
        stmt = stmt.where(Product.active.is_(True))
    if q:
        pattern = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(
                Product.name.ilike(pattern),
                Product.brand.ilike(pattern),
                Product.active_ingredient.ilike(pattern),
            )
        )
    if category is not None:
        stmt = stmt.where(Product.category == category.value)
    if own_brand is not None:
        stmt = stmt.where(Product.own_brand.is_(own_brand))
    after = page.after(Product.created_at, Product.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(Product.created_at, Product.id).limit(page.fetch)
    rows = (await session.execute(stmt)).scalars().all()
    products, next_cursor = page.slice(rows)
    skus = (
        (
            await session.execute(
                select(Sku)
                .where(Sku.product_id.in_([p.id for p in products]), Sku.deleted_at.is_(None))
                .order_by(Sku.pack_size_value, Sku.id)
            )
        )
        .scalars()
        .all()
        if products
        else []
    )
    outs = await _sku_outs(session, list(skus), store_id=store_id, at=services.clock.now().date())
    by_product: dict[uuid.UUID, list[SkuOut]] = {}
    for sku in skus:
        by_product.setdefault(sku.product_id, []).append(outs[sku.id])
    return ProductPage(
        items=[ProductWithSkusOut.from_row(p, by_product.get(p.id, [])) for p in products],
        next_cursor=next_cursor,
    )


@router.get(
    "/skus/{id}",
    operation_id="getSku",
    summary="One SKU with its product, price, stock and label claims",
    response_model=SkuDetailOut,
    responses=problem_responses((404, "not_found")),
)
async def get_sku(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*CATALOG_ROLES)],
    session: DbSession,
    services: Services,
    store_id: Annotated[uuid.UUID | None, Query()] = None,
) -> SkuDetailOut:
    await _store_or_404(session, actor, store_id)
    row = (
        await session.execute(
            select(Sku, Product)
            .join(Product, Product.id == Sku.product_id)
            .where(Sku.id == id, Sku.tenant_id == actor.tenant_id, Sku.deleted_at.is_(None))
        )
    ).first()
    if row is None:
        raise NotFoundError("SKU not found.")
    sku, product = row
    outs = await _sku_outs(session, [sku], store_id=store_id, at=services.clock.now().date())
    claims_stmt = (
        select(LabelClaim, PestOrDisease)
        .join(PestOrDisease, PestOrDisease.id == LabelClaim.pest_or_disease_id)
        .where(LabelClaim.sku_id == sku.id, LabelClaim.deleted_at.is_(None))
        .order_by(LabelClaim.created_at, LabelClaim.id)
    )
    if not _sees_drafts(actor):
        claims_stmt = claims_stmt.where(LabelClaim.status == ClaimStatus.APPROVED.value)
    claims = (await session.execute(claims_stmt)).all()
    return SkuDetailOut(
        **outs[sku.id].model_dump(),
        product=ProductOut.model_validate(product),
        label_claims=[LabelClaimOut.from_row(c, p) for c, p in claims],
    )


@router.get(
    "/label-claims",
    operation_id="listLabelClaims",
    summary="Approved label claims for a crop and/or problem (DX-007); oldest first",
    response_model=LabelClaimPage,
    responses=problem_responses((400, "invalid_cursor")),
)
async def list_label_claims(
    actor: Annotated[User, require_roles(*CATALOG_ROLES)],
    session: DbSession,
    page: Page,
    crop_id: Annotated[uuid.UUID | None, Query()] = None,
    pest_id: Annotated[uuid.UUID | None, Query(description="pest_or_disease id.")] = None,
    sku_id: Annotated[uuid.UUID | None, Query()] = None,
    status: Annotated[
        ClaimStatus,
        Query(description="Only the agronomist / owner may ask for draft or retired claims."),
    ] = ClaimStatus.APPROVED,
) -> LabelClaimPage:
    wanted = status if _sees_drafts(actor) else ClaimStatus.APPROVED
    stmt = (
        select(LabelClaim, PestOrDisease)
        .join(PestOrDisease, PestOrDisease.id == LabelClaim.pest_or_disease_id)
        .where(
            LabelClaim.tenant_id == actor.tenant_id,
            LabelClaim.deleted_at.is_(None),
            LabelClaim.status == wanted.value,
        )
    )
    if crop_id is not None:
        stmt = stmt.where(LabelClaim.crop_id == crop_id)
    if pest_id is not None:
        stmt = stmt.where(LabelClaim.pest_or_disease_id == pest_id)
    if sku_id is not None:
        stmt = stmt.where(LabelClaim.sku_id == sku_id)
    after = page.after(LabelClaim.created_at, LabelClaim.id)
    if after is not None:
        stmt = stmt.where(after)
    stmt = stmt.order_by(LabelClaim.created_at, LabelClaim.id).limit(page.fetch)
    rows = (await session.execute(stmt)).all()
    claims = [c for c, _ in rows]
    items, next_cursor = page.slice(claims)
    pests = {c.id: p for c, p in rows}
    return LabelClaimPage(
        items=[LabelClaimOut.from_row(c, pests[c.id]) for c in items], next_cursor=next_cursor
    )


__all__ = ["CATALOG_ROLES", "CLAIM_DRAFT_ROLES", "router"]
