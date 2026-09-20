import { describe, expect, it } from "vitest";
import { resolutionHours, summariseDataQuality } from "./data-quality";
import type { Flag } from "./flags";

const H = 3_600_000;
const NOW = Date.parse("2026-09-19T00:00:00Z");
const at = (hoursAgo: number) => new Date(NOW - hoursAgo * H).toISOString();

function flag(over: Partial<Flag>): Flag {
  return {
    id: "f",
    rule_id: "VA-F01",
    rule_version: 1,
    subject_type: "employee",
    subject_id: "u1",
    severity: "high",
    title: "t",
    status: "open",
    owner_id: null,
    owner_role: null,
    watchers: [],
    sla_due_at: at(-24),
    overdue: false,
    escalation_level: 0,
    raised_by_mode: "batch",
    resolution_note: null,
    resolved_at: null,
    resolved_by: null,
    created_at: at(48),
    version: 1,
    ...over,
  };
}

describe("AN-009 data quality summary", () => {
  const flags: Flag[] = [
    flag({ id: "1", created_at: at(48), status: "resolved_fixed", resolved_at: at(40) }), // 8 h
    flag({ id: "2", created_at: at(30), status: "resolved_valid", resolved_at: at(26) }), // 4 h, FP
    flag({ id: "3", created_at: at(20), status: "open", overdue: true, severity: "medium" }),
    flag({
      id: "4",
      rule_id: "VA-F03",
      created_at: at(10),
      status: "resolved_fixed",
      resolved_at: at(4),
      severity: "low",
    }), // 6 h
    flag({ id: "5", rule_id: "VA-F03", created_at: at(5), status: "in_review" }),
  ];

  const s = summariseDataQuality(flags, NOW);

  it("counts volume, open flags and severities", () => {
    expect(s.total).toBe(5);
    expect(s.open).toBe(2);
    expect(s.resolved).toBe(3);
    expect(s.overdue).toBe(1);
    expect(s.bySeverity).toEqual({ high: 3, medium: 1, low: 1 });
  });

  it("groups by rule, biggest first, with per-rule resolution time", () => {
    expect(s.byRule.map((r) => r.rule)).toEqual(["VA-F01", "VA-F03"]);
    const first = s.byRule[0]!;
    expect(first).toMatchObject({ total: 3, open: 1, resolved: 2, falsePositives: 1 });
    expect(first.avgResolutionHours).toBe(6);
    expect(first.falsePositiveRate).toBe(0.5);
  });

  it("reports average and median resolution time and the false-positive rate", () => {
    expect(s.avgResolutionHours).toBe(6);
    expect(s.medianResolutionHours).toBe(6);
    expect(s.falsePositiveRate).toBeCloseTo(1 / 3);
  });

  it("lists repeat subjects inside the window only", () => {
    expect(s.repeatSubjects).toHaveLength(1);
    expect(s.repeatSubjects[0]).toMatchObject({ subject_id: "u1", count: 5 });
    expect(s.repeatSubjects[0]!.rules).toEqual(["VA-F01", "VA-F03"]);
    const old = summariseDataQuality(
      flags.map((f) => ({ ...f, created_at: at(120 * 24) })),
      NOW,
    );
    expect(old.repeatSubjects).toEqual([]);
  });

  it("is empty-safe", () => {
    const empty = summariseDataQuality([], NOW);
    expect(empty).toMatchObject({
      total: 0,
      avgResolutionHours: null,
      medianResolutionHours: null,
      falsePositiveRate: null,
      byRule: [],
      repeatSubjects: [],
    });
  });

  it("has no resolution time while a flag is open", () => {
    expect(resolutionHours(flag({ status: "open" }))).toBeNull();
    expect(resolutionHours({ created_at: at(10), resolved_at: at(7) })).toBe(3);
  });
});
