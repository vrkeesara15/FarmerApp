"""Catalogue writes (WC-005): products, SKUs and the label-claim approval workflow.

Label-claim lifecycle (SPEC 3.4, 14.6)::

    draft --approve (agronomist only)--> approved --retire--> retired
      ^                                      |
      +---- edit of an approved claim = new draft (supersedes_id) ----+

* Drafts are edited in place; approved claims are **immutable** — an edit creates a new draft
  version pointing at the approved one (``supersedes_id``). Approving that draft retires the
  superseded version in the same transaction, so there is never a moment with two approved
  versions (the partial unique index ``uq_label_claim_approved`` backs this up) or none.
* Approval is the human gate of SPEC 14.6: only the agronomist role may approve; the claim
  records ``approved_by`` / ``approved_at`` and the audit trail (FA-006) records the change.
* Validation: pest / disease claims only on crop-protection products (pesticide, fungicide,
  herbicide, growth); a crop-specific pest only for its crop; dose value > 0 with a unit and
  PHI >= 0 (schemas); no second approved claim for the same SKU x crop x pest.

Every mutation goes through the ORM so ``farmerapp.db.audit`` writes the ``audit_log`` rows.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from farmerapp.api.errors import NotFoundError
from farmerapp.auth.models import User
from farmerapp.catalog.crops import Crop
from farmerapp.catalog.errors import (
    BarcodeExistsError,
    ClaimCategoryInvalidError,
    ClaimDuplicateError,
    ClaimNotDraftError,
    ClaimRetiredError,
    PestNotForCropError,
    ProductExistsError,
    VersionConflictError,
)
from farmerapp.catalog.models import (
    ClaimStatus,
    LabelClaim,
    PestOrDisease,
    ProblemType,
    Product,
    ProductCategory,
    Sku,
)
from farmerapp.catalog.write_schemas import (
    LabelClaimCreate,
    LabelClaimUpdate,
    ProductCreate,
    ProductUpdate,
    SkuCreate,
    SkuUpdate,
)

#: Product categories that may carry a pest / disease label claim (CIB&RC registrations).
CROP_PROTECTION: frozenset[str] = frozenset(
    {
        ProductCategory.PESTICIDE.value,
        ProductCategory.FUNGICIDE.value,
        ProductCategory.HERBICIDE.value,
        ProductCategory.GROWTH.value,
    }
)
PEST_TYPES: frozenset[str] = frozenset({ProblemType.PEST.value, ProblemType.DISEASE.value})

#: Claim fields copied into a new draft version.
CLAIM_FIELDS: tuple[str, ...] = (
    "dose_per_acre",
    "dose_value",
    "dose_unit",
    "dose_per_tank_15l",
    "phi_days",
    "ppe_text",
    "safety_text",
    "source_ref",
    "efficacy_tier",
)


def check_version(row: Any, expected: int | None) -> None:
    if expected is not None and expected != row.version:
        raise VersionConflictError(
            f"Version {expected} is stale; the current version is {row.version}.",
            extra={"current_version": row.version},
        )


# --------------------------------------------------------------------------- products
async def get_product(session: AsyncSession, tenant_id: uuid.UUID, id: uuid.UUID) -> Product:
    product = await session.scalar(
        select(Product).where(
            Product.id == id, Product.tenant_id == tenant_id, Product.deleted_at.is_(None)
        )
    )
    if product is None:
        raise NotFoundError("Product not found.")
    return product


async def _check_product_unique(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    brand: str,
    name: str,
    exclude: uuid.UUID | None = None,
) -> None:
    stmt = select(Product.id).where(
        Product.tenant_id == tenant_id,
        func.lower(Product.brand) == brand.lower(),
        func.lower(Product.name) == name.lower(),
    )
    if exclude is not None:
        stmt = stmt.where(Product.id != exclude)
    if await session.scalar(stmt.limit(1)) is not None:
        raise ProductExistsError(f"A product {name!r} of brand {brand!r} already exists.")


async def create_product(session: AsyncSession, actor: User, body: ProductCreate) -> Product:
    await _check_product_unique(session, actor.tenant_id, body.brand, body.name)
    data = body.model_dump()
    data["category"] = body.category.value
    product = Product(tenant_id=actor.tenant_id, **data)
    session.add(product)
    await session.flush()
    await session.refresh(product)
    return product


async def update_product(session: AsyncSession, product: Product, body: ProductUpdate) -> Product:
    check_version(product, body.version)
    changes = body.model_dump(exclude_unset=True, exclude={"version"})
    for key in ("name", "brand", "gst_rate_bp", "category", "own_brand", "active", "names"):
        if key in changes and changes[key] is None:
            changes.pop(key)  # NOT NULL columns: an explicit null means "unchanged"
    if "name" in changes or "brand" in changes:
        await _check_product_unique(
            session,
            product.tenant_id,
            changes.get("brand", product.brand),
            changes.get("name", product.name),
            exclude=product.id,
        )
    if isinstance(changes.get("category"), ProductCategory):
        changes["category"] = changes["category"].value
    for key, value in changes.items():
        setattr(product, key, value)
    await session.flush()
    await session.refresh(product)
    return product


# --------------------------------------------------------------------------- SKUs
async def get_sku(session: AsyncSession, tenant_id: uuid.UUID, id: uuid.UUID) -> Sku:
    sku = await session.scalar(
        select(Sku).where(Sku.id == id, Sku.tenant_id == tenant_id, Sku.deleted_at.is_(None))
    )
    if sku is None:
        raise NotFoundError("SKU not found.")
    return sku


async def _check_barcode(
    session: AsyncSession, tenant_id: uuid.UUID, barcode: str | None, exclude: uuid.UUID | None
) -> None:
    if not barcode:
        return
    stmt = select(Sku.id).where(Sku.tenant_id == tenant_id, Sku.barcode == barcode)
    if exclude is not None:
        stmt = stmt.where(Sku.id != exclude)
    if await session.scalar(stmt.limit(1)) is not None:
        raise BarcodeExistsError(
            f"Barcode {barcode} is already used by another SKU.", extra={"barcode": barcode}
        )


async def create_sku(session: AsyncSession, actor: User, body: SkuCreate) -> Sku:
    await get_product(session, actor.tenant_id, body.product_id)
    await _check_barcode(session, actor.tenant_id, body.barcode, None)
    sku = Sku(
        tenant_id=actor.tenant_id,
        product_id=body.product_id,
        pack_size_value=body.pack_size_value,
        pack_size_unit=body.pack_size_unit.value,
        barcode=body.barcode,
        mrp_paise=body.mrp_paise,
        active=body.active,
    )
    session.add(sku)
    await session.flush()
    await session.refresh(sku)
    return sku


async def update_sku(session: AsyncSession, sku: Sku, body: SkuUpdate) -> Sku:
    check_version(sku, body.version)
    changes = body.model_dump(exclude_unset=True, exclude={"version"})
    for key in ("pack_size_value", "pack_size_unit", "mrp_paise", "active"):
        if key in changes and changes[key] is None:
            changes.pop(key)
    if "barcode" in changes:
        await _check_barcode(session, sku.tenant_id, changes["barcode"], sku.id)
    if "pack_size_unit" in changes:
        changes["pack_size_unit"] = str(changes["pack_size_unit"])
    for key, value in changes.items():
        setattr(sku, key, value)
    await session.flush()
    await session.refresh(sku)
    return sku


# --------------------------------------------------------------------------- label claims
async def get_claim(session: AsyncSession, tenant_id: uuid.UUID, id: uuid.UUID) -> LabelClaim:
    claim = await session.scalar(
        select(LabelClaim).where(
            LabelClaim.id == id,
            LabelClaim.tenant_id == tenant_id,
            LabelClaim.deleted_at.is_(None),
        )
    )
    if claim is None:
        raise NotFoundError("Label claim not found.")
    return claim


async def validate_claim_target(
    session: AsyncSession,
    tenant_id: uuid.UUID,
    *,
    sku_id: uuid.UUID,
    crop_id: uuid.UUID,
    pest_or_disease_id: uuid.UUID,
) -> tuple[Sku, Product, Crop, PestOrDisease]:
    """The SKU, product, crop and problem of a claim; 404 / 422 when they do not fit."""
    row = (
        await session.execute(
            select(Sku, Product)
            .join(Product, Product.id == Sku.product_id)
            .where(Sku.id == sku_id, Sku.tenant_id == tenant_id, Sku.deleted_at.is_(None))
        )
    ).first()
    if row is None:
        raise NotFoundError("SKU not found.")
    sku, product = row
    crop = await session.scalar(
        select(Crop).where(
            Crop.id == crop_id, Crop.tenant_id == tenant_id, Crop.deleted_at.is_(None)
        )
    )
    if crop is None:
        raise NotFoundError("Crop not found.")
    pest = await session.scalar(
        select(PestOrDisease).where(
            PestOrDisease.id == pest_or_disease_id,
            PestOrDisease.tenant_id == tenant_id,
            PestOrDisease.deleted_at.is_(None),
        )
    )
    if pest is None:
        raise NotFoundError("Pest or disease not found.")
    if pest.type in PEST_TYPES and product.category not in CROP_PROTECTION:
        raise ClaimCategoryInvalidError(
            f"A {pest.type} claim needs a pesticide, fungicide, herbicide or growth product; "
            f"{product.name} is {product.category}.",
            extra={"category": product.category, "problem_type": pest.type},
        )
    if pest.crop_id is not None and pest.crop_id != crop.id:
        raise PestNotForCropError(
            f"{pest.name} is not a problem of {crop.name}.",
            extra={"pest_crop_id": str(pest.crop_id)},
        )
    return sku, product, crop, pest


async def _approved_for(
    session: AsyncSession,
    claim: LabelClaim | LabelClaimCreate,
    tenant_id: uuid.UUID,
    exclude: uuid.UUID | None = None,
) -> LabelClaim | None:
    stmt = select(LabelClaim).where(
        LabelClaim.tenant_id == tenant_id,
        LabelClaim.sku_id == claim.sku_id,
        LabelClaim.crop_id == claim.crop_id,
        LabelClaim.pest_or_disease_id == claim.pest_or_disease_id,
        LabelClaim.status == ClaimStatus.APPROVED.value,
        LabelClaim.deleted_at.is_(None),
    )
    if exclude is not None:
        stmt = stmt.where(LabelClaim.id != exclude)
    return (await session.execute(stmt.limit(1))).scalar_one_or_none()


def _duplicate(existing: LabelClaim) -> ClaimDuplicateError:
    return ClaimDuplicateError(
        "An approved claim already exists for this SKU, crop and problem; edit it instead "
        "(the edit becomes a new draft version).",
        extra={"existing_id": str(existing.id)},
    )


async def create_claim(session: AsyncSession, actor: User, body: LabelClaimCreate) -> LabelClaim:
    await validate_claim_target(
        session,
        actor.tenant_id,
        sku_id=body.sku_id,
        crop_id=body.crop_id,
        pest_or_disease_id=body.pest_or_disease_id,
    )
    existing = await _approved_for(session, body, actor.tenant_id)
    if existing is not None:
        raise _duplicate(existing)
    data = body.model_dump()
    data["dose_unit"] = body.dose_unit.value
    claim = LabelClaim(tenant_id=actor.tenant_id, status=ClaimStatus.DRAFT.value, **data)
    session.add(claim)
    await session.flush()
    await session.refresh(claim)
    return claim


def _clean_claim_changes(body: LabelClaimUpdate) -> dict[str, Any]:
    changes = body.model_dump(exclude_unset=True, exclude={"version"})
    for key in ("dose_per_acre", "dose_value", "dose_unit", "phi_days", "source_ref"):
        if key in changes and changes[key] is None:
            changes.pop(key)  # required on a claim: null means "unchanged"
    if "dose_unit" in changes:
        changes["dose_unit"] = str(changes["dose_unit"])
    return changes


async def update_claim(
    session: AsyncSession, actor: User, claim: LabelClaim, body: LabelClaimUpdate
) -> LabelClaim:
    """Edit a draft in place; an approved claim yields a new draft version; retired: 409."""
    check_version(claim, body.version)
    changes = _clean_claim_changes(body)
    if claim.status == ClaimStatus.RETIRED.value:
        raise ClaimRetiredError("A retired claim cannot be edited; create a new claim.")
    if claim.status == ClaimStatus.DRAFT.value:
        for key, value in changes.items():
            setattr(claim, key, value)
        await session.flush()
        await session.refresh(claim)
        return claim
    # Approved: immutable. Reuse an open draft of this version if there is one.
    draft = await session.scalar(
        select(LabelClaim).where(
            LabelClaim.tenant_id == actor.tenant_id,
            LabelClaim.supersedes_id == claim.id,
            LabelClaim.status == ClaimStatus.DRAFT.value,
            LabelClaim.deleted_at.is_(None),
        )
    )
    if draft is None:
        draft = LabelClaim(
            tenant_id=actor.tenant_id,
            sku_id=claim.sku_id,
            crop_id=claim.crop_id,
            pest_or_disease_id=claim.pest_or_disease_id,
            status=ClaimStatus.DRAFT.value,
            supersedes_id=claim.id,
            **{key: getattr(claim, key) for key in CLAIM_FIELDS},
        )
        session.add(draft)
    for key, value in changes.items():
        setattr(draft, key, value)
    await session.flush()
    await session.refresh(draft)
    return draft


async def approve_claim(
    session: AsyncSession, actor: User, claim: LabelClaim, now: datetime
) -> LabelClaim:
    """The SPEC 14.6 human gate: the agronomist approves; who and when are recorded."""
    if claim.status != ClaimStatus.DRAFT.value:
        raise ClaimNotDraftError(f"Only a draft can be approved; this claim is {claim.status}.")
    # Re-check the target: the product category or pest scope may have changed since.
    await validate_claim_target(
        session,
        actor.tenant_id,
        sku_id=claim.sku_id,
        crop_id=claim.crop_id,
        pest_or_disease_id=claim.pest_or_disease_id,
    )
    existing = await _approved_for(session, claim, actor.tenant_id, exclude=claim.id)
    if existing is not None:
        if existing.id != claim.supersedes_id:
            raise _duplicate(existing)
        existing.status = ClaimStatus.RETIRED.value
        existing.retired_by = actor.id
        existing.retired_at = now
        await session.flush()  # retire first: the partial unique index allows one approved
    claim.status = ClaimStatus.APPROVED.value
    claim.approved_by = actor.id
    claim.approved_at = now
    await session.flush()
    await session.refresh(claim)
    return claim


async def retire_claim(
    session: AsyncSession, actor: User, claim: LabelClaim, now: datetime
) -> LabelClaim:
    """Retire any version; a retired claim is never recommended again (DX-007)."""
    if claim.status == ClaimStatus.RETIRED.value:
        raise ClaimRetiredError("This claim is already retired.")
    claim.status = ClaimStatus.RETIRED.value
    claim.retired_by = actor.id
    claim.retired_at = now
    await session.flush()
    await session.refresh(claim)
    return claim


async def claim_history(
    session: AsyncSession, tenant_id: uuid.UUID, claim: LabelClaim
) -> list[LabelClaim]:
    """Every version linked to ``claim`` through ``supersedes_id``, newest first."""
    ids: set[uuid.UUID] = {claim.id}
    frontier: set[uuid.UUID] = {claim.id}
    if claim.supersedes_id is not None:
        frontier.add(claim.supersedes_id)
        ids.add(claim.supersedes_id)
    rows: dict[uuid.UUID, LabelClaim] = {}
    for _ in range(100):  # chains are short; bound the walk anyway
        found = (
            (
                await session.execute(
                    select(LabelClaim).where(
                        LabelClaim.tenant_id == tenant_id,
                        LabelClaim.deleted_at.is_(None),
                        or_(
                            LabelClaim.id.in_(frontier),
                            LabelClaim.supersedes_id.in_(frontier),
                        ),
                    )
                )
            )
            .scalars()
            .all()
        )
        new: set[uuid.UUID] = set()
        for row in found:
            rows[row.id] = row
            for ref in (row.id, row.supersedes_id):
                if ref is not None and ref not in ids:
                    ids.add(ref)
                    new.add(ref)
        if not new:
            break
        frontier = new

    def depth(row: LabelClaim) -> int:
        n, ref = 0, row.supersedes_id
        while ref is not None and ref in rows and n < len(rows):
            n, ref = n + 1, rows[ref].supersedes_id
        return n

    # Newest version first: deeper in the supersedes chain, then later created.
    return sorted(rows.values(), key=lambda r: (depth(r), r.created_at, r.id), reverse=True)


__all__ = [
    "CLAIM_FIELDS",
    "CROP_PROTECTION",
    "PEST_TYPES",
    "approve_claim",
    "check_version",
    "claim_history",
    "create_claim",
    "create_product",
    "create_sku",
    "get_claim",
    "get_product",
    "get_sku",
    "retire_claim",
    "update_claim",
    "update_product",
    "update_sku",
    "validate_claim_target",
]
