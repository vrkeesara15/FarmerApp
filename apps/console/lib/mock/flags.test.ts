import { describe, expect, it } from "vitest";
import type { FlagSummary } from "../flags";
import { handleFlags } from "./flags";

const as = (role: string) => ({ id: `u-${role}`, role });
const summary = (role = "owner", qs = "") =>
  handleFlags("GET", ["flags", "summary"], new URLSearchParams(qs), {}, as(role))!;

describe("mock AN-009 GET /v1/flags/summary", () => {
  it("summarises the caller's inbox scope over the window", () => {
    const r = summary("owner", "days=90");
    expect(r.status).toBe(200);
    const s = r.json as FlagSummary;
    expect(s.days).toBe(90);
    expect(s.total).toBeGreaterThan(0);
    expect(s.open + s.resolved).toBe(s.total);
    expect(Object.values(s.by_severity).reduce((a, b) => a + b, 0)).toBe(s.total);
    expect(Object.values(s.by_subject_type).reduce((a, b) => a + b, 0)).toBe(s.total);
    expect(s.by_rule.reduce((n, r) => n + r.total, 0)).toBe(s.total);
    expect(s.repeat_min).toBe(2);
    expect(s.precision_floor).toBe(0.3);
    expect(s.precision_window_weeks).toBe(4);
  });

  it("orders rules by volume and keeps the percentiles ordered", () => {
    const s = summary().json as FlagSummary;
    const totals = s.by_rule.map((r) => r.total);
    expect([...totals].sort((a, b) => b - a)).toEqual(totals);
    for (const rule of s.by_rule) {
      expect(rule.open + rule.resolved).toBe(rule.total);
      if (rule.median_resolution_hours !== null && rule.p90_resolution_hours !== null)
        expect(rule.p90_resolution_hours).toBeGreaterThanOrEqual(rule.median_resolution_hours);
      if (rule.precision !== null) expect(rule.precision_resolved).toBeGreaterThan(0);
    }
    if (s.median_resolution_hours !== null && s.p90_resolution_hours !== null)
      expect(s.p90_resolution_hours).toBeGreaterThanOrEqual(s.median_resolution_hours);
  });

  it("only lists subjects flagged at least twice", () => {
    const s = summary().json as FlagSummary;
    for (const subject of s.repeat_subjects) {
      expect(subject.flags).toBeGreaterThanOrEqual(s.repeat_min);
      expect(subject.open_flags).toBeLessThanOrEqual(subject.flags);
      expect(subject.rules.length).toBeGreaterThan(0);
    }
  });

  it("narrows with the window and the role, and refuses field officers", () => {
    const wide = summary("owner", "days=365").json as FlagSummary;
    const narrow = summary("owner", "days=1").json as FlagSummary;
    expect(narrow.total).toBeLessThanOrEqual(wide.total);
    const manager = summary("store_manager").json as FlagSummary;
    expect(manager.total).toBeLessThan(wide.total);
    expect(summary("field_officer").status).toBe(403);
  });
});
