import { describe, expect, it } from "vitest";
import {
  addDays,
  applyFilterChange,
  daysBetween,
  defaultRange,
  filterQueryString,
  isIsoDate,
  parseFilters,
  reconcileFilters,
  serializeFilters,
  toApiFilters,
  todayIst,
} from "./analytics-filters";

const TODAY = "2026-09-18";
const p = (qs: string) => new URLSearchParams(qs);

describe("AN-011 filters: defaults", () => {
  it("defaults to the 30 days ending today (IST) with no entity filters", () => {
    const { filters, issues, isDefaultRange } = parseFilters(p(""), TODAY);
    expect(filters).toEqual({ from: "2026-08-20", to: "2026-09-18" });
    expect(daysBetween(filters.from, filters.to)).toBe(30);
    expect(issues).toEqual([]);
    expect(isDefaultRange).toBe(true);
    expect(defaultRange(TODAY)).toEqual({ from: "2026-08-20", to: "2026-09-18" });
  });

  it("computes today in IST, not UTC", () => {
    // 20:00 UTC on the 18th is 01:30 IST on the 19th.
    expect(todayIst(new Date("2026-09-18T20:00:00Z"))).toBe("2026-09-19");
    expect(todayIst(new Date("2026-09-18T18:00:00Z"))).toBe("2026-09-18");
  });

  it("writes nothing to the URL for the defaults", () => {
    expect(serializeFilters(defaultRange(TODAY), p(""), TODAY)).toBe("");
  });
});

describe("AN-011 filters: URL round trip", () => {
  it("parse(serialize(f)) === f for every filter", () => {
    const f = {
      from: "2026-07-01",
      to: "2026-07-31",
      cluster: "cluster-tg",
      store: "store-wgl",
      officer: "off-wgl-1",
      crop: "crop-paddy",
    };
    const qs = serializeFilters(f, p(""), TODAY);
    expect(qs).toBe(
      "from=2026-07-01&to=2026-07-31&cluster=cluster-tg&store=store-wgl&officer=off-wgl-1&crop=crop-paddy",
    );
    const back = parseFilters(p(qs), TODAY);
    expect(back.filters).toEqual(f);
    expect(back.issues).toEqual([]);
    expect(back.isDefaultRange).toBe(false);
  });

  it("keeps the screen's own parameters (search, sort, replay date) after the filters", () => {
    const qs = serializeFilters(
      { from: "2026-07-01", to: "2026-07-31", crop: "crop-cotton" },
      p("q=ram&crop=crop-paddy&sort=-ltv&date=2026-07-10"),
      TODAY,
    );
    expect(qs).toBe(
      "from=2026-07-01&to=2026-07-31&crop=crop-cotton&q=ram&sort=-ltv&date=2026-07-10",
    );
  });

  it("builds link queries and API parameters", () => {
    const f = { from: "2026-07-01", to: "2026-07-31", store: "store-wgl" };
    expect(filterQueryString(f, TODAY)).toBe("from=2026-07-01&to=2026-07-31&store=store-wgl");
    expect(toApiFilters(f)).toEqual({
      from: "2026-07-01",
      to: "2026-07-31",
      store_id: "store-wgl",
    });
    expect(toApiFilters(defaultRange(TODAY))).toEqual({ from: "2026-08-20", to: "2026-09-18" });
  });

  it("accepts UUIDs from the real API", () => {
    const id = "0b9a8f7e-1234-4cde-8f00-aa11bb22cc33";
    expect(parseFilters(p(`store=${id}`), TODAY).filters.store).toBe(id);
  });
});

describe("AN-011 filters: invalid values and combinations", () => {
  it("drops malformed dates and falls back to the default range", () => {
    const r = parseFilters(p("from=2026-13-01&to=yesterday"), TODAY);
    expect(r.filters).toEqual(defaultRange(TODAY));
    expect(r.issues).toContain("invalid_date");
    expect(isIsoDate("2026-02-30")).toBe(false);
    expect(isIsoDate("2026-02-28")).toBe(true);
  });

  it("swaps a reversed range", () => {
    const r = parseFilters(p("from=2026-09-10&to=2026-09-01"), TODAY);
    expect(r.filters).toMatchObject({ from: "2026-09-01", to: "2026-09-10" });
    expect(r.issues).toEqual(["reversed_range"]);
  });

  it("cuts a range longer than 366 days (API 422 invalid_date_range) to 366 days", () => {
    const r = parseFilters(p("from=2024-01-01&to=2026-09-18"), TODAY);
    expect(r.filters).toMatchObject({ from: addDays("2026-09-18", -365), to: "2026-09-18" });
    expect(daysBetween(r.filters.from, r.filters.to)).toBe(366);
    expect(r.issues).toEqual(["range_too_long"]);
  });

  it("completes a half-open range", () => {
    expect(parseFilters(p("to=2026-06-30"), TODAY).filters).toMatchObject({
      from: "2026-06-01",
      to: "2026-06-30",
    });
    expect(parseFilters(p("from=2026-09-01"), TODAY).filters).toMatchObject({
      from: "2026-09-01",
      to: TODAY,
    });
  });

  it("drops ids that are not ids", () => {
    const r = parseFilters(p("store=<script>&crop=crop-paddy"), TODAY);
    expect(r.filters.store).toBeUndefined();
    expect(r.filters.crop).toBe("crop-paddy");
    expect(r.issues).toEqual(["invalid_id"]);
  });

  it("changing the cluster clears the store and officer; changing the store clears the officer", () => {
    const base = {
      from: "2026-09-01",
      to: "2026-09-18",
      cluster: "c1",
      store: "s1",
      officer: "o1",
    };
    expect(applyFilterChange(base, { cluster: "c2" })).toEqual({
      from: "2026-09-01",
      to: "2026-09-18",
      cluster: "c2",
    });
    expect(applyFilterChange(base, { store: "s2" })).toEqual({
      from: "2026-09-01",
      to: "2026-09-18",
      cluster: "c1",
      store: "s2",
    });
    // Setting both in one patch keeps both.
    expect(applyFilterChange(base, { cluster: "c2", store: "s9" })).toMatchObject({
      cluster: "c2",
      store: "s9",
    });
    // Crop and dates do not touch the hierarchy.
    expect(applyFilterChange(base, { crop: "crop-paddy", from: "2026-08-01" })).toMatchObject({
      store: "s1",
      officer: "o1",
      crop: "crop-paddy",
      from: "2026-08-01",
    });
    // Clearing a value removes it.
    expect(applyFilterChange(base, { officer: undefined }).officer).toBeUndefined();
  });

  it("reconciles a store outside the cluster and an officer outside the store once options load", () => {
    const m = {
      storeCluster: new Map([
        ["s1", "c1"],
        ["s2", "c2"],
      ]),
      officerPlacement: new Map([
        ["o1", { store: "s1", cluster: "c1" }],
        ["o2", { store: "s2", cluster: "c2" }],
      ]),
    };
    const r = reconcileFilters(
      { from: "2026-09-01", to: "2026-09-18", cluster: "c1", store: "s2", officer: "o2" },
      m,
    );
    expect(r.filters).toEqual({ from: "2026-09-01", to: "2026-09-18", cluster: "c1" });
    expect(r.issues).toEqual(["store_outside_cluster", "officer_outside_scope"]);
    const ok = reconcileFilters(
      { from: "2026-09-01", to: "2026-09-18", cluster: "c1", store: "s1", officer: "o1" },
      m,
    );
    expect(ok.issues).toEqual([]);
    // Unknown ids are left for the API to answer (404).
    expect(
      reconcileFilters({ from: "2026-09-01", to: "2026-09-18", store: "s-unknown" }, m).issues,
    ).toEqual([]);
  });
});
