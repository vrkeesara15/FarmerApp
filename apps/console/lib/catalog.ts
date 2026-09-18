/**
 * Catalogue API (WC-005): product master, label claims, recommendation guardrail, price lists,
 * CSV import / export. Shapes mirror apps/api/openapi.yaml (`/v1/catalog/*`); money is integer
 * paise and dates are `YYYY-MM-DD`. Every call goes through `authedFetch` (bearer token from
 * the session, one refresh + retry on 401).
 */
import { authedFetch, authedFetchText, type UserRole } from "./api";

export const PRODUCT_CATEGORIES = [
  "seed",
  "fertiliser",
  "pesticide",
  "fungicide",
  "herbicide",
  "growth",
  "tool",
  "other",
] as const;
export type ProductCategory = (typeof PRODUCT_CATEGORIES)[number];

/** Categories that may carry a pest / disease label claim (SPEC 3.4, API `claim_category_invalid`). */
export const CLAIM_CATEGORIES: ReadonlyArray<ProductCategory> = [
  "pesticide",
  "fungicide",
  "herbicide",
  "growth",
];

export const PACK_UNITS = ["ml", "l", "g", "kg", "pcs"] as const;
export type PackUnit = (typeof PACK_UNITS)[number];
export const DOSE_UNITS = ["ml", "g", "l", "kg"] as const;
export type DoseUnit = (typeof DOSE_UNITS)[number];
/** GST slabs in basis points (0, 5, 12, 18, 28 %). */
export const GST_RATES_BP = [0, 500, 1200, 1800, 2800] as const;
export const CLAIM_STATUSES = ["draft", "approved", "retired"] as const;
export type ClaimStatus = (typeof CLAIM_STATUSES)[number];
export type ProblemType = "disease" | "pest" | "nutrient" | "abiotic";

// ---- roles (mirror apps/api/farmerapp/catalog/router.py) -----------------------------------
export const CATALOG_WRITE_ROLES: ReadonlyArray<string> = ["owner", "director", "tenant_admin"];
export const CLAIM_EDIT_ROLES: ReadonlyArray<string> = ["owner", "tenant_admin", "agronomist"];
export const CLAIM_APPROVE_ROLES: ReadonlyArray<string> = ["agronomist"];
export const CLAIM_RETIRE_ROLES: ReadonlyArray<string> = ["agronomist", "owner", "tenant_admin"];
export const PRICE_READ_ROLES: ReadonlyArray<string> = [
  "owner",
  "director",
  "tenant_admin",
  "cluster_head",
  "store_manager",
  "accountant",
  "auditor",
];
export const EXPORT_ROLES: ReadonlyArray<string> = [
  "owner",
  "director",
  "tenant_admin",
  "agronomist",
  "auditor",
];

export const can = (role: UserRole | string | undefined, roles: ReadonlyArray<string>): boolean =>
  !!role && roles.includes(role);

// ---- shapes ------------------------------------------------------------------------------
export interface Crop {
  id: string;
  code: string;
  name: string;
  names: Record<string, string>;
  active: boolean;
}

export interface PestOrDisease {
  id: string;
  code: string;
  name: string;
  names: Record<string, string>;
  type: ProblemType;
  crop_id: string | null;
  scientific_name: string | null;
  symptoms: string | null;
  active: boolean;
}

export interface StoreRef {
  id: string;
  code: string;
  name: string;
}

export interface Sku {
  id: string;
  product_id: string;
  pack_size_value: string;
  pack_size_unit: PackUnit;
  pack_label: string;
  barcode: string | null;
  mrp_paise: number;
  active: boolean;
  price_paise: number;
  stock_qty: string | null;
  created_at: string;
  updated_at: string;
  version: number;
}

export interface Product {
  id: string;
  tenant_id: string;
  name: string;
  brand: string;
  own_brand: boolean;
  category: ProductCategory;
  hsn: string | null;
  gst_rate_bp: number;
  description: string | null;
  active_ingredient: string | null;
  formulation: string | null;
  names: Record<string, string>;
  image_uri: string | null;
  active: boolean;
  created_at: string;
  updated_at: string;
  version: number;
}

export interface ProductWithSkus extends Product {
  skus: Sku[];
}

export interface Page<T> {
  items: T[];
  next_cursor: string | null;
}

export interface Items<T> {
  items: T[];
}

export interface ProductInput {
  name: string;
  brand: string;
  own_brand: boolean;
  category: ProductCategory;
  hsn: string | null;
  gst_rate_bp: number;
  active_ingredient?: string | null;
  formulation?: string | null;
  description?: string | null;
  active?: boolean;
}

export interface SkuInput {
  product_id: string;
  pack_size_value: string;
  pack_size_unit: PackUnit;
  barcode: string | null;
  mrp_paise: number;
  active?: boolean;
}

export interface LabelClaim {
  id: string;
  sku_id: string;
  crop_id: string;
  pest_or_disease_id: string;
  dose_per_acre: string;
  dose_value: string | null;
  dose_unit: DoseUnit | null;
  dose_per_tank_15l: string | null;
  phi_days: number | null;
  ppe_text: string | null;
  safety_text: string | null;
  source_ref: string;
  efficacy_tier: number | null;
  status: ClaimStatus;
  approved_by: string | null;
  approved_at: string | null;
  retired_by: string | null;
  retired_at: string | null;
  supersedes_id: string | null;
  created_at: string;
  updated_at: string;
  version: number;
  pest_or_disease?: PestOrDisease | null;
}

export interface LabelClaimInput {
  sku_id: string;
  crop_id: string;
  pest_or_disease_id: string;
  dose_per_acre: string;
  dose_value: string;
  dose_unit: DoseUnit;
  dose_per_tank_15l: string | null;
  phi_days: number;
  ppe_text: string | null;
  safety_text: string | null;
  source_ref: string;
  efficacy_tier: number | null;
}

export type LabelClaimPatch = Partial<
  Omit<LabelClaimInput, "sku_id" | "crop_id" | "pest_or_disease_id">
> & { version?: number };

export interface RecommendableSku {
  sku_id: string;
  product_id: string;
  product_name: string;
  brand: string;
  own_brand: boolean;
  pack_label: string;
  mrp_paise: number;
  label_claim_id: string;
  dose_per_acre: string;
  dose_value: string | null;
  dose_unit: DoseUnit | null;
  dose_per_tank_15l: string | null;
  phi_days: number | null;
  ppe_text: string | null;
  safety_text: string | null;
  efficacy_tier: number | null;
}

export interface PriceRow {
  id: string;
  sku_id: string;
  store_id: string | null;
  price_paise: number;
  effective_from: string;
  effective_to: string | null;
  mrp_paise: number;
  version: number;
}

export interface PriceRowInput {
  sku_id: string;
  price_paise: number;
  effective_from: string;
  effective_to: string | null;
}

/** Per-row problems of `PUT /price-lists` (422 price_above_mrp / 409 price_overlap). */
export interface PriceRowProblem {
  index: number;
  sku_id: string;
  code: "price_above_mrp" | "price_overlap";
  conflicting_id?: string;
}

export type ImportKind = "products" | "label_claims";

export interface ImportRowError {
  row: number;
  column: string | null;
  code: string;
  message: string;
}

export interface ImportReport {
  kind: ImportKind;
  dry_run: boolean;
  applied: boolean;
  rows_total: number;
  rows_ok: number;
  created: number;
  updated: number;
  errors: ImportRowError[];
}

export interface ProductFilters {
  q?: string;
  category?: ProductCategory;
  own_brand?: boolean;
  include_inactive?: boolean;
}

export interface ClaimFilters {
  status?: ClaimStatus | "all";
  crop_id?: string;
  pest_id?: string;
  sku_id?: string;
}

// ---- helpers -----------------------------------------------------------------------------
const BASE = "v1/catalog";

export function queryString(params: Record<string, string | number | boolean | undefined | null>) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v === undefined || v === null || v === "") continue;
    q.set(k, String(v));
  }
  const s = q.toString();
  return s ? `?${s}` : "";
}

/** Follow `next_cursor` until the collection is exhausted (catalogue sizes are small). */
async function allPages<T>(
  path: string,
  params: Record<string, string | number | boolean | undefined>,
) {
  const items: T[] = [];
  let cursor: string | undefined;
  for (let i = 0; i < 100; i++) {
    const page = await authedFetch<Page<T>>(
      `${path}${queryString({ ...params, limit: 200, cursor })}`,
    );
    items.push(...page.items);
    if (!page.next_cursor) break;
    cursor = page.next_cursor;
  }
  return items;
}

// ---- API ---------------------------------------------------------------------------------
export const catalog = {
  crops: () => authedFetch<Items<Crop>>(`${BASE}/crops`).then((r) => r.items),
  pests: (cropId?: string) =>
    authedFetch<Items<PestOrDisease>>(`${BASE}/pests${queryString({ crop_id: cropId })}`).then(
      (r) => r.items,
    ),
  stores: () => authedFetch<Items<StoreRef>>(`${BASE}/stores`).then((r) => r.items),

  products: (f: ProductFilters = {}) =>
    allPages<ProductWithSkus>(`${BASE}/products`, {
      q: f.q,
      category: f.category,
      own_brand: f.own_brand,
      include_inactive: f.include_inactive,
    }),
  createProduct: (body: ProductInput) =>
    authedFetch<Product>(`${BASE}/products`, { method: "POST", body }),
  updateProduct: (id: string, body: Partial<ProductInput> & { version?: number }) =>
    authedFetch<Product>(`${BASE}/products/${id}`, { method: "PATCH", body }),
  createSku: (body: SkuInput) => authedFetch<Sku>(`${BASE}/skus`, { method: "POST", body }),
  updateSku: (id: string, body: Partial<Omit<SkuInput, "product_id">> & { version?: number }) =>
    authedFetch<Sku>(`${BASE}/skus/${id}`, { method: "PATCH", body }),

  labelClaims: (f: ClaimFilters = {}) =>
    allPages<LabelClaim>(`${BASE}/label-claims`, {
      status: f.status,
      crop_id: f.crop_id,
      pest_id: f.pest_id,
      sku_id: f.sku_id,
    }),
  createClaim: (body: LabelClaimInput) =>
    authedFetch<LabelClaim>(`${BASE}/label-claims`, { method: "POST", body }),
  updateClaim: (id: string, body: LabelClaimPatch) =>
    authedFetch<LabelClaim>(`${BASE}/label-claims/${id}`, { method: "PATCH", body }),
  approveClaim: (id: string) =>
    authedFetch<LabelClaim>(`${BASE}/label-claims/${id}/approve`, { method: "POST", body: {} }),
  retireClaim: (id: string) =>
    authedFetch<LabelClaim>(`${BASE}/label-claims/${id}/retire`, { method: "POST", body: {} }),
  claimHistory: (id: string) =>
    authedFetch<Items<LabelClaim>>(`${BASE}/label-claims/${id}/history`).then((r) => r.items),

  recommendable: (cropId: string, pestId: string) =>
    authedFetch<Items<RecommendableSku>>(
      `${BASE}/recommendable${queryString({ crop_id: cropId, pest_id: pestId })}`,
    ).then((r) => r.items),

  priceLists: (storeId: string | null, at?: string) =>
    authedFetch<Items<PriceRow>>(
      `${BASE}/price-lists${queryString({ store_id: storeId ?? undefined, at })}`,
    ).then((r) => r.items),
  putPriceLists: (storeId: string | null, items: PriceRowInput[]) =>
    authedFetch<Items<PriceRow>>(`${BASE}/price-lists`, {
      method: "PUT",
      body: { store_id: storeId, items },
    }).then((r) => r.items),

  importCsv: (kind: ImportKind, csv: string, dryRun: boolean) =>
    authedFetch<ImportReport>(
      `${BASE}/import/${kind === "products" ? "products" : "label-claims"}`,
      { method: "POST", body: { csv, dry_run: dryRun } },
    ),
  exportCsv: (kind: ImportKind) => authedFetchText(`${BASE}/export${queryString({ kind })}`),
};

/** Paise -> rupee string for inputs ("1234.50"); rupee input -> paise (null when invalid). */
export const paiseToRupees = (paise: number): string => (paise / 100).toFixed(2);
export function rupeesToPaise(value: string): number | null {
  const v = value.trim();
  if (!/^\d+(\.\d{1,2})?$/.test(v)) return null;
  const [whole = "0", frac = ""] = v.split(".");
  return Number(whole) * 100 + Number(frac.padEnd(2, "0"));
}

/** Offer the CSV to the user as a download (blob URL; no page navigation). */
export function downloadText(filename: string, text: string, type = "text/csv"): void {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
