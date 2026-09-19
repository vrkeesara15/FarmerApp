import { describe, expect, it } from "vitest";
import {
  FLAG_STATUSES,
  TRANSITIONS,
  availableActions,
  evidenceGeometry,
  flagQuery,
  formatCountdown,
  noteRequired,
  recordHref,
  slaState,
} from "./flags";

describe("flag state machine (SPEC 6.1)", () => {
  it("matches the state diagram", () => {
    expect(TRANSITIONS.open).toEqual(["in_review"]);
    expect([...TRANSITIONS.in_review].sort()).toEqual(
      ["escalated", "resolved_fixed", "resolved_valid"].sort(),
    );
    expect([...TRANSITIONS.escalated].sort()).toEqual(["resolved_action", "resolved_fixed"]);
    for (const s of ["resolved_valid", "resolved_fixed", "resolved_action"] as const)
      expect(TRANSITIONS[s]).toEqual([]);
  });

  it("offers only moves allowed by both the diagram and the server", () => {
    expect(availableActions("open", ["in_review"], "cluster_head")).toEqual(["in_review"]);
    expect(
      availableActions("in_review", ["escalated", "resolved_fixed", "resolved_valid"], "owner"),
    ).toEqual(["resolved_valid", "resolved_fixed", "escalated"]);
    expect(availableActions("escalated", ["resolved_action", "resolved_fixed"], "auditor")).toEqual(
      ["resolved_fixed", "resolved_action"],
    );
    // A stale / tampered server list never adds a move the diagram forbids.
    expect(availableActions("open", ["resolved_valid", "in_review"], "owner")).toEqual([
      "in_review",
    ]);
    expect(availableActions("resolved_fixed", ["escalated"], "owner")).toEqual([]);
  });

  it("offers nothing to the subject or to roles that cannot review", () => {
    for (const status of FLAG_STATUSES) {
      expect(availableActions(status, [], "field_officer")).toEqual([]);
      expect(availableActions(status, TRANSITIONS[status], "field_officer")).toEqual([]);
      expect(availableActions(status, TRANSITIONS[status], "accountant")).toEqual([]);
      expect(availableActions(status, TRANSITIONS[status], undefined)).toEqual([]);
    }
  });

  it("requires a note to resolve or escalate but not to start a review", () => {
    expect(noteRequired("in_review")).toBe(false);
    for (const s of ["resolved_valid", "resolved_fixed", "escalated", "resolved_action"] as const)
      expect(noteRequired(s)).toBe(true);
  });
});

describe("SLA countdown", () => {
  const now = Date.parse("2026-09-18T06:00:00Z");

  it("counts down in days, hours, minutes and seconds", () => {
    expect(formatCountdown(2 * 86_400_000 + 3 * 3_600_000)).toBe("2d 03h");
    expect(formatCountdown(3 * 3_600_000 + 5 * 60_000 + 10_000)).toBe("3h 05m");
    expect(formatCountdown(4 * 60_000 + 9_000)).toBe("4m 09s");
    expect(formatCountdown(-(90 * 60_000))).toBe("1h 30m");
  });

  it("is overdue after the due time and ticks with the clock", () => {
    const due = "2026-09-18T07:00:00Z";
    const a = slaState(due, now);
    expect(a).toMatchObject({ overdue: false, dueSoon: true, text: "1h 00m" });
    const b = slaState(due, now + 30 * 60_000 + 1_000);
    expect(b.text).toBe("29m 59s");
    const c = slaState(due, now + 2 * 3_600_000);
    expect(c).toMatchObject({ overdue: true, text: "1h 00m" });
    expect(c.remainingMs).toBeLessThan(0);
  });

  it("is never overdue once resolved, and trusts the server's overdue flag", () => {
    expect(slaState("2026-09-17T00:00:00Z", now, { status: "resolved_fixed" }).overdue).toBe(false);
    expect(slaState("2026-09-19T00:00:00Z", now, { overdue: true }).overdue).toBe(true);
    expect(slaState("2026-09-20T00:00:00Z", now).dueSoon).toBe(false);
  });
});

describe("inbox query and evidence helpers", () => {
  it("builds repeatable status / severity params and owner=me", () => {
    expect(
      flagQuery({
        status: ["open", "in_review"],
        severity: ["high"],
        rule_id: "VA-F06",
        subject_type: "employee",
        owner_me: true,
        overdue: true,
        cursor: "50",
      }),
    ).toBe(
      "?status=open&status=in_review&severity=high&rule_id=VA-F06&subject_type=employee&owner=me&overdue=true&cursor=50",
    );
    expect(flagQuery({})).toBe("");
  });

  it("keeps valid GeoJSON points and polygons only", () => {
    const g = evidenceGeometry({
      points: [
        { type: "Point", coordinates: [79.5, 17.9], label: "A" },
        { type: "Point", coordinates: ["x"] },
      ],
      polygons: [
        {
          type: "Polygon",
          coordinates: [
            [
              [79, 17],
              [79.1, 17],
              [79.1, 17.1],
              [79, 17],
            ],
          ],
        },
        { type: "Polygon", coordinates: "bad" },
      ],
    });
    expect(g.points).toEqual([{ type: "Point", coordinates: [79.5, 17.9], label: "A" }]);
    expect(g.polygons).toHaveLength(1);
  });

  it("links farmer and officer records only", () => {
    expect(recordHref("farmer", "f1")).toBe("/farmers/f1");
    expect(recordHref("user", "u1")).toBe("/field-team/u1");
    expect(recordHref("farm", "x")).toBeNull();
  });
});
