"""``/v1/catalog`` writes and maintenance reads (WC-005; DX-007 guardrail endpoint).

Mounted under the read router (``farmerapp.catalog.router``). Roles (SPEC 2.6, 14.6):

* products, SKUs, price lists: owner, director, tenant admin write; everyone reads the
  catalogue, price lists are read by management, store and finance roles;
* label claims: owner, tenant admin and agronomist create and edit drafts; **only the
  agronomist approves** (the SPEC 14.6 human gate — the claim records who and when); the
  agronomist, owner and tenant admin may retire;
* ``GET /recommendable`` wraps ``farmerapp.catalog.recommendable.recommendable_skus`` — the
  only list a recommendation may draw from (DX-007);
* ``GET /barcode/{code}``: POS scanning (store roles) and the field officer;
* CSV import (dry run by default) and export.

Every mutation is audited by the ORM hook (FA-006); exports are recorded explicitly.
"""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query, Request, status
from fastapi.responses import StreamingResponse
from sqlalchemy import or_, select

from farmerapp.api.errors import NotFoundError, problem_responses
from farmerapp.api.idempotency import idempotent
from farmerapp.auth.deps import DbSession, Services
from farmerapp.auth.models import User, UserRole
from farmerapp.auth.policy import Role, require_roles
from farmerapp.catalog import csv_io, prices, service
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.models import LabelClaim, PestOrDisease, Product, Sku
from farmerapp.catalog.pricing import prices_for, resolved_price
from farmerapp.catalog.recommendable import recommendable_skus
from farmerapp.catalog.schemas import (
    LabelClaimOut,
    PestOrDiseaseOut,
    ProductOut,
    SkuOut,
)
from farmerapp.catalog.write_schemas import (
    BarcodeLookupOut,
    CatalogKind,
    CropList,
    CropOut,
    ImportReport,
    ImportRequest,
    LabelClaimCreate,
    LabelClaimList,
    LabelClaimUpdate,
    PestList,
    PriceListList,
    PriceListPut,
    ProductCreate,
    ProductUpdate,
    RecommendableList,
    RecommendableSkuOut,
    SkuCreate,
    SkuUpdate,
    StoreBriefList,
    StoreBriefOut,
)
from farmerapp.db import audit
from farmerapp.tenants.models import Store

router = APIRouter()

EVERYONE = tuple(Role)
WRITE_ROLES = (Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN)
CLAIM_EDIT_ROLES = (Role.OWNER, Role.TENANT_ADMIN, Role.AGRONOMIST)
CLAIM_APPROVE_ROLES = (Role.AGRONOMIST,)
CLAIM_RETIRE_ROLES = (Role.AGRONOMIST, Role.OWNER, Role.TENANT_ADMIN)
PRICE_READ_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.ACCOUNTANT,
    Role.AUDITOR,
)
BARCODE_ROLES = (
    Role.OWNER,
    Role.DIRECTOR,
    Role.TENANT_ADMIN,
    Role.CLUSTER_HEAD,
    Role.STORE_MANAGER,
    Role.ACCOUNTANT,
    Role.FIELD_OFFICER,
)
EXPORT_ROLES = (Role.OWNER, Role.DIRECTOR, Role.TENANT_ADMIN, Role.AGRONOMIST, Role.AUDITOR)
#: Roles whose stores are limited to their own (price lists, store picker).
_OWN_STORE_ROLES = frozenset({UserRole.STORE_MANAGER, UserRole.ACCOUNTANT})

_CLAIM_PROBLEMS = (
    (404, "not_found"),
    (409, "claim_duplicate"),
    (409, "version_conflict"),
    (422, "claim_category_invalid"),
    (422, "pest_not_for_crop"),
    (422, "validation_error"),
)


def _own_store_only(actor: User) -> bool:
    return UserRole(actor.role) in _OWN_STORE_ROLES and actor.store_id is not None


async def _claim_out(session: DbSession, claim_id: uuid.UUID) -> LabelClaimOut:
    row = (
        await session.execute(
            select(LabelClaim, PestOrDisease)
            .join(PestOrDisease, PestOrDisease.id == LabelClaim.pest_or_disease_id)
            .where(LabelClaim.id == claim_id)
        )
    ).first()
    if row is None:
        raise NotFoundError("Label claim not found.")
    return LabelClaimOut.from_row(row[0], row[1])


# --------------------------------------------------------------------------- reference data
@router.get(
    "/crops",
    operation_id="listCrops",
    summary="The tenant's crops (label claims, filters)",
    response_model=CropList,
)
async def list_crops(
    actor: Annotated[User, require_roles(*EVERYONE)], session: DbSession
) -> CropList:
    rows = (
        (
            await session.execute(
                select(Crop)
                .where(Crop.tenant_id == actor.tenant_id, Crop.deleted_at.is_(None))
                .order_by(Crop.name)
            )
        )
        .scalars()
        .all()
    )
    return CropList(items=[CropOut.model_validate(c) for c in rows])


@router.get(
    "/pests",
    operation_id="listPests",
    summary="Pests / diseases; with crop_id those of that crop plus polyphagous ones",
    response_model=PestList,
)
async def list_pests(
    actor: Annotated[User, require_roles(*EVERYONE)],
    session: DbSession,
    crop_id: Annotated[uuid.UUID | None, Query()] = None,
) -> PestList:
    stmt = select(PestOrDisease).where(
        PestOrDisease.tenant_id == actor.tenant_id, PestOrDisease.deleted_at.is_(None)
    )
    if crop_id is not None:
        stmt = stmt.where(or_(PestOrDisease.crop_id == crop_id, PestOrDisease.crop_id.is_(None)))
    rows = (await session.execute(stmt.order_by(PestOrDisease.name))).scalars().all()
    return PestList(items=[PestOrDiseaseOut.model_validate(p) for p in rows])


@router.get(
    "/stores",
    operation_id="listCatalogStores",
    summary="Stores for price-list selection (store manager / accountant: own store)",
    response_model=StoreBriefList,
)
async def list_stores(
    actor: Annotated[User, require_roles(*PRICE_READ_ROLES)], session: DbSession
) -> StoreBriefList:
    stmt = select(Store).where(Store.tenant_id == actor.tenant_id, Store.deleted_at.is_(None))
    if _own_store_only(actor):
        stmt = stmt.where(Store.id == actor.store_id)
    rows = (await session.execute(stmt.order_by(Store.code))).scalars().all()
    return StoreBriefList(items=[StoreBriefOut.model_validate(s) for s in rows])


# --------------------------------------------------------------------------- products
@router.post(
    "/products",
    operation_id="createProduct",
    summary="Create a product (own-brand flag, category, HSN, GST slab)",
    status_code=status.HTTP_201_CREATED,
    response_model=ProductOut,
    responses=problem_responses((409, "product_exists"), (422, "validation_error")),
)
@idempotent(status_code=status.HTTP_201_CREATED)
async def create_product(
    request: Request,
    body: ProductCreate,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> ProductOut:
    return ProductOut.model_validate(await service.create_product(session, actor, body))


@router.patch(
    "/products/{id}",
    operation_id="updateProduct",
    summary="Change a product",
    response_model=ProductOut,
    responses=problem_responses(
        (404, "not_found"), (409, "product_exists"), (409, "version_conflict")
    ),
)
async def update_product(
    id: uuid.UUID,
    body: ProductUpdate,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> ProductOut:
    product = await service.get_product(session, actor.tenant_id, id)
    return ProductOut.model_validate(await service.update_product(session, product, body))


@router.post(
    "/skus",
    operation_id="createSku",
    summary="Add a pack size (SKU) with barcode and MRP to a product",
    status_code=status.HTTP_201_CREATED,
    response_model=SkuOut,
    responses=problem_responses((404, "not_found"), (409, "barcode_exists")),
)
@idempotent(status_code=status.HTTP_201_CREATED)
async def create_sku(
    request: Request,
    body: SkuCreate,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> SkuOut:
    sku = await service.create_sku(session, actor, body)
    return SkuOut.from_row(sku, price_paise=sku.mrp_paise)


@router.patch(
    "/skus/{id}",
    operation_id="updateSku",
    summary="Change a SKU (pack, barcode, MRP, active)",
    response_model=SkuOut,
    responses=problem_responses(
        (404, "not_found"), (409, "barcode_exists"), (409, "version_conflict")
    ),
)
async def update_sku(
    id: uuid.UUID,
    body: SkuUpdate,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
    services: Services,
) -> SkuOut:
    sku = await service.get_sku(session, actor.tenant_id, id)
    sku = await service.update_sku(session, sku, body)
    price = (await prices_for(session, [sku.id], None, services.clock.now().date())).get(sku.id)
    return SkuOut.from_row(sku, price_paise=resolved_price(price, sku.mrp_paise))


@router.get(
    "/barcode/{code}",
    operation_id="lookupBarcode",
    summary="SKU and product by barcode (POS scan), priced for the store",
    response_model=BarcodeLookupOut,
    responses=problem_responses((404, "not_found")),
)
async def lookup_barcode(
    code: str,
    actor: Annotated[User, require_roles(*BARCODE_ROLES)],
    session: DbSession,
    services: Services,
    store_id: Annotated[
        uuid.UUID | None, Query(description="Defaults to the caller's own store.")
    ] = None,
) -> BarcodeLookupOut:
    row = (
        await session.execute(
            select(Sku, Product)
            .join(Product, Product.id == Sku.product_id)
            .where(
                Sku.tenant_id == actor.tenant_id,
                Sku.barcode == code.strip(),
                Sku.deleted_at.is_(None),
                Product.deleted_at.is_(None),
            )
        )
    ).first()
    if row is None:
        raise NotFoundError("No SKU with this barcode.")
    sku, product = row
    store = store_id or actor.store_id
    if store is not None:
        await prices.store_or_404(session, actor.tenant_id, store)
    price = (await prices_for(session, [sku.id], store, services.clock.now().date())).get(sku.id)
    return BarcodeLookupOut(
        **SkuOut.from_row(sku, price_paise=resolved_price(price, sku.mrp_paise)).model_dump(),
        product=ProductOut.model_validate(product),
    )


# --------------------------------------------------------------------------- label claims
@router.post(
    "/label-claims",
    operation_id="createLabelClaim",
    summary="Create a label claim (SKU x crop x pest x dose x PHI) as a draft",
    status_code=status.HTTP_201_CREATED,
    response_model=LabelClaimOut,
    responses=problem_responses(*_CLAIM_PROBLEMS),
)
@idempotent(status_code=status.HTTP_201_CREATED)
async def create_label_claim(
    request: Request,
    body: LabelClaimCreate,
    actor: Annotated[User, require_roles(*CLAIM_EDIT_ROLES)],
    session: DbSession,
) -> LabelClaimOut:
    claim = await service.create_claim(session, actor, body)
    return await _claim_out(session, claim.id)


@router.patch(
    "/label-claims/{id}",
    operation_id="updateLabelClaim",
    summary="Edit a draft in place; editing an approved claim returns a new draft version",
    response_model=LabelClaimOut,
    responses=problem_responses(
        (404, "not_found"),
        (409, "claim_retired"),
        (409, "version_conflict"),
        (422, "validation_error"),
    ),
)
async def update_label_claim(
    id: uuid.UUID,
    body: LabelClaimUpdate,
    actor: Annotated[User, require_roles(*CLAIM_EDIT_ROLES)],
    session: DbSession,
) -> LabelClaimOut:
    claim = await service.get_claim(session, actor.tenant_id, id)
    result = await service.update_claim(session, actor, claim, body)
    return await _claim_out(session, result.id)


@router.post(
    "/label-claims/{id}/approve",
    operation_id="approveLabelClaim",
    summary="Approve a draft claim (agronomist only; SPEC 14.6 human gate)",
    response_model=LabelClaimOut,
    responses=problem_responses(
        (404, "not_found"),
        (409, "claim_not_draft"),
        (409, "claim_duplicate"),
        (422, "claim_category_invalid"),
        (422, "pest_not_for_crop"),
    ),
)
async def approve_label_claim(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*CLAIM_APPROVE_ROLES)],
    session: DbSession,
    services: Services,
) -> LabelClaimOut:
    claim = await service.get_claim(session, actor.tenant_id, id)
    await service.approve_claim(session, actor, claim, services.clock.now())
    return await _claim_out(session, claim.id)


@router.post(
    "/label-claims/{id}/retire",
    operation_id="retireLabelClaim",
    summary="Retire a claim: its SKU is no longer recommendable for that crop and pest",
    response_model=LabelClaimOut,
    responses=problem_responses((404, "not_found"), (409, "claim_retired")),
)
async def retire_label_claim(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*CLAIM_RETIRE_ROLES)],
    session: DbSession,
    services: Services,
) -> LabelClaimOut:
    claim = await service.get_claim(session, actor.tenant_id, id)
    await service.retire_claim(session, actor, claim, services.clock.now())
    return await _claim_out(session, claim.id)


@router.get(
    "/label-claims/{id}/history",
    operation_id="labelClaimHistory",
    summary="Every version of a claim (supersedes chain), newest first",
    response_model=LabelClaimList,
    responses=problem_responses((404, "not_found")),
)
async def label_claim_history(
    id: uuid.UUID,
    actor: Annotated[User, require_roles(*CLAIM_EDIT_ROLES)],
    session: DbSession,
) -> LabelClaimList:
    claim = await service.get_claim(session, actor.tenant_id, id)
    versions = await service.claim_history(session, actor.tenant_id, claim)
    return LabelClaimList(items=[await _claim_out(session, v.id) for v in versions])


@router.get(
    "/recommendable",
    operation_id="listRecommendableSkus",
    summary="SKUs with an approved label claim for exactly this crop and pest (DX-007)",
    response_model=RecommendableList,
    responses=problem_responses((422, "validation_error")),
)
async def list_recommendable(
    actor: Annotated[User, require_roles(*EVERYONE)],
    session: DbSession,
    crop_id: Annotated[uuid.UUID, Query()],
    pest_id: Annotated[uuid.UUID, Query(description="pest_or_disease id.")],
) -> RecommendableList:
    rows = await recommendable_skus(
        session, tenant_id=actor.tenant_id, crop_id=crop_id, pest_or_disease_id=pest_id
    )
    return RecommendableList(items=[RecommendableSkuOut.model_validate(r) for r in rows])


# --------------------------------------------------------------------------- price lists
@router.get(
    "/price-lists",
    operation_id="listPriceLists",
    summary="Price-list rows of a store (or the tenant default); `at` = in force that day",
    response_model=PriceListList,
    responses=problem_responses((404, "not_found")),
)
async def list_price_lists(
    actor: Annotated[User, require_roles(*PRICE_READ_ROLES)],
    session: DbSession,
    store_id: Annotated[
        uuid.UUID | None, Query(description="Omit for the tenant default rows.")
    ] = None,
    at: Annotated[date | None, Query()] = None,
    sku_id: Annotated[uuid.UUID | None, Query()] = None,
) -> PriceListList:
    if store_id is not None:
        await prices.store_or_404(session, actor.tenant_id, store_id)
        if _own_store_only(actor) and store_id != actor.store_id:
            raise NotFoundError("Store not found.")
    rows = await prices.list_prices(
        session, actor.tenant_id, store_id=store_id, at=at, sku_id=sku_id
    )
    return PriceListList(items=rows)


@router.put(
    "/price-lists",
    operation_id="upsertPriceLists",
    summary="Bulk upsert price-list rows for a store or the tenant default (all or nothing)",
    response_model=PriceListList,
    responses=problem_responses(
        (404, "not_found"),
        (409, "price_overlap"),
        (422, "price_above_mrp"),
        (422, "validation_error"),
    ),
)
async def upsert_price_lists(
    body: PriceListPut,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> PriceListList:
    return PriceListList(items=await prices.upsert_price_list(session, actor, body))


# --------------------------------------------------------------------------- import / export
async def _import(
    session: DbSession, actor: User, kind: CatalogKind, body: ImportRequest
) -> ImportReport:
    return await csv_io.import_catalog(
        session, actor, kind=kind, text=body.csv, dry_run=body.dry_run
    )


@router.post(
    "/import/products",
    operation_id="importProducts",
    summary="Import products + SKUs from CSV (dry run by default; all or nothing)",
    response_model=ImportReport,
    responses=problem_responses((422, "validation_error")),
)
async def import_products(
    body: ImportRequest,
    actor: Annotated[User, require_roles(*WRITE_ROLES)],
    session: DbSession,
) -> ImportReport:
    return await _import(session, actor, CatalogKind.PRODUCTS, body)


@router.post(
    "/import/label-claims",
    operation_id="importLabelClaims",
    summary="Import label claims from CSV as drafts (dry run by default; never approves)",
    response_model=ImportReport,
    responses=problem_responses((422, "validation_error")),
)
async def import_label_claims(
    body: ImportRequest,
    actor: Annotated[User, require_roles(*CLAIM_EDIT_ROLES)],
    session: DbSession,
) -> ImportReport:
    return await _import(session, actor, CatalogKind.LABEL_CLAIMS, body)


@router.get(
    "/export",
    operation_id="exportCatalog",
    summary="CSV export of products + SKUs or label claims",
    response_class=StreamingResponse,
    responses={200: {"content": {"text/csv": {}}, "description": "CSV file."}},
)
async def export_catalog(
    actor: Annotated[User, require_roles(*EXPORT_ROLES)],
    session: DbSession,
    kind: Annotated[CatalogKind, Query()] = CatalogKind.PRODUCTS,
) -> StreamingResponse:
    lines = await csv_io.export_rows(session, actor.tenant_id, kind)
    audit.record(
        session,
        action="catalog.export",
        entity="catalog",
        entity_id=actor.tenant_id,
        after={"kind": kind.value, "rows": len(lines) - 1},
    )
    await session.flush()
    filename = f"catalog-{kind.value}.csv"
    return StreamingResponse(
        csv_io.iter_lines(lines),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


__all__ = [
    "BARCODE_ROLES",
    "CLAIM_APPROVE_ROLES",
    "CLAIM_EDIT_ROLES",
    "CLAIM_RETIRE_ROLES",
    "EXPORT_ROLES",
    "PRICE_READ_ROLES",
    "WRITE_ROLES",
    "router",
]
