/**
 * Client-side validation for the catalogue forms (C50–C52). Mirrors the API rules in
 * apps/api/farmerapp/catalog (the API stays the authority): GST slab, 4/6/8-digit HSN,
 * pack size > 0, MRP in paise, label claims with dose > 0 + unit, PHI >= 0, the pest scoped to
 * the crop, and price <= MRP. Error messages are i18n message keys (rendered with `t`).
 */
import { z } from "zod";
import type { MessageKey } from "./i18n";
import {
  CLAIM_CATEGORIES,
  DOSE_UNITS,
  GST_RATES_BP,
  PACK_UNITS,
  PRODUCT_CATEGORIES,
  rupeesToPaise,
  type LabelClaimInput,
  type PestOrDisease,
  type ProductCategory,
  type ProductInput,
  type SkuInput,
} from "./catalog";

const msg = (key: MessageKey) => ({ message: key });
const optionalText = (max: number) => z.string().trim().max(max, msg("validation.tooLong"));
const nullIfEmpty = (s: string | undefined): string | null => {
  const v = (s ?? "").trim();
  return v === "" ? null : v;
};

export const HSN_PATTERN = /^(\d{4}|\d{6}|\d{8})$/;
export const DECIMAL_PATTERN = /^\d+(\.\d{1,3})?$/;

// ---- product -----------------------------------------------------------------------------
export const productSchema = z.object({
  name: z.string().trim().min(1, msg("validation.required")).max(200, msg("validation.tooLong")),
  brand: z.string().trim().min(1, msg("validation.required")).max(120, msg("validation.tooLong")),
  own_brand: z.boolean(),
  category: z.enum(PRODUCT_CATEGORIES, msg("validation.required")),
  hsn: z
    .string()
    .trim()
    .refine((v) => v === "" || HSN_PATTERN.test(v), msg("validation.hsn")),
  gst_rate_bp: z
    .string()
    .refine(
      (v) => (GST_RATES_BP as readonly number[]).includes(Number(v)) && v !== "",
      msg("validation.gst"),
    ),
  active_ingredient: optionalText(500),
  formulation: optionalText(64),
  active: z.boolean(),
});
export type ProductFormValues = z.infer<typeof productSchema>;

export function toProductInput(v: ProductFormValues): ProductInput {
  return {
    name: v.name.trim(),
    brand: v.brand.trim(),
    own_brand: v.own_brand,
    category: v.category,
    hsn: nullIfEmpty(v.hsn),
    gst_rate_bp: Number(v.gst_rate_bp),
    active_ingredient: nullIfEmpty(v.active_ingredient),
    formulation: nullIfEmpty(v.formulation),
    active: v.active,
  };
}

// ---- SKU ---------------------------------------------------------------------------------
export const skuSchema = z.object({
  pack_size_value: z
    .string()
    .trim()
    .refine((v) => DECIMAL_PATTERN.test(v) && Number(v) > 0, msg("validation.positive")),
  pack_size_unit: z.enum(PACK_UNITS, msg("validation.required")),
  barcode: z
    .string()
    .trim()
    .refine((v) => v === "" || /^[0-9A-Za-z-]{4,64}$/.test(v), msg("validation.barcode")),
  mrp: z
    .string()
    .trim()
    .refine((v) => rupeesToPaise(v) !== null, msg("validation.money")),
  active: z.boolean(),
});
export type SkuFormValues = z.infer<typeof skuSchema>;

export function toSkuInput(productId: string, v: SkuFormValues): SkuInput {
  return {
    product_id: productId,
    pack_size_value: v.pack_size_value.trim(),
    pack_size_unit: v.pack_size_unit,
    barcode: nullIfEmpty(v.barcode),
    mrp_paise: rupeesToPaise(v.mrp) ?? 0,
    active: v.active,
  };
}

// ---- label claim -------------------------------------------------------------------------
const baseClaimSchema = z.object({
  sku_id: z.string().min(1, msg("validation.required")),
  crop_id: z.string().min(1, msg("validation.required")),
  pest_or_disease_id: z.string().min(1, msg("validation.required")),
  dose_per_acre: z
    .string()
    .trim()
    .min(1, msg("validation.required"))
    .max(120, msg("validation.tooLong")),
  dose_value: z
    .string()
    .trim()
    .refine((v) => DECIMAL_PATTERN.test(v) && Number(v) > 0, msg("validation.positive")),
  dose_unit: z.enum(DOSE_UNITS, msg("validation.doseUnit")),
  dose_per_tank_15l: optionalText(64),
  phi_days: z
    .string()
    .trim()
    .refine((v) => /^\d+$/.test(v), msg("validation.phi")),
  ppe_text: optionalText(2000),
  safety_text: optionalText(2000),
  source_ref: z
    .string()
    .trim()
    .min(1, msg("validation.sourceRef"))
    .max(200, msg("validation.tooLong")),
  efficacy_tier: z
    .string()
    .refine((v) => v === "" || ["1", "2", "3"].includes(v), msg("validation.tier")),
});
export type ClaimFormValues = z.infer<typeof baseClaimSchema>;

export interface ClaimContext {
  pests: ReadonlyArray<PestOrDisease>;
  /** Product category of a SKU (undefined when unknown). */
  skuCategory: (skuId: string) => ProductCategory | undefined;
}

/** The claim schema with the cross-field rules that need reference data. */
export function makeClaimSchema(ctx: ClaimContext) {
  return baseClaimSchema.superRefine((v, issue) => {
    const pest = ctx.pests.find((p) => p.id === v.pest_or_disease_id);
    if (pest && v.crop_id && pest.crop_id !== null && pest.crop_id !== v.crop_id)
      issue.addIssue({
        code: "custom",
        path: ["pest_or_disease_id"],
        message: "validation.pestNotForCrop" satisfies MessageKey,
      });
    const category = ctx.skuCategory(v.sku_id);
    if (
      pest &&
      category &&
      (pest.type === "pest" || pest.type === "disease") &&
      !CLAIM_CATEGORIES.includes(category)
    )
      issue.addIssue({
        code: "custom",
        path: ["sku_id"],
        message: "validation.claimCategory" satisfies MessageKey,
      });
  });
}

export function toClaimInput(v: ClaimFormValues): LabelClaimInput {
  return {
    sku_id: v.sku_id,
    crop_id: v.crop_id,
    pest_or_disease_id: v.pest_or_disease_id,
    dose_per_acre: v.dose_per_acre.trim(),
    dose_value: v.dose_value.trim(),
    dose_unit: v.dose_unit,
    dose_per_tank_15l: nullIfEmpty(v.dose_per_tank_15l),
    phi_days: Number(v.phi_days),
    ppe_text: nullIfEmpty(v.ppe_text),
    safety_text: nullIfEmpty(v.safety_text),
    source_ref: v.source_ref.trim(),
    efficacy_tier: v.efficacy_tier === "" ? null : Number(v.efficacy_tier),
  };
}

// ---- price row ---------------------------------------------------------------------------
export interface PriceDraft {
  price: string;
  effective_from: string;
  effective_to: string;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/** First problem of an edited price row, as a message key; undefined when valid. */
export function validatePriceRow(row: PriceDraft, mrpPaise: number): MessageKey | undefined {
  const paise = rupeesToPaise(row.price);
  if (paise === null) return "validation.money";
  if (paise > mrpPaise) return "problems.priceAboveMrp";
  if (!ISO_DATE.test(row.effective_from)) return "validation.date";
  if (row.effective_to !== "") {
    if (!ISO_DATE.test(row.effective_to)) return "validation.date";
    if (row.effective_to < row.effective_from) return "validation.dateOrder";
  }
  return undefined;
}
