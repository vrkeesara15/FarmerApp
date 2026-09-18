/**
 * In-memory catalogue for the mock API (app/api/mock) so the console and Playwright run without
 * apps/api. Mirrors `/v1/catalog/*` of apps/api/openapi.yaml (WC-005): the same shapes, role
 * lists, validation and problem codes (`barcode_exists`, `product_exists`, `claim_duplicate`,
 * `claim_category_invalid`, `pest_not_for_crop`, `claim_not_draft`, `claim_retired`,
 * `price_above_mrp`, `price_overlap`, `version_conflict`, `validation_error`). Holds no real
 * data; `resetMockCatalog()` restores the seed.
 */
import type { UserRole } from "../api";

export interface MockResult {
  status: number;
  json?: unknown;
  text?: string;
  headers?: Record<string, string>;
}

type Json = Record<string, unknown>;

// ---- roles (same lists as apps/api/farmerapp/catalog/router.py) ----------------------------
const ALL: readonly string[] = [
  "owner",
  "director",
  "cluster_head",
  "auditor",
  "store_manager",
  "accountant",
  "field_officer",
  "agronomist",
  "tenant_admin",
  "farmer",
];
const WRITE = ["owner", "director", "tenant_admin"];
const CLAIM_EDIT = ["owner", "tenant_admin", "agronomist"];
const CLAIM_APPROVE = ["agronomist"];
const CLAIM_RETIRE = ["agronomist", "owner", "tenant_admin"];
const CLAIM_MAINTAIN = ["owner", "tenant_admin", "agronomist"];
const PRICE_READ = [
  "owner",
  "director",
  "tenant_admin",
  "cluster_head",
  "store_manager",
  "accountant",
  "auditor",
];
const BARCODE = [
  "owner",
  "director",
  "tenant_admin",
  "cluster_head",
  "store_manager",
  "accountant",
  "field_officer",
];
const EXPORT = ["owner", "director", "tenant_admin", "agronomist", "auditor"];

const CATEGORIES = [
  "seed",
  "fertiliser",
  "pesticide",
  "fungicide",
  "herbicide",
  "growth",
  "tool",
  "other",
];
const CLAIM_CATEGORIES = ["pesticide", "fungicide", "herbicide", "growth"];
const PACK_UNITS = ["ml", "l", "g", "kg", "pcs"];
const DOSE_UNITS = ["ml", "g", "l", "kg"];
const GST = [0, 500, 1200, 1800, 2800];
const HSN = /^(\d{4}|\d{6}|\d{8})$/;
const TENANT = "t1";

// ---- rows --------------------------------------------------------------------------------
interface Crop {
  id: string;
  code: string;
  name: string;
  names: Record<string, string>;
  active: boolean;
}
interface Pest {
  id: string;
  code: string;
  name: string;
  names: Record<string, string>;
  type: string;
  crop_id: string | null;
  scientific_name: string | null;
  symptoms: string | null;
  active: boolean;
}
interface Store {
  id: string;
  code: string;
  name: string;
}
interface Product {
  id: string;
  tenant_id: string;
  name: string;
  brand: string;
  own_brand: boolean;
  category: string;
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
interface Sku {
  id: string;
  product_id: string;
  pack_size_value: string;
  pack_size_unit: string;
  barcode: string | null;
  mrp_paise: number;
  active: boolean;
  created_at: string;
  updated_at: string;
  version: number;
}
interface Claim {
  id: string;
  sku_id: string;
  crop_id: string;
  pest_or_disease_id: string;
  dose_per_acre: string;
  dose_value: string | null;
  dose_unit: string | null;
  dose_per_tank_15l: string | null;
  phi_days: number | null;
  ppe_text: string | null;
  safety_text: string | null;
  source_ref: string;
  efficacy_tier: number | null;
  status: "draft" | "approved" | "retired";
  approved_by: string | null;
  approved_at: string | null;
  retired_by: string | null;
  retired_at: string | null;
  supersedes_id: string | null;
  created_at: string;
  updated_at: string;
  version: number;
}
interface Price {
  id: string;
  sku_id: string;
  store_id: string | null;
  price_paise: number;
  effective_from: string;
  effective_to: string | null;
  version: number;
}

interface Db {
  crops: Crop[];
  pests: Pest[];
  stores: Store[];
  products: Product[];
  skus: Sku[];
  claims: Claim[];
  prices: Price[];
  seq: number;
}

const SEED_TS = "2026-09-01T04:30:00.000Z";
const SEED_REF = "seed-fixture — replace with CIB&RC data (human gate)";

function seed(): Db {
  const crop = (code: string, name: string): Crop => ({
    id: `crop-${code}`,
    code,
    name,
    names: {},
    active: true,
  });
  const pest = (code: string, name: string, type: string, cropId: string | null): Pest => ({
    id: `pest-${code}`,
    code,
    name,
    names: {},
    type,
    crop_id: cropId,
    scientific_name: null,
    symptoms: null,
    active: true,
  });
  const product = (id: string, p: Partial<Product>): Product => ({
    id,
    tenant_id: TENANT,
    name: "",
    brand: "",
    own_brand: false,
    category: "other",
    hsn: null,
    gst_rate_bp: 1800,
    description: null,
    active_ingredient: null,
    formulation: null,
    names: {},
    image_uri: null,
    active: true,
    created_at: SEED_TS,
    updated_at: SEED_TS,
    version: 1,
    ...p,
  });
  const sku = (
    id: string,
    productId: string,
    value: string,
    unit: string,
    barcode: string,
    mrp: number,
  ): Sku => ({
    id,
    product_id: productId,
    pack_size_value: value,
    pack_size_unit: unit,
    barcode,
    mrp_paise: mrp,
    active: true,
    created_at: SEED_TS,
    updated_at: SEED_TS,
    version: 1,
  });
  const claim = (id: string, c: Partial<Claim>): Claim => ({
    id,
    sku_id: "",
    crop_id: "",
    pest_or_disease_id: "",
    dose_per_acre: "",
    dose_value: null,
    dose_unit: null,
    dose_per_tank_15l: null,
    phi_days: null,
    ppe_text: "Gloves, mask, full sleeves",
    safety_text: "Do not spray against the wind. Keep away from children.",
    source_ref: SEED_REF,
    efficacy_tier: 1,
    status: "draft",
    approved_by: null,
    approved_at: null,
    retired_by: null,
    retired_at: null,
    supersedes_id: null,
    created_at: SEED_TS,
    updated_at: SEED_TS,
    version: 1,
    ...c,
  });
  return {
    crops: [
      crop("paddy", "Paddy"),
      crop("cotton", "Cotton"),
      crop("chilli", "Chilli"),
      crop("maize", "Maize"),
      crop("tomato", "Tomato"),
      crop("groundnut", "Groundnut"),
    ],
    pests: [
      pest("paddy_bph", "Brown planthopper", "pest", "crop-paddy"),
      pest("paddy_blast", "Rice blast", "disease", "crop-paddy"),
      pest("cotton_pbw", "Pink bollworm", "pest", "crop-cotton"),
      pest("chilli_thrips", "Chilli thrips", "pest", "crop-chilli"),
      pest("aphids", "Aphids", "pest", null),
      pest("zinc_deficiency", "Zinc deficiency", "nutrient", null),
    ],
    stores: [
      { id: "store-wgl", code: "WGL", name: "Warangal" },
      { id: "store-knr", code: "KNR", name: "Karimnagar" },
      { id: "store-hbl", code: "HBL", name: "Hubballi" },
    ],
    products: [
      product("prod-imida", {
        name: "FCC Imida",
        brand: "FCC",
        own_brand: true,
        category: "pesticide",
        hsn: "3808",
        active_ingredient: "Imidacloprid 17.8% SL",
        formulation: "SL",
      }),
      product("prod-tricy", {
        name: "Blastguard",
        brand: "Crop Guard",
        category: "fungicide",
        hsn: "3808",
        active_ingredient: "Tricyclazole 75% WP",
        formulation: "WP",
      }),
      product("prod-dap", {
        name: "DAP 18-46-0",
        brand: "Coromandel",
        category: "fertiliser",
        hsn: "3105",
        gst_rate_bp: 500,
      }),
      product("prod-sprayer", {
        name: "Knapsack sprayer 16 L",
        brand: "Aspee",
        category: "tool",
        hsn: "8424",
        gst_rate_bp: 1200,
        active: false,
      }),
    ],
    skus: [
      sku("sku-imida-100", "prod-imida", "100.000", "ml", "8901000000011", 22000),
      sku("sku-imida-250", "prod-imida", "250.000", "ml", "8901000000028", 48000),
      sku("sku-tricy-120", "prod-tricy", "120.000", "g", "8901000000035", 36000),
      sku("sku-dap-50", "prod-dap", "50.000", "kg", "8901000000042", 135000),
      sku("sku-sprayer", "prod-sprayer", "1.000", "pcs", "8901000000059", 320000),
    ],
    claims: [
      claim("claim-imida-bph", {
        sku_id: "sku-imida-100",
        crop_id: "crop-paddy",
        pest_or_disease_id: "pest-paddy_bph",
        dose_per_acre: "40-50 ml",
        dose_value: "50.000",
        dose_unit: "ml",
        dose_per_tank_15l: "4 ml",
        phi_days: 40,
        status: "approved",
        approved_by: "u-agronomist",
        approved_at: SEED_TS,
      }),
      claim("claim-tricy-blast", {
        sku_id: "sku-tricy-120",
        crop_id: "crop-paddy",
        pest_or_disease_id: "pest-paddy_blast",
        dose_per_acre: "120 g",
        dose_value: "120.000",
        dose_unit: "g",
        dose_per_tank_15l: "9 g",
        phi_days: 30,
        status: "draft",
      }),
      claim("claim-imida-thrips", {
        sku_id: "sku-imida-250",
        crop_id: "crop-chilli",
        pest_or_disease_id: "pest-chilli_thrips",
        dose_per_acre: "100 ml",
        dose_value: "100.000",
        dose_unit: "ml",
        phi_days: 3,
        status: "retired",
        approved_by: "u-agronomist",
        approved_at: SEED_TS,
        retired_by: "u-agronomist",
        retired_at: SEED_TS,
      }),
    ],
    prices: [
      {
        id: "price-1",
        sku_id: "sku-imida-100",
        store_id: null,
        price_paise: 20900,
        effective_from: "2026-05-01",
        effective_to: null,
        version: 1,
      },
      {
        id: "price-2",
        sku_id: "sku-imida-250",
        store_id: null,
        price_paise: 45600,
        effective_from: "2026-05-01",
        effective_to: null,
        version: 1,
      },
      {
        id: "price-3",
        sku_id: "sku-tricy-120",
        store_id: null,
        price_paise: 36000,
        effective_from: "2026-05-01",
        effective_to: null,
        version: 1,
      },
      {
        id: "price-4",
        sku_id: "sku-dap-50",
        store_id: null,
        price_paise: 135000,
        effective_from: "2026-05-01",
        effective_to: null,
        version: 1,
      },
      {
        id: "price-5",
        sku_id: "sku-imida-100",
        store_id: "store-wgl",
        price_paise: 19200,
        effective_from: "2026-08-15",
        effective_to: null,
        version: 1,
      },
    ],
    seq: 0,
  };
}

let db: Db = seed();

/** Test hook: restore the seeded catalogue. */
export function resetMockCatalog(): void {
  db = seed();
}

// ---- helpers -----------------------------------------------------------------------------
function problem(status: number, code: string, detail?: string, extra?: Json): MockResult {
  return {
    status,
    json: {
      type: `https://farmerapp.dev/problems/${code}`,
      title: code,
      status,
      code,
      detail,
      ...extra,
    },
    headers: { "content-type": "application/problem+json" },
  };
}
const ok = (json: unknown, status = 200): MockResult => ({ status, json });
const invalid = (field: string, msg: string) =>
  problem(422, "validation_error", "Request validation failed.", {
    errors: [{ loc: ["body", field], msg, type: "value_error" }],
  });
const forbidden = () => problem(403, "forbidden", "Your role does not allow this action.");
const notFound = (what: string) => problem(404, "not_found", `${what} not found.`);

const now = () => new Date().toISOString();
const today = () => now().slice(0, 10);
const newId = (prefix: string) => {
  db.seq += 1;
  return `${prefix}-${Date.now().toString(36)}-${db.seq}`;
};
const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);
const optStr = (v: unknown): string | null => {
  const s = typeof v === "string" ? v.trim() : "";
  return s === "" ? null : s;
};
const isDecimalPositive = (v: unknown) => {
  const s = typeof v === "number" ? String(v) : typeof v === "string" ? v.trim() : "";
  return /^\d+(\.\d{1,3})?$/.test(s) && Number(s) > 0;
};
const toDecimal = (v: unknown) => Number(v).toFixed(3);
const isInt = (v: unknown) => typeof v === "number" && Number.isInteger(v);

function packLabel(s: Sku): string {
  return `${Number(s.pack_size_value)} ${s.pack_size_unit}`;
}

function inForce(p: Price, at: string): boolean {
  return p.effective_from <= at && (p.effective_to === null || p.effective_to >= at);
}

function resolvedPrice(sku: Sku, storeId: string | null, at: string): number {
  const rows = db.prices.filter((p) => p.sku_id === sku.id && inForce(p, at));
  for (const candidates of [
    rows.filter((p) => storeId !== null && p.store_id === storeId),
    rows.filter((p) => p.store_id === null),
  ]) {
    const best = [...candidates].sort((a, b) =>
      b.effective_from.localeCompare(a.effective_from),
    )[0];
    if (best) return best.price_paise;
  }
  return sku.mrp_paise;
}

function skuOut(s: Sku, storeId: string | null = null) {
  return {
    ...s,
    pack_label: packLabel(s),
    price_paise: resolvedPrice(s, storeId, today()),
    stock_qty: null,
  };
}

function productOut(p: Product) {
  return { ...p };
}

function claimOut(c: Claim) {
  return { ...c, pest_or_disease: db.pests.find((p) => p.id === c.pest_or_disease_id) ?? null };
}

function priceOut(p: Price) {
  const sku = db.skus.find((s) => s.id === p.sku_id);
  return { ...p, mrp_paise: sku?.mrp_paise ?? 0 };
}

function checkVersion(row: { version: number }, body: Json): MockResult | null {
  if (typeof body.version === "number" && body.version !== row.version)
    return problem(409, "version_conflict", "Stale version.", { current_version: row.version });
  return null;
}

// ---- products / SKUs ---------------------------------------------------------------------
function validateProduct(body: Json, partial: boolean): MockResult | null {
  const has = (k: string) => k in body;
  for (const k of ["name", "brand"]) {
    if (!partial || has(k)) {
      const v = str(body[k])?.trim() ?? "";
      if (!v) return invalid(k, "Field required");
    }
  }
  if ((!partial || has("category")) && !CATEGORIES.includes(String(body.category)))
    return invalid("category", "Input should be a known category");
  if ((!partial || has("gst_rate_bp")) && !GST.includes(Number(body.gst_rate_bp)))
    return invalid("gst_rate_bp", "GST rate must be 0, 5, 12, 18 or 28 %");
  if (has("hsn") && body.hsn !== null && body.hsn !== "" && !HSN.test(String(body.hsn)))
    return invalid("hsn", "HSN must have 4, 6 or 8 digits");
  return null;
}

function productExists(brand: string, name: string, exceptId?: string): boolean {
  return db.products.some(
    (p) =>
      p.id !== exceptId &&
      p.brand.toLowerCase() === brand.toLowerCase() &&
      p.name.toLowerCase() === name.toLowerCase(),
  );
}

function createProduct(body: Json): MockResult {
  const bad = validateProduct(body, false);
  if (bad) return bad;
  const name = String(body.name).trim();
  const brand = String(body.brand).trim();
  if (productExists(brand, name)) return problem(409, "product_exists", "Product already exists.");
  const p: Product = {
    id: newId("prod"),
    tenant_id: TENANT,
    name,
    brand,
    own_brand: body.own_brand === true,
    category: String(body.category),
    hsn: optStr(body.hsn),
    gst_rate_bp: Number(body.gst_rate_bp),
    description: optStr(body.description),
    active_ingredient: optStr(body.active_ingredient),
    formulation: optStr(body.formulation),
    names: {},
    image_uri: null,
    active: body.active !== false,
    created_at: now(),
    updated_at: now(),
    version: 1,
  };
  db.products.push(p);
  return ok(productOut(p), 201);
}

function updateProduct(id: string, body: Json): MockResult {
  const p = db.products.find((x) => x.id === id);
  if (!p) return notFound("Product");
  const conflict = checkVersion(p, body);
  if (conflict) return conflict;
  const bad = validateProduct(body, true);
  if (bad) return bad;
  const name = "name" in body ? String(body.name).trim() : p.name;
  const brand = "brand" in body ? String(body.brand).trim() : p.brand;
  if (productExists(brand, name, p.id))
    return problem(409, "product_exists", "Product already exists.");
  Object.assign(p, {
    name,
    brand,
    ...("own_brand" in body ? { own_brand: body.own_brand === true } : {}),
    ...("category" in body ? { category: String(body.category) } : {}),
    ...("hsn" in body ? { hsn: optStr(body.hsn) } : {}),
    ...("gst_rate_bp" in body ? { gst_rate_bp: Number(body.gst_rate_bp) } : {}),
    ...("active_ingredient" in body ? { active_ingredient: optStr(body.active_ingredient) } : {}),
    ...("formulation" in body ? { formulation: optStr(body.formulation) } : {}),
    ...("description" in body ? { description: optStr(body.description) } : {}),
    ...("active" in body ? { active: body.active !== false } : {}),
    updated_at: now(),
    version: p.version + 1,
  });
  return ok(productOut(p));
}

function validateSku(body: Json, partial: boolean): MockResult | null {
  const has = (k: string) => k in body;
  if ((!partial || has("pack_size_value")) && !isDecimalPositive(body.pack_size_value))
    return invalid("pack_size_value", "Input should be greater than 0");
  if ((!partial || has("pack_size_unit")) && !PACK_UNITS.includes(String(body.pack_size_unit)))
    return invalid("pack_size_unit", "Input should be a pack unit");
  if ((!partial || has("mrp_paise")) && !(isInt(body.mrp_paise) && Number(body.mrp_paise) >= 0))
    return invalid("mrp_paise", "Input should be a non-negative integer");
  return null;
}

function barcodeTaken(barcode: string | null, exceptId?: string): boolean {
  return barcode !== null && db.skus.some((s) => s.id !== exceptId && s.barcode === barcode);
}

function createSku(body: Json): MockResult {
  const bad = validateSku(body, false);
  if (bad) return bad;
  if (!db.products.some((p) => p.id === body.product_id)) return notFound("Product");
  const barcode = optStr(body.barcode);
  if (barcodeTaken(barcode)) return problem(409, "barcode_exists", "Barcode already used.");
  const s: Sku = {
    id: newId("sku"),
    product_id: String(body.product_id),
    pack_size_value: toDecimal(body.pack_size_value),
    pack_size_unit: String(body.pack_size_unit),
    barcode,
    mrp_paise: Number(body.mrp_paise),
    active: body.active !== false,
    created_at: now(),
    updated_at: now(),
    version: 1,
  };
  db.skus.push(s);
  return ok(skuOut(s), 201);
}

function updateSku(id: string, body: Json): MockResult {
  const s = db.skus.find((x) => x.id === id);
  if (!s) return notFound("SKU");
  const conflict = checkVersion(s, body);
  if (conflict) return conflict;
  const bad = validateSku(body, true);
  if (bad) return bad;
  if ("barcode" in body && barcodeTaken(optStr(body.barcode), s.id))
    return problem(409, "barcode_exists", "Barcode already used.");
  Object.assign(s, {
    ...("pack_size_value" in body ? { pack_size_value: toDecimal(body.pack_size_value) } : {}),
    ...("pack_size_unit" in body ? { pack_size_unit: String(body.pack_size_unit) } : {}),
    ...("barcode" in body ? { barcode: optStr(body.barcode) } : {}),
    ...("mrp_paise" in body ? { mrp_paise: Number(body.mrp_paise) } : {}),
    ...("active" in body ? { active: body.active !== false } : {}),
    updated_at: now(),
    version: s.version + 1,
  });
  return ok(skuOut(s));
}

function listProducts(q: URLSearchParams): MockResult {
  const text = (q.get("q") ?? "").trim().toLowerCase();
  const category = q.get("category");
  const own = q.get("own_brand");
  const includeInactive = q.get("include_inactive") === "true";
  const storeId = q.get("store_id");
  if (category && !CATEGORIES.includes(category)) return invalid("category", "Unknown category");
  const items = db.products
    .filter((p) => includeInactive || p.active)
    .filter((p) => !category || p.category === category)
    .filter((p) => own === null || p.own_brand === (own === "true"))
    .filter(
      (p) =>
        !text ||
        [p.name, p.brand, p.active_ingredient ?? ""].some((v) => v.toLowerCase().includes(text)),
    )
    .map((p) => ({
      ...productOut(p),
      skus: db.skus
        .filter((s) => s.product_id === p.id)
        .sort((a, b) => Number(a.pack_size_value) - Number(b.pack_size_value))
        .map((s) => skuOut(s, storeId)),
    }));
  return ok({ items, next_cursor: null });
}

// ---- label claims ------------------------------------------------------------------------
function validateClaimFields(body: Json, partial: boolean): MockResult | null {
  const has = (k: string) => k in body;
  if (!partial || has("dose_per_acre")) {
    const v = str(body.dose_per_acre)?.trim() ?? "";
    if (!v || v.length > 120) return invalid("dose_per_acre", "Field required");
  }
  if ((!partial || has("dose_value")) && !isDecimalPositive(body.dose_value))
    return invalid("dose_value", "Input should be greater than 0");
  if ((!partial || has("dose_unit")) && !DOSE_UNITS.includes(String(body.dose_unit)))
    return invalid("dose_unit", "Input should be a dose unit");
  if ((!partial || has("phi_days")) && !(isInt(body.phi_days) && Number(body.phi_days) >= 0))
    return invalid("phi_days", "Input should be greater than or equal to 0");
  if (!partial || has("source_ref")) {
    const v = str(body.source_ref)?.trim() ?? "";
    if (!v || v.length > 200) return invalid("source_ref", "Field required");
  }
  if (
    has("efficacy_tier") &&
    body.efficacy_tier !== null &&
    !(
      isInt(body.efficacy_tier) &&
      Number(body.efficacy_tier) >= 1 &&
      Number(body.efficacy_tier) <= 3
    )
  )
    return invalid("efficacy_tier", "Input should be 1, 2 or 3");
  return null;
}

function claimRules(skuId: string, cropId: string, pestId: string): MockResult | null {
  const sku = db.skus.find((s) => s.id === skuId);
  if (!sku) return notFound("SKU");
  const crop = db.crops.find((c) => c.id === cropId);
  if (!crop) return notFound("Crop");
  const pest = db.pests.find((p) => p.id === pestId);
  if (!pest) return notFound("Pest or disease");
  const product = db.products.find((p) => p.id === sku.product_id);
  if (
    (pest.type === "pest" || pest.type === "disease") &&
    !CLAIM_CATEGORIES.includes(product?.category ?? "")
  )
    return problem(
      422,
      "claim_category_invalid",
      "This product category cannot carry a pest or disease claim.",
    );
  if (pest.crop_id !== null && pest.crop_id !== cropId)
    return problem(422, "pest_not_for_crop", "This pest or disease does not occur on the crop.");
  return null;
}

const approvedFor = (skuId: string, cropId: string, pestId: string) =>
  db.claims.find(
    (c) =>
      c.status === "approved" &&
      c.sku_id === skuId &&
      c.crop_id === cropId &&
      c.pest_or_disease_id === pestId,
  );

function claimFromBody(body: Json, base: Partial<Claim>): Claim {
  const t = now();
  return {
    id: newId("claim"),
    sku_id: String(body.sku_id ?? base.sku_id),
    crop_id: String(body.crop_id ?? base.crop_id),
    pest_or_disease_id: String(body.pest_or_disease_id ?? base.pest_or_disease_id),
    dose_per_acre: String(body.dose_per_acre ?? base.dose_per_acre).trim(),
    dose_value: "dose_value" in body ? toDecimal(body.dose_value) : (base.dose_value ?? null),
    dose_unit: "dose_unit" in body ? String(body.dose_unit) : (base.dose_unit ?? null),
    dose_per_tank_15l:
      "dose_per_tank_15l" in body
        ? optStr(body.dose_per_tank_15l)
        : (base.dose_per_tank_15l ?? null),
    phi_days: "phi_days" in body ? Number(body.phi_days) : (base.phi_days ?? null),
    ppe_text: "ppe_text" in body ? optStr(body.ppe_text) : (base.ppe_text ?? null),
    safety_text: "safety_text" in body ? optStr(body.safety_text) : (base.safety_text ?? null),
    source_ref: String(body.source_ref ?? base.source_ref).trim(),
    efficacy_tier:
      "efficacy_tier" in body
        ? body.efficacy_tier === null
          ? null
          : Number(body.efficacy_tier)
        : (base.efficacy_tier ?? null),
    status: "draft",
    approved_by: null,
    approved_at: null,
    retired_by: null,
    retired_at: null,
    supersedes_id: base.id ?? null,
    created_at: t,
    updated_at: t,
    version: 1,
  };
}

function createClaim(body: Json): MockResult {
  const bad = validateClaimFields(body, false);
  if (bad) return bad;
  const skuId = String(body.sku_id ?? "");
  const cropId = String(body.crop_id ?? "");
  const pestId = String(body.pest_or_disease_id ?? "");
  const rule = claimRules(skuId, cropId, pestId);
  if (rule) return rule;
  if (approvedFor(skuId, cropId, pestId))
    return problem(
      409,
      "claim_duplicate",
      "An approved claim exists; edit it to create a new version.",
    );
  const c = claimFromBody(body, {});
  db.claims.push(c);
  return ok(claimOut(c), 201);
}

function updateClaim(id: string, body: Json): MockResult {
  const c = db.claims.find((x) => x.id === id);
  if (!c) return notFound("Label claim");
  const conflict = checkVersion(c, body);
  if (conflict) return conflict;
  if (c.status === "retired") return problem(409, "claim_retired", "Retired claims cannot change.");
  const fields = { ...body };
  delete fields.sku_id;
  delete fields.crop_id;
  delete fields.pest_or_disease_id;
  delete fields.version;
  const bad = validateClaimFields(fields, true);
  if (bad) return bad;
  if (c.status === "approved") {
    // Approved claims are immutable: the edit becomes a new draft version.
    const draft = claimFromBody(fields, c);
    db.claims.push(draft);
    return ok(claimOut(draft));
  }
  const next = claimFromBody(fields, c);
  Object.assign(c, {
    dose_per_acre: next.dose_per_acre,
    dose_value: next.dose_value,
    dose_unit: next.dose_unit,
    dose_per_tank_15l: next.dose_per_tank_15l,
    phi_days: next.phi_days,
    ppe_text: next.ppe_text,
    safety_text: next.safety_text,
    source_ref: next.source_ref,
    efficacy_tier: next.efficacy_tier,
    updated_at: now(),
    version: c.version + 1,
  });
  return ok(claimOut(c));
}

function approveClaim(id: string, actorId: string): MockResult {
  const c = db.claims.find((x) => x.id === id);
  if (!c) return notFound("Label claim");
  if (c.status !== "draft") return problem(409, "claim_not_draft", "Only drafts can be approved.");
  const current = approvedFor(c.sku_id, c.crop_id, c.pest_or_disease_id);
  if (current && current.id !== c.supersedes_id)
    return problem(
      409,
      "claim_duplicate",
      "Another approved claim exists for this SKU, crop and pest.",
    );
  const t = now();
  if (current)
    Object.assign(current, {
      status: "retired",
      retired_by: actorId,
      retired_at: t,
      updated_at: t,
      version: current.version + 1,
    });
  Object.assign(c, {
    status: "approved",
    approved_by: actorId,
    approved_at: t,
    updated_at: t,
    version: c.version + 1,
  });
  return ok(claimOut(c));
}

function retireClaim(id: string, actorId: string): MockResult {
  const c = db.claims.find((x) => x.id === id);
  if (!c) return notFound("Label claim");
  if (c.status === "retired") return problem(409, "claim_retired", "Already retired.");
  const t = now();
  Object.assign(c, {
    status: "retired",
    retired_by: actorId,
    retired_at: t,
    updated_at: t,
    version: c.version + 1,
  });
  return ok(claimOut(c));
}

function rootOf(c: Claim): string {
  let cur: Claim | undefined = c;
  for (let i = 0; i < 100 && cur?.supersedes_id; i++) {
    const prev: Claim | undefined = db.claims.find((x) => x.id === cur?.supersedes_id);
    if (!prev) break;
    cur = prev;
  }
  return cur?.id ?? c.id;
}

function claimHistory(id: string): MockResult {
  const c = db.claims.find((x) => x.id === id);
  if (!c) return notFound("Label claim");
  const root = rootOf(c);
  const items = db.claims
    .filter((x) => rootOf(x) === root)
    .sort((a, b) => b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id))
    .map(claimOut);
  return ok({ items });
}

function listClaims(q: URLSearchParams, role: string): MockResult {
  const asked = q.get("status") ?? "approved";
  if (!["draft", "approved", "retired", "all"].includes(asked))
    return invalid("status", "Unknown status");
  const status = CLAIM_MAINTAIN.includes(role) ? asked : "approved";
  const items = db.claims
    .filter((c) => status === "all" || c.status === status)
    .filter((c) => !q.get("crop_id") || c.crop_id === q.get("crop_id"))
    .filter((c) => !q.get("pest_id") || c.pest_or_disease_id === q.get("pest_id"))
    .filter((c) => !q.get("sku_id") || c.sku_id === q.get("sku_id"))
    .sort((a, b) => a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id))
    .map(claimOut);
  return ok({ items, next_cursor: null });
}

function recommendable(q: URLSearchParams): MockResult {
  const cropId = q.get("crop_id");
  const pestId = q.get("pest_id");
  if (!cropId)
    return problem(422, "validation_error", "crop_id is required.", {
      errors: [{ loc: ["query", "crop_id"], msg: "Field required", type: "missing" }],
    });
  if (!pestId)
    return problem(422, "validation_error", "pest_id is required.", {
      errors: [{ loc: ["query", "pest_id"], msg: "Field required", type: "missing" }],
    });
  const items = db.claims
    .filter(
      (c) => c.status === "approved" && c.crop_id === cropId && c.pest_or_disease_id === pestId,
    )
    .flatMap((c) => {
      const sku = db.skus.find((s) => s.id === c.sku_id && s.active);
      const product = sku && db.products.find((p) => p.id === sku.product_id && p.active);
      if (!sku || !product) return [];
      return [
        {
          sku_id: sku.id,
          product_id: product.id,
          product_name: product.name,
          brand: product.brand,
          own_brand: product.own_brand,
          pack_label: packLabel(sku),
          mrp_paise: sku.mrp_paise,
          label_claim_id: c.id,
          dose_per_acre: c.dose_per_acre,
          dose_value: c.dose_value,
          dose_unit: c.dose_unit,
          dose_per_tank_15l: c.dose_per_tank_15l,
          phi_days: c.phi_days,
          ppe_text: c.ppe_text,
          safety_text: c.safety_text,
          efficacy_tier: c.efficacy_tier,
        },
      ];
    })
    .sort(
      (a, b) =>
        Number(b.own_brand) - Number(a.own_brand) ||
        (a.efficacy_tier ?? 9) - (b.efficacy_tier ?? 9) ||
        a.product_name.localeCompare(b.product_name),
    );
  return ok({ items });
}

// ---- price lists -------------------------------------------------------------------------
const overlaps = (a: { from: string; to: string | null }, b: { from: string; to: string | null }) =>
  a.from <= (b.to ?? "9999-12-31") && b.from <= (a.to ?? "9999-12-31");

function listPrices(q: URLSearchParams): MockResult {
  const storeId = q.get("store_id");
  const at = q.get("at");
  const skuId = q.get("sku_id");
  if (storeId && !db.stores.some((s) => s.id === storeId)) return notFound("Store");
  const items = db.prices
    .filter((p) => p.store_id === (storeId || null))
    .filter((p) => !at || inForce(p, at))
    .filter((p) => !skuId || p.sku_id === skuId)
    .sort(
      (a, b) =>
        a.sku_id.localeCompare(b.sku_id) || b.effective_from.localeCompare(a.effective_from),
    )
    .map(priceOut);
  return ok({ items });
}

function putPrices(body: Json): MockResult {
  const storeId =
    body.store_id === null || body.store_id === undefined ? null : String(body.store_id);
  if (storeId !== null && !db.stores.some((s) => s.id === storeId)) return notFound("Store");
  const items = Array.isArray(body.items) ? (body.items as Json[]) : null;
  if (!items) return invalid("items", "Field required");
  const rows: Json[] = [];
  const parsed = items.map((it, index) => ({
    index,
    sku_id: String(it.sku_id ?? ""),
    price_paise: it.price_paise,
    from: String(it.effective_from ?? ""),
    to:
      it.effective_to === null || it.effective_to === undefined || it.effective_to === ""
        ? null
        : String(it.effective_to),
  }));
  for (const it of parsed) {
    if (!isInt(it.price_paise) || Number(it.price_paise) < 0)
      return problem(422, "validation_error", "Request validation failed.", {
        errors: [
          {
            loc: ["body", "items", String(it.index), "price_paise"],
            msg: "Input should be a non-negative integer",
            type: "value_error",
          },
        ],
      });
    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(it.from) ||
      (it.to !== null && (!/^\d{4}-\d{2}-\d{2}$/.test(it.to) || it.to < it.from))
    )
      return problem(422, "validation_error", "Request validation failed.", {
        errors: [
          {
            loc: ["body", "items", String(it.index), "effective_to"],
            msg: "effective_to must not be before effective_from",
            type: "value_error",
          },
        ],
      });
    if (!db.skus.some((s) => s.id === it.sku_id)) return notFound("SKU");
  }
  for (const it of parsed) {
    const sku = db.skus.find((s) => s.id === it.sku_id);
    if (sku && Number(it.price_paise) > sku.mrp_paise)
      rows.push({ index: it.index, sku_id: it.sku_id, code: "price_above_mrp" });
  }
  if (rows.length)
    return problem(422, "price_above_mrp", "The price must not exceed the MRP.", { rows });
  for (const it of parsed) {
    const existing = db.prices.find(
      (p) =>
        p.sku_id === it.sku_id &&
        p.store_id === storeId &&
        p.effective_from !== it.from &&
        !parsed.some((o) => o.sku_id === p.sku_id && o.from === p.effective_from) &&
        overlaps({ from: p.effective_from, to: p.effective_to }, it),
    );
    const sibling = parsed.find((o) => o !== it && o.sku_id === it.sku_id && overlaps(o, it));
    if (existing || sibling)
      rows.push({
        index: it.index,
        sku_id: it.sku_id,
        code: "price_overlap",
        ...(existing ? { conflicting_id: existing.id } : {}),
      });
  }
  if (rows.length)
    return problem(409, "price_overlap", "Effective ranges overlap for the same SKU and store.", {
      rows,
    });
  const out: Price[] = parsed.map((it) => {
    const found = db.prices.find(
      (p) => p.sku_id === it.sku_id && p.store_id === storeId && p.effective_from === it.from,
    );
    if (found) {
      Object.assign(found, {
        price_paise: Number(it.price_paise),
        effective_to: it.to,
        version: found.version + 1,
      });
      return found;
    }
    const row: Price = {
      id: newId("price"),
      sku_id: it.sku_id,
      store_id: storeId,
      price_paise: Number(it.price_paise),
      effective_from: it.from,
      effective_to: it.to,
      version: 1,
    };
    db.prices.push(row);
    return row;
  });
  return ok({ items: out.map(priceOut) });
}

// ---- CSV import / export ------------------------------------------------------------------
export const PRODUCT_COLUMNS = [
  "brand",
  "product_name",
  "category",
  "own_brand",
  "hsn",
  "gst_rate_percent",
  "active_ingredient",
  "formulation",
  "pack_size_value",
  "pack_size_unit",
  "barcode",
  "mrp_paise",
  "active",
];
export const CLAIM_COLUMNS = [
  "id",
  "status",
  "sku_barcode",
  "crop_code",
  "pest_code",
  "dose_per_acre",
  "dose_value",
  "dose_unit",
  "dose_per_tank_15l",
  "phi_days",
  "ppe_text",
  "safety_text",
  "source_ref",
  "efficacy_tier",
];

export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') {
        cell += '"';
        i++;
      } else if (ch === '"') quoted = false;
      else cell += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ",") {
      row.push(cell);
      cell = "";
    } else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && text[i + 1] === "\n") i++;
      row.push(cell);
      rows.push(row);
      row = [];
      cell = "";
    } else cell += ch;
  }
  if (cell !== "" || row.length) {
    row.push(cell);
    rows.push(row);
  }
  return rows.filter((r) => r.some((c) => c.trim() !== ""));
}

const csvCell = (v: unknown) => {
  const s = v === null || v === undefined ? "" : String(v);
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const csvLine = (cells: unknown[]) => cells.map(csvCell).join(",");

function exportCsv(kind: string): MockResult {
  let lines: string[];
  if (kind === "products") {
    lines = [csvLine(PRODUCT_COLUMNS)];
    for (const p of db.products)
      for (const s of db.skus.filter((x) => x.product_id === p.id))
        lines.push(
          csvLine([
            p.brand,
            p.name,
            p.category,
            p.own_brand,
            p.hsn,
            p.gst_rate_bp / 100,
            p.active_ingredient,
            p.formulation,
            Number(s.pack_size_value),
            s.pack_size_unit,
            s.barcode,
            s.mrp_paise,
            s.active && p.active,
          ]),
        );
  } else if (kind === "label_claims") {
    lines = [csvLine(CLAIM_COLUMNS)];
    for (const c of db.claims) {
      const sku = db.skus.find((s) => s.id === c.sku_id);
      const crop = db.crops.find((x) => x.id === c.crop_id);
      const pest = db.pests.find((x) => x.id === c.pest_or_disease_id);
      lines.push(
        csvLine([
          c.id,
          c.status,
          sku?.barcode,
          crop?.code,
          pest?.code,
          c.dose_per_acre,
          c.dose_value,
          c.dose_unit,
          c.dose_per_tank_15l,
          c.phi_days,
          c.ppe_text,
          c.safety_text,
          c.source_ref,
          c.efficacy_tier,
        ]),
      );
    }
  } else return invalid("kind", "Input should be 'products' or 'label_claims'");
  return {
    status: 200,
    text: lines.join("\n") + "\n",
    headers: {
      "content-type": "text/csv; charset=utf-8",
      "content-disposition": `attachment; filename="${kind}.csv"`,
    },
  };
}

interface RowError {
  row: number;
  column: string | null;
  code: string;
  message: string;
}

function importCsv(kind: "products" | "label_claims", body: Json): MockResult {
  const dryRun = body.dry_run !== false;
  const rows = parseCsv(String(body.csv ?? ""));
  const errors: RowError[] = [];
  const header = (rows[0] ?? []).map((h) => h.trim());
  const required = kind === "products" ? PRODUCT_COLUMNS : CLAIM_COLUMNS.slice(2);
  for (const col of required)
    if (!header.includes(col))
      errors.push({
        row: 1,
        column: col,
        code: "missing_column",
        message: `Missing column ${col}`,
      });
  const data = rows.slice(1);
  const report = (created: number, updated: number, applied: boolean, okRows: number) =>
    ok({
      kind,
      dry_run: dryRun,
      applied,
      rows_total: data.length,
      rows_ok: okRows,
      created,
      updated,
      errors,
    });
  if (errors.length) return report(0, 0, false, 0);
  const get = (r: string[], col: string) => (r[header.indexOf(col)] ?? "").trim();
  const fail = (row: number, column: string | null, code: string, message: string) => {
    errors.push({ row, column, code, message });
  };
  let created = 0;
  let updated = 0;
  const actions: Array<() => void> = [];
  const seenBarcodes = new Set<string>();
  data.forEach((r, i) => {
    const line = i + 2;
    const before = errors.length;
    if (kind === "products") {
      const brand = get(r, "brand");
      const name = get(r, "product_name");
      const category = get(r, "category");
      const hsn = get(r, "hsn");
      const gst = get(r, "gst_rate_percent");
      const value = get(r, "pack_size_value");
      const unit = get(r, "pack_size_unit");
      const barcode = get(r, "barcode");
      const mrp = get(r, "mrp_paise");
      if (!brand) fail(line, "brand", "required", "brand is required");
      if (!name) fail(line, "product_name", "required", "product_name is required");
      if (!CATEGORIES.includes(category))
        fail(line, "category", "invalid_category", `Unknown category ${category}`);
      if (hsn && !HSN.test(hsn)) fail(line, "hsn", "invalid_hsn", "HSN must have 4, 6 or 8 digits");
      if (!GST.includes(Math.round(Number(gst) * 100)) || gst === "")
        fail(line, "gst_rate_percent", "invalid_gst_rate", "GST must be 0, 5, 12, 18 or 28");
      if (!isDecimalPositive(value))
        fail(line, "pack_size_value", "invalid_pack_size", "pack_size_value must be > 0");
      if (!PACK_UNITS.includes(unit))
        fail(line, "pack_size_unit", "invalid_unit", `Unknown unit ${unit}`);
      if (!/^\d+$/.test(mrp))
        fail(line, "mrp_paise", "invalid_mrp", "mrp_paise must be a whole number of paise");
      if (barcode) {
        if (seenBarcodes.has(barcode))
          fail(line, "barcode", "barcode_exists", "Barcode repeated in the file");
        seenBarcodes.add(barcode);
      }
      if (errors.length > before) return;
      const existingProduct = db.products.find((p) => p.brand === brand && p.name === name);
      const existingSku = barcode ? db.skus.find((s) => s.barcode === barcode) : undefined;
      if (existingSku && existingProduct && existingSku.product_id !== existingProduct.id)
        return fail(line, "barcode", "barcode_exists", "Barcode belongs to another product");
      if (existingSku && !existingProduct)
        return fail(line, "barcode", "barcode_exists", "Barcode belongs to another product");
      if (existingSku) updated++;
      else created++;
      actions.push(() => {
        let product = db.products.find((p) => p.brand === brand && p.name === name);
        const fields = {
          category,
          own_brand: get(r, "own_brand").toLowerCase() === "true",
          hsn: hsn || null,
          gst_rate_bp: Math.round(Number(gst) * 100),
          active_ingredient: get(r, "active_ingredient") || null,
          formulation: get(r, "formulation") || null,
        };
        if (!product) {
          const res = createProduct({ name, brand, ...fields, active: true });
          product = res.json as Product;
        } else Object.assign(product, fields, { updated_at: now(), version: product.version + 1 });
        const sku = barcode ? db.skus.find((s) => s.barcode === barcode) : undefined;
        const active = get(r, "active").toLowerCase() !== "false";
        if (sku)
          Object.assign(sku, {
            pack_size_value: toDecimal(value),
            pack_size_unit: unit,
            mrp_paise: Number(mrp),
            active,
            updated_at: now(),
            version: sku.version + 1,
          });
        else
          createSku({
            product_id: product.id,
            pack_size_value: value,
            pack_size_unit: unit,
            barcode: barcode || null,
            mrp_paise: Number(mrp),
            active,
          });
      });
    } else {
      const sku = db.skus.find((s) => s.barcode === get(r, "sku_barcode"));
      const crop = db.crops.find((c) => c.code === get(r, "crop_code"));
      const pest = db.pests.find((p) => p.code === get(r, "pest_code"));
      if (!sku) fail(line, "sku_barcode", "unknown_sku", "No SKU with this barcode");
      if (!crop) fail(line, "crop_code", "unknown_crop", "Unknown crop code");
      if (!pest) fail(line, "pest_code", "unknown_pest", "Unknown pest or disease code");
      const fields: Json = {
        dose_per_acre: get(r, "dose_per_acre"),
        dose_value: get(r, "dose_value"),
        dose_unit: get(r, "dose_unit"),
        dose_per_tank_15l: get(r, "dose_per_tank_15l") || null,
        phi_days: /^\d+$/.test(get(r, "phi_days")) ? Number(get(r, "phi_days")) : -1,
        ppe_text: get(r, "ppe_text") || null,
        safety_text: get(r, "safety_text") || null,
        source_ref: get(r, "source_ref"),
        efficacy_tier: get(r, "efficacy_tier") ? Number(get(r, "efficacy_tier")) : null,
      };
      const bad = validateClaimFields(fields, false);
      if (bad) {
        const e = (bad.json as { errors?: Array<{ loc: string[]; msg: string }> }).errors?.[0];
        fail(line, e?.loc[1] ?? null, "invalid_value", e?.msg ?? "Invalid value");
      }
      if (sku && crop && pest) {
        const rule = claimRules(sku.id, crop.id, pest.id);
        if (rule)
          fail(
            line,
            "pest_code",
            String((rule.json as Json).code),
            String((rule.json as Json).detail),
          );
        else if (approvedFor(sku.id, crop.id, pest.id))
          fail(
            line,
            "pest_code",
            "claim_duplicate",
            "An approved claim exists for this SKU, crop and pest",
          );
      }
      if (errors.length > before || !sku || !crop || !pest) return;
      created++;
      actions.push(() => {
        db.claims.push(
          claimFromBody(
            { ...fields, sku_id: sku.id, crop_id: crop.id, pest_or_disease_id: pest.id },
            {},
          ),
        );
      });
    }
  });
  const okRows = data.length - new Set(errors.map((e) => e.row)).size;
  const apply = !dryRun && errors.length === 0;
  if (apply) actions.forEach((a) => a());
  return report(created, updated, apply, okRows);
}

// ---- router ------------------------------------------------------------------------------
export interface MockActor {
  id: string;
  role: UserRole | string;
}

/** Handles `/catalog/...` (path without the `v1` prefix); null when not a catalogue route. */
export function handleCatalog(
  method: string,
  path: string[],
  query: URLSearchParams,
  body: Json,
  actor: MockActor | null,
): MockResult | null {
  if (path[0] !== "catalog") return null;
  if (!actor) return problem(401, "unauthenticated", "Bearer token required.");
  const role = actor.role;
  const allow = (roles: readonly string[]) => roles.includes(role);
  const [, a, b, c] = path;
  const route = `${method} ${[a, b ? ":id" : null, c].filter(Boolean).join("/")}`;
  const gate = (roles: readonly string[], fn: () => MockResult) =>
    allow(roles) ? fn() : forbidden();

  switch (route) {
    case "GET crops":
      return gate(ALL, () => ok({ items: db.crops }));
    case "GET pests":
      return gate(ALL, () => {
        const cropId = query.get("crop_id");
        return ok({
          items: db.pests.filter((p) => !cropId || p.crop_id === null || p.crop_id === cropId),
        });
      });
    case "GET stores":
      // Store roles see only their own store (the mock store user works at the first one).
      return gate(PRICE_READ, () =>
        ok({
          items:
            role === "store_manager" || role === "accountant" ? db.stores.slice(0, 1) : db.stores,
        }),
      );
    case "GET products":
      return gate(ALL, () => listProducts(query));
    case "POST products":
      return gate(WRITE, () => createProduct(body));
    case "PATCH products/:id":
      return gate(WRITE, () => updateProduct(b ?? "", body));
    case "POST skus":
      return gate(WRITE, () => createSku(body));
    case "PATCH skus/:id":
      return gate(WRITE, () => updateSku(b ?? "", body));
    case "GET barcode/:id":
      return gate(BARCODE, () => {
        const sku = db.skus.find((s) => s.barcode === b);
        const product = sku && db.products.find((p) => p.id === sku.product_id);
        if (!sku || !product) return notFound("SKU");
        return ok({ ...skuOut(sku, query.get("store_id")), product: productOut(product) });
      });
    case "GET label-claims":
      return gate(ALL, () => listClaims(query, role));
    case "POST label-claims":
      return gate(CLAIM_EDIT, () => createClaim(body));
    case "PATCH label-claims/:id":
      return gate(CLAIM_EDIT, () => updateClaim(b ?? "", body));
    case "POST label-claims/:id/approve":
      return gate(CLAIM_APPROVE, () => approveClaim(b ?? "", actor.id));
    case "POST label-claims/:id/retire":
      return gate(CLAIM_RETIRE, () => retireClaim(b ?? "", actor.id));
    case "GET label-claims/:id/history":
      return gate(CLAIM_MAINTAIN, () => claimHistory(b ?? ""));
    case "GET recommendable":
      return gate(ALL, () => recommendable(query));
    case "GET price-lists":
      return gate(PRICE_READ, () => listPrices(query));
    case "PUT price-lists":
      return gate(WRITE, () => putPrices(body));
    case "POST import/:id":
      if (b === "products") return gate(WRITE, () => importCsv("products", body));
      if (b === "label-claims") return gate(CLAIM_EDIT, () => importCsv("label_claims", body));
      return notFound("Import kind");
    case "GET export":
      return gate(EXPORT, () => exportCsv(query.get("kind") ?? ""));
    default:
      return problem(404, "not_found", `No mock for ${method} /catalog/${path.slice(1).join("/")}`);
  }
}
