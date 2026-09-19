import { describe, expect, it } from "vitest";
import {
  SLA_BREACH_HOURS,
  SLA_WARNING_HOURS,
  candidateRows,
  formatScore,
  formatSpan,
  localName,
  reviewBody,
  reviewQueueQuery,
  reviewSla,
  validateReview,
  type DiagnosisScores,
  type ReviewDraft,
} from "./diagnosis";

const H = 3_600_000;
const NOW = Date.parse("2026-09-19T12:00:00Z");
const ago = (hours: number) => new Date(NOW - hours * H).toISOString();

describe("review SLA (DX-006: alert at 18 h, breach at 24 h)", () => {
  it("is ok before 18 h and counts down to the 24 h SLA", () => {
    const s = reviewSla(ago(3), NOW);
    expect(s.level).toBe("ok");
    expect(s.ageHours).toBeCloseTo(3);
    expect(s.remainingMs).toBe(21 * H);
    expect(s.text).toBe("21h 00m");
  });

  it("warns from 18 h (the ageing alert) until the SLA", () => {
    expect(SLA_WARNING_HOURS).toBe(18);
    expect(reviewSla(ago(17.99), NOW).level).toBe("ok");
    expect(reviewSla(ago(18), NOW).level).toBe("warning");
    const s = reviewSla(ago(19.25), NOW);
    expect(s.level).toBe("warning");
    expect(s.text).toBe("4h 45m");
  });

  it("trusts the API's overdue flag even when the local clock is behind", () => {
    expect(reviewSla(ago(17), NOW, { overdue: true }).level).toBe("warning");
  });

  it("is breached at 24 h and then shows the time since the breach", () => {
    expect(SLA_BREACH_HOURS).toBe(24);
    expect(reviewSla(ago(24), NOW).level).toBe("breach");
    const s = reviewSla(ago(26.5), NOW);
    expect(s.level).toBe("breach");
    expect(s.remainingMs).toBe(-2.5 * H);
    expect(s.text).toBe("2h 30m");
  });

  it("formats spans as days+hours, hours+minutes or minutes+seconds", () => {
    expect(formatSpan(26 * H)).toBe("1d 02h");
    expect(formatSpan(-(5 * H + 7 * 60_000))).toBe("5h 07m");
    expect(formatSpan(12 * 60_000 + 9_000)).toBe("12m 09s");
  });
});

describe("model candidates (DX-003 scores, DX-005 provenance)", () => {
  const scores: DiagnosisScores = {
    votes: { a: 6, b: 4 },
    decision: { problem_id: "a" },
    candidates: [
      { problem_id: "b", score: 0.897, votes: 4 },
      { problem_id: "a", score: 0.912, votes: 6 },
    ],
    llm: { problem_id: "b", status: "answered" },
  };

  it("sorts by similarity and computes the vote share of the top 10", () => {
    const rows = candidateRows(scores);
    expect(rows.map((r) => r.problemId)).toEqual(["a", "b"]);
    expect(rows[0]).toMatchObject({ score: 0.912, votes: 6, voteShare: 0.6, proposed: true });
    expect(rows[1]).toMatchObject({ votes: 4, voteShare: 0.4, llmChoice: true, proposed: false });
    expect(formatScore(rows[0]!.score)).toBe("0.912");
  });

  it("falls back to candidate votes and handles missing scores", () => {
    expect(candidateRows(null)).toEqual([]);
    expect(candidateRows({ candidates: [] })).toEqual([]);
    const rows = candidateRows({ candidates: [{ problem_id: "x", score: 0.8, votes: 2 }] });
    expect(rows[0]).toMatchObject({ voteShare: 1, proposed: true, llmChoice: false });
    expect(
      candidateRows({ candidates: [{ problem_id: "x", score: 0.8, votes: 0 }] })[0]!.voteShare,
    ).toBe(0);
  });
});

describe("review form validation (WC-006)", () => {
  const draft = (d: Partial<ReviewDraft>): ReviewDraft => ({
    action: "confirm",
    problemId: "",
    note: "Checked the photos",
    addToCorpus: false,
    ...d,
  });

  it("needs a decision and a note", () => {
    expect(validateReview(draft({ action: "" }))).toEqual({ action: "required" });
    expect(validateReview(draft({ note: "   " }))).toEqual({ note: "required" });
    expect(validateReview(draft({}))).toEqual({});
  });

  it("correct requires a problem that differs from the current label", () => {
    expect(validateReview(draft({ action: "correct" }))).toEqual({ problem: "required" });
    expect(validateReview(draft({ action: "correct", problemId: "p1" }), "p1")).toEqual({
      problem: "same",
    });
    expect(validateReview(draft({ action: "correct", problemId: "p2" }), "p1")).toEqual({});
  });

  it("builds the ReviewIn body: problem only to correct, never add not-diagnosable photos", () => {
    expect(
      reviewBody(draft({ action: "correct", problemId: "p2", note: " x ", addToCorpus: true })),
    ).toEqual({
      action: "correct",
      problem_id: "p2",
      note: "x",
      add_to_corpus: true,
    });
    expect(reviewBody(draft({ problemId: "p2" })).problem_id).toBeNull();
    expect(reviewBody(draft({ action: "not_diagnosable", addToCorpus: true })).add_to_corpus).toBe(
      false,
    );
  });
});

describe("helpers", () => {
  it("builds the queue query with repeatable confidence", () => {
    expect(reviewQueueQuery({})).toBe("");
    expect(
      reviewQueueQuery({
        crop_id: "c1",
        confidence: ["low", "medium"],
        min_age_hours: 18,
        flagged: true,
      }),
    ).toBe("?crop_id=c1&confidence=low&confidence=medium&min_age_hours=18&flagged=true");
  });

  it("picks the local name, falling back to English", () => {
    const names = { en: "Rice blast", te: "అగ్గి తెగులు" };
    expect(localName(names, "te")).toBe("అగ్గి తెగులు");
    expect(localName(names, "mr")).toBe("Rice blast");
    expect(localName(undefined, "mr", "paddy_blast")).toBe("paddy_blast");
  });
});
