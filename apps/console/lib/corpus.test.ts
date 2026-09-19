import { describe, expect, it } from "vitest";
import {
  CORPUS_STATUSES,
  bumpsVersion,
  compactLists,
  compactNames,
  corpusActions,
  isEditable,
  isServed,
  matchesProblem,
  servedImageCount,
} from "./corpus";

describe("corpus status workflow (WC-007, SPEC 3.2)", () => {
  it("agronomists move draft -> reviewed -> approved -> retired (reviewed may go back)", () => {
    expect(corpusActions("draft", "agronomist")).toEqual(["reviewed", "retired"]);
    expect(corpusActions("reviewed", "agronomist")).toEqual(["approved", "draft", "retired"]);
    expect(corpusActions("approved", "agronomist")).toEqual(["retired"]);
    expect(corpusActions("retired", "agronomist")).toEqual([]);
  });

  it("owners and directors read only; other roles and a loading session get no actions", () => {
    for (const role of ["owner", "director", "tenant_admin", "field_officer", undefined])
      for (const status of CORPUS_STATUSES) expect(corpusActions(status, role)).toEqual([]);
  });

  it("never offers draft -> approved (review first)", () => {
    expect(corpusActions("draft", "agronomist")).not.toContain("approved");
  });

  it("locks approved and retired entries; bumps the version when production changes", () => {
    expect(isEditable("draft")).toBe(true);
    expect(isEditable("reviewed")).toBe(true);
    expect(isEditable("approved")).toBe(false);
    expect(isEditable("retired")).toBe(false);
    expect(bumpsVersion("reviewed", "approved")).toBe(true);
    expect(bumpsVersion("approved", "retired")).toBe(true);
    expect(bumpsVersion("draft", "reviewed")).toBe(false);
    expect(bumpsVersion("reviewed", "retired")).toBe(false);
  });

  it("production serves approved problems' approved images only", () => {
    expect(isServed({ status: "approved" })).toBe(true);
    expect(isServed({ status: "reviewed" })).toBe(false);
    expect(
      servedImageCount({ status: "approved", image_counts: { approved: 3, reviewed: 2 } }),
    ).toBe(3);
    expect(servedImageCount({ status: "reviewed", image_counts: { approved: 3 } })).toBe(0);
  });
});

describe("corpus form helpers", () => {
  it("searches names in every language and the code", () => {
    const p = {
      names: { en: "Rice blast", te: "అగ్గి తెగులు", hi: "झोंका रोग" },
      pest_code: "paddy_blast",
    };
    expect(matchesProblem(p, "BLAST")).toBe(true);
    expect(matchesProblem(p, "అగ్గి")).toBe(true);
    expect(matchesProblem(p, "झोंका")).toBe(true);
    expect(matchesProblem(p, "paddy_")).toBe(true);
    expect(matchesProblem(p, "thrips")).toBe(false);
    expect(matchesProblem(p, "  ")).toBe(true);
  });

  it("drops empty languages and blank symptom lines", () => {
    expect(compactNames({ en: " Aphids ", te: "", kn: "  ", hi: "माहू" })).toEqual({
      en: "Aphids",
      hi: "माहू",
    });
    expect(compactLists({ en: "Sticky leaves\n\n  Curling \n", te: "" })).toEqual({
      en: ["Sticky leaves", "Curling"],
    });
  });
});
