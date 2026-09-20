import { describe, expect, it } from "vitest";
import {
  isMonth,
  previousMonth,
  recentMonths,
  starterDefinition,
  validateDefinition,
  verifiedVisitsNote,
  type RuleDefinition,
} from "./incentives";

const codes = (def: RuleDefinition) =>
  validateDefinition(def)
    .map((i) => i.code)
    .sort();

describe("C90 incentive rule document validation", () => {
  it("accepts the starter document", () => {
    expect(validateDefinition(starterDefinition())).toEqual([]);
  });

  it("needs at least one component", () => {
    expect(codes({ components: [] })).toEqual(["noComponents"]);
  });

  it("checks ids, metrics and kinds", () => {
    expect(
      codes({
        components: [
          { id: "Visits", metric: "nope", kind: "per_unit", rate_paise: 1 },
          { id: "sales", metric: "sales_paise", kind: "unknown" as never },
        ],
      }),
    ).toEqual(["idInvalid", "kindUnknown", "metricUnknown"]);
  });

  it("refuses duplicate component ids", () => {
    expect(
      codes({
        components: [
          { id: "a", metric: "new_farmers", kind: "per_unit", rate_paise: 100 },
          { id: "a", metric: "new_farmers", kind: "per_unit", rate_paise: 100 },
        ],
      }),
    ).toEqual(["idDuplicate"]);
  });

  it("only allows percent on a money metric and needs a rate", () => {
    expect(
      codes({ components: [{ id: "s", metric: "verified_visits", kind: "percent" }] }),
    ).toEqual(["percentNeedsMoney", "rateBpRequired"]);
  });

  it("checks slab continuity and an open-ended last slab", () => {
    expect(
      codes({
        components: [
          {
            id: "v",
            metric: "verified_visits",
            kind: "slab_per_unit",
            slabs: [
              { from: 5, to: 40, rate_paise: 0 },
              { from: 45, to: 80, rate_paise: 2000 },
            ],
          },
        ],
      }),
    ).toEqual(["slabGap", "slabOpenEnd", "slabStart"]);
  });

  it("checks thresholds, caps and multipliers", () => {
    expect(
      codes({
        components: [{ id: "ob", metric: "own_brand_share", kind: "threshold", cap_paise: 0 }],
        multipliers: [{ metric: "nope", gte: 1, factor: 0 }],
        cap_paise: -1,
      }),
    ).toEqual([
      "amountRequired",
      "capInvalid",
      "capInvalid",
      "multiplierFactor",
      "multiplierMetric",
      "thresholdRequired",
    ]);
  });

  it("accepts an attainment multiplier", () => {
    const def = starterDefinition();
    def.multipliers = [{ metric: "attainment.verified_visits", gte: 1.2, factor: 1.25 }];
    expect(validateDefinition(def)).toEqual([]);
  });
});

describe("VV-005 verified-visits note", () => {
  it("says verified visits only for the default document", () => {
    expect(verifiedVisitsNote(starterDefinition())).toEqual({
      key: "verifiedOnly",
      statuses: ["verified"],
    });
    expect(verifiedVisitsNote(null).key).toBe("verifiedOnly");
  });

  it("calls out a document that counts more than verified visits", () => {
    const def = starterDefinition();
    def.eligibility = { count_visit_statuses: ["verified", "partial"] };
    expect(verifiedVisitsNote(def)).toEqual({
      key: "widened",
      statuses: ["verified", "partial"],
    });
  });

  it("flags an empty status list as invalid", () => {
    const def = starterDefinition();
    def.eligibility = { count_visit_statuses: [] };
    expect(codes(def)).toEqual(["visitStatusesEmpty"]);
  });
});

describe("month helpers", () => {
  it("opens on the month before today", () => {
    expect(previousMonth(new Date("2026-09-19T00:00:00Z"))).toBe("2026-08");
    expect(previousMonth(new Date("2026-01-05T00:00:00Z"))).toBe("2025-12");
  });

  it("lists recent ended months newest first", () => {
    expect(recentMonths(3, new Date("2026-09-19T00:00:00Z"))).toEqual([
      "2026-08",
      "2026-07",
      "2026-06",
    ]);
  });

  it("validates a month string", () => {
    expect(isMonth("2026-09")).toBe(true);
    expect(isMonth("2026-13")).toBe(false);
    expect(isMonth("2026-9")).toBe(false);
  });
});
