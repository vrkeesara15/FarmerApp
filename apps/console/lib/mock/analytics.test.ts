import { describe, expect, it } from "vitest";
import type {
  ChurnListOut,
  DayReplayOut,
  Farmer360Out,
  FarmerDirectoryOut,
  FieldTeamOut,
  OwnerHomeOut,
  SavedSegment,
  SegmentPreviewOut,
  StoreDetailOut,
  StoreRow,
} from "../analytics";
import type { ClusterList } from "../clusters";
import { handleAnalytics, handleClusters, MOCK_OFFICERS, MOCK_STORES } from "./analytics";
import { MOCK_EVIDENCE_FARMER_IDS, MOCK_EVIDENCE_OFFICER_IDS } from "./flags";

const as = (role: string) => ({ id: `u-${role}`, role });
const get = (path: string, role = "owner", qs = "") =>
  handleAnalytics("GET", path.split("/"), new URLSearchParams(qs), as(role))!;

describe("mock /v1/analytics (shapes of apps/api/openapi.yaml)", () => {
  it("ignores other paths", () => {
    expect(
      handleAnalytics("GET", ["catalog", "crops"], new URLSearchParams(), as("owner")),
    ).toBeNull();
  });

  it("owner home: 7 KPIs in API order, echoed filters, 24 stores with bands", () => {
    const r = get("analytics/owner-home", "owner", "from=2026-08-01&to=2026-08-30");
    expect(r.status).toBe(200);
    const body = r.json as OwnerHomeOut;
    expect(body.kpis.map((k) => k.key)).toEqual([
      "revenue",
      "own_brand_share",
      "credit_outstanding",
      "credit_overdue",
      "verified_visits",
      "active_farmers",
      "open_flags",
    ]);
    expect(body.filters).toMatchObject({
      from: "2026-08-01",
      to: "2026-08-30",
      days: 30,
      scope: "tenant",
    });
    expect(body.granularity).toBe("day");
    expect(body.series.revenue).toHaveLength(30);
    expect(body.stores).toHaveLength(24);
    expect(new Set(body.stores.map((s) => s.band)).size).toBeGreaterThan(1);
    expect(body.officers_top).toHaveLength(5);
    expect(body.high_severity_flags.length).toBeGreaterThan(0);
    expect(body.crop_health_alerts).toEqual([]);
    for (const k of body.kpis)
      expect(Number.isInteger(k.unit === "paise" ? k.value : 0)).toBe(true);
  });

  it("weekly buckets above 31 days; same figures on every call", () => {
    const a = get("analytics/owner-home", "owner", "from=2026-06-01&to=2026-08-30")
      .json as OwnerHomeOut;
    const b = get("analytics/owner-home", "owner", "from=2026-06-01&to=2026-08-30")
      .json as OwnerHomeOut;
    expect(a.granularity).toBe("week");
    expect(a.series.revenue).toHaveLength(13);
    expect(a.kpis[0]!.value).toBe(b.kpis[0]!.value);
  });

  it("AN-011 problems: bad range 422, unknown id 404, store outside cluster 422", () => {
    expect(get("analytics/owner-home", "owner", "from=2026-09-10&to=2026-09-01").status).toBe(422);
    expect(get("analytics/owner-home", "owner", "from=2024-01-01&to=2026-09-01").status).toBe(422);
    expect(get("analytics/owner-home", "owner", "store_id=nope").status).toBe(404);
    const bad = get("analytics/owner-home", "owner", "cluster_id=cluster-ka&store_id=store-wgl");
    expect(bad.status).toBe(422);
    expect((bad.json as { code: string }).code).toBe("invalid_filter_combination");
    const off = get("analytics/field-team", "owner", "store_id=store-knr&officer_id=off-wgl-1");
    expect((off.json as { code: string }).code).toBe("invalid_filter_combination");
  });

  it("filters narrow the figures", () => {
    const all = get("analytics/stores", "owner").json as { items: unknown[] };
    const tg = get("analytics/stores", "owner", "cluster_id=cluster-tg").json as {
      items: unknown[];
    };
    expect(all.items).toHaveLength(24);
    expect(tg.items).toHaveLength(8);
  });

  it("roles: store manager own store, no km, 403 on the replay; officer own row", () => {
    const home = get("analytics/owner-home", "store_manager").json as OwnerHomeOut;
    expect(home.filters.scope).toBe("store");
    expect(home.stores.map((s) => s.id)).toEqual(["store-wgl"]);
    const team = get("analytics/field-team", "store_manager").json as FieldTeamOut;
    expect(team.location_visible).toBe(false);
    expect(team.items.every((r) => r.km_per_day === null)).toBe(true);
    expect(
      get("analytics/officers/off-wgl-1/day-replay", "store_manager", "date=2026-09-10").status,
    ).toBe(403);
    const own = get("analytics/field-team", "field_officer").json as FieldTeamOut;
    expect(own.items.map((r) => r.officer_id)).toEqual(["off-wgl-1"]);
    expect(get("analytics/officers/off-knr-1", "field_officer").status).toBe(404);
    expect(get("analytics/owner-home", "field_officer").status).toBe(403);
    expect(get("analytics/stores", "accountant").status).toBe(200);
    expect(get("analytics/farmers", "agronomist").status).toBe(403);
  });

  it("day replay: track split at the gap, stops, visits by status, gaps with and without a reason", () => {
    const r = get("analytics/officers/off-wgl-1/day-replay", "owner", "date=2026-09-10");
    const d = r.json as DayReplayOut;
    expect(d.track.type).toBe("MultiLineString");
    expect(d.track.coordinates.length).toBe(3);
    expect(d.visits.map((v) => v.status)).toEqual([
      "verified",
      "partial",
      "unverified",
      "verified",
    ]);
    expect(d.visits.map((v) => v.colour)).toEqual(["green", "amber", "red", "green"]);
    expect(d.gaps.map((g) => g.reason)).toEqual([null, "Phone battery died"]);
    expect(d.stops).toHaveLength(1);
    expect(d.timeline[0]!.type).toBe("duty_start");
    expect(d.timeline.at(-1)!.type).toBe("duty_end");
    const sorted = [...d.timeline].sort((a, b) => a.ts.localeCompare(b.ts));
    expect(d.timeline).toEqual(sorted);
    // No points inside a gap.
    for (const g of d.gaps)
      expect(d.points.some((p) => p.ts > g.start && p.ts < g.end)).toBe(false);
    // A Sunday has no duty.
    const sunday = get("analytics/officers/off-wgl-1/day-replay", "owner", "date=2026-09-13")
      .json as DayReplayOut;
    expect(sunday.points).toEqual([]);
    expect(get("analytics/officers/off-wgl-1/day-replay", "owner").status).toBe(422);
  });

  it("farmers: search, filters, sort and cursor pagination; masked phones", () => {
    const first = get("analytics/farmers", "owner", "limit=20&sort=name")
      .json as FarmerDirectoryOut;
    expect(first.total).toBe(72);
    expect(first.items).toHaveLength(20);
    expect(first.next_cursor).toBe("o20");
    expect(first.items.every((f) => f.phone_masked.startsWith("*********"))).toBe(true);
    const names = first.items.map((f) => f.name);
    expect(names).toEqual([...names].sort((a, b) => a.localeCompare(b)));
    const next = get("analytics/farmers", "owner", "limit=20&sort=name&cursor=o20")
      .json as FarmerDirectoryOut;
    expect(next.items[0]!.id).not.toBe(first.items[0]!.id);
    const search = get("analytics/farmers", "owner", "q=ramesh").json as FarmerDirectoryOut;
    expect(search.items.length).toBeGreaterThan(0);
    expect(search.items.every((f) => f.name.toLowerCase().includes("ramesh"))).toBe(true);
    const risky = get("analytics/farmers", "owner", "credit_risk=high").json as FarmerDirectoryOut;
    expect(risky.items.every((f) => f.credit_risk === "high")).toBe(true);
    expect(get("analytics/farmers", "owner", "sort=bogus").status).toBe(422);
    expect(get("analytics/farmers", "owner", "cursor=zzz").status).toBe(400);
  });

  it("farmer 360 and store detail with P&L by month", () => {
    const f = get("analytics/farmers/farmer-001/360", "owner").json as Farmer360Out;
    expect(f.profile.phone).toMatch(/^\+91/);
    expect(f.farms[0]!.boundary!.type).toBe("Polygon");
    expect(f.consent.history.length).toBeGreaterThan(0);
    expect(get("analytics/farmers/farmer-999/360", "owner").status).toBe(404);
    const s = get("analytics/stores/store-wgl", "owner", "from=2025-10-01&to=2026-09-18")
      .json as StoreDetailOut;
    expect(s.pnl.map((m) => m.month)).toHaveLength(12);
    expect(s.pnl.at(-1)).toMatchObject({ month: "2026-09", partial: true });
    expect(s.pnl[0]).toMatchObject({ month: "2025-10", partial: false });
    for (const m of s.pnl) {
      expect(m.gross_sales_paise - m.discounts_paise).toBe(m.net_sales_paise);
      expect(m.net_sales_paise - m.cogs_paise).toBe(m.gross_margin_paise);
      expect(m.gross_margin_paise - m.write_offs_paise).toBe(m.contribution_paise);
    }
    expect(s.pnl_opex_included).toBe(false);
    expect(get("analytics/stores/store-knr", "store_manager").status).toBe(404);
  });

  it("fixtures: 24 stores in three states, 30 officers", () => {
    expect(MOCK_STORES).toHaveLength(24);
    expect(new Set(MOCK_STORES.map((s) => s.cluster_id)).size).toBe(3);
    expect(MOCK_OFFICERS).toHaveLength(30);
    expect(new Set(MOCK_OFFICERS.map((o) => o.id)).size).toBe(30);
  });
});

describe("mock /v1/clusters and the flag cross-links", () => {
  const clusters = (role: string) => handleClusters("GET", ["clusters"], as(role))!;

  it("names every cluster for tenant-wide roles and scopes the rest (SPEC 2.6)", () => {
    const all = clusters("owner").json as ClusterList;
    expect(all.items.map((c) => c.name)).toEqual(["Telangana", "Karnataka", "Maharashtra"]);
    expect(all.items.reduce((n, c) => n + c.store_ids.length, 0)).toBe(24);
    const head = clusters("cluster_head").json as ClusterList;
    expect(head.items.map((c) => [c.id, c.store_ids.length])).toEqual([["cluster-tg", 8]]);
    const manager = clusters("store_manager").json as ClusterList;
    expect(manager.items.map((c) => c.store_ids)).toEqual([["store-wgl"]]);
    expect((clusters("agronomist").json as ClusterList).items).toEqual([]);
    expect(clusters("farmer").status).toBe(403);
    expect(handleClusters("GET", ["catalog", "stores"], as("owner"))).toBeNull();
  });

  it("owner home lists the inbox's open high-severity flags; their records exist here", () => {
    const home = get("analytics/owner-home").json as OwnerHomeOut;
    expect(home.high_severity_flags.length).toBeGreaterThan(0);
    for (const f of home.high_severity_flags) expect(f.id).toMatch(/^f1a90000-/);
    for (const id of Object.values(MOCK_EVIDENCE_FARMER_IDS))
      expect(get(`analytics/farmers/${id}/360`).status).toBe(200);
    for (const id of Object.values(MOCK_EVIDENCE_OFFICER_IDS))
      expect(get(`analytics/officers/${id}`).status).toBe(200);
  });
});

describe("mock AN-004 segments and AN-005 store fields", () => {
  const call = (method: string, path: string, role = "owner", qs = "", body?: unknown) =>
    handleAnalytics(method, path.split("/"), new URLSearchParams(qs), as(role), body)!;
  const preview = (definition: object, role = "owner") =>
    call("POST", "analytics/segments/preview", role, "", { definition });

  it("previews a definition with counts and every AN-004 breakdown", () => {
    const r = preview({});
    expect(r.status).toBe(200);
    const body = r.json as SegmentPreviewOut;
    expect(body.matched).toBeGreaterThan(0);
    expect(body.consented + body.excluded_no_consent).toBe(body.matched);
    const sum = (f: SegmentPreviewOut["by_acreage_band"]) => f.reduce((n, x) => n + x.count, 0);
    expect(sum(body.by_acreage_band)).toBe(body.matched);
    expect(sum(body.by_spend_band)).toBe(body.matched);
    expect(sum(body.by_last_visit)).toBe(body.matched);
    expect(sum(body.by_consent)).toBe(body.matched);
    expect(sum(body.by_app_usage)).toBe(body.matched);
    expect(body.by_acreage_band.map((f) => f.key)).toEqual(["under_2", "2_5", "5_10", "over_10"]);
    expect(body.churn_window_days).toBe(90);
  });

  it("narrows on criteria and by role scope", () => {
    const all = (preview({}).json as SegmentPreviewOut).matched;
    const big = (preview({ min_acres: 6 }).json as SegmentPreviewOut).matched;
    expect(big).toBeLessThan(all);
    const head = (preview({}, "cluster_head").json as SegmentPreviewOut).matched;
    expect(head).toBeLessThan(all);
    expect(preview({}, "field_officer").status).toBe(403);
  });

  it("saves, renames, lists and deletes a segment; names are unique", () => {
    const created = call("POST", "analytics/segments", "owner", "", {
      name: "Vitest segment",
      definition: { app_user: true },
    });
    expect(created.status).toBe(201);
    const row = created.json as SavedSegment;
    expect(row.last_count).not.toBeNull();
    expect(
      call("POST", "analytics/segments", "owner", "", {
        name: "vitest segment",
        definition: {},
      }).status,
    ).toBe(409);
    expect(
      call("POST", "analytics/segments", "cluster_head", "", { name: "x", definition: {} }).status,
    ).toBe(403);
    const listed = call("GET", "analytics/segments").json as { items: SavedSegment[] };
    expect(listed.items.map((s) => s.id)).toContain(row.id);
    const patched = call("PATCH", `analytics/segments/${row.id}`, "owner", "", {
      name: "Vitest renamed",
    });
    expect((patched.json as SavedSegment).name).toBe("Vitest renamed");
    expect(call("DELETE", `analytics/segments/${row.id}`).status).toBe(204);
    expect(call("GET", `analytics/segments/${row.id}`).status).toBe(404);
  });

  it("lists churn-risk farmers, biggest LTV first, honouring the window", () => {
    const body = get("analytics/farmers-churn-risk", "owner", "days=90").json as ChurnListOut;
    expect(body.window_days).toBe(90);
    expect(body.items.length).toBeLessThanOrEqual(50);
    for (const row of body.items) {
      expect(row.orders).toBeGreaterThan(0);
      expect(row.days_since_last_purchase).toBeGreaterThan(90);
      expect(row.phone_masked).toMatch(/^\*{9}\d{4}$/);
    }
    const ltvs = body.items.map((r) => r.ltv_paise);
    expect([...ltvs].sort((a, b) => b - a)).toEqual(ltvs);
    const wider = get("analytics/farmers-churn-risk", "owner", "days=365").json as ChurnListOut;
    expect(wider.total).toBeLessThanOrEqual(body.total);
  });

  it("store rows and detail carry the AN-005 fields", () => {
    const list = get("analytics/stores").json as { items: StoreRow[] };
    const row = list.items[0]!;
    expect(row.stock_turns_annualised).not.toBeNull();
    expect(Object.keys(row.credit_overdue_buckets)).toEqual(["0_30", "31_60", "61_90", "90_plus"]);
    expect(typeof row.day_close_variance_paise).toBe("number");
    const detail = get(`analytics/stores/${row.id}`).json as StoreDetailOut;
    expect(detail.sales_by_brand.some((b) => b.own_brand)).toBe(true);
    const shares = detail.sales_by_brand.map((b) => b.net_sales_paise);
    expect([...shares].sort((a, b) => b - a)).toEqual(shares);
    expect(detail.stock.stockouts.length).toBe(row.stockouts);
    expect(detail.stock.stockout_days).toBe(
      detail.stock.stockouts.reduce((n, s) => n + s.days_out_of_stock, 0),
    );
  });
});
