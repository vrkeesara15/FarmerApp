import { describe, expect, it } from "vitest";
import { rupeesToPaise, paiseToRupees, type PestOrDisease } from "./catalog";
import {
  makeClaimSchema,
  productSchema,
  skuSchema,
  toClaimInput,
  toProductInput,
  toSkuInput,
  validatePriceRow,
  type ClaimFormValues,
} from "./catalog-schemas";

const pest = (id: string, cropId: string | null, type: PestOrDisease["type"] = "pest") =>
  ({
    id,
    code: id,
    name: id,
    names: {},
    type,
    crop_id: cropId,
    scientific_name: null,
    symptoms: null,
    active: true,
  }) as PestOrDisease;

const product = {
  name: "FCC Imida",
  brand: "FCC",
  own_brand: true,
  category: "pesticide" as const,
  hsn: "3808",
  gst_rate_bp: "1800",
  active_ingredient: "",
  formulation: "SL",
  active: true,
};

const messages = (r: {
  success: boolean;
  error?: { issues: Array<{ path: PropertyKey[]; message: string }> };
}) => Object.fromEntries((r.error?.issues ?? []).map((i) => [String(i.path[0]), i.message]));

describe("productSchema (mirrors API GST / HSN validation)", () => {
  it("accepts a valid product and maps it to the API body", () => {
    const parsed = productSchema.parse(product);
    expect(toProductInput(parsed)).toEqual({
      name: "FCC Imida",
      brand: "FCC",
      own_brand: true,
      category: "pesticide",
      hsn: "3808",
      gst_rate_bp: 1800,
      active_ingredient: null,
      formulation: "SL",
      active: true,
    });
  });

  it.each(["3808", "380891", "38089199", ""])("HSN %j is allowed", (hsn) => {
    expect(productSchema.safeParse({ ...product, hsn }).success).toBe(true);
  });

  it.each(["38", "38089", "3808919", "38O8"])("HSN %j is rejected", (hsn) => {
    expect(messages(productSchema.safeParse({ ...product, hsn })).hsn).toBe("validation.hsn");
  });

  it("only allows the GST slabs 0/5/12/18/28 %", () => {
    for (const bp of ["0", "500", "1200", "1800", "2800"])
      expect(productSchema.safeParse({ ...product, gst_rate_bp: bp }).success).toBe(true);
    for (const bp of ["1500", "", "18"])
      expect(messages(productSchema.safeParse({ ...product, gst_rate_bp: bp })).gst_rate_bp).toBe(
        "validation.gst",
      );
  });

  it("requires name and brand", () => {
    const m = messages(productSchema.safeParse({ ...product, name: " ", brand: "" }));
    expect(m).toMatchObject({ name: "validation.required", brand: "validation.required" });
  });
});

describe("skuSchema", () => {
  const sku = {
    pack_size_value: "250",
    pack_size_unit: "ml" as const,
    barcode: "",
    mrp: "480.50",
    active: true,
  };
  it("converts rupees to integer paise", () => {
    expect(toSkuInput("p1", skuSchema.parse(sku))).toEqual({
      product_id: "p1",
      pack_size_value: "250",
      pack_size_unit: "ml",
      barcode: null,
      mrp_paise: 48050,
      active: true,
    });
  });
  it("rejects a zero pack, a bad barcode and a bad amount", () => {
    const m = messages(
      skuSchema.safeParse({ ...sku, pack_size_value: "0", barcode: "a b", mrp: "4.555" }),
    );
    expect(m).toEqual({
      pack_size_value: "validation.positive",
      barcode: "validation.barcode",
      mrp: "validation.money",
    });
  });
});

describe("claim schema (dose > 0 with unit, PHI >= 0, pest scoped to crop)", () => {
  const schema = makeClaimSchema({
    pests: [pest("bph", "paddy"), pest("aphids", null), pest("zinc", null, "nutrient")],
    skuCategory: (id) => (id === "dap" ? "fertiliser" : "pesticide"),
  });
  const claim: ClaimFormValues = {
    sku_id: "imida",
    crop_id: "paddy",
    pest_or_disease_id: "bph",
    dose_per_acre: "40-50 ml",
    dose_value: "50",
    dose_unit: "ml",
    dose_per_tank_15l: "",
    phi_days: "40",
    ppe_text: "",
    safety_text: "",
    source_ref: "CIB-123",
    efficacy_tier: "",
  };

  it("accepts a complete claim and builds the API body", () => {
    expect(toClaimInput(schema.parse(claim))).toMatchObject({
      dose_value: "50",
      phi_days: 40,
      dose_per_tank_15l: null,
      efficacy_tier: null,
    });
  });

  it("rejects dose 0, negative or fractional PHI and a missing source reference", () => {
    const m = messages(
      schema.safeParse({ ...claim, dose_value: "0", phi_days: "-1", source_ref: "" }),
    );
    expect(m).toMatchObject({
      dose_value: "validation.positive",
      phi_days: "validation.phi",
      source_ref: "validation.sourceRef",
    });
    expect(messages(schema.safeParse({ ...claim, phi_days: "2.5" })).phi_days).toBe(
      "validation.phi",
    );
    expect(schema.safeParse({ ...claim, phi_days: "0" }).success).toBe(true);
  });

  it("rejects a pest of another crop but allows polyphagous pests", () => {
    expect(messages(schema.safeParse({ ...claim, crop_id: "cotton" })).pest_or_disease_id).toBe(
      "validation.pestNotForCrop",
    );
    expect(
      schema.safeParse({ ...claim, crop_id: "cotton", pest_or_disease_id: "aphids" }).success,
    ).toBe(true);
  });

  it("only agrochemical categories may carry pest / disease claims", () => {
    expect(messages(schema.safeParse({ ...claim, sku_id: "dap" })).sku_id).toBe(
      "validation.claimCategory",
    );
    expect(schema.safeParse({ ...claim, sku_id: "dap", pest_or_disease_id: "zinc" }).success).toBe(
      true,
    );
  });
});

describe("price rows (price <= MRP)", () => {
  const row = { price: "450", effective_from: "2026-10-01", effective_to: "" };
  it("validates amount, MRP and date order", () => {
    expect(validatePriceRow(row, 45000)).toBeUndefined();
    expect(validatePriceRow(row, 44999)).toBe("problems.priceAboveMrp");
    expect(validatePriceRow({ ...row, price: "abc" }, 45000)).toBe("validation.money");
    expect(validatePriceRow({ ...row, effective_from: "" }, 45000)).toBe("validation.date");
    expect(validatePriceRow({ ...row, effective_to: "2026-09-30" }, 45000)).toBe(
      "validation.dateOrder",
    );
  });
  it("converts rupees and paise exactly", () => {
    expect(rupeesToPaise("0.05")).toBe(5);
    expect(rupeesToPaise("1234.5")).toBe(123450);
    expect(rupeesToPaise("12.345")).toBeNull();
    expect(paiseToRupees(123450)).toBe("1234.50");
  });
});
