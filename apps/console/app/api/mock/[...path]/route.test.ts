import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it } from "vitest";
import { GET, MOCK_UNKNOWN_PHONE, PATCH, POST, PUT, resetMockState, roleFromToken } from "./route";

const ctx = (path: string) => ({ params: Promise.resolve({ path: path.split("/") }) });

const post = (path: string, body: unknown) =>
  POST(
    new NextRequest(`http://localhost/api/mock/${path}`, {
      method: "POST",
      body: JSON.stringify(body),
      headers: { "content-type": "application/json" },
    }),
    ctx(path),
  );

describe("in-app mock API (keeps e2e in sync with apps/api shapes)", () => {
  beforeEach(() => resetMockState());

  it("send -> verify -> me happy path", async () => {
    const send = await post("v1/auth/otp/send", { phone: "+919876543210" });
    expect(send.status).toBe(202);
    const sent = await send.json();
    expect(sent).toMatchObject({ channel: "sms", expires_in: 300, resends_left: 3 });
    expect(sent.phone_masked).toBe("+91******3210");

    const verify = await post("v1/auth/otp/verify", { phone: "+919876543210", code: "123456" });
    expect(verify.status).toBe(200);
    const tokens = await verify.json();
    expect(tokens.token_type).toBe("Bearer");
    expect(tokens.user.role).toBe("owner");

    const me = await GET(
      new NextRequest("http://localhost/api/mock/v1/me", {
        headers: { authorization: `Bearer ${tokens.access_token}` },
      }),
      ctx("v1/me"),
    );
    expect(me.status).toBe(200);
    const refresh = await post("v1/auth/refresh", { refresh_token: tokens.refresh_token });
    expect(refresh.status).toBe(200);
  });

  it("wrong code five times locks the number (otp_locked) and blocks resends", async () => {
    await post("v1/auth/otp/send", { phone: "+919876543210" });
    for (let i = 4; i >= 1; i--) {
      const res = await post("v1/auth/otp/verify", { phone: "+919876543210", code: "000000" });
      expect(res.status).toBe(401);
      expect(await res.json()).toMatchObject({ code: "otp_invalid", attempts_left: i });
    }
    const locked = await post("v1/auth/otp/verify", { phone: "+919876543210", code: "000000" });
    expect(locked.status).toBe(423);
    expect(await locked.json()).toMatchObject({ code: "otp_locked", retry_after: 900 });
    const send = await post("v1/auth/otp/send", { phone: "+919876543210" });
    expect(send.status).toBe(423);
  });

  it("fourth resend within the window is rate limited", async () => {
    for (let i = 0; i < 4; i++) {
      const res = await post("v1/auth/otp/send", { phone: "+919876543211" });
      expect(res.status).toBe(202);
    }
    const res = await post("v1/auth/otp/send", { phone: "+919876543211" });
    expect(res.status).toBe(429);
    expect(await res.json()).toMatchObject({ code: "otp_rate_limited" });
  });

  it("validates phones, unknown numbers and unauthenticated /me", async () => {
    expect((await post("v1/auth/otp/send", { phone: "123" })).status).toBe(422);
    expect((await post("v1/auth/otp/send", { phone: MOCK_UNKNOWN_PHONE })).status).toBe(404);
    expect((await post("v1/auth/otp/verify", { phone: "+919000000000", code: "1" })).status).toBe(
      404,
    );
    const me = await GET(new NextRequest("http://localhost/api/mock/v1/me"), ctx("v1/me"));
    expect(me.status).toBe(401);
    expect((await post("v1/auth/logout", { refresh_token: "x" })).status).toBe(204);
  });
});

// ---- WC-005 catalogue (lib/mock/catalog.ts mirrors /v1/catalog/*) -------------------------
type Method = "GET" | "POST" | "PUT" | "PATCH";
const HANDLERS = { GET, POST, PUT, PATCH };

async function call(method: Method, path: string, role: string | null, body?: unknown) {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (role) headers.authorization = `Bearer mock-access-${role}-1`;
  const [pathOnly = ""] = path.split("?");
  const res = await HANDLERS[method](
    new NextRequest(`http://localhost/api/mock/${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    ctx(pathOnly),
  );
  const text = await res.text();
  let json: Record<string, unknown> = {};
  try {
    json = JSON.parse(text) as Record<string, unknown>;
  } catch {
    /* CSV */
  }
  return { status: res.status, json, text, headers: res.headers };
}

type Item = Record<string, unknown>;
const items = (r: { json: Record<string, unknown> }) => r.json.items as Item[];

const claimBody = (over: Record<string, unknown> = {}) => ({
  sku_id: "sku-imida-250",
  crop_id: "crop-paddy",
  pest_or_disease_id: "pest-paddy_bph",
  dose_per_acre: "100 ml",
  dose_value: "100",
  dose_unit: "ml",
  dose_per_tank_15l: "8 ml",
  phi_days: 30,
  ppe_text: "Gloves",
  safety_text: null,
  source_ref: "CIB-TEST-1",
  efficacy_tier: 2,
  ...over,
});

describe("mock catalogue (WC-005 contract)", () => {
  beforeEach(() => resetMockState());

  it("keeps the role in tokens: phone -> role, refresh keeps it, /me reports it", async () => {
    await post("v1/auth/otp/send", { phone: "+919000000008" });
    const tokens = await (
      await post("v1/auth/otp/verify", { phone: "+919000000008", code: "123456" })
    ).json();
    expect(tokens.user.role).toBe("agronomist");
    expect(roleFromToken(tokens.access_token, "access")).toBe("agronomist");
    const refreshed = await (
      await post("v1/auth/refresh", { refresh_token: tokens.refresh_token })
    ).json();
    expect(refreshed.user.role).toBe("agronomist");
    expect(roleFromToken("mock-access-1234", "access")).toBe("owner");
    const me = await call("GET", "v1/me", "agronomist");
    expect(me.json.role).toBe("agronomist");
  });

  it("needs a bearer token and enforces the route roles", async () => {
    expect((await call("GET", "v1/catalog/products", null)).status).toBe(401);
    expect((await call("GET", "v1/catalog/products", "farmer")).status).toBe(200);
    const denied = await call("POST", "v1/catalog/products", "agronomist", {});
    expect(denied.status).toBe(403);
    expect(denied.json.code).toBe("forbidden");
    expect((await call("GET", "v1/catalog/price-lists", "field_officer")).status).toBe(403);
    expect((await call("GET", "v1/catalog/stores", "field_officer")).status).toBe(403);
    expect(items(await call("GET", "v1/catalog/stores", "store_manager"))).toHaveLength(1);
    expect(
      (await call("POST", "v1/catalog/label-claims/claim-tricy-blast/approve", "owner")).status,
    ).toBe(403);
    expect(
      (await call("POST", "v1/catalog/import/products", "agronomist", { csv: "" })).status,
    ).toBe(403);
  });

  it("creates products and SKUs with GST / HSN / barcode rules", async () => {
    const base = { name: "Test", brand: "T", category: "pesticide", gst_rate_bp: 1800 };
    const bad = await call("POST", "v1/catalog/products", "owner", { ...base, gst_rate_bp: 1500 });
    expect(bad.status).toBe(422);
    expect(bad.json.errors).toEqual([expect.objectContaining({ loc: ["body", "gst_rate_bp"] })]);
    expect(
      (await call("POST", "v1/catalog/products", "owner", { ...base, hsn: "38089" })).status,
    ).toBe(422);
    const created = await call("POST", "v1/catalog/products", "owner", {
      ...base,
      hsn: "38089199",
    });
    expect(created.status).toBe(201);
    const dup = await call("POST", "v1/catalog/products", "owner", base);
    expect(dup.json.code).toBe("product_exists");

    const sku = {
      product_id: created.json.id,
      pack_size_value: "500",
      pack_size_unit: "ml",
      mrp_paise: 50000,
    };
    const taken = await call("POST", "v1/catalog/skus", "owner", {
      ...sku,
      barcode: "8901000000011",
    });
    expect(taken.status).toBe(409);
    expect(taken.json.code).toBe("barcode_exists");
    const ok = await call("POST", "v1/catalog/skus", "owner", { ...sku, barcode: "123456789" });
    expect(ok.status).toBe(201);
    expect(ok.json).toMatchObject({ pack_label: "500 ml", price_paise: 50000 });
    const stale = await call("PATCH", `v1/catalog/skus/${ok.json.id as string}`, "owner", {
      version: 7,
      mrp_paise: 1,
    });
    expect(stale.json.code).toBe("version_conflict");
    const scanned = await call("GET", "v1/catalog/barcode/123456789", "store_manager");
    expect(scanned.json.product).toMatchObject({ name: "Test" });

    const list = await call("GET", "v1/catalog/products?q=imidacloprid", "field_officer");
    expect(items(list).map((p) => p.name)).toEqual(["FCC Imida"]);
    const inactive = await call("GET", "v1/catalog/products?include_inactive=true", "owner");
    expect(items(inactive).some((p) => p.active === false)).toBe(true);
  });

  it("validates label claims like the API", async () => {
    const post = (b: unknown) => call("POST", "v1/catalog/label-claims", "agronomist", b);
    expect((await post(claimBody({ dose_value: "0" }))).status).toBe(422);
    expect((await post(claimBody({ phi_days: -1 }))).status).toBe(422);
    expect((await post(claimBody({ source_ref: "" }))).status).toBe(422);
    expect((await post(claimBody({ crop_id: "crop-cotton" }))).json.code).toBe("pest_not_for_crop");
    expect((await post(claimBody({ sku_id: "sku-dap-50" }))).json.code).toBe(
      "claim_category_invalid",
    );
    expect((await post(claimBody({ sku_id: "sku-imida-100" }))).json.code).toBe("claim_duplicate");
    // Polyphagous pests fit any crop; fertiliser may carry a nutrient claim.
    expect(
      (await post(claimBody({ crop_id: "crop-cotton", pest_or_disease_id: "pest-aphids" }))).status,
    ).toBe(201);
    expect(
      (await post(claimBody({ sku_id: "sku-dap-50", pest_or_disease_id: "pest-zinc_deficiency" })))
        .status,
    ).toBe(201);
    // Non-maintainers only ever see approved claims.
    const officer = await call("GET", "v1/catalog/label-claims?status=draft", "field_officer");
    expect(items(officer).every((c) => c.status === "approved")).toBe(true);
  });

  it("guardrail: only approved claims are recommendable; retire removes; versions supersede", async () => {
    const rec = async () =>
      items(
        await call(
          "GET",
          "v1/catalog/recommendable?crop_id=crop-paddy&pest_id=pest-paddy_bph",
          "field_officer",
        ),
      ).map((r) => r.sku_id);
    expect(await rec()).toEqual(["sku-imida-100"]);
    const draft = await call("POST", "v1/catalog/label-claims", "owner", claimBody());
    expect(draft.json.status).toBe("draft");
    expect(await rec()).toEqual(["sku-imida-100"]);
    const id = draft.json.id as string;
    const approved = await call("POST", `v1/catalog/label-claims/${id}/approve`, "agronomist");
    expect(approved.json).toMatchObject({ status: "approved", approved_by: "u-agronomist" });
    expect(await rec()).toEqual(["sku-imida-100", "sku-imida-250"]);
    expect(
      (await call("POST", `v1/catalog/label-claims/${id}/approve`, "agronomist")).json.code,
    ).toBe("claim_not_draft");

    // Editing an approved claim makes a new draft; approving it retires the old version.
    const v2 = await call("PATCH", `v1/catalog/label-claims/${id}`, "agronomist", { phi_days: 35 });
    expect(v2.json).toMatchObject({ status: "draft", supersedes_id: id, phi_days: 35 });
    await call("POST", `v1/catalog/label-claims/${v2.json.id as string}/approve`, "agronomist");
    const history = await call("GET", `v1/catalog/label-claims/${id}/history`, "agronomist");
    expect(items(history).map((c) => c.status)).toEqual(["approved", "retired"]);

    const retired = await call(
      "POST",
      `v1/catalog/label-claims/${v2.json.id as string}/retire`,
      "owner",
    );
    expect(retired.json.status).toBe("retired");
    expect(await rec()).toEqual(["sku-imida-100"]);
    expect(
      (await call("PATCH", `v1/catalog/label-claims/${id}`, "owner", { phi_days: 1 })).json.code,
    ).toBe("claim_retired");
    expect((await call("GET", "v1/catalog/recommendable?crop_id=crop-paddy", "owner")).status).toBe(
      422,
    );
  });

  it("price lists: upsert, <= MRP and no overlapping ranges, per row", async () => {
    const above = await call("PUT", "v1/catalog/price-lists", "owner", {
      store_id: null,
      items: [
        {
          sku_id: "sku-tricy-120",
          price_paise: 30000,
          effective_from: "2027-01-01",
          effective_to: null,
        },
        { sku_id: "sku-imida-100", price_paise: 99999, effective_from: "2027-01-01" },
      ],
    });
    expect(above.status).toBe(422);
    expect(above.json).toMatchObject({
      code: "price_above_mrp",
      rows: [{ index: 1, sku_id: "sku-imida-100" }],
    });
    const overlap = await call("PUT", "v1/catalog/price-lists", "owner", {
      store_id: null,
      items: [{ sku_id: "sku-imida-100", price_paise: 20000, effective_from: "2027-01-01" }],
    });
    expect(overlap.status).toBe(409);
    expect(overlap.json).toMatchObject({
      code: "price_overlap",
      rows: [{ index: 0, conflicting_id: "price-1" }],
    });
    // Closing the open range (same effective_from = update) then adding the next one works.
    const ok = await call("PUT", "v1/catalog/price-lists", "director", {
      store_id: null,
      items: [
        {
          sku_id: "sku-imida-100",
          price_paise: 20900,
          effective_from: "2026-05-01",
          effective_to: "2026-12-31",
        },
        { sku_id: "sku-imida-100", price_paise: 21500, effective_from: "2027-01-01" },
      ],
    });
    expect(ok.status).toBe(200);
    expect(items(ok)).toHaveLength(2);
    const at = await call(
      "GET",
      "v1/catalog/price-lists?at=2027-02-01&sku_id=sku-imida-100",
      "accountant",
    );
    expect(items(at).map((r) => r.price_paise)).toEqual([21500]);
    const store = await call("GET", "v1/catalog/price-lists?store_id=store-wgl", "store_manager");
    expect(items(store).map((r) => r.store_id)).toEqual(["store-wgl"]);
  });

  it("CSV import is a dry run by default with row errors; export streams CSV", async () => {
    const exported = await call("GET", "v1/catalog/export?kind=products", "auditor");
    expect(exported.headers.get("content-type")).toContain("text/csv");
    const [header] = exported.text.split("\n");
    expect(header).toBe(
      "brand,product_name,category,own_brand,hsn,gst_rate_percent,active_ingredient,formulation,pack_size_value,pack_size_unit,barcode,mrp_paise,active",
    );
    const csv = [
      header,
      "Acme,Acme Neem,pesticide,false,3808,12,Azadirachtin 1500 ppm,EC,1,l,555000111,65000,true",
      "Acme,Acme Bad,snacks,false,38,7,,,0,box,,x,true",
    ].join("\n");
    const dry = await call("POST", "v1/catalog/import/products", "owner", { csv });
    expect(dry.json).toMatchObject({
      kind: "products",
      dry_run: true,
      applied: false,
      rows_total: 2,
      rows_ok: 1,
    });
    const cols = (dry.json.errors as Item[]).filter((e) => e.row === 3).map((e) => e.column);
    expect(cols).toEqual(
      expect.arrayContaining([
        "category",
        "hsn",
        "gst_rate_percent",
        "pack_size_value",
        "pack_size_unit",
        "mrp_paise",
      ]),
    );
    expect((dry.json.errors as Item[]).some((e) => e.row === 2)).toBe(false);
    const refused = await call("POST", "v1/catalog/import/products", "owner", {
      csv,
      dry_run: false,
    });
    expect(refused.json.applied).toBe(false);
    const good = await call("POST", "v1/catalog/import/products", "owner", {
      csv: csv.split("\n").slice(0, 2).join("\n"),
      dry_run: false,
    });
    expect(good.json).toMatchObject({ applied: true, created: 1 });
    expect(items(await call("GET", "v1/catalog/products?q=neem", "owner"))).toHaveLength(1);

    const claims = await call("POST", "v1/catalog/import/label-claims", "agronomist", {
      csv: "sku_barcode,crop_code,pest_code,dose_per_acre,dose_value,dose_unit,dose_per_tank_15l,phi_days,ppe_text,safety_text,source_ref,efficacy_tier\n555000111,cotton,aphids,1 l,1,l,,7,,,CIB-X,\n",
      dry_run: false,
    });
    expect(claims.json).toMatchObject({ kind: "label_claims", applied: true, created: 1 });
    const drafts = await call(
      "GET",
      "v1/catalog/label-claims?status=draft&crop_id=crop-cotton",
      "agronomist",
    );
    expect(items(drafts)).toHaveLength(1);
  });
});
