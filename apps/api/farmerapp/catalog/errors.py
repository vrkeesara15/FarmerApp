"""Problem codes of the catalogue write endpoints (WC-005, DX-007)."""

from __future__ import annotations

from farmerapp.api.errors import AppError


class ProductExistsError(AppError):
    status = 409
    code = "product_exists"


class BarcodeExistsError(AppError):
    status = 409
    code = "barcode_exists"


class VersionConflictError(AppError):
    status = 409
    code = "version_conflict"


class ClaimCategoryInvalidError(AppError):
    """A pest / disease claim on a SKU that is not a crop-protection product."""

    status = 422
    code = "claim_category_invalid"


class PestNotForCropError(AppError):
    status = 422
    code = "pest_not_for_crop"


class ClaimDuplicateError(AppError):
    status = 409
    code = "claim_duplicate"


class ClaimNotDraftError(AppError):
    status = 409
    code = "claim_not_draft"


class ClaimRetiredError(AppError):
    status = 409
    code = "claim_retired"


class PriceAboveMrpError(AppError):
    status = 422
    code = "price_above_mrp"


class PriceOverlapError(AppError):
    status = 409
    code = "price_overlap"


class SkuNotRecommendable(AppError):  # noqa: N818  (domain name used by DX-007 callers)
    """A SKU / label claim that may not back a recommendation (DX-007, SPEC 3.4)."""

    status = 422
    code = "sku_not_recommendable"


__all__ = [
    "BarcodeExistsError",
    "ClaimCategoryInvalidError",
    "ClaimDuplicateError",
    "ClaimNotDraftError",
    "ClaimRetiredError",
    "PestNotForCropError",
    "PriceAboveMrpError",
    "PriceOverlapError",
    "ProductExistsError",
    "SkuNotRecommendable",
    "VersionConflictError",
]
