import { describe, expect, it } from "vitest";
import { ApiError } from "./api";
import { t } from "./i18n";
import { fieldErrors, problemCode, problemMessage, problemMessageKey } from "./problem-messages";

const err = (status: number, code?: string, extra: Record<string, unknown> = {}) =>
  new ApiError({ title: "x", status, code, ...extra });

describe("problem+json code -> message key", () => {
  it.each([
    ["barcode_exists", "problems.barcodeExists"],
    ["product_exists", "problems.productExists"],
    ["price_above_mrp", "problems.priceAboveMrp"],
    ["price_overlap", "problems.priceOverlap"],
    ["claim_duplicate", "problems.claimDuplicate"],
    ["claim_category_invalid", "problems.claimCategoryInvalid"],
    ["pest_not_for_crop", "problems.pestNotForCrop"],
    ["claim_not_draft", "problems.claimNotDraft"],
    ["claim_retired", "problems.claimRetired"],
    ["version_conflict", "problems.versionConflict"],
    ["validation_error", "problems.validation"],
    ["forbidden", "problems.forbidden"],
    ["unauthenticated", "problems.unauthenticated"],
    ["not_found", "problems.notFound"],
  ])("%s", (code, key) => {
    expect(problemMessageKey(err(400, code))).toBe(key);
  });

  it("falls back for unknown codes, network errors and non-API errors", () => {
    expect(problemMessageKey(err(500, "internal_error"))).toBe("problems.default");
    expect(problemMessageKey(err(0))).toBe("problems.network");
    expect(problemMessageKey(new Error("boom"))).toBe("problems.default");
    expect(problemMessage(err(409, "price_overlap"), t)).toBe(
      "This date range overlaps another price for the same SKU.",
    );
    expect(problemCode(err(409, "barcode_exists"))).toBe("barcode_exists");
    expect(problemCode(new Error("x"))).toBeUndefined();
  });

  it("extracts field errors from validation problems", () => {
    const e = err(422, "validation_error", {
      errors: [
        { loc: ["body", "gst_rate_bp"], msg: "GST rate must be 0, 5, 12, 18 or 28 %" },
        { loc: ["body", "hsn"], msg: "HSN must have 4, 6 or 8 digits" },
      ],
    });
    expect(fieldErrors(e)).toEqual({
      gst_rate_bp: "GST rate must be 0, 5, 12, 18 or 28 %",
      hsn: "HSN must have 4, 6 or 8 digits",
    });
    expect(fieldErrors(new Error("x"))).toEqual({});
  });
});
